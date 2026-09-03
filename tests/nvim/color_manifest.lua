--- DX Semantic Color System (DX-COLOR-002)
--- Shared Color Manifest: Single Source of Truth for Language Fixtures & Sentinels.
--- Consumed identically by Tier-1 (Unit Contract), Tier-2A (Locked Neovim), and Tier-2B (DevContainer).

local M = {
	languages = {
		rust = {
			filetype = "rust",
			path = "tests/nvim/color/rust/src/main.rs",
			lsp = { "rust-analyzer", "rust_analyzer" },
			sentinels = {
				{
					tag = "rust.download_summary.type",
					token = "DownloadSummary",
					role = "DxType",
					desc = "Rust struct definition",
				},
				{
					tag = "rust.size.method",
					token = "size",
					role = "DxCallable",
					desc = "Rust method definition",
				},
				{
					tag = "rust.size.field",
					token = "size",
					role = "DxMember",
					desc = "Rust struct field access",
				},
				{
					tag = "rust.fetch_stream.fn",
					token = "uri",
					role = "DxParameter",
					desc = "Rust function parameter",
				},
				{
					tag = "rust.lifetime.param",
					token = "a",
					role = "DxLifetime",
					desc = "Rust type-level lifetime generic parameter ('a)",
					required_ts_capture = "type.lifetime.rust",
				},
				{
					tag = "rust.lifetime.static",
					token = "static",
					role = "DxLifetime",
					desc = "Rust static lifetime specifier ('static)",
					required_ts_capture = "type.lifetime.rust",
				},
				{
					tag = "rust.must_use.attribute",
					token = "must_use",
					role = "DxMeta",
					desc = "Rust standard attribute (#[must_use])",
					forbidden_ts_capture = "type.lifetime.rust",
				},
				{
					tag = "rust.dispatch.label",
					token = "dispatch",
					role = "DxLabel",
					desc = "Rust loop control-flow label ('dispatch: loop)",
				},
			},
		},

		c = {
			filetype = "c",
			path = "tests/nvim/color/c/main.c",
			lsp = { "clangd" },
			sentinels = {
				{
					tag = "c.buffer_capacity.macro",
					token = "BUFFER_CAPACITY",
					role = "DxMeta",
					desc = "C preprocessor object-like macro (#define BUFFER_CAPACITY)",
				},
				{
					tag = "c.buffer.struct",
					token = "Buffer",
					role = "DxType",
					desc = "C struct declaration (struct Buffer)",
				},
				{
					tag = "c.size.member",
					token = "size",
					role = "DxMember",
					desc = "C struct member field (size_t size)",
				},
				{
					tag = "c.decode.fn",
					token = "decode",
					role = "DxCallable",
					desc = "C static function definition (decode)",
				},
				{
					tag = "c.buffer.param",
					token = "buffer",
					role = "DxParameter",
					desc = "C function parameter pointer (struct Buffer *buffer)",
				},
				{
					tag = "c.retry.label",
					token = "retry",
					role = "DxLabel",
					desc = "C goto control-flow label (retry:)",
				},
			},
		},

		cpp = {
			filetype = "cpp",
			path = "tests/nvim/color/cpp/src/main.cpp",
			lsp = { "clangd" },
			sentinels = {
				{
					tag = "cpp.buffer_capacity.macro",
					token = "BUFFER_CAPACITY",
					role = "DxMeta",
					desc = "C++ preprocessor object-like macro (#define BUFFER_CAPACITY)",
				},
				{
					tag = "cpp.packet_decoder.class",
					token = "PacketDecoder",
					role = "DxType",
					desc = "C++ class definition",
				},
				{
					tag = "cpp.decode.method",
					token = "decode",
					role = "DxCallable",
					desc = "C++ class method definition",
				},
				{
					tag = "cpp.state.member",
					token = "state_",
					role = "DxMember",
					desc = "C++ private member declaration",
				},
				{
					tag = "cpp.log_diagnostic.fn",
					token = "log_diagnostic",
					role = "DxCallable",
					desc = "C++ standalone function definition",
				},
				{
					tag = "cpp.retry.label",
					token = "retry",
					role = "DxLabel",
					desc = "C++ goto control-flow label (retry:)",
				},
			},
		},

		zig = {
			filetype = "zig",
			path = "tests/nvim/color/zig/src/main.zig",
			lsp = { "zls" },
			sentinels = {
				{
					tag = "zig.network_buffer.type",
					token = "NetworkBuffer",
					role = "DxType",
					desc = "Zig struct definition",
				},
				{
					tag = "zig.bytes.member",
					token = "bytes",
					role = "DxMember",
					desc = "Zig struct member field",
				},
				{
					tag = "zig.append.method",
					token = "append",
					role = "DxCallable",
					desc = "Zig method-style function definition",
				},
				{
					tag = "zig.sizeof.builtin",
					token = "sizeOf",
					role = "DxMeta",
					desc = "Zig builtin function call (@sizeOf)",
				},
				{
					tag = "zig.drain.label",
					token = "drain",
					role = "DxLabel",
					desc = "Zig labeled while loop (drain: while)",
				},
			},
		},

		python = {
			filetype = "python",
			path = "tests/nvim/color/python/main.py",
			lsp = { "pyright" },
			sentinels = {
				{
					tag = "python.download_summary.class",
					token = "DownloadSummary",
					role = "DxType",
					desc = "Python class definition",
				},
				{
					tag = "python.size.member",
					token = "size",
					role = "DxMember",
					desc = "Python instance attribute access (self.size)",
				},
				{
					tag = "python.validate_bounds.method",
					token = "validate_bounds",
					role = "DxCallable",
					desc = "Python instance method definition",
				},
				{
					tag = "python.fetch_async.fn",
					token = "fetch_async",
					role = "DxCallable",
					desc = "Python async standalone function",
				},
				{
					tag = "python.pattern.regexp",
					token = "DX42",
					role = "DxString",
					desc = "Python regular expression string pattern (re.compile)",
				},
			},
		},
	},
}

return M
