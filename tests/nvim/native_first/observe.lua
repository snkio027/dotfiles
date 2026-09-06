local function fail(message)
	error("NATIVE_FIRST_E1_FAILURE: " .. message, 2)
end

local function assert_equal(actual, expected, message)
	if not vim.deep_equal(actual, expected) then
		fail(("%s\n  expected: %s\n  observed: %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
	end
end

local function sorted_unique(values)
	local seen = {}
	for _, value in ipairs(values) do
		seen[value] = true
	end
	local result = vim.tbl_keys(seen)
	table.sort(result)
	return result
end

local function sorted_enabled_keys(values)
	local result = {}
	for key, value in pairs(values or {}) do
		if value then
			result[#result + 1] = key
		end
	end
	table.sort(result)
	return result
end

local function hex(value)
	if not value then
		return nil
	end
	return ("#%06X"):format(value)
end

local highlight_attributes = {
	"fg",
	"bg",
	"sp",
	"bold",
	"italic",
	"underline",
	"undercurl",
	"underdouble",
	"underdotted",
	"underdashed",
	"strikethrough",
	"reverse",
	"standout",
	"nocombine",
	"blend",
}

local function normalized_highlight(group)
	local raw = vim.api.nvim_get_hl(0, { name = group, link = false })
	local normalized = {}
	for _, key in ipairs(highlight_attributes) do
		local value = raw[key]
		if value ~= nil and value ~= false then
			normalized[key] = (key == "fg" or key == "bg" or key == "sp") and hex(value) or value
		end
	end
	return normalized
end

local function locate_case(bufnr, case, lang)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	for marker_line, line in ipairs(lines) do
		if line:find(case.tag, 1, true) then
			for candidate_line = marker_line + 1, math.min(#lines, marker_line + 10) do
				local candidate = lines[candidate_line]
				local trimmed = vim.trim(candidate)
				local is_comment = trimmed:sub(1, 2) == "//" or (lang == "python" and trimmed:sub(1, 1) == "#")
				if not is_comment then
					local column = candidate:find("%f[%w_]" .. vim.pesc(case.token) .. "%f[^%w_]")
					if column then
						return candidate_line - 1, column - 1
					end
				end
			end
		end
	end
	fail(("case locator failed: %s (%s)"):format(case.tag, case.token))
end

local function wait_for_clients(bufnr, expectations)
	local by_name = {}
	local ready = vim.wait(15000, function()
		by_name = {}
		for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
			if client.initialized then
				by_name[client.name] = client
			end
		end
		for _, expected in ipairs(expectations) do
			if not by_name[expected.name] then
				return false
			end
		end
		return true
	end, 100)
	if not ready then
		fail("expected clients did not attach: " .. vim.inspect(expectations))
	end

	local expected_names = {}
	for _, expected in ipairs(expectations) do
		expected_names[expected.name] = true
		local has_semantic_tokens = by_name[expected.name].server_capabilities.semanticTokensProvider ~= nil
		assert_equal(
			has_semantic_tokens,
			expected.semantic_tokens,
			"semantic-token capability drift for " .. expected.name
		)
	end
	for name in pairs(by_name) do
		if not expected_names[name] then
			fail("undeclared LSP client attached to evidence fixture: " .. name)
		end
	end
	return by_name
end

local function decode_modifier_bits(bits, legend, provider)
	local modifiers = {}
	local index = 1
	while bits > 0 do
		if bits % 2 == 1 then
			local modifier = legend[index]
			if not modifier then
				fail(("raw token from %s references unknown modifier bit %d"):format(provider, index - 1))
			end
			modifiers[#modifiers + 1] = modifier
		end
		bits = math.floor(bits / 2)
		index = index + 1
	end
	table.sort(modifiers)
	return modifiers
end

local function request_raw_semantic_tokens(bufnr, client)
	local provider = client.server_capabilities.semanticTokensProvider
	local legend = provider and provider.legend
	if type(legend) ~= "table" then
		fail("semantic-token legend unavailable for " .. client.name)
	end
	local response, request_error = client:request_sync(
		"textDocument/semanticTokens/full",
		{ textDocument = vim.lsp.util.make_text_document_params(bufnr) },
		15000,
		bufnr
	)
	if not response or response.err or type(response.result) ~= "table" or type(response.result.data) ~= "table" then
		fail(("raw semanticTokens/full failed for %s: %s"):format(client.name, vim.inspect(request_error or response)))
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local tokens = {}
	local row
	local start_character = 0
	for index = 1, #response.result.data, 5 do
		local delta_line = response.result.data[index]
		row = row and row + delta_line or delta_line
		local delta_start = response.result.data[index + 1]
		start_character = delta_line == 0 and start_character + delta_start or delta_start
		local length = response.result.data[index + 2]
		local type_index = response.result.data[index + 3]
		local line = lines[row + 1]
		local token_type = legend.tokenTypes[type_index + 1]
		if not line or not token_type then
			fail("invalid raw semantic-token coordinates or type from " .. client.name)
		end
		tokens[#tokens + 1] = {
			provider = client.name,
			client_id = client.id,
			position_encoding = client.offset_encoding,
			row = row,
			start_col = vim.str_byteindex(line, client.offset_encoding, start_character, false),
			end_col = vim.str_byteindex(line, client.offset_encoding, start_character + length, false),
			type = token_type,
			modifiers = decode_modifier_bits(response.result.data[index + 4], legend.tokenModifiers, client.name),
		}
	end
	return tokens
end

local function raw_tokens_at_position(tokens, row, column)
	local result = {}
	for _, token in ipairs(tokens) do
		if token.row == row and token.start_col <= column and column < token.end_col then
			result[#result + 1] = token
		end
	end
	return result
end

local function decoded_tokens_at_position(bufnr, row, column, clients)
	local by_id = {}
	for name, client in pairs(clients) do
		by_id[client.id] = name
	end
	local result = {}
	for _, token in ipairs(vim.lsp.semantic_tokens.get_at_pos(bufnr, row, column) or {}) do
		local provider = by_id[token.client_id]
		if not provider then
			fail("semantic token came from undeclared client id " .. tostring(token.client_id))
		end
		result[#result + 1] = {
			provider = provider,
			client_id = token.client_id,
			type = token.type,
			modifiers = sorted_enabled_keys(token.modifiers),
		}
	end
	table.sort(result, function(left, right)
		return left.provider .. left.type < right.provider .. right.type
	end)
	return result
end

local function comparable_tokens(tokens)
	local result = {}
	for _, token in ipairs(tokens) do
		result[#result + 1] = {
			provider = token.provider,
			client_id = token.client_id,
			type = token.type,
			modifiers = token.modifiers,
		}
	end
	table.sort(result, function(left, right)
		return left.provider .. left.type < right.provider .. right.type
	end)
	return result
end

local function tree_sitter_captures(inspected)
	local captures = {}
	for _, capture in ipairs(inspected.treesitter or {}) do
		captures[#captures + 1] = capture.capture
	end
	return sorted_unique(captures)
end

local function applied_semantic_groups(inspected)
	local groups = {}
	for _, token in ipairs(inspected.semantic_tokens or {}) do
		local group = token.opts and token.opts.hl_group
		if group then
			groups[#groups + 1] = {
				group = group,
				priority = tonumber(token.opts.priority) or (vim.hl and vim.hl.priorities.semantic_tokens) or 125,
				attributes = normalized_highlight(group),
			}
		end
	end
	table.sort(groups, function(left, right)
		if left.priority ~= right.priority then
			return left.priority > right.priority
		end
		return left.group < right.group
	end)
	return groups
end

local function foreground_candidates(inspected)
	local candidates = {}
	local priorities = vim.hl and vim.hl.priorities or {}
	local function add(group, source, priority, order)
		if group then
			local attributes = normalized_highlight(group)
			if attributes.fg then
				candidates[#candidates + 1] = {
					group = group,
					source = source,
					priority = priority,
					order = order,
					attributes = attributes,
				}
			end
		end
	end
	for index, token in ipairs(inspected.semantic_tokens or {}) do
		add(
			token.opts and token.opts.hl_group,
			"lsp",
			tonumber(token.opts and token.opts.priority) or priorities.semantic_tokens or 125,
			index
		)
	end
	for index, capture in ipairs(inspected.treesitter or {}) do
		local raw_priority = capture.metadata and capture.metadata.priority
		add(
			capture.hl_group or ("@" .. capture.capture),
			"treesitter",
			tonumber(raw_priority) or priorities.treesitter or 100,
			index
		)
	end
	for index, syntax in ipairs(inspected.syntax or {}) do
		add(syntax.hl_group, "syntax", priorities.syntax or 50, index)
	end
	table.sort(candidates, function(left, right)
		if left.priority ~= right.priority then
			return left.priority > right.priority
		end
		return left.order > right.order
	end)
	return candidates
end

local function client_record(client)
	local provider = client.server_capabilities.semanticTokensProvider
	local legend = provider and provider.legend or {}
	local capabilities = client.server_capabilities
	return {
		id = client.id,
		name = client.name,
		position_encoding = client.offset_encoding,
		server = client.server_info,
		capabilities = {
			completion = capabilities.completionProvider ~= nil,
			definition = capabilities.definitionProvider == true,
			hover = capabilities.hoverProvider == true,
			references = capabilities.referencesProvider == true,
			rename = capabilities.renameProvider ~= nil and capabilities.renameProvider ~= false,
			semantic_tokens = provider ~= nil,
		},
		semantic_legend = provider and {
			token_types = legend.tokenTypes,
			token_modifiers = legend.tokenModifiers,
		} or nil,
	}
end

local function highlight_graph()
	local names = sorted_unique(vim.fn.getcompletion("", "highlight"))
	local graph = {}
	for _, name in ipairs(names) do
		graph[#graph + 1] = { name = name, attributes = normalized_highlight(name) }
	end
	local canonical = vim.json.encode(graph)
	return { count = #graph, sha256 = vim.fn.sha256(canonical) }
end

local function module_source(name, member)
	local module = package.loaded[name]
	if not module then
		return "not-loaded"
	end
	local target = member and module[member] or module
	if type(target) ~= "function" then
		return "loaded-source-unavailable"
	end
	local source = debug.getinfo(target, "S").source
	return source:sub(1, 1) == "@" and source:sub(2) or source
end

local function command_output(command)
	local result = vim.system(command, { text = true }):wait()
	if result.code ~= 0 then
		fail(("command failed (%s): %s"):format(table.concat(command, " "), result.stderr or result.stdout))
	end
	return vim.trim(result.stdout)
end

local selected_tags = {
	rust = { "rust.binding.local_let", "rust.binding.struct_field" },
	c = { "c.binding.local_variable", "c.binding.struct_member" },
	cpp = { "cpp.binding.static_data_member", "cpp.binding.instance_member" },
	zig = { "zig.binding.local_const", "zig.binding.struct_field" },
	python = { "python.binding.local_binding", "python.binding.instance_attribute" },
}

local function selected_cases(spec, tags)
	local by_tag = {}
	for _, case in ipairs(spec.binding_cases or {}) do
		by_tag[case.tag] = case
	end
	local result = {}
	for _, tag in ipairs(tags) do
		if not by_tag[tag] then
			fail("selected manifest case is missing: " .. tag)
		end
		result[#result + 1] = by_tag[tag]
	end
	return result
end

local function assert_isolated_paths(root)
	for _, kind in ipairs({ "config", "data", "state", "cache" }) do
		local value = vim.fn.stdpath(kind)
		if value:sub(1, #root) ~= root then
			fail(("stdpath(%s) escaped E1 root: %s"):format(kind, value))
		end
	end
end

local function assert_runtime_isolation(root)
	local user_home = vim.env.HOME
	local forbidden = user_home
			and {
				user_home .. "/.config/nvim",
				user_home .. "/.local/share/nvim",
				user_home .. "/.local/state/nvim",
				user_home .. "/.cache/nvim",
			}
		or {}
	for _, path in ipairs(vim.opt.runtimepath:get()) do
		for _, prefix in ipairs(forbidden) do
			if path:sub(1, #prefix) == prefix then
				fail("runtimepath leaked a real user Neovim path: " .. path)
			end
		end
	end
	for _, source in pairs({
		module_source("catppuccin", "setup"),
		module_source("lazy", "setup"),
	}) do
		if source:sub(1, #root) ~= root then
			fail("plugin module source escaped E1 root: " .. source)
		end
	end
end

local function catppuccin_config_summary(expect_dx)
	local options = require("catppuccin").options
	for _, severity in ipairs({ "errors", "hints", "warnings", "information", "ok" }) do
		assert_equal(
			options.lsp_styles.virtual_text[severity],
			{ "nocombine" },
			"registered virtual-text UX drift for " .. severity
		)
	end
	assert_equal(options.lsp_styles.inlay_hints.background, false, "registered inlay-hint UX drift")
	for _, integration in ipairs({
		"blink_cmp",
		"fzf",
		"gitsigns",
		"mason",
		"render_markdown",
		"snacks",
		"treesitter",
		"which_key",
	}) do
		local setting = options.integrations[integration]
		local enabled = setting == true or (type(setting) == "table" and setting.enabled ~= false)
		assert_equal(enabled, true, "Catppuccin integration drift for " .. integration)
	end
	assert_equal(options.integrations.native_lsp.enabled, true, "native LSP integration drift")
	assert_equal(type(options.custom_highlights), expect_dx and "function" or "nil", "custom highlight ownership drift")
	return {
		custom_highlights = expect_dx and "M5/C4.4" or "none",
		virtual_text = "nocombine",
		inlay_hint_background = false,
		integrations = {
			"blink_cmp",
			"fzf",
			"gitsigns",
			"mason",
			"native_lsp",
			"render_markdown",
			"snacks",
			"treesitter",
			"which_key",
		},
	}
end

local function main()
	vim.opt.swapfile = false
	local case = vim.env.DOTFILES_NATIVE_FIRST_CASE
	local root = vim.env.DOTFILES_NATIVE_FIRST_ROOT
	local output = vim.env.DOTFILES_NATIVE_FIRST_OUTPUT
	if not case or not root or not output then
		fail("launcher environment is incomplete")
	end
	assert_isolated_paths(root)
	assert_runtime_isolation(root)

	local expectations = {
		m5 = { flavour = "mocha", background = "#1A1B2A", dx = true },
		["native-mocha"] = { flavour = "mocha", background = "#1E1E2E", dx = false },
		["native-macchiato"] = { flavour = "macchiato", background = "#24273A", dx = false },
		["native-frappe"] = { flavour = "frappe", background = "#303446", dx = false },
	}
	local expected = expectations[case]
	if not expected then
		fail("unsupported E1 case: " .. tostring(case))
	end

	local valid_colorschemes = {
		catppuccin = true,
		["catppuccin-mocha"] = true,
		["catppuccin-macchiato"] = true,
		["catppuccin-frappe"] = true,
	}
	if not valid_colorschemes[vim.g.colors_name] then
		fail("Catppuccin is not the active colorscheme: " .. tostring(vim.g.colors_name))
	end
	local actual_flavour = require("catppuccin").flavour
	assert_equal(actual_flavour, expected.flavour, "Catppuccin runtime flavour does not match case")
	assert_equal(normalized_highlight("Normal").bg, expected.background, "Normal background does not match case")
	assert_equal(package.loaded.theme ~= nil, expected.dx, "C4.4 theme module presence does not match case")
	assert_equal(vim.fn.hlexists("DxVariable") == 1, expected.dx, "Dx runtime group presence does not match case")
	local catppuccin_config = catppuccin_config_summary(expected.dx)

	local repo_root = vim.fs.root(0, ".git") or vim.fn.getcwd()
	local manifest = dofile(repo_root .. "/tests/nvim/color_manifest.lua")
	local lock = vim.json.decode(table.concat(vim.fn.readfile(vim.fn.stdpath("config") .. "/lazy-lock.json"), "\n"))
	local catppuccin_root = vim.fn.stdpath("data") .. "/lazy/catppuccin"
	local catppuccin_commit = command_output({ "git", "-C", catppuccin_root, "rev-parse", "HEAD" })
	assert_equal(
		catppuccin_commit,
		"edefef779ab08ce1a4a404713e3012b0d202bd35",
		"Catppuccin checkout drifted from E1 baseline"
	)
	assert_equal(lock.catppuccin.commit, catppuccin_commit, "Catppuccin checkout does not match lazy-lock.json")
	command_output({ "git", "-C", catppuccin_root, "diff", "--quiet" })
	pcall(require("lazy").load, { plugins = { "nvim-lspconfig" } })
	for _, name in ipairs({ "zls", "clangd", "rust_analyzer", "ruff", "ty" }) do
		vim.lsp.config(name, {
			capabilities = { workspace = { didChangeWatchedFiles = { dynamicRegistration = false } } },
		})
	end

	local report = {
		schema = 1,
		case = case,
		flavour = actual_flavour,
		base = "1eeb84a54fb7f37e58f2df62897b9268e20e7cb8",
		harness_status = "PASS",
		policy_verdict = "NOT_EVALUATED",
		neovim = vim.version(),
		catppuccin_commit = catppuccin_commit,
		catppuccin_config = catppuccin_config,
		normal = normalized_highlight("Normal"),
		stdpath = {},
		runtimepath = vim.opt.runtimepath:get(),
		load_sources = {
			catppuccin = module_source("catppuccin", "setup"),
			lazy = module_source("lazy", "setup"),
			theme = module_source("theme", "highlights"),
		},
		observations = {},
		languages = {},
	}
	for _, kind in ipairs({ "config", "data", "state", "cache" }) do
		report.stdpath[kind] = vim.fn.stdpath(kind)
	end

	for _, lang in ipairs({ "zig", "c", "cpp", "rust", "python" }) do
		local spec = manifest.languages[lang]
		vim.cmd.edit(vim.fn.fnameescape(repo_root .. "/" .. spec.path))
		local bufnr = vim.api.nvim_get_current_buf()
		if vim.bo[bufnr].filetype ~= spec.filetype then
			vim.bo[bufnr].filetype = spec.filetype
		end
		vim.treesitter.get_parser(bufnr, spec.filetype):parse()
		local clients = wait_for_clients(bufnr, spec.evidence_clients)
		vim.lsp.semantic_tokens.force_refresh(bufnr)

		local raw_by_name = {}
		local client_records = {}
		for name, client in pairs(clients) do
			client_records[#client_records + 1] = client_record(client)
			if client.server_capabilities.semanticTokensProvider then
				raw_by_name[name] = request_raw_semantic_tokens(bufnr, client)
			end
		end
		table.sort(client_records, function(left, right)
			return left.name < right.name
		end)
		report.languages[lang] = {
			filetype = spec.filetype,
			fixture = spec.path,
			clients = client_records,
			parser_sources = vim.api.nvim_get_runtime_file("parser/" .. spec.filetype .. ".so", true),
			query_sources = vim.api.nvim_get_runtime_file("queries/" .. spec.filetype .. "/highlights.scm", true),
		}
		if #report.languages[lang].parser_sources == 0 or #report.languages[lang].query_sources == 0 then
			fail("parser or highlight-query source is unavailable for " .. lang)
		end

		for _, evidence_case in ipairs(selected_cases(spec, selected_tags[lang])) do
			local row, column = locate_case(bufnr, evidence_case, lang)
			local ready = vim.wait(15000, function()
				return #decoded_tokens_at_position(bufnr, row, column, clients) > 0
			end, 100)
			if not ready then
				fail("semantic token did not arrive for " .. evidence_case.tag)
			end
			local raw = {}
			for _, raw_tokens in pairs(raw_by_name) do
				vim.list_extend(raw, raw_tokens_at_position(raw_tokens, row, column))
			end
			local decoded = decoded_tokens_at_position(bufnr, row, column, clients)
			assert_equal(decoded, comparable_tokens(raw), "raw/Neovim semantic-token drift for " .. evidence_case.tag)

			pcall(vim.api.nvim_win_set_cursor, 0, { row + 1, column })
			vim.cmd.redraw()
			local inspected
			local settled = vim.wait(15000, function()
				inspected = vim.inspect_pos(bufnr, row, column)
				return #foreground_candidates(inspected) > 0
			end, 100)
			if not settled then
				fail("highlight application did not settle for " .. evidence_case.tag)
			end
			local candidates = foreground_candidates(inspected)
			report.observations[#report.observations + 1] = {
				language = lang,
				tag = evidence_case.tag,
				token = evidence_case.token,
				source_semantics = evidence_case.semantic_description,
				policy_baseline = evidence_case.evidence.effective,
				position = { row = row, byte_column = column },
				treesitter = tree_sitter_captures(inspected),
				raw_semantic_tokens = raw,
				decoded_semantic_tokens = decoded,
				applied_semantic_groups = applied_semantic_groups(inspected),
				foreground_candidates = candidates,
				effective = candidates[1],
			}
		end

		local attached = vim.lsp.get_clients({ bufnr = bufnr })
		vim.cmd.bdelete({ bang = true })
		vim.lsp.stop_client(attached, false)
		if
			not vim.wait(5000, function()
				for _, client in ipairs(attached) do
					if vim.lsp.get_client_by_id(client.id) then
						return false
					end
				end
				return true
			end, 50)
		then
			fail("LSP clients did not stop after " .. lang)
		end
	end

	assert_equal(#report.observations, 10, "E1 observation count changed")
	report.highlight_graph = highlight_graph()
	local encoded = vim.json.encode(report)
	local handle, open_error = io.open(output, "wb")
	if not handle then
		fail("cannot create evidence output: " .. tostring(open_error))
	end
	handle:write(encoded)
	handle:write("\n")
	handle:close()
	print(("Native-first E1 harness passed: %s (10 observations)"):format(case))
end

main()
