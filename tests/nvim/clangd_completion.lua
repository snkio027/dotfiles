-- Real clangd -> Blink -> LuaSnip -> keyboard integration. The child inherits
-- the isolated/installed configuration used by cold-start and Lifecycle.
local function equal(actual, expected, label)
	assert(vim.deep_equal(actual, expected), label .. ": " .. vim.inspect(actual))
end

local transform = dofile("home/dot_config/nvim/lua/config/clangd_completion.lua").transform_items
local raw = "if (${1:condition}) {\n$0\n}"
local item = {
	client_name = "clangd",
	kind = 15,
	insertTextFormat = 2,
	filterText = "if",
	insertText = raw,
	textEdit = { newText = raw, range = { start = { line = 1, character = 4 }, ["end"] = { line = 1, character = 6 } } },
	additionalTextEdits = { { newText = "#include <example>\n" } },
}
local repaired = transform(nil, { vim.deepcopy(item) })[1]
equal(repaired.insertText, "if (${1:condition}) {\n\t$0\n}", "relative block indentation")
equal(repaired.textEdit.newText, repaired.insertText, "text edit and insert text agree")
equal(repaired.textEdit.range, item.textEdit.range, "replacement range preserved")
equal(repaired.additionalTextEdits, item.additionalTextEdits, "header edits preserved")
equal(transform(nil, { vim.deepcopy(repaired) })[1], repaired, "resolve pass is idempotent")
for key, value in pairs({ client_name = "other", kind = 3, insertTextFormat = 1, filterText = "namespace" }) do
	local untouched = vim.tbl_extend("force", item, { [key] = value })
	equal(transform(nil, { vim.deepcopy(untouched) })[1], untouched, key .. " isolation")
end
for _, text in ipairs({ "call(${1:arg})$0", "if (${1:x}) {\n    $0\n}", "template<$0>", "if (${1:x}) {\nwork();\n}" }) do
	local untouched = vim.tbl_extend("force", item, { insertText = text, textEdit = { newText = text } })
	equal(transform(nil, { vim.deepcopy(untouched) })[1], untouched, "existing text preserved")
end

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
vim.fn.writefile({
	"CompileFlags:",
	"  Add: [-std=c++23]",
	"Completion:",
	"  CodePatterns: All",
	"  ArgumentLists: FullPlaceholders",
}, root .. "/.clangd")
vim.fn.writefile({ "int main() {", "    if", "}" }, root .. "/probe.cpp")
local channel = vim.fn.jobstart(
	{ vim.v.progpath, "--embed", "-n", "-i", "NONE", root .. "/probe.cpp" },
	{ rpc = true, cwd = root }
)
assert(channel > 0, "could not start Neovim UI child")
local function lua(code, args)
	return vim.rpcrequest(channel, "nvim_exec_lua", code, args or {})
end
local function input(keys)
	vim.rpcrequest(channel, "nvim_input", keys)
end
local function wait(label, predicate)
	assert(vim.wait(15000, predicate, 20), "CLANGD_COMPLETION: timeout: " .. label)
end
local function lines()
	return lua("return vim.api.nvim_buf_get_lines(0, 0, -1, false)")
end
local function node()
	return lua(
		[[local n = require('luasnip').session.current_nodes[vim.api.nvim_get_current_buf()]; return n and n.pos]]
	)
end
local function jump(pos, key)
	input(key or "<Tab>")
	wait("placeholder " .. pos, function()
		return node() == pos
	end)
end
local function accept(prefix, text, filter, match)
	input("<Esc>")
	wait("normal mode", function()
		return lua("return vim.api.nvim_get_mode().mode") == "n"
	end)
	lua(
		[[
    require('blink.cmp').hide()
    local ls = require('luasnip')
    if ls.session.current_nodes[vim.api.nvim_get_current_buf()] then ls.unlink_current() end
    local prefix = ...
    vim.api.nvim_buf_set_lines(0, 0, -1, false, prefix)
    vim.api.nvim_win_set_cursor(0, {#prefix - 1, 0})
  ]],
		{ prefix }
	)
	input("A" .. text)
	wait("insert text", function()
		return lua("return vim.api.nvim_get_current_line()") == prefix[#prefix - 1] .. text
	end)
	lua("require('blink.cmp').show({providers = {'lsp'}})")
	local index
	wait("clangd candidate " .. filter, function()
		-- Snippet provider items may contain functions/userdata. Keep the real
		-- menu and its indices, but send only observable scalar fields over RPC.
		local items = lua([[
      return vim.tbl_map(function(item)
        return {client_name=item.client_name, filterText=item.filterText, insertText=item.insertText}
      end, require('blink.cmp').get_items())
    ]])
		for i, candidate in ipairs(items) do
			if
				candidate.client_name == "clangd"
				and candidate.filterText == filter
				and (not match or (candidate.insertText or ""):find(match, 1, true))
			then
				index = i
				return true
			end
		end
	end)
	-- Navigate the actual menu, not a stubbed select/accept function.
	local selected = lua("return require('blink.cmp').get_selected_item_idx()") or 0
	for _ = selected + 1, index do
		input("<Down>")
	end
	for _ = index + 1, selected do
		input("<Up>")
	end
	wait("menu selection", function()
		return lua("return require('blink.cmp').get_selected_item_idx()") == index
	end)
	local chosen = lua([[
    local item = assert(require('blink.cmp').get_selected_item(), 'no selected candidate')
    return {client_name=item.client_name, filterText=item.filterText,
      insertText=item.insertText, insertTextFormat=item.insertTextFormat}
  ]])
	equal(chosen.client_name, "clangd", "selected real provider")
	equal(chosen.filterText, filter, "selected real candidate")
	local has_first_placeholder = (chosen.insertText or ""):find("${1:", 1, true) ~= nil
	input("<CR>")
	wait("snippet accepted", function()
		return (chosen.insertTextFormat ~= 2 or node() ~= nil)
			and (not has_first_placeholder or (node() == 1 and lua("return vim.api.nvim_get_mode().mode") == "s"))
			and not lua("return require('blink.cmp').is_menu_visible()")
			and lines()[#prefix - 1] ~= prefix[#prefix - 1] .. text
	end)
end

local ok, err = xpcall(function()
	vim.rpcrequest(channel, "nvim_ui_attach", 100, 40, { rgb = true })
	wait("clangd attached", function()
		return lua("return #vim.lsp.get_clients({bufnr=0,name='clangd'})") == 1
	end)
	wait("initial parse", function()
		return lua("return #vim.diagnostic.get(0) > 0")
	end)
	equal(
		lua(
			[[return vim.lsp.get_clients({bufnr=0,name='clangd'})[1].capabilities.textDocument.completion.completionItem.snippetSupport]]
		),
		true,
		"negotiated snippet support"
	)
	input("A")
	-- Blink setup is async: keymap descriptions alone do not prove that the
	-- completion event listeners have been installed yet.
	wait("Blink initialized", function()
		return lua("return require('blink.cmp.completion.trigger').buffer_events ~= nil")
	end)
	for _, option in ipairs({ "shiftwidth", "tabstop", "softtabstop" }) do
		equal(lua("return vim.bo[...]", { option }), 4, "C++ " .. option)
	end
	equal(lua("return vim.bo.expandtab"), true, "C++ expandtab")

	local function body(pattern, match, expected, jumps, row)
		accept({ "int main() {", "    ", "}" }, pattern, pattern, match)
		equal(lines(), expected, pattern .. " expanded text")
		for _, pos in ipairs(jumps) do
			jump(pos)
		end
		equal(lua("return vim.api.nvim_win_get_cursor(0)"), { row, 8 }, pattern .. " body cursor")
	end
	body("if", nil, { "int main() {", "    if (condition) {", "        ", "    }", "}" }, { 0 }, 3)
	input("return 0;")
	wait("body typing", function()
		return lines()[3] == "        return 0;"
	end)
	body("while", nil, { "int main() {", "    while (condition) {", "        ", "    }", "}" }, { 0 }, 3)
	body(
		"for",
		"init-statement",
		{ "int main() {", "    for (init-statement; condition; inc-expression) {", "        ", "    }", "}" },
		{ 2, 3, 0 },
		3
	)
	body(
		"for",
		"range-declaration",
		{ "int main() {", "    for (range-declaration : range-expression) {", "        ", "    }", "}" },
		{ 2, 0 },
		3
	)
	body("switch", nil, { "int main() {", "    switch (condition) {", "        ", "    }", "}" }, { 0 }, 3)
	body(
		"try",
		nil,
		{ "int main() {", "    try {", "        statements", "    } catch (declaration) {", "        ", "    }", "}" },
		{ 2, 0 },
		5
	)
	accept({ "int main() {", "    ", "}" }, "do", "do")
	equal(lines(), { "int main() {", "    do {", "        statements", "    }while ()", "}" }, "do body indentation")
	equal(lua("return vim.api.nvim_win_get_cursor(0)")[1], 3, "do first placeholder is body")
	jump(0)

	accept({ "template<class T>", "concept Valid = ", ";" }, "requires", "requires")
	equal(
		lines(),
		{ "template<class T>", "concept Valid = requires (parameters) {", "    ", "}", ";" },
		"requires expression"
	)
	jump(0)
	equal(lua("return vim.api.nvim_win_get_cursor(0)"), { 3, 4 }, "requires body cursor")

	accept({ "", "" }, "namespace", "namespace")
	equal(lines(), { "namespace identifier {", "", "}", "" }, "namespace indentation not rewritten")
	local function_decl = { "int compute(int count, bool enabled);", "int main() {", "    ", "}" }
	accept(function_decl, "compu", "compute")
	equal(lines()[3], "    compute(int count, bool enabled)", "function arguments and single parentheses")
	jump(2)
	jump(1, "<S-Tab>")
	input("42")
	jump(2)
	input("true")
	jump(0)
	equal(lines()[3], "    compute(42, true)", "editable arguments")

	local template_decl = { "template<class T> T construct();", "int main() {", "    ", "}" }
	accept(template_decl, "constr", "construct")
	equal(lines()[3], "    construct<class T>()", "template argument completion")
	input("int")
	jump(0)
	equal(lines()[3], "    construct<int>()", "template argument replacement")

	local member_decl = { "struct Box { int field; int size() const; };", "int main() {", "    Box box;", "    ", "}" }
	accept(member_decl, "box.fie", "field")
	equal(lines()[4], "    box.field", "plain member completion")
	accept(member_decl, "box.si", "size")
	equal(lines()[4], "    box.size()", "method completion")
	local explicit_object =
		{ "struct Box { int read(this const Box& self); };", "int main() {", "    Box box;", "    ", "}" }
	accept(explicit_object, "box.re", "read")
	equal(lines()[4], "    box.read()", "C++23 explicit object parameter is not a call argument")
	local constrained = {
		"template<class T> concept Addable = requires(T v) { v + v; };",
		"template<Addable T> T twice(T value);",
		"int main() {",
		"    ",
		"}",
	}
	accept(constrained, "twi", "twice")
	equal(lines()[4], "    twice(T value)", "constrained template completion")
	input("7")
	jump(0)
	equal(lines()[4], "    twice(7)", "constrained template argument replacement")
end, debug.traceback)

-- Observe graceful fixture LSP shutdown before requesting editor exit; both
-- the shutdown deadline and the final child exit status remain hard assertions.
local cleanup_ok, cleanup_err = pcall(
	lua,
	[[
  local clients = vim.lsp.get_clients()
  for _, client in ipairs(clients) do client:stop(false) end
  assert(vim.wait(10000, function()
    for _, client in ipairs(clients) do
      if not client:is_stopped() then return false end
    end
    return true
  end, 20), 'CLANGD_COMPLETION: fixture LSP shutdown timed out')
]]
)
pcall(vim.rpcnotify, channel, "nvim_exec_lua", "vim.schedule(function() vim.cmd('qa!') end)", {})
local status = vim.fn.jobwait({ channel }, 5000)[1]
if status == -1 then
	vim.fn.jobstop(channel)
end
vim.fn.delete(root, "rf")
assert(ok, err)
assert(cleanup_ok, cleanup_err)
assert(status == 0, "Neovim child did not exit cleanly: " .. status)
print(
	"Clangd completion contract passed: real candidates, block indentation, call/template arguments and keyboard jumps."
)
