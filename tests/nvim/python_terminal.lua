-- Real child processes and Snacks terminals; only disposable fixture files change.
local context = require("config.python_context")
local fixture = assert(vim.uv.fs_realpath(assert(vim.env.DOTFILES_PYTHON_FIXTURES)))
require("lazy").load({ plugins = { "venv-selector.nvim" } })
local selector = require("venv-selector")
local a, b, plain = fixture .. "/terminal-a", fixture .. "/terminal-b", fixture .. "/terminal-plain"
for _, root in ipairs({ a, b, plain }) do
	vim.fn.mkdir(root .. "/.git", "p")
	vim.fn.writefile({ "value = 1" }, root .. "/probe.py")
	vim.fn.writefile({ "plain project" }, root .. "/README.txt")
end
assert(vim.fn.executable(a .. "/.venv/bin/python") == 1, "terminal A environment fixture is missing")
assert(vim.fn.executable(b .. "/.venv/bin/python") == 1, "terminal B environment fixture is missing")
local probe = fixture .. "/terminal-observe.py"
vim.fn.writefile({
	"import json, os, sys",
	"def record():",
	"    value = {'python': sys.executable, 'prefix': os.path.realpath(sys.prefix), 'cwd': os.getcwd(), 'venv': os.environ.get('VIRTUAL_ENV'), 'conda': os.environ.get('CONDA_PREFIX'), 'path': os.environ['PATH']}",
	"    with open(sys.argv[1], 'a') as handle: handle.write(json.dumps(value) + '\\n')",
	"record()",
	"if len(sys.argv) > 2:",
	"    input()",
	"    record()",
}, probe)
local evidence = {}
local editor_window = vim.api.nvim_get_current_win()
local function eq(actual, expected, message)
	assert(vim.deep_equal(actual, expected), message .. ": " .. vim.inspect(actual) .. " ~= " .. vim.inspect(expected))
end
local function wait(message, predicate)
	assert(vim.wait(10000, predicate, 10), message)
end
local function records(file)
	return vim.fn.filereadable(file) == 1 and vim.tbl_map(vim.json.decode, vim.fn.readfile(file)) or {}
end
local function edit(root, file)
	vim.api.nvim_set_current_win(editor_window)
	vim.cmd.edit(vim.fn.fnameescape(root .. "/" .. (file or "probe.py")))
	context.activate(vim.api.nvim_get_current_buf())
end
local function child(label, root)
	local file = fixture .. "/terminal-" .. label .. ".jsonl"
	local command = "exec python3 " .. vim.fn.shellescape(probe) .. " " .. vim.fn.shellescape(file)
	local result = vim.system({ "/bin/sh", "-c", command }, { cwd = root, text = true }):wait(10000)
	eq(result.code, 0, label .. " child failed: " .. (result.stderr or ""))
	local observed = assert(records(file)[1], label .. " child did not record")
	evidence[#evidence + 1] = { label = label, observed = observed }
	return observed
end
local terminals = {}
local function terminal(label, source, hold)
	local file = fixture .. "/terminal-" .. label .. ".jsonl"
	local command = "exec python3 "
		.. vim.fn.shellescape(probe)
		.. " "
		.. vim.fn.shellescape(file)
		.. (hold and " wait" or "")
	local term = assert(
		context.terminal(source, {
			command = { "/bin/sh", "-c", command },
			interactive = false,
			auto_close = false,
		}),
		"project terminal was not opened"
	)
	terminals[#terminals + 1] = term
	wait(label .. " terminal did not record", function()
		return #records(file) == 1
	end)
	local observed = records(file)[1]
	evidence[#evidence + 1] = { label = label, observed = observed }
	return term, observed, file
end
local function env_python(observed, root, label)
	eq(observed.python, root .. "/.venv/bin/python3", label .. " interpreter")
	eq(observed.venv, root .. "/.venv", label .. " VIRTUAL_ENV")
	eq(observed.prefix, vim.uv.fs_realpath(root .. "/.venv"), label .. " actual Python prefix")
end

-- Load filetype integrations (including Mason PATH setup) before the baseline.
edit(plain)
-- Begin from released editor-owned state; inherited external state is a baseline.
selector.deactivate()
local baseline_path, baseline_venv, baseline_conda = vim.env.PATH, vim.env.VIRTUAL_ENV, vim.env.CONDA_PREFIX
local baseline_uv = vim.env.UV_PROJECT_ENVIRONMENT
local baseline = child("baseline", plain)
vim.env.UV_PROJECT_ENVIRONMENT = nil
edit(a)
selector.activate_from_path(a .. "/.venv/bin/python", "venv")
env_python(child("activated-a", a), a, "A")
selector.deactivate()
eq(vim.env.PATH, baseline_path, "deactivation left editor-owned PATH behind")
eq(vim.env.VIRTUAL_ENV, baseline_venv, "deactivation changed inherited VIRTUAL_ENV")
eq(vim.env.CONDA_PREFIX, baseline_conda, "deactivation changed inherited CONDA_PREFIX")
eq(child("deactivated-a", a).python, baseline.python, "new child still uses deactivated A")
selector.activate_from_path(a .. "/.venv/bin/python", "venv")
env_python(child("reactivated-a", a), a, "same-environment reactivation")

local custom_bin = fixture .. "/user-added-bin"
vim.fn.mkdir(custom_bin, "p")
vim.env.PATH = custom_bin .. ":" .. vim.env.PATH
edit(b)
wait("B did not become active", function()
	return selector.python() == b .. "/.venv/bin/python"
end)
env_python(child("activated-b", b), b, "B")
assert(vim.env.PATH:find(custom_bin, 1, true), "environment switch erased later PATH edits")
edit(plain)
wait("plain project did not release previous environment", function()
	return selector.python() == nil
end)
eq(vim.env.PATH, custom_bin .. ":" .. baseline_path, "plain project changed unrelated PATH entries")
eq(child("plain-after-b", plain).python, baseline.python, "plain project inherited editor-selected B")

-- A pre-existing external environment must survive editor selection/deactivation.
local external = fixture .. "/manual/env"
vim.env.PATH = external .. "/bin:" .. vim.env.PATH
vim.env.VIRTUAL_ENV, vim.env.CONDA_PREFIX = external, "external-conda-context"
local external_path = vim.env.PATH
edit(a)
selector.activate_from_path(a .. "/.venv/bin/python", "venv")
selector.deactivate()
eq(vim.env.PATH, external_path, "inherited external PATH was removed")
eq(vim.env.VIRTUAL_ENV, external, "inherited external venv was lost")
eq(vim.env.CONDA_PREFIX, "external-conda-context", "inherited external Conda state was lost")
eq(child("external-restored", plain).python, external .. "/bin/python3", "external interpreter was not restored")

-- New project terminals use their explicit target even while editor cwd is B.
edit(a)
selector.activate_from_path(a .. "/.venv/bin/python", "venv")
vim.cmd.cd(b)
local running, observed_a, running_file = terminal("target-a", a .. "/probe.py", true)
env_python(observed_a, a, "A project terminal")
eq(observed_a.cwd, a, "project terminal used ambient cwd B")
assert(observed_a.path:find(custom_bin, 1, true), "project terminal lost later user PATH addition")
assert(not observed_a.path:find(external .. "/bin", 1, true), "project terminal leaked external interpreter PATH")
edit(b)
local _, observed_b = terminal("target-b", b .. "/probe.py")
env_python(observed_b, b, "B project terminal")
eq(observed_b.cwd, b, "B project terminal cwd")
local channel = assert(vim.b[running.buf].terminal_job_id)
vim.fn.chansend(channel, "\n")
wait("original A terminal did not resume", function()
	return #records(running_file) == 2
end)
eq(records(running_file)[2], observed_a, "switching projects changed an existing terminal process")
edit(plain, "README.txt")
wait("non-Python project retained B's active terminal state", function()
	return selector.python() == nil
end)
eq(vim.env.PATH, external_path, "non-Python project did not restore external PATH")

-- Exercise the user command with a real interactive shell as well as the API.
edit(a)
selector.activate_from_path(a .. "/.venv/bin/python", "venv")
vim.cmd.cd(b)
assert(vim.fn.exists(":PythonProjectTerminal") == 2, "project terminal command is missing")
assert(vim.fn.maparg("<leader>fP", "n") ~= "", "project terminal key is missing")
local shell = vim.o.shell
vim.o.shell = "/bin/sh"
vim.cmd.PythonProjectTerminal()
vim.o.shell = shell
local shell_buf = vim.api.nvim_get_current_buf()
assert(vim.bo[shell_buf].buftype == "terminal", "command did not focus a real terminal")
local shell_file = fixture .. "/terminal-command.jsonl"
vim.fn.chansend(
	assert(vim.b[shell_buf].terminal_job_id),
	"python3 " .. vim.fn.shellescape(probe) .. " " .. vim.fn.shellescape(shell_file) .. "\n"
)
wait("project terminal shell did not execute", function()
	return #records(shell_file) == 1
end)
local shell_observed = records(shell_file)[1]
env_python(shell_observed, a, "project terminal command")
eq(shell_observed.cwd, a, "command used ambient cwd B")
evidence[#evidence + 1] = { label = "project-command", observed = shell_observed }
for _, term in pairs(Snacks.terminal.list()) do
	if term.buf == shell_buf then
		terminals[#terminals + 1] = term
	end
end

-- Explicit deactivation selects the system interpreter for this project's terminal.
edit(a)
selector.deactivate()
local deactivated = context.require_context(a)
eq(deactivated.source, "deactivated", "explicit project deactivation was forgotten")
local prefix_result = vim.system(
	{ deactivated.python, "-c", "import os,sys;print(os.path.realpath(sys.prefix))" },
	{ text = true }
):wait(10000)
eq(prefix_result.code, 0, "system interpreter prefix probe failed")
local _, deactivated_observed = terminal("deactivated-target-a", a .. "/probe.py")
eq(deactivated_observed.cwd, a, "deactivated terminal lost its target root")
eq(
	deactivated_observed.prefix,
	vim.trim(prefix_result.stdout),
	"deactivated terminal did not use the system interpreter"
)
eq(deactivated_observed.venv, "", "deactivated terminal fabricated a venv")
eq(deactivated_observed.conda, "", "deactivated terminal leaked ambient Conda")
assert(not deactivated_observed.path:find(a .. "/.venv/bin", 1, true), "deactivated terminal retained A on PATH")

-- Missing required project environments fail before a terminal or environment change.
local missing = fixture .. "/terminal-missing"
vim.fn.mkdir(missing, "p")
vim.fn.writefile({ "version = 1" }, missing .. "/uv.lock")
local before_missing = { vim.env.PATH, vim.env.VIRTUAL_ENV, vim.env.CONDA_PREFIX }
local count_before = vim.tbl_count(Snacks.terminal.list())
local notify, warning = vim.notify
vim.notify = function(message)
	warning = message
end
local missing_ok, missing_result = pcall(context.terminal, missing)
vim.notify = notify
assert(missing_ok and missing_result == nil, "missing environment created a project terminal")
assert(warning and warning:find("unavailable", 1, true), "missing environment lost the actionable warning")
eq(vim.tbl_count(Snacks.terminal.list()), count_before, "missing environment opened a terminal")
eq(
	{ vim.env.PATH, vim.env.VIRTUAL_ENV, vim.env.CONDA_PREFIX },
	before_missing,
	"failed terminal resolution mutated global environment"
)

-- Preserve explicit user edits made after editor activation, not an old snapshot.
edit(a)
selector.activate_from_path(a .. "/.venv/bin/python", "venv")
vim.env.VIRTUAL_ENV = "user-changed-external"
vim.env.CONDA_PREFIX = "user-changed-conda"
selector.deactivate()
eq(vim.env.VIRTUAL_ENV, "user-changed-external", "deactivation overwrote a later explicit environment edit")
eq(vim.env.CONDA_PREFIX, "user-changed-conda", "deactivation overwrote a later explicit Conda edit")
for _, term in ipairs(terminals) do
	term:close()
end
vim.env.PATH, vim.env.VIRTUAL_ENV, vim.env.CONDA_PREFIX = baseline_path, baseline_venv, baseline_conda
vim.env.UV_PROJECT_ENVIRONMENT = baseline_uv
print("PYTHON_TERMINAL_EVIDENCE " .. vim.json.encode(evidence))
print("PYTHON_TERMINAL_COMPLETE")
