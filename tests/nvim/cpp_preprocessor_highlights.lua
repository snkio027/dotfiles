-- Synthetic macro-wrapped header: no SDK dependency, no libc++ macro whitelist.
-- Called by the existing runtime contract with its real foreground resolver.
return function(effective)
	local evidence = dofile("tests/nvim/highlight_evidence.lua")
	local previous = vim.api.nvim_get_current_buf()
	local buffers = {}
	local ns = vim.api.nvim_create_namespace("cpp-preprocessor-inactive-control")
	local function open(lines, lang)
		local buf = vim.api.nvim_create_buf(false, true)
		buffers[#buffers + 1] = buf
		vim.api.nvim_set_current_buf(buf)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		-- Do not start LSP/provisioning for scratch parser fixtures.
		vim.cmd("noautocmd setlocal filetype=" .. lang)
		vim.treesitter.start(buf, lang)
		vim.treesitter.get_parser(buf, lang):parse(true)
		return buf
	end
	local function check(buf, line, token, role)
		local text = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1]
		local col = assert(text:find(token, 1, true), token) - 1
		local group, hl, _, candidates = effective(buf, line - 1, col)
		assert(hl, "Missing highlight: " .. token)
		evidence.assert_role(group, role, hl.fg)
		-- No equal-priority foreground conflict may hide behind traversal order.
		for _, candidate in ipairs(candidates) do
			if candidate.priority == candidates[1].priority then
				evidence.assert_role(candidate.hl_name, role, candidate.fg)
			end
		end
		return col, hl
	end
	local ok, err = xpcall(function()
		local buf = open({
			"#include <vendor_header.h>",
			"#if FEATURE_LEVEL >= 20",
			"VENDOR_NAMESPACE_BEGIN",
			"enum class ByteOrder {",
			"  little = 1, big = 2,",
			"#if LITTLE_ENDIAN",
			"  native = little",
			"#else",
			"  native = big",
			"#endif",
			"};",
			"VENDOR_NAMESPACE_END",
			"#endif",
		}, "cpp")
		check(buf, 1, "#include", "DxKeyword")
		check(buf, 4, "enum", "DxKeyword")
		check(buf, 4, "class", "DxKeyword")
		-- A real clangd inactive-region token must still outrank this recovery.
		-- Raw server evidence is independently checked by clangd_context.lua.
		vim.api.nvim_buf_set_extmark(buf, ns, 3, 0, {
			end_row = 3,
			end_col = 10,
			hl_group = "@lsp.type.comment.cpp",
			priority = vim.hl.priorities.semantic_tokens,
		})
		local _, inactive = check(buf, 4, "enum", "DxComment")
		assert(inactive.italic, "Inactive code lost its italic style")
		check(buf, 4, "class", "DxComment")
		vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
		check(buf, 4, "enum", "DxKeyword")

		-- The namespace macro makes the first alias after public: recover as a
		-- declaration with a type_identifier named "using". Exercise qualified
		-- and builtin RHS types, and the ordinary namespace control, independently.
		for _, wrapped in ipairs({ false, true }) do
			for _, rhs in ipairs({ "Thread::id", "int" }) do
				buf = open({
					wrapped and "VENDOR_NAMESPACE_BEGIN" or "namespace vendor {",
					"class Worker {",
					"public:",
					"  using id = " .. rhs .. ";",
					"  using native_handle_type = Thread::native_handle_type;",
					"};",
					wrapped and "VENDOR_NAMESPACE_END" or "}",
				}, "cpp")
				check(buf, 4, "using", "DxKeyword")
				check(buf, 5, "using", "DxKeyword")
				check(buf, 5, "native_handle_type", "DxType")
				if not wrapped then
					check(buf, 4, "id", "DxType")
				end
				-- Do not recolor the alias identifier; its semantic type remains
				-- provider-owned when the parser has lost the alias structure.
				for _, capture in ipairs(vim.treesitter.get_captures_at_pos(buf, 3, 8)) do
					assert(capture.capture ~= "keyword", "Using recovery escaped onto the alias name")
				end
				vim.api.nvim_buf_set_extmark(buf, ns, 3, 2, {
					end_row = 3,
					end_col = 7,
					hl_group = "@lsp.type.comment.cpp",
					priority = vim.hl.priorities.semantic_tokens,
				})
				local _, inactive_using = check(buf, 4, "using", "DxComment")
				assert(inactive_using.italic, "Inactive using lost its italic style")
				vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
				check(buf, 4, "using", "DxKeyword")
			end
		end
		buf = open({
			"using_type value;",
			"// using id = int;",
			'const char *text = "using id = int;";',
		}, "cpp")
		check(buf, 1, "using_type", "DxType")
		check(buf, 2, "using", "DxComment")
		check(buf, 3, "using", "DxString")

		-- Access labels and declaration decorators recover differently from the
		-- first using alias. Exercise whole reserved words, not vendor macro names.
		buf = open({
			"VENDOR_NAMESPACE_BEGIN",
			"class Worker {",
			"public:",
			"  typedef int size_type;",
			"  VENDOR_ABI explicit Worker(int);",
			"  VENDOR_ABI friend bool equal(const Worker&, const Worker&);",
			"protected:",
			"  int guard;",
			"private:",
			"  int field;",
			"};",
			"VENDOR_NAMESPACE_END",
		}, "cpp")
		for _, point in ipairs({
			{ 3, "public" },
			{ 4, "typedef" },
			{ 5, "explicit" },
			{ 6, "friend" },
			{ 7, "protected" },
			{ 9, "private" },
		}) do
			check(buf, point[1], point[2], "DxKeyword")
		end
		buf = open({
			"#if FEATURE_LEVEL >= 20",
			"VENDOR_NAMESPACE_BEGIN",
			"using ::global_type VENDOR_ATTR;",
			"VENDOR_NAMESPACE_END",
			"#endif",
		}, "cpp")
		check(buf, 3, "using", "DxKeyword")
		buf = open({
			"VENDOR_BEGIN",
			"static VENDOR_CONSTEXPR const bool value = true;",
			"inline VENDOR_ABI const int* address();",
			"VENDOR_END",
		}, "cpp")
		for _, point in ipairs({ { 2, "static" }, { 2, "const" }, { 3, "inline" }, { 3, "const" } }) do
			check(buf, point[1], point[2], "DxKeyword")
		end

		buf = open({
			"inline namespace versioned {}",
			"template<class T> struct Box {};",
			"extern template struct Box<int>;",
			"struct alignas(16) Aligned {};",
			"consteval int immediate() { return 1; }",
			"constinit int initial = 0;",
			"constexpr int evaluate(int x) {",
			"  if consteval { return 1; }",
			"  else { return x; }",
			"}",
			"void casts(int* p) {",
			"  static_cast<void>(p);",
			"  dynamic_cast<Derived*>(base);",
			"  const_cast<const int*>(p);",
			"  reinterpret_cast<char*>(p);",
			"  typeid(int);",
			"  static_assert(sizeof(int) > 0);",
			"}",
			"wchar_t wide;",
			"int ordinary;",
			"char8_t utf8;",
		}, "cpp")
		for _, point in ipairs({
			{ 1, "inline" },
			{ 3, "extern" },
			{ 4, "alignas" },
			{ 5, "consteval" },
			{ 6, "constinit" },
			{ 8, "consteval" },
			{ 9, "else" },
			{ 9, "return" },
			{ 12, "static_cast" },
			{ 13, "dynamic_cast" },
			{ 14, "const_cast" },
			{ 15, "reinterpret_cast" },
			{ 16, "typeid" },
			{ 17, "static_assert" },
		}) do
			local col = check(buf, point[1], point[2], "DxKeyword")
			vim.api.nvim_buf_set_extmark(buf, ns, point[1] - 1, col, {
				end_col = col + #point[2],
				hl_group = "@lsp.type.comment.cpp",
				priority = vim.hl.priorities.semantic_tokens,
			})
			local _, inactive_keyword = check(buf, point[1], point[2], "DxComment")
			assert(inactive_keyword.italic, "Keyword recovery overrode inactive style")
			vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
		end
		for _, point in ipairs({ { 19, "wchar_t" }, { 20, "int" }, { 21, "char8_t" } }) do
			check(buf, point[1], point[2], "DxBuiltin")
		end

		buf = open({
			"using_type object;",
			"int explicit_value, friendship, classification;",
			"int final, override, module, import;",
			"// public explicit using wchar_t static_cast",
			'const char* text = R"(public explicit using wchar_t static_cast)";',
			"[[vendor::using]] int attributed;",
			"#define TOKEN using id = int;",
			"#define static_assert(...) vendor_assert(__VA_ARGS__)",
			"#ifdef static_assert",
			"#if defined(typedef)",
			"#endif",
			"#endif",
		}, "cpp")
		check(buf, 1, "using_type", "DxType")
		for _, token in ipairs({ "explicit_value", "friendship", "classification" }) do
			check(buf, 2, token, "DxVariable")
		end
		for _, token in ipairs({ "final", "override", "module", "import" }) do
			check(buf, 3, token, "DxVariable")
		end
		for _, token in ipairs({ "public", "explicit", "using", "wchar_t", "static_cast" }) do
			check(buf, 4, token, "DxComment")
			check(buf, 5, token, "DxString")
		end
		-- Keywords may occur in attribute tokens and legacy compatibility macro
		-- definitions. Neither is an ordinary grammar-keyword recovery site.
		for _, point in ipairs({
			{ 6, "using" },
			{ 7, "using" },
			{ 8, "static_assert" },
			{ 9, "static_assert" },
			{ 10, "typedef" },
		}) do
			local line = vim.api.nvim_buf_get_lines(buf, point[1] - 1, point[1], false)[1]
			local col = assert(line:find(point[2], 1, true)) - 1
			for _, capture in ipairs(vim.treesitter.get_captures_at_pos(buf, point[1] - 1, col)) do
				assert(tonumber(capture.metadata.priority) ~= 101, "Recovery escaped into attribute/macro")
			end
		end

		for _, lang in ipairs({ "c", "cpp" }) do
			buf = open({
				"#include <vendor_header.h>",
				"#  pragma GCC system_header",
				"#pragma ACME diagnostic push",
				'#pragma message("enum class GCC")',
				"#define DECL GCC value",
				"struct GCC { int field; };",
				"// enum class GCC",
				'const char *text = "enum class GCC";',
				"int classification = 0;",
				"enum Normal { value = 1 };",
				"#error Vendor message",
			}, lang)
			check(buf, 1, "#include", "DxKeyword")
			check(buf, 2, "pragma", "DxKeyword")
			check(buf, 2, "GCC", "DxMeta")
			check(buf, 2, "system_header", "DxMeta")
			check(buf, 3, "ACME", "DxMeta")
			check(buf, 3, "push", "DxMeta")
			vim.api.nvim_buf_set_extmark(buf, ns, 1, 0, {
				end_row = 1,
				end_col = 27,
				hl_group = "@lsp.type.comment." .. lang,
				priority = vim.hl.priorities.semantic_tokens,
			})
			check(buf, 2, "GCC", "DxComment")
			vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
			check(buf, 4, "enum", "DxString")
			check(buf, 6, "GCC", "DxType")
			check(buf, 7, "enum", "DxComment")
			check(buf, 8, "class", "DxString")
			check(buf, 9, "classification", "DxVariable")
			check(buf, 10, "enum", "DxKeyword")
			-- Neither other preprocessor directives nor ordinary identifiers
			-- may receive the pragma-only metadata override.
			for _, point in ipairs({ { 5, "GCC" }, { 6, "GCC" }, { 11, "Vendor" } }) do
				local line = vim.api.nvim_buf_get_lines(buf, point[1] - 1, point[1], false)[1]
				local col = assert(line:find(point[2], 1, true)) - 1
				for _, capture in ipairs(vim.treesitter.get_captures_at_pos(buf, point[1] - 1, col)) do
					assert(capture.capture ~= "attribute", "Pragma override escaped its boundary")
				end
			end
		end
	end, debug.traceback)
	vim.api.nvim_set_current_buf(previous)
	for _, buf in ipairs(buffers) do
		vim.api.nvim_buf_delete(buf, { force = true })
	end
	assert(ok, err)
	print("C/C++ preprocessor highlights passed: imports, macro recovery, pragma boundaries, inactive precedence.")
end
