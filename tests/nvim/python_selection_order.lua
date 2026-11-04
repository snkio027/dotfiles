-- Exercise the plugin's real cache callback with deterministic event ordering.
local context = require("config.python_context")
local fixture = assert(vim.env.DOTFILES_PYTHON_FIXTURES)
fixture = assert(vim.uv.fs_realpath(fixture))
local old = fixture .. "/project-a/.venv/bin/python"
local selected = fixture .. "/manual/env/bin/python"
local project = fixture .. "/selection-order"
vim.fn.mkdir(project .. "/.git", "p")
vim.fn.writefile({ "value = 1" }, project .. "/first.py")
vim.fn.writefile({ "value = 2" }, project .. "/second.py")
vim.cmd.edit(project .. "/first.py")
local first = vim.api.nvim_get_current_buf()
assert(vim.wait(5000, function()
	return package.loaded["venv-selector"] ~= nil
end, 10))
local selector = require("venv-selector")
local cache = require("venv-selector.cached_venv")
local hooks = require("venv-selector.config").user_settings.hooks
local hook_calls = 0
local observer = function()
	hook_calls = hook_calls + 1
	return 0
end
hooks[#hooks + 1] = observer

local function eq(actual, expected, message)
	assert(vim.deep_equal(actual, expected), message .. ": " .. vim.inspect(actual) .. " ~= " .. vim.inspect(expected))
end
local function snapshot(buf)
	local resolved = context.require_context(project)
	return {
		python = selector.python(),
		resolved = resolved.python,
		source = resolved.source,
		virtual_env = vim.env.VIRTUAL_ENV,
		conda_prefix = vim.env.CONDA_PREFIX,
		path = vim.env.PATH,
		last = vim.b[buf].venv_selector_last_python,
		kind = vim.b[buf].venv_selector_last_type,
		hooks = hook_calls,
	}
end
local function hold_restore(buf)
	local callbacks = {}
	local schedule = vim.schedule
	vim.schedule = function(callback)
		callbacks[#callbacks + 1] = callback
	end
	local ok, err = pcall(cache.retrieve, buf)
	vim.schedule = schedule
	assert(ok, err)
	eq(#callbacks, 1, "real cache restore did not schedule exactly one callback")
	return callbacks[1]
end

-- A persisted external environment is valid before any explicit choice this session.
cache.save(old, "venv", first)
hold_restore(first)()
eq(selector.python(), old, "initial cache restore was rejected")
eq(context.require_context(project).python, old, "initial cache restore was not remembered")

local restore_old = hold_restore(first)
selector.activate_from_path(selected, "venv")
local before = snapshot(first)
restore_old()
eq(snapshot(first), before, "stale restore changed a newer explicit choice or its side effects")

-- A later actual user choice still wins; a matching auto restore keeps that priority.
selector.activate_from_path(old, "venv")
eq(context.require_context(project).python, old, "later explicit choice was rejected")
hold_restore(first)()
cache.save(selected, "venv", first)
local restore_selected = hold_restore(first)
before = snapshot(first)
restore_selected()
eq(snapshot(first), before, "matching cache restore erased explicit-choice priority")

-- A callback for another buffer in the same project must respect deactivation too.
vim.cmd.edit(project .. "/second.py")
local second = vim.api.nvim_get_current_buf()
cache.save(old, "venv", second)
local restore_sibling = hold_restore(second)
vim.api.nvim_set_current_buf(first)
selector.deactivate()
before = snapshot(second)
restore_sibling()
eq(snapshot(second), before, "queued sibling restore undid explicit deactivation")
eq(context.require_context(project).source, "deactivated", "deactivation priority was lost")
selector.activate_from_path(selected, "venv")
eq(context.require_context(project).python, selected, "explicit reactivation did not recover")

for index, hook in ipairs(hooks) do
	if hook == observer then
		table.remove(hooks, index)
		break
	end
end
print("PYTHON_SELECTION_ORDER_COMPLETE")
