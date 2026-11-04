-- Run with the isolated full-config runner and pre-created, offline fixtures.
-- See python_workflow_fixtures.py; no package installation occurs in this test.
local test_dir = vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"))
local fixture_path = assert(vim.env.DOTFILES_PYTHON_FIXTURES, "DOTFILES_PYTHON_FIXTURES is required")
local fixture = assert(vim.uv.fs_realpath(fixture_path))
local a, b, c = fixture .. "/project-a", fixture .. "/project-b", fixture .. "/project-c"
local manual = fixture .. "/manual/env/bin/python"
local context = require("config.python_context")
vim.env.PYTHONPATH = fixture .. "/packages"
vim.env.PYTEST_DISABLE_PLUGIN_AUTOLOAD = "1"
vim.env.UV_PROJECT_ENVIRONMENT = nil
local evidence = {}
local function wait(message, condition, timeout)
	assert(vim.wait(timeout or 15000, condition, 20), message)
end
local function eq(actual, expected, message)
	assert(vim.deep_equal(actual, expected), message .. ": " .. vim.inspect(actual) .. " ~= " .. vim.inspect(expected))
end
local function records(root)
	local file = root .. "/runs.jsonl"
	if vim.fn.filereadable(file) == 0 then
		return {}
	end
	return vim.tbl_map(vim.json.decode, vim.fn.readfile(file))
end
local function edit(root, custom)
	vim.env.UV_PROJECT_ENVIRONMENT = custom
	vim.cmd.edit(root .. "/test_context.py")
	vim.api.nvim_win_set_cursor(0, { 9, 0 })
	wait("automatic target environment activation", function()
		return package.loaded["venv-selector"]
			and require("venv-selector").python() == root .. "/" .. (custom or ".venv") .. "/bin/python"
	end)
end
for _, root in ipairs({ a, b, c }) do
	vim.fn.delete(root .. "/runs.jsonl")
end
edit(a)
local finished = {}
local plugin = require("lazy.core.config").plugins.neotest
local configure = plugin.config
plugin.config = function(spec, opts)
	opts.consumers = opts.consumers or {}
	opts.consumers.python_workflow = function(client)
		client.listeners.results = function(_, results, partial)
			if partial then
				return
			end
			for _, root in ipairs({ a, b, c }) do
				for id in pairs(results) do
					if id:sub(1, #root) == root then
						finished[root] = (finished[root] or 0) + 1
						break
					end
				end
			end
		end
		return {}
	end
	configure(spec, opts)
end
require("lazy").load({ plugins = { "neotest", "nvim-dap" } })
plugin.config = configure
local neotest = require("neotest")
local function run(label, root, action, expected)
	local count = #records(root)
	local completed = finished[root] or 0
	action()
	wait(label .. " did not execute", function()
		return #records(root) > count
	end, 30000)
	local result = records(root)[count + 1]
	eq(
		result.python,
		expected or root .. (root == a and "/.venv/bin/python" or "/custom-env/bin/python"),
		label .. " python"
	)
	eq(result.cwd, root, label .. " cwd")
	evidence[#evidence + 1] = { action = label, observed = result }
	wait(label .. " still running", function()
		if (finished[root] or 0) <= completed then
			return false
		end
		for _, task in ipairs(require("overseer").list_tasks({ unique = false })) do
			if task.status == "RUNNING" then
				return false
			end
		end
		return true
	end)
end
run("A nearest", a, function()
	neotest.run.run()
end)
edit(b, "custom-env")
run("A RunLast while B active", a, function()
	neotest.run.run_last()
end)
run("B nearest", b, function()
	neotest.run.run()
end)

run("C .git-only discovery while B active", c, function()
	neotest.run.run(c .. "/test_context.py")
end, c .. "/.venv/bin/python")
run("C .git-only RunLast while B active", c, function()
	neotest.run.run_last()
end, c .. "/.venv/bin/python")

-- Use the real summary mapping on A while cwd and ambient venv still belong to B.
vim.cmd.cd(b)
neotest.summary.open({ enter = true })
wait("summary buffer missing", function()
	return vim.bo.filetype == "neotest-summary"
end)
neotest.summary:expand(a, true)
wait("summary A test not rendered", function()
	local target_section = false
	for i, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
		if line:find("project-a", 1, true) then
			target_section = true
		end
		if target_section and line:find("test_context.py", 1, true) then
			vim.api.nvim_win_set_cursor(0, { i, 0 })
			return true
		end
	end
	return false
end)
run("summary A while B active", a, function()
	local mapping = vim.fn.maparg("r", "n", false, true)
	assert(type(mapping.callback) == "function", "summary run mapping absent")
	mapping.callback()
end)
neotest.summary.close()

-- A real debugpy stop evaluates sys.executable inside the debuggee.
local dap = require("dap")
local function debug_run(label, root, action)
	local observed, reason, debug_error
	local count = #records(root)
	dap.listeners.after.event_stopped.python_workflow = function(session, body)
		reason = body.reason
		session:request("stackTrace", { threadId = body.threadId }, function(err, stack)
			if err then
				debug_error = vim.inspect(err)
				return
			end
			session:request("evaluate", {
				frameId = stack.stackFrames[1].id,
				expression = "__import__('sys').executable + '|' + __import__('os').getcwd() + '|' + str(__import__('os').getenv('DOTFILES_TARGET'))",
				context = "repl",
			}, function(eval_err, response)
				if eval_err then
					debug_error = vim.inspect(eval_err)
					return
				end
				observed = response.result
			end)
		end)
	end
	action()
	wait(label .. " did not reach a breakpoint", function()
		return observed or debug_error
	end, 45000)
	assert(not debug_error, debug_error)
	eq(reason, "breakpoint", label .. " stop reason")
	local expected = root .. (root == a and "/.venv/bin/python" or "/custom-env/bin/python")
	assert(observed:find(expected .. "|" .. root .. "|" .. vim.fs.basename(root), 1, true), observed)
	evidence[#evidence + 1] = { action = label, reason = reason, observed = observed }
	dap.continue()
	wait(label .. " debuggee did not finish", function()
		return #records(root) > count and dap.session() == nil
	end, 30000)
	dap.listeners.after.event_stopped.python_workflow = nil
end
edit(a)
dap.set_breakpoint()
debug_run("A DebugNearest", a, function()
	neotest.run.run({ strategy = "dap" })
end)
edit(b, "custom-env")
dap.set_breakpoint()
debug_run("B custom DebugNearest", b, function()
	neotest.run.run({ strategy = "dap" })
end)
edit(b, "custom-env")
debug_run("DAP A target while B active", a, function()
	dap.run({
		name = "Python target fixture",
		type = "python",
		request = "launch",
		module = "pytest",
		args = { a .. "/test_context.py" },
		cwd = a,
		console = "internalConsole",
	})
end)

edit(b, "custom-env")
vim.cmd.cd(b)
debug_run("DAP relative program A while B active", a, function()
	dap.run({
		name = "Python relative target",
		type = "python",
		request = "launch",
		program = "debug_relative.py",
		cwd = a,
		console = "internalConsole",
	})
end)

-- The real Ty terminal must resolve an environment-specific import from A,
-- even though B is active. The same input with B's interpreter fails typing.
edit(b, "custom-env")
local ty_exits = {}
local group = vim.api.nvim_create_augroup("python_workflow_ty", { clear = true })
vim.api.nvim_create_autocmd("TermClose", {
	group = group,
	callback = function(args)
		ty_exits[args.buf] = vim.v.event.status
	end,
})
local terminal = assert(context.ty_check(a), "Ty check did not create a terminal")
local term_buffer = terminal.buf
wait("Ty terminal did not finish", function()
	return ty_exits[term_buffer] ~= nil
end)
eq(ty_exits[term_buffer], 0, "target-aware Ty check")
evidence[#evidence + 1] = { action = "Ty A while B active", command = terminal.cmd, exit = ty_exits[term_buffer] }
local wrong = vim.system(
	{ "ty", "check", "--project", a, "--python", b .. "/custom-env/bin/python" },
	{ text = true, cwd = b }
)
	:wait()
eq(wrong.code, 1, "Ty wrong-environment negative control must fail")
assert((wrong.stdout .. wrong.stderr):find("invalid%-assignment"), wrong.stdout .. wrong.stderr)
evidence[#evidence + 1] = { action = "Ty wrong-environment negative control", exit = wrong.code }
vim.api.nvim_del_augroup_by_id(group)
edit(a)

-- A manual selection survives BufEnter and is resolved by target after switching.
require("venv-selector").activate_from_path(manual, "venv")
vim.api.nvim_exec_autocmds("BufEnter", { buffer = 0 })
vim.wait(150, function()
	return false
end)
eq(require("venv-selector").python(), manual, "manual selection was replaced")
edit(b, "custom-env")
eq(context.require_context(a).python, manual, "target lost manual selection")
vim.fn.writefile({ manual }, a .. "/expected-python.txt", "b")
run("A manual selection while B active", a, function()
	neotest.run.run(a .. "/test_context.py")
end, manual)
vim.fn.writefile({ a .. "/.venv/bin/python" }, a .. "/expected-python.txt", "b")
vim.env.UV_PROJECT_ENVIRONMENT = nil
vim.cmd.edit(a .. "/test_context.py")
require("venv-selector").deactivate()
vim.api.nvim_exec_autocmds("BufEnter", { buffer = 0 })
vim.wait(150, function()
	return false
end)
eq(require("venv-selector").python(), nil, "deactivated environment was restored")
eq(context.require_context(a).source, "deactivated", "deactivation retained target selection")
assert(context.require_context(a).python ~= manual, "deactivated target retained manual interpreter")
require("venv-selector").activate_from_path(a .. "/.venv/bin/python", "venv")
eq(context.require_context(a).python, a .. "/.venv/bin/python", "explicit reactivation did not recover")

-- An unselected active project refreshes changed UV_PROJECT_ENVIRONMENT immediately.
edit(b, "custom-env")
vim.env.UV_PROJECT_ENVIRONMENT = fixture .. "/manual/env"
eq(context.require_context(b).python, manual, "absolute UV environment change was cached")
vim.env.UV_PROJECT_ENVIRONMENT = "custom-env"
eq(context.require_context(b).python, b .. "/custom-env/bin/python", "relative UV environment did not recover")

-- Explicit adapter choices must work even when the uv default env is absent.
local explicit = fixture .. "/explicit"
vim.fn.mkdir(explicit, "p")
vim.fn.writefile({ "version = 1" }, explicit .. "/uv.lock")
vim.fn.writefile(vim.fn.readfile(a .. "/test_context.py"), explicit .. "/test_context.py")
vim.fn.writefile({ manual }, explicit .. "/expected-python.txt", "b")
local callback_root, explicit_result, explicit_error
local explicit_adapter = context.neotest_adapter({
	python = function(root)
		callback_root = root
		return { manual }
	end,
})
require("nio").run(function()
	local ok, result = pcall(function()
		local tree = explicit_adapter.discover_positions(explicit .. "/test_context.py")
		assert(tree, "explicit interpreter could not discover tests")
		local spec = explicit_adapter.build_spec({ tree = tree })
		spec.context.stop_stream()
		eq(spec.command[1], manual, "explicit adapter command")
		eq(spec.env.VIRTUAL_ENV, fixture .. "/manual/env", "explicit adapter environment")
		require("nio").scheduler()
		return vim.system(spec.command, { cwd = spec.cwd, env = spec.env, text = true }):wait()
	end)
	if ok then
		explicit_result = result
	else
		explicit_error = result
	end
end)
wait("explicit adapter test did not finish", function()
	return explicit_result or explicit_error
end, 30000)
assert(not explicit_error, explicit_error)
eq(callback_root, explicit, "explicit Python callback received ambient root")
eq(explicit_result.code, 0, explicit_result.stdout .. explicit_result.stderr)
evidence[#evidence + 1] = { action = "explicit adapter with missing default venv", observed = records(explicit)[1] }

-- Explicit relative interpreter paths belong to the test target, including argv lists.
edit(b, "custom-env")
vim.cmd.cd(b)
for _, option in ipairs({ ".venv/bin/python", { ".venv/bin/python", "-B" } }) do
	local original = vim.deepcopy(option)
	local label = type(option) == "table" and "relative explicit argv while B active"
		or "relative explicit string while B active"
	local relative_adapter = context.neotest_adapter({ python = option })
	local relative_result, relative_error
	local before = #records(a)
	require("nio").run(function()
		local ok, result = pcall(function()
			local tree = relative_adapter.discover_positions(a .. "/test_context.py")
			assert(tree, "relative interpreter could not discover target tests")
			local spec = relative_adapter.build_spec({ tree = tree })
			spec.context.stop_stream()
			eq(spec.command[1], a .. "/.venv/bin/python", label .. " command")
			eq(spec.env.VIRTUAL_ENV, a .. "/.venv", label .. " environment")
			eq(spec.cwd, a, label .. " cwd")
			if type(option) == "table" then
				eq(spec.command[2], "-B", label .. " argv")
			end
			eq(option, original, label .. " mutated caller options")
			require("nio").scheduler()
			return vim.system(spec.command, { cwd = spec.cwd, env = spec.env, text = true }):wait()
		end)
		if ok then
			relative_result = result
		else
			relative_error = result
		end
	end)
	wait(label .. " did not finish", function()
		return relative_result or relative_error
	end, 30000)
	assert(not relative_error, relative_error)
	eq(relative_result.code, 0, relative_result.stdout .. relative_result.stderr)
	local observed = records(a)[before + 1]
	eq(observed.python, a .. "/.venv/bin/python", label .. " actual interpreter")
	eq(observed.cwd, a, label .. " actual cwd")
	evidence[#evidence + 1] = { action = label, observed = observed }
end

-- Choosing the already-active interpreter in another project skips upstream hooks.
vim.env.UV_PROJECT_ENVIRONMENT = nil
vim.cmd.edit(a .. "/test_context.py")
require("venv-selector").activate_from_path(manual, "venv")
vim.cmd.edit(explicit .. "/test_context.py")
require("venv-selector").activate_from_path(manual, "venv")
eq(context.require_context(explicit).python, manual, "same-interpreter manual selection was lost")
vim.api.nvim_exec_autocmds("BufEnter", { buffer = 0 })
vim.wait(100, function()
	return false
end)
eq(context.require_context(explicit).python, manual, "same-interpreter selection did not survive BufEnter")

-- Missing known environments fail explicitly; no ambient B fallback or install.
local missing = fixture .. "/missing"
vim.fn.mkdir(missing, "p")
vim.fn.writefile({ "version = 1" }, missing .. "/uv.lock")
local resolved, err = context.resolve(missing)
assert(resolved == nil and err:find("unavailable", 1, true), "missing environment silently fell back")
dofile(test_dir .. "/python_selection_order.lua")
dofile(test_dir .. "/python_selection_scope.lua")
print("PYTHON_WORKFLOW_EVIDENCE " .. vim.json.encode(evidence))
io.stdout:write("PYTHON_WORKFLOW_COMPLETE\n")
io.stdout:flush()
