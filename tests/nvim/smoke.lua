local function contains(values, expected)
	return vim.tbl_contains(values or {}, expected)
end

assert(vim.fn.exists(":OverseerRun") == 2, "Overseer command is unavailable")
assert(vim.fn.exists(":MasonToolsInstallSync") == 2, "Mason tool installer command is unavailable")

local installer_opts = LazyVim.opts("mason-tool-installer.nvim")
assert(installer_opts.auto_update == false, "Mason tools must not update automatically")
assert(installer_opts.run_on_start == false, "mason-tool-installer must not run on startup")
assert(not package.loaded["mason-tool-installer"], "mason-tool-installer loaded without an explicit command")

local cpp = require("config.cpp")
local cpp_buffer = vim.api.nvim_create_buf(false, true)
cpp.configure_buffer(cpp_buffer)
assert(vim.bo[cpp_buffer].expandtab, "C/C++ buffers must use spaces")
assert(vim.bo[cpp_buffer].tabstop == 4, "C/C++ tabstop must match clang-format")
assert(vim.bo[cpp_buffer].shiftwidth == 4, "C/C++ shiftwidth must match clang-format")
assert(vim.bo[cpp_buffer].softtabstop == 4, "C/C++ softtabstop must match clang-format")
vim.api.nvim_buf_delete(cpp_buffer, { force = true })

local managed_fixture = vim.fn.tempname()
local managed_source = vim.fs.joinpath(managed_fixture, "src", "main.cpp")
vim.fn.mkdir(vim.fs.dirname(managed_source), "p")
vim.fn.writefile({ "int main() {}" }, managed_source)
vim.fn.writefile({ "schema_version = 1" }, vim.fs.joinpath(managed_fixture, ".cxx.toml"))
local database = cpp.compile_database(managed_fixture)
assert(database == vim.fs.joinpath(managed_fixture, "build", "dev", "compile_commands.json"))

local warning_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(warning_buffer, managed_source)
local original_notify = vim.notify
local compile_database_warnings = {}
vim.notify = function(message, level, opts)
	compile_database_warnings[#compile_database_warnings + 1] = { message = message, level = level, opts = opts }
end
assert(cpp.warn_if_compile_database_missing(warning_buffer) == true)
assert(cpp.warn_if_compile_database_missing(warning_buffer) == false)
vim.fn.mkdir(vim.fs.dirname(database), "p")
vim.fn.writefile({ "[]" }, database)
assert(cpp.warn_if_compile_database_missing(warning_buffer) == false)
vim.notify = original_notify
assert(#compile_database_warnings == 1, "Managed C++ project warning must be emitted exactly once")
assert(compile_database_warnings[1].message:find("build/dev/compile_commands.json", 1, true))
assert(compile_database_warnings[1].message:find("cmake --workflow --preset dev", 1, true))
assert(compile_database_warnings[1].message:find(":LspRestart", 1, true))
assert(compile_database_warnings[1].level == vim.log.levels.WARN)
vim.api.nvim_buf_delete(warning_buffer, { force = true })

local editorconfig_fixture = vim.fn.tempname()
local editorconfig_source = vim.fs.joinpath(editorconfig_fixture, "src", "main.cpp")
vim.fn.mkdir(vim.fs.joinpath(editorconfig_fixture, "build", "dev"), "p")
vim.fn.mkdir(vim.fs.dirname(editorconfig_source), "p")
vim.fn.writefile({ "schema_version = 1" }, vim.fs.joinpath(editorconfig_fixture, ".cxx.toml"))
vim.fn.writefile({ "[]" }, cpp.compile_database(editorconfig_fixture))
vim.fn.writefile(
	{ "root = true", "", "[*.cpp]", "indent_style = space", "indent_size = 2" },
	vim.fs.joinpath(editorconfig_fixture, ".editorconfig")
)
vim.fn.writefile({ "int main() {}" }, editorconfig_source)
vim.cmd.edit(vim.fn.fnameescape(editorconfig_source))
assert(vim.bo.filetype == "cpp", "EditorConfig fixture did not load as C++")
assert(vim.bo.expandtab, "EditorConfig indent_style did not override the C++ fallback")
assert(vim.bo.tabstop == 2, "EditorConfig indent_size did not override C++ tabstop")
assert(vim.bo.shiftwidth == 2, "EditorConfig indent_size did not override C++ shiftwidth")
local effective_softtabstop = vim.bo.softtabstop < 0 and vim.bo.shiftwidth or vim.bo.softtabstop
assert(effective_softtabstop == 2, "EditorConfig indent_size did not override C++ softtabstop")
vim.api.nvim_buf_delete(0, { force = true })

for _, database_mode in ipairs({ "Ancestors", "None" }) do
	local unmanaged_fixture = vim.fn.tempname()
	local unmanaged_source = vim.fs.joinpath(unmanaged_fixture, "src", "main.cpp")
	vim.fn.mkdir(vim.fs.dirname(unmanaged_source), "p")
	vim.fn.writefile({ "int main() {}" }, unmanaged_source)
	vim.fn.writefile(
		{ "CompileFlags:", "  CompilationDatabase: " .. database_mode },
		vim.fs.joinpath(unmanaged_fixture, ".clangd")
	)
	local unmanaged_buffer = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(unmanaged_buffer, unmanaged_source)
	assert(cpp.warn_if_compile_database_missing(unmanaged_buffer) == nil, database_mode .. " caused a false warning")
	vim.api.nvim_buf_delete(unmanaged_buffer, { force = true })
	vim.fn.delete(unmanaged_fixture, "rf")
end

vim.fn.delete(managed_fixture, "rf")
vim.fn.delete(editorconfig_fixture, "rf")

require("lazy").load({ plugins = { "mini.icons" } })
local icon_cases_path = vim.fn.getcwd() .. "/tests/icons/generated_cases.json"
local icon_payload = vim.json.decode(table.concat(vim.fn.readfile(icon_cases_path), "\n"))
local mini_icons = require("mini.icons")
local verified_icons = 0
for _, case in ipairs(icon_payload.explicit_cases) do
	local glyph, highlight = mini_icons.get("file", case.fixture)
	assert(glyph == case.glyph, ("Icon glyph mismatch for %s"):format(case.pattern))
	assert(highlight == case.nvim_highlight, ("Icon highlight mismatch for %s"):format(case.pattern))
	verified_icons = verified_icons + 1
end
assert(verified_icons == icon_payload.explicit_expected, "Explicit icon mappings are incomplete")

local runtime_verified = 0
for _, case in ipairs(icon_payload.runtime_observations.nvim) do
	local glyph, highlight = mini_icons.get(case.kind, case.fixture)
	if glyph == case.glyph and highlight == case.highlight then
		runtime_verified = runtime_verified + 1
	else
		print(
			("Neovim runtime drift %s: baseline=%s/%s upstream=%s/%s"):format(
				case.label,
				case.glyph,
				case.highlight,
				glyph,
				highlight
			)
		)
	end
end

local verified_colors = 0
for role, expected in pairs(icon_payload.color_roles) do
	local highlight = vim.api.nvim_get_hl(0, { name = expected.nvim_highlight, link = false })
	local expected_rgb = tonumber(expected.rgb:sub(2), 16)
	assert(
		highlight.fg == expected_rgb,
		("Final RGB mismatch for %s/%s: expected %s, got #%06x"):format(
			role,
			expected.nvim_highlight,
			expected.rgb,
			highlight.fg or 0
		)
	)
	verified_colors = verified_colors + 1
end
assert(verified_colors == icon_payload.color_role_expected, "Color role coverage is incomplete")

print(("Audit scope                 %d/%d"):format(icon_payload.audit_expected, icon_payload.audit_expected))
print(("Explicit consumer mappings  %d/%d"):format(verified_icons, icon_payload.explicit_expected))
print(("Real-project observations   %d/%d"):format(icon_payload.real_project_expected, icon_payload.audit_expected))
print(("Final highlight RGB roles   %d/%d"):format(verified_colors, icon_payload.color_role_expected))
print(
	("Neovim runtime observations %d/%d (informational)"):format(
		runtime_verified,
		#icon_payload.runtime_observations.nvim
	)
)

local mason = LazyVim.opts("mason.nvim")
local mason_names = {}
local codelldb_count = 0
for _, tool in ipairs(mason.ensure_installed or {}) do
	local name = require("config.mason").tool_name(tool)
	assert(not mason_names[name], ("Duplicate Mason tool: %s"):format(name))
	mason_names[name] = true
	if name == "codelldb" then
		codelldb_count = codelldb_count + 1
	end
end
assert(codelldb_count == 1, ("Expected codelldb exactly once, got %d"):format(codelldb_count))
for _, tool in ipairs({
	"codelldb",
	"gersemi",
	"markdownlint-cli2",
	"debugpy",
	"pyright",
	"ruff",
	"sqlfluff",
	"ty",
	"zls",
	"delve",
	"gopls",
}) do
	assert(contains(mason.ensure_installed, tool), ("Mason tool is missing: %s"):format(tool))
end
assert(not contains(mason.ensure_installed, "clangd"), "Mason must not shadow Homebrew clangd")
assert(not contains(mason.ensure_installed, "clang-format"), "Mason must not shadow Homebrew clang-format")
assert(not contains(mason.ensure_installed, "cmakelang"), "Obsolete cmakelang should not be installed")
assert(not contains(mason.ensure_installed, "cmakelint"), "Obsolete cmakelint should not be installed")

require("lazy").load({ plugins = { "mason.nvim" } })
for _, executable in ipairs({
	"codelldb",
	"gersemi",
	"markdownlint-cli2",
	"debugpy",
	"pyright",
	"ruff",
	"sqlfluff",
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

local lsp = LazyVim.opts("nvim-lspconfig")
local clangd = lsp.servers.clangd
assert(clangd.mason == false, "Homebrew clangd must be enabled outside Mason")
assert(clangd.cmd[1]:match("/opt/llvm/bin/clangd$"), "clangd is not from Homebrew LLVM")
assert(vim.fn.executable(clangd.cmd[1]) == 1, "Homebrew clangd is unavailable")
assert(not contains(clangd.cmd, "--function-arg-placeholders"), "clangd has an invalid placeholders flag")
assert(lsp.servers.neocmake.init_options.lint.enable, "neocmake lint is disabled")
assert(not lsp.servers.neocmake.init_options.format.enable, "neocmake competes with gersemi formatting")

local config_home = vim.env.XDG_CONFIG_HOME or vim.fs.dirname(vim.fn.stdpath("config"))
local neocmake_config = config_home .. "/neocmakelsp/config.toml"
local neocmake_config_lines = vim.fn.readfile(neocmake_config)
assert(contains(neocmake_config_lines, "line_max_words = 100"), "neocmake line length is not 100 columns")
assert(contains(neocmake_config_lines, "enable_external_cmake_lint = false"), "neocmake external cmake-lint is enabled")

local conform = LazyVim.opts("conform.nvim")
local clang_format = conform.formatters["clang-format"].command
assert(clang_format:match("/opt/llvm/bin/clang%-format$"), "clang-format is not from Homebrew LLVM")
assert(vim.fn.executable(clang_format) == 1, "Homebrew clang-format is unavailable")
assert(contains(conform.formatters_by_ft.cmake, "gersemi"), "CMake is not formatted by gersemi")
assert(contains(conform.formatters.gersemi.prepend_args, "100"), "CMake line length is not 100 columns")

local lint = LazyVim.opts("nvim-lint")
assert(vim.tbl_isempty(lint.linters_by_ft.cmake), "Redundant external cmakelint is still enabled")

local function llvm_major(command)
	local output = vim.fn.system({ command, "--version" })
	assert(vim.v.shell_error == 0, ("Unable to query %s"):format(command))
	return output:match("version%s+(%d+)")
end

assert(llvm_major(clangd.cmd[1]) == llvm_major(clang_format), "clangd and clang-format versions differ")

require("lazy").load({ plugins = { "nvim-lspconfig" } })
assert(vim.lsp.is_enabled("clangd"), "Homebrew clangd is configured but not enabled")

require("lazy").load({ plugins = { "SchemaStore.nvim" } })
local yaml_config = { settings = { yaml = { schemas = {} } } }
lsp.servers.yamlls.before_init(nil, yaml_config)
for _, matches in pairs(yaml_config.settings.yaml.schemas) do
	for _, pattern in ipairs(type(matches) == "table" and matches or { matches }) do
		assert(pattern ~= ".clang-format", "Obsolete clang-format schema is still enabled")
	end
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
