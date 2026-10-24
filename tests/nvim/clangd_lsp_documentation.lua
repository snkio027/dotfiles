-- Exercise the configured K, manual signature and auto-trigger request paths
-- with real clangd responses, then inspect Noice's actual rendered windows.
require("lazy").load({ plugins = { "noice.nvim", "nvim-lspconfig" } })
local config = require("noice.config")
config.setup(LazyVim.opts("noice.nvim"))
local router = require("noice.message.router")
local docs = require("noice.lsp.docs")
local views = {}
for _, route in ipairs(config.options.routes) do
	if route.filter.event == "lsp" and (route.filter.kind == "hover" or route.filter.kind == "signature") then
		views[route.filter.kind] = router.add(route).view
	end
end
assert(views.hover and views.signature, "LSP_DOCS_ROUTES_MISSING")
local api = vim.api
local original_win = api.nvim_get_current_win()
local columns, lines = vim.o.columns, vim.o.lines
vim.cmd.tabnew()
local source_win, source_buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
vim.bo[source_buf].buftype, vim.bo[source_buf].bufhidden = "nofile", "wipe"
local root, client = vim.fn.tempname(), nil
local source = {
	"/// \\brief Loads a document.",
	"/// \\detail \\cpp",
	'/// auto result = render_docs("config.toml", 1);',
	"/// \\ecpp",
	"/// \\param file_path Input path.",
	"/// \\param flags Mode flags.",
	"/// \\returns The result.",
	"int render_docs(const char* file_path, int flags);",
	'int main() { return render_docs("config.toml", 1); }',
}
local function equal(actual, expected, label)
	assert(vim.deep_equal(actual, expected), label .. ": " .. vim.inspect(actual))
end
local function close()
	for _, message in pairs(docs._messages) do
		docs.hide(message)
	end
	router.update()
end
local function rendered(kind, expected, allow_commands)
	assert(
		vim.wait(5000, function()
			router.update()
			local popup = views[kind]._nui
			return popup and popup.winid and api.nvim_win_is_valid(popup.winid)
		end),
		"LSP_DOCS_WINDOW_TIMEOUT: " .. kind
	)
	local popup = views[kind]._nui
	local text = table.concat(api.nvim_buf_get_lines(popup.bufnr, 0, -1, false), "\n")
	for _, value in ipairs(expected) do
		assert(text:find(value, 1, true), "LSP_DOCS_CONTENT_MISSING: " .. kind .. ": " .. value .. "\n" .. text)
	end
	if not allow_commands then
		for _, command in ipairs({ "brief", "detail", "param", "returns", "cpp", "ecpp" }) do
			assert(not text:find("\\" .. command, 1, true), "LSP_DOCS_RAW_COMMAND: " .. kind .. ": " .. command)
		end
	end
	assert(api.nvim_get_current_win() == source_win, "LSP_DOCS_STOLE_FOCUS")
	equal(api.nvim_buf_get_lines(source_buf, 0, -1, false), source, "LSP_DOCS_CHANGED_SOURCE")
	return popup
end
local function active_parameter(popup, expected)
	for _, mark in ipairs(api.nvim_buf_get_extmarks(popup.bufnr, -1, 0, -1, { details = true })) do
		local detail = mark[4]
		if detail.hl_group == "LspSignatureActiveParameter" then
			local text = api.nvim_buf_get_text(popup.bufnr, mark[2], mark[3], detail.end_row, detail.end_col, {})
			equal(table.concat(text, "\n"), expected, "LSP_DOCS_ACTIVE_PARAMETER_CHANGED")
			return
		end
	end
	error("LSP_DOCS_ACTIVE_PARAMETER_MISSING")
end
local function request(method, column)
	local response = assert(client:request_sync("textDocument/" .. method, {
		textDocument = { uri = vim.uri_from_bufnr(source_buf) },
		position = { line = #source - 1, character = column },
	}, 10000, source_buf))
	assert(not response.err, vim.inspect(response.err))
	return assert(response.result)
end

local ok, err = xpcall(function()
	vim.o.columns, vim.o.lines = 180, 60
	for _, format in ipairs({ "Plaintext", "Doxygen" }) do
		local dir = root .. "/" .. format
		vim.fn.mkdir(dir, "p")
		vim.fn.writefile({ "Documentation:", "  CommentFormat: " .. format }, dir .. "/.clangd")
		vim.fn.writefile(source, dir .. "/probe.cpp")
		api.nvim_buf_set_name(source_buf, dir .. "/probe.cpp")
		api.nvim_buf_set_lines(source_buf, 0, -1, false, source)
		local uri, diagnosed = vim.uri_from_bufnr(source_buf), false
		local id = vim.lsp.start({
			name = "clangd",
			cmd = { LazyVim.opts("nvim-lspconfig").servers.clangd.cmd[1], "--background-index=false", "--log=error" },
			root_dir = dir,
			capabilities = require("blink.cmp").get_lsp_capabilities(),
			handlers = {
				["textDocument/publishDiagnostics"] = function(_, result)
					diagnosed = diagnosed or result.uri == uri
				end,
			},
		})
		client = assert(vim.lsp.get_client_by_id(id))
		assert(
			vim.wait(15000, function()
				return client.initialized and diagnosed
			end),
			"LSP_DOCS_CLANGD_START_TIMEOUT"
		)
		local hover_column = source[#source]:find("render_docs", 1, true) + 2
		local signature_column = source[#source]:find(", 1", 1, true)
		local expected = {
			"Loads a document.",
			"Input path.",
			"Mode flags.",
			"The result.",
			'auto result = render_docs("config.toml", 1);',
		}
		local hover = request("hover", hover_column)
		local signature = request("signatureHelp", signature_column)
		assert(vim.inspect(hover):find("ecpp", 1, true), "LSP_DOCS_HOVER_FIXTURE_NO_RAW_COMMAND")
		assert(vim.inspect(signature):find("brief", 1, true), "LSP_DOCS_SIGNATURE_FIXTURE_NO_RAW_COMMAND")
		local sig = signature.signatures[signature.activeSignature + 1]
		local bounds = sig.parameters[signature.activeParameter + 1].label
		local parameter = sig.label:sub(bounds[1] + 1, bounds[2])
		equal(parameter, "int flags", "LSP_DOCS_FIXTURE_ACTIVE_PARAMETER")
		for _, entry in ipairs({ "hover", "signature", "auto" }) do
			local kind = entry == "hover" and "hover" or "signature"
			local column = entry == "hover" and hover_column or signature_column
			api.nvim_win_set_cursor(source_win, { #source, column })
			if entry == "hover" then
				vim.lsp.buf.hover()
			elseif entry == "signature" then
				vim.lsp.buf.signature_help()
			else
				assert(require("noice.lsp.signature").get_char(source_buf) == ",", "LSP_DOCS_AUTO_TRIGGER_POSITION")
				api.nvim_exec_autocmds("TextChangedI", { buffer = source_buf })
			end
			local popup = rendered(kind, expected)
			if kind == "signature" then
				rendered(kind, { sig.label })
				active_parameter(popup, parameter)
			end
			equal(api.nvim_win_get_cursor(source_win), { #source, column }, "LSP_DOCS_MOVED_CURSOR")
			close()
		end
		-- The server response is immutable even though Noice attaches render state.
		local snapshot = vim.deepcopy(signature)
		require("noice.lsp.signature").on_signature(nil, signature, { client_id = id, bufnr = source_buf })
		rendered("signature", expected)
		equal(signature, snapshot, "LSP_DOCS_MUTATED_RESPONSE")
		close()
		if format == "Doxygen" then
			-- Parameter docs are separate optional fields, including across overloads.
			local overloads = {
				activeSignature = 1,
				activeParameter = 0,
				signatures = {
					{
						label = "sample(int first)",
						documentation = "\\brief First overload.",
						parameters = { { label = "int first", documentation = "\\brief First parameter." } },
					},
					{
						label = "sample(int second)",
						documentation = { kind = "plaintext", value = "\\brief Second overload." },
						parameters = {
							{
								label = { 7, 17 },
								documentation = { kind = "markdown", value = "\\brief Second parameter." },
							},
						},
					},
				},
			}
			local before = vim.deepcopy(overloads)
			require("noice.lsp.signature").on_signature(nil, overloads, { client_id = id, bufnr = source_buf })
			active_parameter(
				rendered(
					"signature",
					{ "First overload.", "Second overload.", "First parameter.", "Second parameter." }
				),
				"int second"
			)
			equal(overloads, before, "LSP_DOCS_MUTATED_OVERLOADS")
			close()
			local mixed = {
				contents = {
					"\\brief Summary",
					{ language = "cpp", value = "\\param literal_code" },
					{ kind = "markdown", value = "**\\custom**keep this" },
				},
			}
			local mixed_before = vim.deepcopy(mixed)
			require("noice.lsp.hover").on_hover(nil, mixed, { client_id = id, bufnr = source_buf })
			rendered("hover", { "Summary", "\\param literal_code", "\\custom" }, true)
			equal(mixed, mixed_before, "LSP_DOCS_MUTATED_MARKED_STRINGS")
			close()
			for _, ctx in ipairs({ { bufnr = source_buf }, { client_id = id, bufnr = source_buf } }) do
				client.name = "other-server"
				require("noice.lsp.hover").on_hover(nil, { contents = "\\brief Keep provider output" }, ctx)
				rendered("hover", { "\\brief Keep provider output" }, true)
				close()
				require("noice.lsp.signature").on_signature(nil, {
					signatures = { { label = "other()", documentation = "\\brief Keep signature output" } },
				}, ctx)
				rendered("signature", { "\\brief Keep signature output" }, true)
				close()
			end
			client.name = "clangd"
		end
		client:stop()
		assert(
			vim.wait(5000, function()
				return client:is_stopped()
			end),
			"LSP_DOCS_CLANGD_STOP_TIMEOUT"
		)
	end
	local hover_handler = require("noice.lsp.hover").on_hover
	local signature_handler = require("noice.lsp.signature").on_signature
	require("config.clangd_documentation").setup_noice()
	assert(hover_handler == require("noice.lsp.hover").on_hover, "LSP_DOCS_WRAPPED_HOVER_TWICE")
	assert(signature_handler == require("noice.lsp.signature").on_signature, "LSP_DOCS_WRAPPED_SIGNATURE_TWICE")
end, debug.traceback)
close()
for _, view in pairs(views) do
	view:hide()
end
if client and not client:is_stopped() then
	client:stop(true)
end
api.nvim_win_close(source_win, true)
api.nvim_set_current_win(original_win)
vim.o.columns, vim.o.lines = columns, lines
vim.fn.delete(root, "rf")
assert(ok, err)
print(
	"Clangd LSP documentation contract passed: real hover/manual/auto signature, intact parameters and provider isolation"
)
