-- Contextual query regressions, using the production foreground resolver.
-- No LSP tokens are fabricated; native inactive precedence is tested separately.
return function(effective)
	local evidence = dofile("tests/nvim/highlight_evidence.lua")
	local previous = vim.api.nvim_get_current_buf()
	local buffers = {}
	local checked = 0
	local function check(lang, source, points)
		local lines = vim.split(source, "\n", { plain = true })
		local buf = vim.api.nvim_create_buf(false, true)
		buffers[#buffers + 1] = buf
		vim.api.nvim_set_current_buf(buf)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.cmd("noautocmd setlocal filetype=" .. lang)
		vim.treesitter.start(buf, lang)
		vim.treesitter.get_parser(buf, lang):parse(true)
		for _, point in ipairs(points) do
			local pattern = point[2]:match("^[%a_][%w_]*$") and ("%f[%w_]" .. point[2] .. "%f[^%w_]")
			local col = assert(lines[point[1]]:find(pattern or point[2], 1, not pattern)) - 1
			local group, hl, _, candidates = effective(buf, point[1] - 1, col)
			local ok, err = pcall(function()
				assert(hl, "Missing foreground")
				evidence.assert_role(group, point[3], hl.fg)
				for _, candidate in ipairs(candidates) do
					-- Upstream generic identifier captures overlap at priority 100.
					-- Our recovery overrides must not introduce a new equal-priority conflict.
					if candidate.priority > 100 and candidate.priority == candidates[1].priority then
						evidence.assert_role(candidate.hl_name, point[3], candidate.fg)
					end
				end
			end)
			assert(ok, ("KEYWORD_CONTEXT_FAILURE %s:%d %s: %s"):format(lang, point[1], point[2], tostring(err)))
			checked = checked + 1
		end
	end
	local ok, err = xpcall(function()
		check(
			"cpp",
			[[#define VENDOR_BEGIN namespace vendor {
#define VENDOR_END }
VENDOR_BEGIN
enum class Mode : unsigned short { first };
enum class Kind : signed char { second };
long long ordinary;
VENDOR_END
const char* text = "unsigned short signed long";
// unsigned short signed long
]],
			{
				{ 4, "unsigned", "DxBuiltin" },
				{ 4, "short", "DxBuiltin" },
				{ 5, "signed", "DxBuiltin" },
				{ 5, "char", "DxBuiltin" },
				{ 6, "long", "DxBuiltin" },
				{ 8, "unsigned", "DxString" },
				{ 9, "unsigned", "DxComment" },
			}
		)
		check(
			"rust",
			[[extern crate alloc as allocations;
unsafe extern "C" {
    pub safe fn read_value() -> i32;
    pub safe static LIMIT: i32;
}
]],
			{
				{ 1, "crate", "DxKeyword" },
				{ 1, "as allocations", "DxKeyword" },
				{ 3, "safe", "DxKeyword" },
				{ 4, "safe", "DxKeyword" },
			}
		)
		check(
			"rust",
			[[unsafe extern "C" { fn safe(); }
fn safe() {
    let safe = 1;
    let r#safe = 2;
    let _ = crate::value;
    let text = "safe extern crate as";
    // safe extern crate as
}
]],
			{
				{ 1, "safe", "DxCallable" },
				{ 2, "safe", "DxCallable" },
				{ 3, "safe", "DxVariable" },
				{ 4, "r#safe", "DxVariable" },
				{ 5, "crate", "DxNamespace" },
				{ 6, "safe", "DxString" },
				{ 7, "safe", "DxComment" },
			}
		)
		check(
			"python",
			[[lazy import json
lazy from pathlib import Path
if True:
    lazy import os
    lazy from os import path
lazy = 1
lazy
import json
lazy; import os
obj.lazy = lazy
text = "lazy import json"
# lazy import json
]],
			{
				{ 1, "lazy", "DxKeyword" },
				{ 2, "lazy", "DxKeyword" },
				{ 4, "lazy", "DxKeyword" },
				{ 5, "lazy", "DxKeyword" },
				{ 6, "lazy", "DxVariable" },
				{ 7, "lazy", "DxVariable" },
				{ 9, "lazy", "DxVariable" },
				{ 10, "lazy", "DxMember" },
				{ 11, "lazy", "DxString" },
				{ 12, "lazy", "DxComment" },
			}
		)
		-- Valid Zig 0.17 asm clobbers trigger recovery in the installed parser.
		-- Reduced from std.Io.fiber: syntax-only, never executes the assembly.
		check(
			"zig",
			[[const Switch = usize;
const builtin = @import("builtin");
pub inline fn contextSwitch(s: *const Switch) *const Switch {
    return switch (builtin.cpu.arch) {
        .aarch64 => asm volatile (
            \\ ldp x0, x2, [x1]
            : [received_message] "={x1}" (-> *const Switch),
            : [message_to_send] "{x1}" (s),
            : .{
              .x0 = true,
              .x1 = true,
            }),
        .riscv64 => asm volatile (
            \\ ld a0, 0(a1)
            : [received_message] "={a1}" (-> *const Switch),
            : [message_to_send] "{a1}" (s),
            : .{
              .x1 = true,
              .x3 = true,
            }),
        .x86_64 => asm volatile (
            \\ movq 0(%%rsi), %%rax
            \\ movq 8(%%rsi), %%rcx
            \\ leaq 0f(%%rip), %%rdx
            \\ movq %%rsp, 0(%%rax)
            : [received_message] "={rsi}" (-> *const Switch),
            : [message_to_send] "{rsi}" (s),
            : .{
              .rax = true,
              .rcx = true,
            }),
        else => |arch| @compileError("unimplemented architecture: " ++ @tagName(arch)),
    };
}
]],
			{ { 32, "else", "DxKeyword" } }
		)
		-- An editing/recovery fragment models the same ERROR > block_label shape
		-- observed after asm in std.Io.Dispatch and std.Io.Uring. Not a valid TU.
		check(
			"zig",
			[[fn partial() void { asm volatile ("" : :
fn after() void {
const value: usize = 1;
var other: usize = 2;
}
]],
			{ { 3, "const", "DxKeyword" }, { 4, "var", "DxKeyword" } }
		)
		check(
			"zig",
			[[fn ordinary(value: u32) void {
    const @"const" = value;
    var @"var" = value;
    switch (value) { else => {} }
    const text = "else const var";
    // else const var
    label: { break :label; }
}
]],
			{
				{ 1, "fn", "DxFunctionKeyword" },
				{ 1, "u32", "DxBuiltin" },
				{ 2, '@"const"', "DxVariable" },
				{ 3, '@"var"', "DxVariable" },
				{ 4, "else", "DxKeyword" },
				{ 5, "else", "DxString" },
				{ 6, "else", "DxComment" },
				{ 7, "label:", "DxLabel" },
			}
		)
	end, debug.traceback)
	vim.api.nvim_set_current_buf(previous)
	for _, buf in ipairs(buffers) do
		vim.api.nvim_buf_delete(buf, { force = true })
	end
	assert(ok, err)
	print(("Contextual keyword highlights passed: %d positions across C++, Rust, Python and Zig."):format(checked))
end
