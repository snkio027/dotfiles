local function contains(values, expected)
	return vim.tbl_contains(values or {}, expected)
end

assert(vim.fn.exists(":OverseerRun") == 2, "Overseer command is unavailable")
assert(vim.fn.exists(":MasonToolsInstallSync") == 2, "Mason tool installer command is unavailable")

local mason = LazyVim.opts("mason.nvim")
for _, tool in ipairs({
	"clangd",
	"clang-format",
	"codelldb",
	"debugpy",
	"pyright",
	"ruff",
	"ty",
	"zls",
	"delve",
	"gopls",
}) do
	assert(contains(mason.ensure_installed, tool), ("Mason tool is missing: %s"):format(tool))
end

require("lazy").load({ plugins = { "mason.nvim" } })
for _, executable in ipairs({
	"clangd",
	"clang-format",
	"codelldb",
	"debugpy",
	"pyright",
	"ruff",
	"ty",
	"zls",
	"dlv",
	"gofumpt",
	"goimports",
	"golangci-lint",
	"gopls",
}) do
	assert(vim.fn.executable(executable) == 1, ("Mason executable is unavailable: %s"):format(executable))
end

local rust = LazyVim.opts("rustaceanvim")
local rust_analyzer = rust.server.default_settings["rust-analyzer"]
assert(rust_analyzer.check.command == "clippy", "rust-analyzer is not using Clippy")

local cmake = LazyVim.opts("cmake-tools.nvim")
assert(contains(cmake.cmake_generate_options, "-DCMAKE_EXPORT_COMPILE_COMMANDS=1"), "CMake compile DB is disabled")
assert(contains(cmake.cmake_generate_options, "-DCMAKE_CXX_COMPILER_LAUNCHER=ccache"), "CMake is not using ccache")
assert(cmake.cmake_executor.name == "overseer", "CMake executor is not Overseer")
assert(cmake.cmake_runner.name == "overseer", "CMake runner is not Overseer")
assert(cmake.cmake_dap_configuration.type == "codelldb", "CMake debugger is not codelldb")

local neotest = LazyVim.opts("neotest")
assert(neotest.adapters["neotest-golang"].dap_go_enabled, "Go tests are not debuggable")
assert(neotest.adapters["neotest-python"].runner == "pytest", "Python tests are not using pytest")

require("lazy").load({ plugins = { "nvim-dap" } })
local dap = require("dap")
assert(dap.adapters.codelldb, "codelldb adapter is unavailable")
assert(#(dap.configurations.zig or {}) >= 2, "Zig launch/attach configurations are unavailable")

print("Neovim toolchain smoke tests passed")
