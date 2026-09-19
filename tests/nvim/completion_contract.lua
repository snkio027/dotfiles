local function fail(message)
	error("COMPLETION_CONTRACT_FAILURE: " .. message, 0)
end

if vim.g.dotfiles_completion_contract_negative then
	fail("COMPLETION_CONTRACT_NEGATIVE_CONTROL")
end

local function assert_equal(actual, expected, label)
	if not vim.deep_equal(actual, expected) then
		fail(("%s: expected %s, got %s"):format(label, vim.inspect(expected), vim.inspect(actual)))
	end
end

local lazy_config = require("lazy.core.config")
for _, name in ipairs({ "LuaSnip", "blink.pairs", "nvim-dap-view", "octo.nvim", "snacks.nvim" }) do
	if not lazy_config.plugins[name] then
		fail(("replacement plugin is unavailable: %s"):format(name))
	end
end
for _, name in ipairs({ "mini.snippets", "mini.pairs", "fzf-lua", "nvim-dap-ui", "gh.nvim", "litee.nvim" }) do
	if lazy_config.plugins[name] then
		fail(("retired plugin remains active: %s"):format(name))
	end
end

assert_equal(vim.g.lazyvim_picker, "snacks", "LazyVim picker ownership")
assert_equal(LazyVim.opts("octo.nvim").picker, "snacks", "Octo picker integration")
assert_equal(LazyVim.opts("nvim-dap-view").auto_toggle, true, "DAP view session lifecycle")
assert_equal(LazyVim.opts("blink.pairs").highlights.enabled, false, "Blink pairs rainbow highlights")

local blink_opts = LazyVim.opts("blink.cmp")
assert_equal(blink_opts.snippets.preset, "luasnip", "Blink snippet engine")
assert_equal(blink_opts.keymap.preset, "enter", "LazyVim Blink keymap preset")

require("lazy").load({ plugins = { "LuaSnip", "blink.cmp", "blink.pairs" } })
local blink_config = require("blink.cmp.config")
local luasnip = require("luasnip")

assert_equal(blink_config.completion.list.selection.preselect({}), true, "default Blink preselection")
assert_equal(blink_config.completion.list.selection.auto_insert({}), true, "default Blink preview insertion")
assert_equal(blink_config.completion.trigger.show_in_snippet, true, "default completion inside snippets")
assert_equal(blink_config.snippets.preset, "luasnip", "runtime Blink snippet engine")
assert_equal(
	require("blink.cmp").get_lsp_capabilities().textDocument.completion.completionItem.snippetSupport,
	true,
	"LSP snippet support must remain enabled for call arguments"
)
assert_equal(
	LazyVim.opts("nvim-lspconfig").servers.clangd.init_options.usePlaceholders,
	true,
	"clangd call placeholders"
)
assert(require("blink.pairs").library_available(), "Blink pairs native library is unavailable")

local function feed(keys)
	vim.fn.feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt")
end

local function unlink_snippet()
	if luasnip.in_snippet() then
		luasnip.unlink_current()
	end
end

local snippet_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(snippet_buffer)
vim.bo[snippet_buffer].filetype = "cpp"
vim.bo[snippet_buffer].expandtab = true
vim.bo[snippet_buffer].shiftwidth = 4
vim.bo[snippet_buffer].tabstop = 4
vim.wo.virtualedit = "onemore"
-- Blink initializes asynchronously, then installs buffer-local i/s maps on
-- InsertEnter. Wait for that real path instead of injecting a test keymap.
assert(
	vim.wait(30000, function()
		feed("i<Esc>")
		local mapping = vim.fn.maparg("<Tab>", "s", false, true)
		return mapping.desc and mapping.desc:find("blink.cmp:", 1, true) == 1
	end, 50),
	"Blink snippet keymaps did not attach within 30s"
)

local cpp_if
local cpp_forr
assert(
	vim.wait(2000, function()
		local if_candidates = {}
		local forr_candidates = {}
		for _, snippet in ipairs(luasnip.get_snippets("cpp")) do
			if snippet.trigger == "if" then
				table.insert(if_candidates, snippet)
			elseif snippet.trigger == "forr" then
				table.insert(forr_candidates, snippet)
			end
		end
		if #if_candidates == 1 and #forr_candidates == 1 then
			cpp_if = if_candidates[1]
			cpp_forr = forr_candidates[1]
			return true
		end
		return false
	end, 10),
	"C++ snippet candidates did not settle to one if and one forr"
)
assert_equal(cpp_if.name, "if", "friendly-snippets C++ if candidate")
assert_equal(cpp_forr.name, "Safe reverse iterator loop", "safe C++ forr candidate")

local snippet_source = require("blink.cmp.sources.snippets.luasnip").new({})

local function accept_snippet_candidate(trigger, indent, shiftwidth, expected)
	unlink_snippet()
	vim.bo[snippet_buffer].shiftwidth = shiftwidth
	vim.bo[snippet_buffer].tabstop = shiftwidth
	local line = indent .. trigger
	vim.api.nvim_buf_set_lines(snippet_buffer, 0, -1, false, { line })
	vim.api.nvim_win_set_cursor(0, { 1, #line })

	local context = {
		line = line,
		cursor = { 1, #line },
		get_cursor = function()
			return vim.api.nvim_win_get_cursor(0)
		end,
		get_line = function()
			return vim.api.nvim_get_current_line()
		end,
	}
	local response
	snippet_source:get_completions(context, function(value)
		response = value
	end)
	assert(response, ("Blink snippet response unavailable for %s"):format(trigger))

	local candidates = {}
	for _, item in ipairs(response.items) do
		if item.label == trigger then
			table.insert(candidates, item)
		end
	end
	assert_equal(#candidates, 1, ("Blink %s candidate count"):format(trigger))
	local selected = candidates[1]
	assert_equal(
		luasnip.get_id_snippet(selected.data.snip_id).trigger,
		trigger,
		("Blink %s source identity"):format(trigger)
	)

	selected.textEdit = {
		newText = trigger,
		range = {
			start = { line = 0, character = #indent },
			["end"] = { line = 0, character = #line },
		},
	}
	selected.cursor_column = #line
	snippet_source:execute(context, selected)
	assert_equal(
		vim.api.nvim_buf_get_lines(snippet_buffer, 0, -1, false),
		expected,
		("Blink %s expansion"):format(trigger)
	)
	assert(luasnip.in_snippet(), ("LuaSnip session did not start for %s"):format(trigger))
	return vim.api.nvim_buf_get_lines(snippet_buffer, 0, -1, false)
end

accept_snippet_candidate("if", "    ", 4, {
	"    if () {",
	"        ",
	"    }",
})

accept_snippet_candidate("forr", "  ", 2, {
	"  for (auto it = container.rbegin(); it != container.rend(); ++it) {",
	"    ",
	"  }",
})
for _, line in ipairs(vim.api.nvim_buf_get_lines(snippet_buffer, 0, -1, false)) do
	assert(not line:find("size_t", 1, true), "unsafe unsigned forr candidate remains")
	assert(not line:find(">= 0", 1, true), "non-terminating forr condition remains")
end

-- Independent expected text: exercise the actual registered Blink provider
-- candidates, never a handwritten snippet expanded in their place.
local templates = {
	{ "tfn", { "template <typename T>", "void function_name(T value) {", "\t", "}" }, 4 },
	{ "tclass", { "template <typename T>", "struct Box {", "\tT value;", "\t", "};" }, 3 },
	{ "tusing", { "template <typename T>", "using Alias = T;" }, 2 },
	{
		"concept",
		{ "template <typename T>", "concept HasValueType = requires {", "\ttypename T::value_type;", "};" },
		3,
	},
	{ "requires", { "requires (T value) {", "\tvalue.size();", "\t", "}" }, 3 },
	{ "ifce", { "if constexpr (condition) {", "\t", "}" }, 1 },
	{
		"tpack",
		{
			"template <typename... Args>",
			"void visit_all(Args&&... args) {",
			"\t(static_cast<void>(consume(std::forward<Args>(args))), ...);",
			"\t",
			"}",
		},
		4,
	},
	{ "tspec", { "template <>", "struct Box<int> {", "\t", "};" }, 2 },
}
local compiler = vim.fn.exepath("c++")
assert(compiler ~= "", "C++ compiler is required for the snippet contract")
for _, width in ipairs({ 2, 4 }) do
	local generated = {}
	local indent = string.rep(" ", width * 2)
	for _, case in ipairs(templates) do
		local trigger, body, stops = unpack(case)
		local expected = vim.tbl_map(function(line)
			return indent .. line:gsub("\t", string.rep(" ", width))
		end, body)
		local actual = accept_snippet_candidate(trigger, indent, width, expected)
		generated[trigger] = table.concat(actual, "\n")

		-- Flush LuaSnip's real Select-mode entry, then exercise the installed keys.
		feed("")
		local function position()
			local node = luasnip.session.current_nodes[snippet_buffer]
			return node and node.pos
		end
		assert_equal(position(), 1, trigger .. " first placeholder")
		for pos = 2, stops do
			feed("<Tab>")
			assert(
				vim.wait(1000, function()
					return position() == pos
				end, 10),
				trigger .. " forward placeholder"
			)
		end
		if stops > 1 then
			feed("<S-Tab>")
			assert(
				vim.wait(1000, function()
					return position() == stops - 1
				end, 10),
				trigger .. " backward placeholder"
			)
			feed("<Tab>")
			assert(
				vim.wait(1000, function()
					return position() == stops
				end, 10),
				trigger .. " return placeholder"
			)
		end
		feed("<Tab>")
		assert(
			vim.wait(1000, function()
				return position() == 0
			end, 10),
			trigger .. " final placeholder"
		)
		assert_equal(
			vim.api.nvim_buf_get_lines(snippet_buffer, 0, -1, false),
			expected,
			trigger .. " navigation preserves text"
		)
		assert(not luasnip.jumpable(1), trigger .. " should finish at the final placeholder")
		feed("<Esc>")
	end

	-- Compile what was actually expanded. Context supplies the primary template,
	-- headers and callable required by these deliberately small building blocks.
	local program = table.concat({
		"#include <type_traits>",
		"#include <utility>",
		generated.tfn,
		generated.tclass,
		generated.tusing,
		generated.concept,
		generated.tspec,
		"template <typename T> concept Sized = " .. generated.requires .. ";",
		"template <bool condition> void branch() {" .. generated.ifce .. "}",
		"struct Container { using value_type = int; int size() const; };",
		"struct MoveOnly { MoveOnly() = default; MoveOnly(const MoveOnly&) = delete; };",
		"struct Result { Result operator,(const Result&) const = delete; };",
		"Result consume(int&) { return {}; } Result consume(MoveOnly&&) { return {}; }",
		generated.tpack,
		"static_assert(std::is_same_v<Alias<int>, int>);",
		"static_assert(HasValueType<Container> && !HasValueType<int>);",
		"static_assert(Sized<Container> && !Sized<int>);",
		"static_assert(sizeof(Box<int>) > 0);",
		"void instantiate() { int n = 1; function_name(n); Box<long> box{1}; (void)box;",
		"visit_all(n, MoveOnly{}); visit_all(); branch<true>(); branch<false>(); }",
	}, "\n")
	local result = vim.system({ compiler, "-std=c++23", "-pedantic-errors", "-x", "c++", "-fsyntax-only", "-" }, {
		stdin = program,
		text = true,
	}):wait(20000)
	assert_equal(result.code, 0, "Expanded C++23 snippets: " .. (result.stderr or ""))
end

accept_snippet_candidate("tfn", "", 4, { "template <typename T>", "void function_name(T value) {", "    ", "}" })
feed("")
feed("Element<Esc>")
local renamed = { "template <typename Element>", "void function_name(Element value) {", "    ", "}" }
assert(
	vim.wait(1000, function()
		return vim.deep_equal(vim.api.nvim_buf_get_lines(snippet_buffer, 0, -1, false), renamed)
	end, 10),
	"Editing a template parameter did not update its mirror"
)
print(
	"C++ template snippets passed: 8 provider candidates, 2/4-space nesting, navigation, mirrors, C++23 instantiation."
)
unlink_snippet()
vim.api.nvim_buf_delete(snippet_buffer, { force = true })
feed("<Esc>")

local pair_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(pair_buffer)
vim.bo[pair_buffer].filetype = "cpp"
vim.api.nvim_buf_set_lines(pair_buffer, 0, -1, false, { "" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
feed("i(<Esc>")
assert_equal(vim.api.nvim_buf_get_lines(pair_buffer, 0, -1, false), { "()" }, "Blink pair insertion")
vim.api.nvim_buf_set_lines(pair_buffer, 0, -1, false, { "" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
feed("i()<Esc>")
assert_equal(vim.api.nvim_buf_get_lines(pair_buffer, 0, -1, false), { "()" }, "Blink closing-pair skip")
vim.api.nvim_buf_delete(pair_buffer, { force = true })

print("Completion interaction contract passed: LazyVim defaults, LuaSnip expansion, replacement plugin topology.")
