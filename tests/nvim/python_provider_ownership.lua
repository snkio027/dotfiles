--- DX-COLOR-003 M2C-A Python provider-ownership runtime evidence.
--- Observes either production startup or the isolated Ty-excluded control.

local function fail(message)
	error("M2C_PROVIDER_OWNERSHIP_FAILURE: " .. message, 2)
end

local function assert_equal(actual, expected, message)
	if not vim.deep_equal(actual, expected) then
		fail(("%s\n  expected: %s\n  observed: %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
	end
end

local function sorted(values)
	table.sort(values)
	return values
end

local function sorted_keys(values)
	local keys = {}
	for key, value in pairs(values or {}) do
		if value then
			keys[#keys + 1] = key
		end
	end
	return sorted(keys)
end

local function contains(values, expected)
	return vim.tbl_contains(values, expected)
end

local function read_json(path)
	local ok, lines = pcall(vim.fn.readfile, path)
	if not ok then
		fail("could not read JSON evidence: " .. path)
	end
	return vim.json.decode(table.concat(lines, "\n"))
end

local function lazy_server_state(server)
	local opts = LazyVim.opts("nvim-lspconfig")
	local config = opts.servers and opts.servers[server]
	if config == nil then
		return "absent"
	end
	if type(config) == "table" and config.enabled == false then
		return "disabled"
	end
	return "enabled"
end

local function capability_summary(client)
	local capabilities = client.server_capabilities
	local function supported(name)
		local value = capabilities[name]
		return value ~= nil and value ~= false
	end
	return {
		semantic_tokens = supported("semanticTokensProvider"),
		completion = supported("completionProvider"),
		hover = supported("hoverProvider"),
		definition = supported("definitionProvider"),
		references = supported("referencesProvider"),
		rename = supported("renameProvider"),
		code_action = supported("codeActionProvider"),
	}
end

local function locate_probe(bufnr, probe)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	for marker_line, line in ipairs(lines) do
		if line:find(probe.tag, 1, true) then
			for candidate_line = marker_line + 1, math.min(#lines, marker_line + 10) do
				local candidate = lines[candidate_line]
				if vim.trim(candidate):sub(1, 1) ~= "#" then
					local column = candidate:find("%f[%w_]" .. vim.pesc(probe.token) .. "%f[^%w_]")
					if column then
						return candidate_line - 1, column - 1
					end
				end
			end
		end
	end
	fail("semantic probe locator failed: " .. probe.tag)
end

local function decode_modifier_bits(bits, legend)
	local modifiers = {}
	local index = 1
	while bits > 0 do
		if bits % 2 == 1 then
			local modifier = legend[index]
			if not modifier then
				fail(("raw Ty token references unknown modifier bit %d"):format(index - 1))
			end
			modifiers[#modifiers + 1] = modifier
		end
		bits = math.floor(bits / 2)
		index = index + 1
	end
	return sorted(modifiers)
end

local function request_raw_tokens(bufnr, client)
	local provider = client.server_capabilities.semanticTokensProvider
	local legend = provider and provider.legend
	if type(legend) ~= "table" or type(legend.tokenTypes) ~= "table" or type(legend.tokenModifiers) ~= "table" then
		fail("Ty semantic-token legend is unavailable")
	end
	local response, request_error = client:request_sync(
		"textDocument/semanticTokens/full",
		{ textDocument = vim.lsp.util.make_text_document_params(bufnr) },
		15000,
		bufnr
	)
	if not response then
		fail("raw Ty semantic-token request failed: " .. tostring(request_error))
	end
	if response.err then
		fail("raw Ty semantic-token response failed: " .. vim.inspect(response.err))
	end
	local data = response.result and response.result.data
	if type(data) ~= "table" or #data % 5 ~= 0 then
		fail("raw Ty semantic-token response does not contain valid full-token data")
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local tokens = {}
	local row
	local start_character = 0
	for index = 1, #data, 5 do
		local delta_line = data[index]
		row = row and row + delta_line or delta_line
		start_character = delta_line == 0 and start_character + data[index + 1] or data[index + 1]
		local line = lines[row + 1]
		if line == nil then
			fail(("raw Ty token references missing row %d"):format(row))
		end
		local token_type = legend.tokenTypes[data[index + 3] + 1]
		if not token_type then
			fail(("raw Ty token references unknown type index %d"):format(data[index + 3]))
		end
		local start_col = vim.str_byteindex(line, client.offset_encoding, start_character, false)
		local end_col = vim.str_byteindex(line, client.offset_encoding, start_character + data[index + 2], false)
		tokens[#tokens + 1] = {
			client_id = client.id,
			provider = client.name,
			row = row,
			start_col = start_col,
			end_col = end_col,
			type = token_type,
			modifiers = decode_modifier_bits(data[index + 4], legend.tokenModifiers),
		}
	end
	return tokens
end

local function raw_at_position(tokens, row, column)
	local found = {}
	for _, token in ipairs(tokens) do
		if token.row == row and token.start_col <= column and column < token.end_col then
			found[#found + 1] = {
				client_id = token.client_id,
				provider = token.provider,
				type = token.type,
				modifiers = token.modifiers,
			}
		end
	end
	return found
end

local function neovim_at_position(bufnr, row, column, known_clients)
	local found = {}
	for _, token in ipairs(vim.lsp.semantic_tokens.get_at_pos(bufnr, row, column) or {}) do
		local client = known_clients[token.client_id]
		if not client then
			fail("Neovim applied a semantic token from an unknown client ID: " .. tostring(token.client_id))
		end
		found[#found + 1] = {
			client_id = token.client_id,
			provider = client.name,
			type = token.type,
			modifiers = sorted_keys(token.modifiers),
		}
	end
	table.sort(found, function(left, right)
		return left.client_id < right.client_id
	end)
	return found
end

local function roles_for_foreground(foreground)
	local roles = {}
	for role in pairs(require("theme.domain").roles) do
		if vim.api.nvim_get_hl(0, { name = role, link = false }).fg == foreground then
			roles[#roles + 1] = role
		end
	end
	return sorted(roles)
end

local function semantic_application(bufnr, row, column)
	vim.api.nvim_win_set_cursor(0, { row + 1, column })
	vim.cmd.redraw()
	local inspected = vim.inspect_pos(bufnr, row, column)
	local groups = {}
	local foregrounds = {}
	local priorities = vim.hl and vim.hl.priorities or {}
	for _, applied in ipairs(inspected.semantic_tokens or {}) do
		local group = applied.opts and applied.opts.hl_group
		if group then
			local priority = tonumber(applied.opts.priority) or priorities.semantic_tokens or 125
			groups[#groups + 1] = { group = group, priority = priority }
			local highlight = vim.api.nvim_get_hl(0, { name = group, link = false })
			if highlight.fg then
				local roles = roles_for_foreground(highlight.fg)
				if #roles ~= 1 then
					fail(
						("semantic foreground does not resolve to one DX role: %s -> %s"):format(
							group,
							vim.inspect(roles)
						)
					)
				end
				foregrounds[#foregrounds + 1] = { group = group, priority = priority, role = roles[1] }
			end
		end
	end
	table.sort(groups, function(left, right)
		return left.group < right.group
	end)
	table.sort(foregrounds, function(left, right)
		if left.priority ~= right.priority then
			return left.priority > right.priority
		end
		return left.group < right.group
	end)
	return groups, foregrounds
end

local function main()
	vim.opt.swapfile = false
	local mode = vim.env.M2C_MODE
	if mode ~= "production" and mode ~= "ty-excluded" then
		fail("M2C_MODE must be production or ty-excluded")
	end
	local report_path = vim.env.M2C_REPORT_PATH
	if report_path == nil or report_path == "" then
		fail("M2C_REPORT_PATH is required")
	end
	if type(_G.DX_M2C_ENABLE_TRACE) ~= "table" then
		fail("pre-init vim.lsp.enable trace is missing")
	end

	local repo_root = vim.fs.root(0, ".git") or vim.fn.getcwd()
	local manifest = dofile(repo_root .. "/tests/nvim/python_provider_ownership_manifest.lua")
	local expected = mode == "production" and manifest.production or manifest.ty_excluded

	local loaded, load_error = pcall(require("lazy").load, { plugins = { "nvim-lspconfig" } })
	if not loaded then
		fail("could not load nvim-lspconfig: " .. tostring(load_error))
	end

	local lazy_state = {}
	for _, name in ipairs({ "pyright", "ruff", "ty" }) do
		lazy_state[name] = lazy_server_state(name)
	end
	assert_equal(lazy_state, expected.lazy_server_state, "effective LazyVim Python server configuration drifted")

	local mason_opts = LazyVim.opts("mason.nvim")
	local ty_entries = 0
	for _, tool in ipairs(mason_opts.ensure_installed or {}) do
		if tool == "ty" then
			ty_entries = ty_entries + 1
		end
	end
	assert_equal(ty_entries, 1, "Ty must be installed exactly once through the Mason tool manifest")

	local registry = require("mason-registry")
	local ty_package = registry.get_package("ty")
	assert_equal(ty_package:is_installed(), true, "Mason Ty package is not installed")
	local receipt_path = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "packages", "ty", "mason-receipt.json")
	local receipt = read_json(receipt_path)
	assert_equal(receipt.name, "ty", "Mason Ty receipt name drifted")
	local ty_binary = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin", "ty")
	assert_equal(vim.fn.executable(ty_binary), 1, "Mason Ty executable is unavailable")

	local mappings = require("mason-lspconfig.mappings").get_mason_map()
	assert_equal(
		mappings.package_to_lspconfig[manifest.activation.mason_package],
		manifest.activation.lspconfig_server,
		"Mason package-to-lspconfig mapping drifted"
	)
	local resolved_ty = vim.lsp.config[manifest.activation.lspconfig_server]
	if type(resolved_ty) ~= "table" then
		fail("nvim-lspconfig did not provide a resolvable Ty configuration")
	end
	assert_equal(resolved_ty.cmd, manifest.activation.resolved_cmd, "resolved Ty command drifted")
	assert_equal(resolved_ty.filetypes, manifest.activation.resolved_filetypes, "resolved Ty filetypes drifted")

	local automatic_enable = require("mason-lspconfig.settings").current.automatic_enable
	if type(automatic_enable) ~= "table" or type(automatic_enable.exclude) ~= "table" then
		fail("effective mason-lspconfig automatic_enable policy is not an exclusion list")
	end
	local automatic_exclude = sorted(vim.deepcopy(automatic_enable.exclude))
	assert_equal(
		contains(automatic_exclude, "ty"),
		mode == "ty-excluded",
		"Ty automatic-enable exclusion does not match the test topology"
	)

	local enable_trace = {}
	for _, call in ipairs(_G.DX_M2C_ENABLE_TRACE) do
		if contains({ "pyright", "ruff", "ty" }, call.name) then
			enable_trace[#enable_trace + 1] = call
		end
	end
	local trace_by_name = {}
	for _, call in ipairs(enable_trace) do
		trace_by_name[call.name] = trace_by_name[call.name] or {}
		trace_by_name[call.name][#trace_by_name[call.name] + 1] = call
	end
	for _, name in ipairs({ "pyright", "ruff" }) do
		assert_equal(#(trace_by_name[name] or {}), 1, name .. " must be enabled exactly once")
	end
	if mode == "production" then
		assert_equal(#(trace_by_name.ty or {}), 1, "Ty must be enabled exactly once in production startup")
		local ty_call = trace_by_name.ty[1]
		if not ty_call.source:match("mason%-lspconfig%.nvim/lua/mason%-lspconfig/features/automatic_enable%.lua$") then
			fail("Ty was not enabled by mason-lspconfig automatic_enable: " .. ty_call.source)
		end
	else
		assert_equal(#(trace_by_name.ty or {}), 0, "test-only exclusion must prevent the Ty enable call")
	end

	local native_enabled = {}
	for _, name in ipairs({ "pyright", "ruff", "ty" }) do
		native_enabled[name] = vim.lsp.is_enabled(name)
		assert_equal(native_enabled[name], expected.enabled[name], "native enabled-config state drifted: " .. name)
		vim.lsp.config(name, {
			capabilities = { workspace = { didChangeWatchedFiles = { dynamicRegistration = false } } },
		})
	end

	local python_path = repo_root .. "/tests/nvim/color/python/main.py"
	vim.cmd.edit(vim.fn.fnameescape(python_path))
	local bufnr = vim.api.nvim_get_current_buf()
	local clients_by_name = {}
	local attached = vim.wait(30000, function()
		clients_by_name = {}
		for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
			if client.initialized then
				clients_by_name[client.name] = client
			end
		end
		for _, name in ipairs(expected.attached) do
			if clients_by_name[name] == nil then
				return false
			end
		end
		return true
	end, 100)
	if not attached then
		fail("expected Python clients did not attach: " .. vim.inspect(expected.attached))
	end
	assert_equal(sorted(vim.tbl_keys(clients_by_name)), expected.attached, "attached Python client topology drifted")

	local client_reports = {}
	local semantic_producers = {}
	local clients_by_id = {}
	for _, name in ipairs({ "pyright", "ruff", "ty" }) do
		local client = clients_by_name[name]
		if client then
			clients_by_id[client.id] = client
			local capabilities = capability_summary(client)
			assert_equal(
				capabilities,
				manifest.capabilities[name],
				"Python client capability topology drifted: " .. name
			)
			if capabilities.semantic_tokens then
				semantic_producers[#semantic_producers + 1] = name
			end
			client_reports[name] = {
				attached = true,
				id = client.id,
				server_name = client.server_info and client.server_info.name or "unreported",
				server_version = client.server_info and client.server_info.version or "unreported",
				capabilities = capabilities,
			}
		else
			client_reports[name] = { attached = false }
		end
	end
	semantic_producers = sorted(semantic_producers)
	assert_equal(semantic_producers, expected.semantic_producers, "semantic-token producer topology drifted")

	local probe_report = { producer = "none", neovim_tokens = {}, applied_groups = {}, foregrounds = {} }
	local row, column = locate_probe(bufnr, manifest.semantic_probe)
	if mode == "production" then
		local ty = clients_by_name.ty
		vim.lsp.semantic_tokens.force_refresh(bufnr)
		local raw = raw_at_position(request_raw_tokens(bufnr, ty), row, column)
		local expected_token = {
			client_id = ty.id,
			provider = manifest.semantic_probe.provider,
			type = manifest.semantic_probe.type,
			modifiers = manifest.semantic_probe.modifiers,
		}
		assert_equal(raw, { expected_token }, "raw Ty semantic-token provenance drifted")
		local decoded
		local decoded_ready = vim.wait(15000, function()
			decoded = neovim_at_position(bufnr, row, column, clients_by_id)
			return #decoded > 0
		end, 100)
		if not decoded_ready then
			fail("Neovim did not apply Ty's semantic token")
		end
		assert_equal(decoded, raw, "Neovim client-ID-bound Ty token differs from the raw response")
		local groups, foregrounds = semantic_application(bufnr, row, column)
		assert_equal(groups, manifest.semantic_probe.applied_groups, "Neovim-applied Ty semantic groups drifted")
		assert_equal(foregrounds, manifest.semantic_probe.foregrounds, "Ty foreground authority drifted")
		probe_report = {
			producer = "ty",
			raw_token = expected_token,
			neovim_tokens = decoded,
			applied_groups = groups,
			foregrounds = foregrounds,
		}
	else
		local decoded = neovim_at_position(bufnr, row, column, clients_by_id)
		assert_equal(decoded, {}, "Ty-excluded control must not apply semantic tokens")
		local inspected = vim.inspect_pos(bufnr, row, column)
		assert_equal(inspected.semantic_tokens or {}, {}, "Ty-excluded control has semantic extmarks")
	end

	local report = {
		milestone = manifest.milestone,
		mode = mode,
		lazy_server_state = lazy_state,
		mason = {
			installed = true,
			receipt_name = receipt.name,
			binary = ty_binary,
			package_to_lspconfig = mappings.package_to_lspconfig.ty,
		},
		resolved_config = { cmd = resolved_ty.cmd, filetypes = resolved_ty.filetypes },
		automatic_enable = { exclude = automatic_exclude },
		enable_trace = enable_trace,
		native_enabled = native_enabled,
		attached = sorted(vim.tbl_keys(clients_by_name)),
		clients = client_reports,
		semantic_producers = semantic_producers,
		semantic_probe = probe_report,
		decision = manifest.decision,
	}
	vim.fn.writefile({ vim.json.encode(report) }, report_path)

	for _, name in ipairs(report.attached) do
		local client = report.clients[name]
		io.stdout:write(
			("[M2C CLIENT] mode=%s name=%s id=%d semantic=%s completion=%s hover=%s definition=%s references=%s rename=%s code_action=%s\n"):format(
				mode,
				name,
				client.id,
				tostring(client.capabilities.semantic_tokens),
				tostring(client.capabilities.completion),
				tostring(client.capabilities.hover),
				tostring(client.capabilities.definition),
				tostring(client.capabilities.references),
				tostring(client.capabilities.rename),
				tostring(client.capabilities.code_action)
			)
		)
	end
	for _, call in ipairs(enable_trace) do
		io.stdout:write(
			("[M2C ENABLE] mode=%s name=%s enabled=%s source=%s:%d\n"):format(
				mode,
				call.name,
				tostring(call.enabled),
				call.source,
				call.line
			)
		)
	end
	io.stdout:write(
		("[M2C PROVENANCE] mode=%s installed=true mapping=ty enabled=%s attached=%s semantic=%s\n"):format(
			mode,
			tostring(native_enabled.ty),
			tostring(clients_by_name.ty ~= nil),
			table.concat(semantic_producers, ",")
		)
	)
	if mode == "production" then
		local raw = probe_report.raw_token
		local foreground = probe_report.foregrounds[1]
		io.stdout:write(
			("[M2C SEMANTIC] raw=%s#%d:%s[%s] neovim=client#%d groups=%d foreground=%s@%d->%s\n"):format(
				raw.provider,
				raw.client_id,
				raw.type,
				table.concat(raw.modifiers, ","),
				probe_report.neovim_tokens[1].client_id,
				#probe_report.applied_groups,
				foreground.group,
				foreground.priority,
				foreground.role
			)
		)
	end
	io.stdout:write(("M2C-A Python provider ownership evidence passed (%s).\n"):format(mode))
	io.stdout:flush()

	local attached_clients = vim.lsp.get_clients({ bufnr = bufnr })
	vim.cmd.bdelete({ bang = true })
	vim.lsp.stop_client(attached_clients, false)
end

local ok, err = xpcall(main, debug.traceback)
if not ok then
	io.stderr:write(("\n!!! M2C PROVIDER OWNERSHIP FAILURE !!!\n%s\n"):format(tostring(err)))
	vim.api.nvim_err_writeln(("\n!!! M2C PROVIDER OWNERSHIP FAILURE !!!\n%s\n"):format(tostring(err)))
	vim.cmd("cquit 1")
end
