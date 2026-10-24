local docs = require("config.clangd_documentation")
local function equal(actual, expected, label)
	assert(vim.deep_equal(actual, expected), label .. ": " .. vim.inspect(actual))
end

local input = {
	kind = "markdown",
	value = [=[\\brief Parses a document.

\\detail \\cpp auto value = parse_file("config.toml");
const char* newline = "\\n";
\\ecpp

\\param file_path Input path.
May contain spaces.
\\returns \\conditional_return{With exceptions}
A table.
\\conditional_return{Without exceptions}
A result.]=],
}
local expected = {
	kind = "markdown",
	value = [=[Parses a document.

```cpp
auto value = parse_file("config.toml");
const char* newline = "\n";
```

**Parameters**

- `file_path`: Input path.
  May contain spaces.

**Returns**

**With exceptions:**
A table.

**Without exceptions:**
A result.]=],
}
equal(docs.normalize(input), expected, "Doxygen/Poxy sections and escaped code")
equal(docs.normalize(expected), expected, "normalization is idempotent")
for _, text in ipairs({
	"Normal **Markdown**, `\\param` and [a link](https://example.com).",
	"Use \\brief at the start of a comment.",
	"\\unknown{keep this}",
	"    \\brief indented code",
	"```cpp\n\\brief code content\n```",
	"~~~~text\n@brief code content\n~~~\n@param still code\n~~~~",
	"\\brief Summary\n\\code{.cpp}\nunclosed code",
}) do
	local original = { kind = "markdown", value = text }
	assert(docs.normalize(original) == original, "DOCS_CHANGED_UNSUPPORTED_INPUT: " .. text)
end
assert(docs.normalize(nil) == nil)
equal(docs.normalize("@brief Summary\n@param[in,out] value Description\n@tparam T Value type\n@return Result"), {
	kind = "markdown",
	value = "Summary\n\n**Parameters**\n\n- `value` (in,out): Description\n\n**Template parameters**\n\n- `T`: Value type\n\n**Returns**\n\nResult",
}, "at-sign commands, direction and template parameter")
local code = docs.normalize({ kind = "markdown", value = "\\code{.cpp}\n```\n\\param is literal\n\\endcode" })
assert(code.value == "````cpp\n```\n\\param is literal\n````\n", "DOCS_CODE_FENCE_UNSAFE")
local unknown = docs.normalize({ kind = "markdown", value = "\\brief Summary\n\\custom{preserve me}" })
assert(unknown.value == "Summary\n\\custom{preserve me}", "DOCS_DROPPED_UNKNOWN_COMMAND")
equal(docs.normalize("\\brief Summary\n\n```cpp\n\\param literal\n```"), {
	kind = "markdown",
	value = "Summary\n\n```cpp\n\\param literal\n```",
}, "existing Markdown code is preserved beside converted prose")
equal(docs.normalize("\\out\nresult: 42\n\\eout"), {
	kind = "markdown",
	value = "```text\nresult: 42\n```\n",
}, "Poxy output remains a literal block")

-- Request actual completion documentation from the configured clangd binary,
-- then render that response through Blink's real resolve/draw/window path.
require("lazy").load({ plugins = { "blink.cmp", "nvim-lspconfig" } })
local api = vim.api
local menu = require("blink.cmp.completion.windows.menu")
local window = require("blink.cmp.completion.windows.documentation")
local original_win = api.nvim_get_current_win()
local columns, lines = vim.o.columns, vim.o.lines
vim.cmd.tabnew()
local source_win, source_buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
vim.bo[source_buf].buftype = "nofile"
vim.bo[source_buf].bufhidden = "wipe"
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local client
local source = {
	"/// \\brief Loads a document.",
	"///",
	"/// \\details Example:",
	"/// \\code{.cpp}",
	'/// auto example = render_docs("config.toml");',
	"/// \\endcode",
	"///",
	"/// \\detail \\cpp",
	'/// auto second = render_docs("other.toml");',
	"/// \\ecpp",
	"///",
	"/// \\param[in] file_path Input path.",
	"/// \\returns \\conditional_return{With exceptions}",
	"/// The result.",
	"int render_docs(const char* file_path);",
	"int main() { render_ }",
}
local ok, err = xpcall(function()
	vim.o.columns, vim.o.lines = 180, 50
	for _, format in ipairs({ "Plaintext", "Doxygen" }) do
		local dir = root .. "/" .. format
		vim.fn.mkdir(dir, "p")
		vim.fn.writefile({ "Documentation:", "  CommentFormat: " .. format }, dir .. "/.clangd")
		vim.fn.writefile(source, dir .. "/probe.cpp")
		api.nvim_buf_set_name(source_buf, dir .. "/probe.cpp")
		api.nvim_buf_set_lines(source_buf, 0, -1, false, source)
		local cursor = { #source, #source[#source] - 2 }
		api.nvim_win_set_cursor(source_win, cursor)
		local uri = vim.uri_from_bufnr(source_buf)
		local diagnosed = false
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
			"DOCS_CLANGD_START_TIMEOUT"
		)
		local response = assert(client:request_sync("textDocument/completion", {
			textDocument = { uri = uri },
			position = { line = cursor[1] - 1, character = cursor[2] },
		}, 10000, source_buf))
		assert(not response.err, vim.inspect(response.err))
		local item
		for _, candidate in ipairs(response.result.items or response.result) do
			if candidate.filterText == "render_docs" then
				item = vim.deepcopy(candidate)
			end
		end
		assert(item and item.documentation, "DOCS_CLANGD_DOCUMENTATION_MISSING")
		item.client_name, item.source_id, item.source_name = "clangd", "docs_contract", "Contract"
		item.client_id, item.cursor_column = client.id, cursor[2]
		local context = {
			id = 1,
			timestamp = vim.uv.now(),
			bufnr = source_buf,
			cursor = cursor,
			bounds = { start_col = 14, length = 7 },
			get_line = function()
				return source[#source]
			end,
			get_cursor = function()
				return api.nvim_win_get_cursor(source_win)
			end,
		}
		local snapshot = vim.deepcopy(item)
		menu.open_with_items(context, { item })
		window.show_item(context, item)
		assert(
			vim.wait(2000, function()
				return window.win:is_open()
			end),
			"DOCS_WINDOW_TIMEOUT"
		)
		local rendered = table.concat(api.nvim_buf_get_lines(window.win:get_buf(), 0, -1, false), "\n")
		for _, text in ipairs({
			"Loads a document.",
			"**Parameters**",
			"`file_path`",
			"**Returns**",
			"**With exceptions:**",
			'auto example = render_docs("config.toml");',
			'auto second = render_docs("other.toml");',
		}) do
			assert(rendered:find(text, 1, true), "DOCS_RENDERED_TEXT_MISSING: " .. text)
		end
		assert(
			not rendered:find("\\brief", 1, true) and not rendered:find("\\param", 1, true),
			"DOCS_RAW_COMMAND_VISIBLE"
		)
		equal(item, snapshot, "provider item and edits remain intact")
		equal(api.nvim_buf_get_lines(source_buf, 0, -1, false), source, "source text intact")
		equal(api.nvim_win_get_cursor(source_win), cursor, "source cursor intact")
		assert(api.nvim_get_current_win() == source_win, "DOCS_STOLE_FOCUS")
		menu.close()
		-- Same content from another provider must retain its original rendering.
		local other = vim.deepcopy(item)
		other.client_name = "other-server"
		other.documentation = { kind = "markdown", value = "\\brief Keep other provider output" }
		menu.open_with_items(context, { other })
		window.show_item(context, other)
		assert(
			vim.wait(2000, function()
				return window.win:is_open()
			end),
			"DOCS_OTHER_WINDOW_TIMEOUT"
		)
		local other_text = table.concat(api.nvim_buf_get_lines(window.win:get_buf(), 0, -1, false), "\n")
		assert(other_text:find(other.documentation.value, 1, true), "DOCS_CHANGED_OTHER_PROVIDER")
		menu.close()
		client:stop()
		assert(
			vim.wait(5000, function()
				return client:is_stopped()
			end),
			"DOCS_CLANGD_STOP_TIMEOUT"
		)
	end
end, debug.traceback)
menu.close()
window.close()
if client and not client:is_stopped() then
	client:stop(true)
end
api.nvim_win_close(source_win, true)
api.nvim_set_current_win(original_win)
vim.o.columns, vim.o.lines = columns, lines
vim.fn.delete(root, "rf")
assert(ok, err)
print(
	"Clangd documentation contract passed: real completion, Markdown sections/code, unchanged edits and other providers"
)
