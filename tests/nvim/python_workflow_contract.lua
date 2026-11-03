-- Pure configuration contract: no LSP, venv-selector, Neotest or DAP startup.
local context = require("config.python_context")
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
root = assert(vim.uv.fs_realpath(root))
local original_uv = vim.env.UV_PROJECT_ENVIRONMENT
vim.env.UV_PROJECT_ENVIRONMENT = nil
local system = context.require_context(root)
assert(system.source == "system", "plain project must use an available system interpreter")
assert(system.env.VIRTUAL_ENV == "" and system.env.CONDA_PREFIX == "", "system Python must not impersonate a venv")
local specs = dofile("home/dot_config/nvim/lua/plugins/python.lua")
local before_init = specs[2].opts.servers.pyright.before_init
local config =
	{ root_dir = root, settings = { python = { pythonPath = "explicit-user-python" } }, cmd_env = { KEEP = "yes" } }
before_init({}, config)
assert(
	config.settings.python.pythonPath == "explicit-user-python",
	"system fallback changed explicit Pyright configuration"
)
assert(vim.deep_equal(config.cmd_env, { KEEP = "yes" }), "system fallback fabricated a Pyright virtual environment")

vim.fn.writefile({ "version = 1" }, root .. "/uv.lock")
local absent, missing = context.resolve(root)
assert(absent == nil and missing:find("unavailable", 1, true), "missing uv env must not use ambient Python")
local environment = root .. "/custom env"
vim.fn.mkdir(environment .. "/bin", "p")
assert(vim.uv.fs_symlink(system.python, environment .. "/bin/python"))
vim.env.UV_PROJECT_ENVIRONMENT = "custom env"
local relative = context.require_context(root)
assert(relative.python == environment .. "/bin/python", "relative uv custom path was not rooted at the uv project")
vim.env.UV_PROJECT_ENVIRONMENT = environment
assert(context.require_context(root).python == relative.python, "absolute uv custom path drifted")
config = { root_dir = root }
before_init({}, config)
assert(config.cmd_env.VIRTUAL_ENV == environment, "Pyright rollback lost the real project environment")
-- A nested venv wins over an enclosing Conda environment consistently.
vim.fn.delete(root .. "/uv.lock")
local previous_cwd, previous_venv, previous_conda = vim.fn.getcwd(), vim.env.VIRTUAL_ENV, vim.env.CONDA_PREFIX
vim.env.UV_PROJECT_ENVIRONMENT = nil
vim.env.VIRTUAL_ENV, vim.env.CONDA_PREFIX = environment, root .. "/outer-conda"
vim.cmd.cd(root)
local nested_context = dofile(previous_cwd .. "/home/dot_config/nvim/lua/config/python_context.lua")
local nested = nested_context.require_context(root)
assert(
	nested.env.VIRTUAL_ENV == environment and nested.env.CONDA_PREFIX == "",
	"nested venv was mislabeled as Conda: "
		.. vim.inspect(nested)
		.. " cwd="
		.. vim.fn.getcwd()
		.. " root="
		.. nested_context.root(root)
)
vim.env.VIRTUAL_ENV, vim.env.CONDA_PREFIX = previous_venv, previous_conda
vim.cmd.cd(previous_cwd)
vim.env.UV_PROJECT_ENVIRONMENT = original_uv
vim.fn.delete(root, "rf")
print("Python workflow configuration contract passed")
