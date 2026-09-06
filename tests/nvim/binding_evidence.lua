--- DX-COLOR-003 M2A/M2B binding and classification runtime evidence contract.
--- Observes production Tree-sitter/LSP state and fails closed on evidence drift.

local function fail(message)
	error("M2_BINDING_EVIDENCE_FAILURE: " .. message, 2)
end

local function assert_equal(actual, expected, message)
	if not vim.deep_equal(actual, expected) then
		fail(("%s\n  expected: %s\n  observed: %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
	end
end

local function sorted_enabled_keys(enabled)
	local result = {}
	for key, value in pairs(enabled or {}) do
		if value then
			result[#result + 1] = key
		end
	end
	table.sort(result)
	return result
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

local function assert_contains(values, expected, message)
	if not vim.tbl_contains(values, expected) then
		fail(("%s\n  expected member: %s\n  observed: %s"):format(message, expected, vim.inspect(values)))
	end
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

local function tree_sitter_captures(inspected)
	local captures = {}
	for _, capture in ipairs(inspected.treesitter or {}) do
		captures[#captures + 1] = capture.capture
	end
	return sorted_unique(captures)
end

local function foreground_candidates(inspected)
	local candidates = {}
	local priorities = vim.hl and vim.hl.priorities or {}

	for index, token in ipairs(inspected.semantic_tokens or {}) do
		local group = token.opts and token.opts.hl_group
		if group then
			local highlight = vim.api.nvim_get_hl(0, { name = group, link = false })
			if highlight.fg then
				candidates[#candidates + 1] = {
					group = group,
					source = "lsp",
					priority = tonumber(token.opts.priority) or priorities.semantic_tokens or 125,
					order = index,
					foreground = highlight.fg,
				}
			end
		end
	end

	for index, capture in ipairs(inspected.treesitter or {}) do
		local group = capture.hl_group or ("@" .. capture.capture)
		local highlight = vim.api.nvim_get_hl(0, { name = group, link = false })
		if highlight.fg then
			local raw_priority = (capture.metadata and capture.metadata.priority)
				or (
					capture.metadata
					and capture.id
					and capture.metadata[capture.id]
					and capture.metadata[capture.id].priority
				)
			candidates[#candidates + 1] = {
				group = group,
				source = "treesitter",
				priority = tonumber(raw_priority) or priorities.treesitter or 100,
				order = index,
				foreground = highlight.fg,
			}
		end
	end

	for index, syntax in ipairs(inspected.syntax or {}) do
		local group = syntax.hl_group
		if group then
			local highlight = vim.api.nvim_get_hl(0, { name = group, link = false })
			if highlight.fg then
				candidates[#candidates + 1] = {
					group = group,
					source = "syntax",
					priority = priorities.syntax or 50,
					order = index,
					foreground = highlight.fg,
				}
			end
		end
	end

	table.sort(candidates, function(left, right)
		if left.priority ~= right.priority then
			return left.priority > right.priority
		end
		return left.order > right.order
	end)
	return candidates
end

local function role_for_group(group)
	local roles = require("theme.domain").roles
	local candidate = group
	local visited = {}

	while candidate and not visited[candidate] do
		visited[candidate] = true
		if roles[candidate] then
			return candidate
		end

		local highlight = vim.api.nvim_get_hl(0, { name = candidate, link = true })
		if highlight.link then
			candidate = highlight.link
		elseif candidate:sub(1, 1) == "@" and candidate:find("%.") then
			candidate = candidate:match("^(.*)%.[^.]+$")
		else
			candidate = nil
		end
	end

	return nil
end

local function role_foreground(role)
	local highlight = vim.api.nvim_get_hl(0, { name = role, link = false })
	if not highlight.fg then
		fail("DX role has no resolved foreground: " .. role)
	end
	return highlight.fg
end

local function assert_role_foreground(actual, role, message)
	assert_equal(actual, role_foreground(role), message)
end

local function verify_effective_foreground_negative_control()
	local group = "@lsp.type.variable.dx004WrongForeground"
	vim.api.nvim_set_hl(0, group, { fg = "#ff0000" })

	assert_equal(role_for_group(group), "DxVariable", "negative-control topology must still resolve to DxVariable")
	local accepted = pcall(function()
		local highlight = vim.api.nvim_get_hl(0, { name = group, link = false })
		assert_role_foreground(
			highlight.fg,
			"DxVariable",
			"negative-control direct foreground must not inherit parent semantic authority"
		)
	end)

	vim.api.nvim_set_hl(0, group, {})
	if accepted then
		fail("wrong direct child foreground bypassed effective-foreground evidence")
	end
end

local function expected_semantic_groups(token, filetype)
	local priorities = vim.hl and vim.hl.priorities or {}
	local base_priority = priorities.semantic_tokens or 125
	local groups = {
		{ group = ("@lsp.type.%s.%s"):format(token.type, filetype), priority = base_priority },
	}
	for _, modifier in ipairs(token.modifiers) do
		groups[#groups + 1] = {
			group = ("@lsp.mod.%s.%s"):format(modifier, filetype),
			priority = base_priority + 1,
		}
		groups[#groups + 1] = {
			group = ("@lsp.typemod.%s.%s.%s"):format(token.type, modifier, filetype),
			priority = base_priority + 2,
		}
	end
	table.sort(groups, function(left, right)
		return left.group < right.group
	end)
	return groups
end

local function semantic_application(inspected, token, filetype, tag)
	local priorities = vim.hl and vim.hl.priorities or {}
	local base_priority = priorities.semantic_tokens or 125
	local groups = {}
	local foregrounds = {}
	local seen = {}
	for _, applied in ipairs(inspected.semantic_tokens or {}) do
		local group = applied.opts and applied.opts.hl_group
		if group then
			if seen[group] then
				fail(("duplicate Neovim semantic highlight for %s: %s"):format(tag, group))
			end
			seen[group] = true
			local priority = tonumber(applied.opts.priority) or base_priority
			groups[#groups + 1] = { group = group, priority = priority }
			local highlight = vim.api.nvim_get_hl(0, { name = group, link = false })
			if highlight.fg then
				local role = role_for_group(group)
				if not role then
					fail(
						("semantic foreground for %s does not resolve through DX link topology: %s"):format(tag, group)
					)
				end
				assert_role_foreground(highlight.fg, role, ("semantic foreground drift for %s: %s"):format(tag, group))
				foregrounds[#foregrounds + 1] = {
					group = group,
					priority_delta = priority - base_priority,
					role = role,
				}
			end
		end
	end
	table.sort(groups, function(left, right)
		return left.group < right.group
	end)
	table.sort(foregrounds, function(left, right)
		return left.group < right.group
	end)
	assert_equal(groups, expected_semantic_groups(token, filetype), "Neovim-applied semantic groups drift for " .. tag)
	return { groups = groups, foregrounds = foregrounds }
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
		local client = by_name[expected.name]
		local has_semantic_tokens = client.server_capabilities.semanticTokensProvider ~= nil
		assert_equal(
			has_semantic_tokens,
			expected.semantic_tokens,
			("semantic-token capability drift for client %s"):format(expected.name)
		)
		if expected.legend then
			local provider = client.server_capabilities.semanticTokensProvider
			if not provider or type(provider.legend) ~= "table" then
				fail(("semantic-token legend missing for client %s"):format(expected.name))
			end
			for _, token_type in ipairs(expected.legend.token_types or {}) do
				assert_contains(
					provider.legend.tokenTypes or {},
					token_type,
					("semantic-token type legend drift for client %s"):format(expected.name)
				)
			end
			for _, modifier in ipairs(expected.legend.token_modifiers or {}) do
				assert_contains(
					provider.legend.tokenModifiers or {},
					modifier,
					("semantic-token modifier legend drift for client %s"):format(expected.name)
				)
			end
		end
	end
	for name in pairs(by_name) do
		if not expected_names[name] then
			fail(("undeclared LSP client attached to evidence fixture: %s"):format(name))
		end
	end
	return by_name
end

local function print_client_topology(lang, clients_by_name)
	local names = vim.tbl_keys(clients_by_name)
	table.sort(names)
	for _, name in ipairs(names) do
		local client = clients_by_name[name]
		local provider = client.server_capabilities.semanticTokensProvider
		local legend = provider and provider.legend or {}
		local server_info = client.server_info or {}
		io.stdout:write(
			("[M2 CLIENT] %s | id=%d | name=%s | server=%s | version=%s | semantic=%s | types=%s | modifiers=%s\n"):format(
				lang,
				client.id,
				client.name,
				server_info.name or "unreported",
				server_info.version or "unreported",
				provider and "true" or "false",
				table.concat(legend.tokenTypes or {}, ","),
				table.concat(legend.tokenModifiers or {}, ",")
			)
		)
		io.stdout:flush()
	end
end

local function decode_modifier_bits(bits, legend, provider)
	local modifiers = {}
	local index = 1
	while bits > 0 do
		if bits % 2 == 1 then
			local modifier = legend[index]
			if not modifier then
				fail(("raw semantic token from %s references unknown modifier bit %d"):format(provider, index - 1))
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
	local semantic_provider = client.server_capabilities.semanticTokensProvider
	local legend = semantic_provider and semantic_provider.legend
	if type(legend) ~= "table" or type(legend.tokenTypes) ~= "table" or type(legend.tokenModifiers) ~= "table" then
		fail("semantic-token legend unavailable for raw request: " .. client.name)
	end

	local response, request_error = client:request_sync(
		"textDocument/semanticTokens/full",
		{ textDocument = vim.lsp.util.make_text_document_params(bufnr) },
		15000,
		bufnr
	)
	if not response then
		fail(("raw semantic-token request failed for %s: %s"):format(client.name, tostring(request_error)))
	end
	if response.err then
		fail(("raw semantic-token response failed for %s: %s"):format(client.name, vim.inspect(response.err)))
	end
	if type(response.result) ~= "table" or type(response.result.data) ~= "table" then
		fail(("raw semantic-token response has no full token data for %s"):format(client.name))
	end
	if #response.result.data % 5 ~= 0 then
		fail(("raw semantic-token data length is invalid for %s: %d"):format(client.name, #response.result.data))
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
		local token_type = legend.tokenTypes[type_index + 1]
		if not token_type then
			fail(("raw semantic token from %s references unknown type index %d"):format(client.name, type_index))
		end
		local line = lines[row + 1]
		if line == nil then
			fail(("raw semantic token from %s references missing row %d"):format(client.name, row))
		end
		local start_col = vim.str_byteindex(line, client.offset_encoding, start_character, false)
		local end_col = vim.str_byteindex(line, client.offset_encoding, start_character + length, false)
		tokens[#tokens + 1] = {
			provider = client.name,
			row = row,
			start_col = start_col,
			end_col = end_col,
			type = token_type,
			modifiers = decode_modifier_bits(response.result.data[index + 4], legend.tokenModifiers, client.name),
		}
	end
	return tokens
end

local function raw_tokens_at_position(raw_tokens_by_name, row, column)
	local tokens = {}
	for _, raw_tokens in pairs(raw_tokens_by_name) do
		for _, token in ipairs(raw_tokens) do
			if token.row == row and token.start_col <= column and column < token.end_col then
				tokens[#tokens + 1] = {
					provider = token.provider,
					type = token.type,
					modifiers = token.modifiers,
				}
			end
		end
	end
	table.sort(tokens, function(left, right)
		local left_key = left.provider .. ":" .. tostring(left.type) .. ":" .. table.concat(left.modifiers, ",")
		local right_key = right.provider .. ":" .. tostring(right.type) .. ":" .. table.concat(right.modifiers, ",")
		return left_key < right_key
	end)
	return tokens
end

local function tokens_at_position(bufnr, row, column, clients_by_name)
	local by_id = {}
	for name, client in pairs(clients_by_name) do
		by_id[client.id] = name
	end

	local tokens = {}
	for _, token in ipairs(vim.lsp.semantic_tokens.get_at_pos(bufnr, row, column) or {}) do
		local provider = by_id[token.client_id]
		if not provider then
			fail(("semantic token came from undeclared client id %s"):format(tostring(token.client_id)))
		end
		tokens[#tokens + 1] = {
			provider = provider,
			type = token.type,
			modifiers = sorted_enabled_keys(token.modifiers),
		}
	end
	table.sort(tokens, function(left, right)
		local left_key = left.provider .. ":" .. tostring(left.type) .. ":" .. table.concat(left.modifiers, ",")
		local right_key = right.provider .. ":" .. tostring(right.type) .. ":" .. table.concat(right.modifiers, ",")
		return left_key < right_key
	end)
	return tokens
end

local function capture_case(bufnr, case, lang, spec, clients_by_name, raw_tokens_by_name)
	local expected = case.evidence
	if type(expected) ~= "table" or type(expected.lsp) ~= "table" or type(expected.effective) ~= "table" then
		fail("incomplete evidence manifest entry: " .. case.tag)
	end
	local provider = clients_by_name[expected.lsp.provider]
	if not provider or provider.server_capabilities.semanticTokensProvider == nil then
		fail(("declared semantic provider unavailable for %s: %s"):format(case.tag, expected.lsp.provider))
	end

	local row, column = locate_case(bufnr, case, lang)
	local ready = vim.wait(15000, function()
		for _, token in ipairs(tokens_at_position(bufnr, row, column, clients_by_name)) do
			if token.provider == expected.lsp.provider then
				return true
			end
		end
		return false
	end, 100)
	if not ready then
		fail(("semantic token did not arrive for %s from %s"):format(case.tag, expected.lsp.provider))
	end

	local tokens = tokens_at_position(bufnr, row, column, clients_by_name)
	local protocol_tokens = raw_tokens_at_position(raw_tokens_by_name, row, column)
	assert_equal(protocol_tokens, { expected.lsp }, "raw semanticTokens/full evidence drift for " .. case.tag)
	assert_equal(tokens, protocol_tokens, "Neovim semantic-token decoder drift for " .. case.tag)

	local expected_client = clients_by_name[spec.evidence_client]
	if not expected_client then
		fail(("expected interactive client missing for %s: %s"):format(case.tag, spec.evidence_client))
	end
	if expected_client.server_capabilities.semanticTokensProvider == nil then
		for _, token in ipairs(tokens) do
			if token.provider == spec.evidence_client then
				fail(
					("non-semantic client unexpectedly emitted a token for %s: %s"):format(
						case.tag,
						spec.evidence_client
					)
				)
			end
		end
	end

	pcall(vim.api.nvim_win_set_cursor, 0, { row + 1, column })
	vim.cmd.redraw()
	local inspected
	local rendered = vim.wait(15000, function()
		inspected = vim.inspect_pos(bufnr, row, column)
		local candidate = foreground_candidates(inspected)[1]
		return candidate and candidate.group == expected.effective.group
	end, 100)
	if not rendered then
		fail(("effective highlight did not settle for %s (expected %s)"):format(case.tag, expected.effective.group))
	end
	local captures = tree_sitter_captures(inspected)
	assert_equal(captures, expected.treesitter, "Tree-sitter evidence drift for " .. case.tag)

	local winner = foreground_candidates(inspected)[1]
	if not winner then
		fail("no effective foreground candidate for " .. case.tag)
	end
	assert_equal(winner.group, expected.effective.group, "effective highlight group drift for " .. case.tag)
	assert_equal(winner.source, expected.effective.source, "effective authority drift for " .. case.tag)
	assert_equal(role_for_group(winner.group), expected.effective.role, "effective Dx role drift for " .. case.tag)
	assert_role_foreground(winner.foreground, expected.effective.role, "effective foreground drift for " .. case.tag)

	local application
	if expected.applied_foregrounds then
		application = semantic_application(inspected, expected.lsp, spec.filetype, case.tag)
		assert_equal(
			application.foregrounds,
			expected.applied_foregrounds,
			"Neovim semantic foreground competition drift for " .. case.tag
		)
		if expected.require_unique_top_foreground then
			local top_priority
			local top_groups = {}
			for _, foreground in ipairs(application.foregrounds) do
				if top_priority == nil or foreground.priority_delta > top_priority then
					top_priority = foreground.priority_delta
					top_groups = { foreground.group }
				elseif foreground.priority_delta == top_priority then
					top_groups[#top_groups + 1] = foreground.group
				end
			end
			assert_equal(
				top_groups,
				{ expected.effective.group },
				"equal-priority semantic foreground competition detected for " .. case.tag
			)
		end
	end

	local observation = {
		tag = case.tag,
		treesitter = captures,
		lsp = tokens[1],
		effective = {
			group = winner.group,
			source = winner.source,
			role = expected.effective.role,
		},
		application = application,
	}
	io.stdout:write(
		("[M2 EVIDENCE] %s | TS=%s | expected=%s | LSP=%s:%s[%s] | effective=%s->%s\n"):format(
			case.tag,
			table.concat(captures, "+"),
			spec.evidence_client,
			observation.lsp.provider,
			observation.lsp.type,
			table.concat(observation.lsp.modifiers, "+"),
			observation.effective.group,
			observation.effective.role
		)
	)
	io.stdout:flush()
	if observation.application then
		local applied_groups = {}
		for _, applied in ipairs(observation.application.groups) do
			applied_groups[#applied_groups + 1] = ("%s@%d"):format(applied.group, applied.priority)
		end
		local foregrounds = {}
		for _, applied in ipairs(observation.application.foregrounds) do
			foregrounds[#foregrounds + 1] = ("%s@+%d->%s"):format(applied.group, applied.priority_delta, applied.role)
		end
		io.stdout:write(
			("[M2B APPLICATION] %s | source=%s/%s | groups=%s | foregrounds=%s | winner=%s->%s\n"):format(
				case.tag,
				case.source_identity,
				case.occurrence,
				table.concat(applied_groups, ","),
				table.concat(foregrounds, ","),
				observation.effective.group,
				observation.effective.role
			)
		)
		io.stdout:flush()
	end
	return observation
end

local function signature(observation, producer)
	if producer == "treesitter" then
		return table.concat(observation.treesitter, "\0")
	end
	local token = observation.lsp
	return token.provider .. "\0" .. token.type .. "\0" .. table.concat(token.modifiers, "\0")
end

local function main()
	vim.opt.swapfile = false
	local colorscheme = vim.g.colors_name
	if colorscheme ~= "tokyonight-storm" then
		fail("production TokyoNight Storm colorscheme is not active")
	end

	local domain = require("theme.domain")
	assert_equal(vim.tbl_count(domain.roles), 23, "M2A must preserve the 23-role domain closure")
	assert_equal(domain.roles.DxModuleBinding, nil, "M2A must not admit DxModuleBinding")
	verify_effective_foreground_negative_control()
	print("M2 effective role and foreground evidence negative control passed.")

	local repo_root = vim.fs.root(0, ".git") or vim.fn.getcwd()
	local manifest = dofile(repo_root .. "/tests/nvim/color_manifest.lua")
	pcall(require("lazy").load, { plugins = { "nvim-lspconfig" } })

	-- Recursive workspace watchers are irrelevant to immutable fixtures and can
	-- exhaust macOS's per-process kqueue budget in a multi-provider run.
	for _, name in ipairs({ "zls", "clangd", "rust_analyzer", "pyright", "ruff", "ty" }) do
		vim.lsp.config(name, {
			capabilities = {
				workspace = { didChangeWatchedFiles = { dynamicRegistration = false } },
			},
		})
	end

	local observations = {}
	local classification_observations = {}
	local correction_observations = {}
	local case_count = 0
	local classification_count = 0
	local correction_count = 0
	for _, lang in ipairs({ "zig", "c", "cpp", "rust", "python" }) do
		local spec = manifest.languages[lang]
		if not spec or not spec.evidence_client or not spec.evidence_clients then
			fail("language evidence metadata missing: " .. lang)
		end

		vim.cmd.edit(vim.fn.fnameescape(repo_root .. "/" .. spec.path))
		local bufnr = vim.api.nvim_get_current_buf()
		if vim.bo[bufnr].filetype ~= spec.filetype then
			vim.bo[bufnr].filetype = spec.filetype
		end
		vim.treesitter.get_parser(bufnr, spec.filetype):parse()
		local clients_by_name = wait_for_clients(bufnr, spec.evidence_clients)
		print_client_topology(lang, clients_by_name)
		vim.lsp.semantic_tokens.force_refresh(bufnr)
		local raw_tokens_by_name = {}
		for name, client in pairs(clients_by_name) do
			if client.server_capabilities.semanticTokensProvider ~= nil then
				raw_tokens_by_name[name] = request_raw_semantic_tokens(bufnr, client)
			end
		end

		for _, case in ipairs(spec.binding_cases or {}) do
			if observations[case.tag] then
				fail("duplicate binding evidence tag: " .. case.tag)
			end
			observations[case.tag] = capture_case(bufnr, case, lang, spec, clients_by_name, raw_tokens_by_name)
			case_count = case_count + 1
		end
		if lang == "cpp" then
			local review = manifest.classification_reviews and manifest.classification_reviews.cpp_static_data_member
			if not review or type(review.cases) ~= "table" then
				fail("M2B C++ static data member review is missing")
			end
			for _, case in ipairs(review.cases) do
				if observations[case.tag] or classification_observations[case.tag] then
					fail("duplicate M2B classification evidence tag: " .. case.tag)
				end
				classification_observations[case.tag] =
					capture_case(bufnr, case, lang, spec, clients_by_name, raw_tokens_by_name)
				classification_count = classification_count + 1
			end

			local correction = manifest.behavior_corrections and manifest.behavior_corrections.cpp_static_data_member
			if not correction or type(correction.additional_cases) ~= "table" then
				fail("M2B-B C++ static data member behavior correction is missing")
			end
			for _, case in ipairs(correction.additional_cases) do
				if
					observations[case.tag]
					or classification_observations[case.tag]
					or correction_observations[case.tag]
				then
					fail("duplicate M2B-B behavior evidence tag: " .. case.tag)
				end
				correction_observations[case.tag] =
					capture_case(bufnr, case, lang, spec, clients_by_name, raw_tokens_by_name)
				correction_count = correction_count + 1
			end
		end

		local attached_clients = vim.lsp.get_clients({ bufnr = bufnr })
		vim.cmd.bdelete({ bang = true })
		vim.lsp.stop_client(attached_clients, false)
		local stopped = vim.wait(5000, function()
			for _, client in ipairs(attached_clients) do
				if vim.lsp.get_client_by_id(client.id) then
					return false
				end
			end
			return true
		end, 50)
		if not stopped then
			fail("LSP clients did not stop cleanly after " .. lang)
		end
	end

	assert_equal(case_count, 28, "binding evidence case count changed")
	for _, comparison in ipairs(manifest.binding_comparisons or {}) do
		local left = observations[comparison.left]
		local right = observations[comparison.right]
		if not left or not right then
			fail("comparison references missing evidence: " .. comparison.axis)
		end
		assert_equal(
			signature(left, "treesitter") ~= signature(right, "treesitter"),
			comparison.treesitter_distinguishes,
			"Tree-sitter distinction drift: " .. comparison.axis
		)
		assert_equal(
			signature(left, "lsp") ~= signature(right, "lsp"),
			comparison.lsp_distinguishes,
			"LSP distinction drift: " .. comparison.axis
		)
	end

	local review = manifest.classification_reviews and manifest.classification_reviews.cpp_static_data_member
	if not review then
		fail("M2B classification review metadata missing")
	end
	assert_equal(classification_count, 7, "M2B C++ classification evidence case count changed")
	local observed_tags = vim.tbl_keys(classification_observations)
	table.sort(observed_tags)
	local declared_tags = vim.deepcopy(review.case_tags or {})
	table.sort(declared_tags)
	assert_equal(observed_tags, declared_tags, "M2B classification case topology drift")
	local allowed_decisions = {
		["RECLASSIFY STATIC DATA MEMBER TO DxMember"] = true,
		["KEEP STATIC DATA MEMBER AS DxVariable"] = true,
		["DEFER STATIC DATA MEMBER CLASSIFICATION"] = true,
	}
	if not allowed_decisions[review.decision] then
		fail("M2B classification decision is not one of the three authorized outcomes")
	end

	local correction = manifest.behavior_corrections and manifest.behavior_corrections.cpp_static_data_member
	if not correction then
		fail("M2B-B behavior correction metadata missing")
	end
	assert_equal(correction.decision, review.decision, "M2B-B behavior correction changed the approved decision")
	assert_equal(correction_count, 6, "M2B-B additional behavior-case count changed")
	local all_behavior_observations = vim.tbl_extend("error", classification_observations, correction_observations)
	local behavior_categories = {
		correction.positive_case_tags,
		correction.preserved_member_case_tags,
		correction.negative_control_tags,
	}
	local categorized = {}
	for _, tags in ipairs(behavior_categories) do
		for _, tag in ipairs(tags or {}) do
			if categorized[tag] then
				fail("M2B-B behavior case appears in multiple categories: " .. tag)
			end
			if not all_behavior_observations[tag] then
				fail("M2B-B behavior category references missing observation: " .. tag)
			end
			categorized[tag] = true
		end
	end
	assert_equal(vim.tbl_count(all_behavior_observations), 13, "M2B-B behavior observation count changed")
	assert_equal(vim.tbl_count(categorized), 13, "M2B-B behavior category topology changed")

	print(
		("M2A binding-topology evidence passed: %d/28 cases, %d/%d comparisons."):format(
			case_count,
			#manifest.binding_comparisons,
			#manifest.binding_comparisons
		)
	)
	print(
		("M2B static-data-member evidence passed: %d/7 cases; decision: %s"):format(
			classification_count,
			review.decision
		)
	)
	print(
		("M2B-B static-data-member behavior correction passed: %d/13 cases; decision: %s"):format(
			vim.tbl_count(all_behavior_observations),
			correction.decision
		)
	)
end

local ok, err = xpcall(main, debug.traceback)
if not ok then
	io.stderr:write(("\n!!! M2 BINDING EVIDENCE FAILURE !!!\n%s\n"):format(tostring(err)))
	vim.api.nvim_err_writeln(("\n!!! M2 BINDING EVIDENCE FAILURE !!!\n%s\n"):format(tostring(err)))
	vim.cmd("cquit 1")
end
