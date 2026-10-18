-- Observe actual clangd tokens and the production foreground resolver. No SDK
-- header names, manufactured semantic tokens or alternate color oracle.
return function(effective, repo_root)
	local evidence = dofile(repo_root .. "/tests/nvim/highlight_evidence.lua")
	local root = vim.fn.tempname()
	vim.fn.mkdir(root, "p")
	local source = {
		"#define VENDOR_BEGIN namespace vendor {",
		"#define VENDOR_END }",
		"#define VENDOR_ABI",
		"VENDOR_BEGIN",
		"class Worker {",
		"public:",
		"  typedef int size_type;",
		"  VENDOR_ABI explicit Worker(int);",
		"  VENDOR_ABI friend bool equal(const Worker&, const Worker&);",
		"protected: int guard;",
		"private: int field;",
		"};",
		"VENDOR_END",
		"inline namespace versioned {}",
		"template<class T> struct Box {};",
		"extern template struct Box<int>;",
		"struct alignas(16) Aligned {};",
		"constexpr int eval(int x) { if consteval { return 1; } else { return x; } }",
		"wchar_t wide;",
		"#if 0",
		"class Dormant { public:",
		"  using id = int;",
		"  Dormant();",
		"  Dormant(int) : Dormant() {}",
		"  Dormant& operator=(const Dormant&) = default;",
		"  ~Dormant();",
		"};",
		"#endif",
		"#include <typeinfo>",
		"struct Base { virtual ~Base() = default; };",
		"struct Derived : Base {};",
		"void casts(Base* p, const int* q) {",
		"  static_cast<Derived*>(p);",
		"  dynamic_cast<Derived*>(p);",
		"  const_cast<int*>(q);",
		"  reinterpret_cast<const char*>(q);",
		"  typeid(Base);",
		"  static_assert(sizeof(int) > 0);",
		"}",
	}
	vim.fn.writefile(source, root .. "/keywords.cpp")
	vim.fn.writefile({ "-std=c++23" }, root .. "/compile_flags.txt")
	local previous = vim.api.nvim_get_current_buf()
	local foldenable = vim.wo.foldenable
	local buf, client
	local ok, err = xpcall(function()
		vim.cmd("noautocmd edit " .. vim.fn.fnameescape(root .. "/keywords.cpp"))
		buf = vim.api.nvim_get_current_buf()
		vim.cmd("noautocmd setlocal filetype=cpp")
		vim.wo.foldenable = false
		vim.treesitter.start(buf, "cpp")
		local config = vim.deepcopy(vim.lsp.config.clangd)
		assert(config.on_attach == require("theme.adapters.clangd").attach, "Missing clangd authority adapter")
		config.root_dir = root
		client = assert(vim.lsp.get_client_by_id(assert(vim.lsp.start(config, { bufnr = buf }))))
		assert(
			vim.wait(15000, function()
				return client.initialized and #(vim.lsp.semantic_tokens.get_at_pos(buf, 4, 6) or {}) > 0
			end, 30),
			"clangd did not supply native class evidence"
		)
		local function check(line, token, role, inactive)
			local col = assert(source[line]:find(token, 1, true)) - 1
			local last_error
			assert(
				vim.wait(15000, function()
					vim.api.nvim_win_set_cursor(0, { line, col })
					vim.cmd("normal! zz")
					vim.cmd("redraw")
					local matched, failure = pcall(function()
						local has_comment = false
						for _, value in ipairs(vim.lsp.semantic_tokens.get_at_pos(buf, line - 1, col) or {}) do
							if value.client_id == client.id and value.type == "comment" then
								has_comment = true
							end
						end
						assert(has_comment == inactive, "Native inactive evidence mismatch")
						local group, hl = effective(buf, line - 1, col)
						assert(hl, "No foreground for " .. token)
						evidence.assert_role(group, role, hl.fg)
						if inactive then
							assert(hl.italic, "Native inactive style lost")
						end
					end)
					last_error = failure
					return matched
				end, 30),
				("keywords.cpp:%d %s: %s"):format(line, token, tostring(last_error))
			)
		end
		for _, point in ipairs({
			{ 6, "public" },
			{ 7, "typedef" },
			{ 8, "explicit" },
			{ 9, "friend" },
			{ 10, "protected" },
			{ 11, "private" },
			{ 14, "inline" },
			{ 16, "extern" },
			{ 17, "alignas" },
			{ 18, "consteval" },
			{ 18, "else" },
			{ 33, "static_cast" },
			{ 34, "dynamic_cast" },
			{ 35, "const_cast" },
			{ 36, "reinterpret_cast" },
			{ 37, "typeid" },
			{ 38, "static_assert" },
		}) do
			check(point[1], point[2], "DxKeyword", false)
		end
		check(19, "wchar_t", "DxBuiltin", false)
		local inactive_points = {
			{ 21, "public", "DxKeyword" },
			{ 22, "using", "DxKeyword" },
			{ 24, "Dormant()", "DxCallable" },
			{ 25, "operator=", "DxCallable" },
			{ 25, "=", "DxCallable" },
			{ 26, "~Dormant", "DxCallable" },
		}
		for _, state in ipairs({ false, true, false }) do
			source[20] = state and "#if 1" or "#if 0"
			vim.api.nvim_buf_set_lines(buf, 19, 20, false, { source[20] })
			for _, point in ipairs(inactive_points) do
				check(point[1], point[2], state and point[3] or "DxComment", not state)
			end
		end
		-- The override belongs to clangd's native token namespace and lifetime.
		vim.lsp.buf_detach_client(buf, client.id)
		assert(not vim.lsp.buf_is_attached(buf, client.id), "clangd still attached")
		local group = "dx_clangd_inactive_" .. client.id .. "_" .. buf
		assert(vim.fn.exists("#" .. group) == 0, "Inactive callback survived detach")
		local col = assert(source[25]:find("operator=", 1, true)) - 1
		local name, hl = effective(buf, 24, col)
		assert(hl)
		evidence.assert_role(name, "DxCallable", hl.fg)
	end, debug.traceback)
	if client then
		dofile(repo_root .. "/tests/nvim/lsp_shutdown.lua")({ client }, "cpp-keyword-runtime", 10000)
	end
	vim.api.nvim_set_current_buf(previous)
	vim.wo.foldenable = foldenable
	if buf then
		vim.api.nvim_buf_delete(buf, { force = true })
	end
	vim.fn.delete(root, "rf")
	assert(ok, err)
	print("C++ keyword runtime passed: macro recovery, builtin identity, native inactive transitions and detach.")
end
