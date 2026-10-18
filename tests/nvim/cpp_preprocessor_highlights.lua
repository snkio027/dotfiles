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
