local function eq(actual, expected, label)
	assert(vim.deep_equal(actual, expected), label .. ": " .. vim.inspect(actual))
end

local function feed(keys)
	vim.fn.feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt")
end

require("lazy").load({ plugins = { "overseer.nvim", "cmake-tools.nvim", "neotest" } })
vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy" })
local overseer = require("overseer")
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/a", "p")
vim.fn.mkdir(root .. "/b", "p")
root = assert(vim.uv.fs_realpath(root))
local tasks = {}
for index, project in ipairs({ "a", "b" }) do
	local task = overseer.new_task({
		name = "same named test",
		cmd = { "sh", "-c", "printf '" .. project .. " output\\n'; pwd; exit " .. (index - 1) * 7 },
		cwd = root .. "/" .. project,
		env = { DOTFILES_PRIVATE_TOKEN = "not-exported-env-sentinel" },
		strategy = { "jobstart", use_terminal = false },
		components = { "on_exit_set_status" },
	})
	task:start()
	assert(
		vim.wait(5000, function()
			return task.status == (index == 1 and "SUCCESS" or "FAILURE")
		end, 10),
		"real task did not finish"
	)
	tasks[index] = task
end

local shell_command = "printf 'shell output\\n'"
tasks[3] = overseer.new_task({
	name = "shell command",
	cmd = shell_command,
	cwd = root .. "/b",
	ephemeral = true,
	strategy = { "jobstart", use_terminal = false },
	components = { "on_exit_set_status" },
})
tasks[3]:start()
assert(
	vim.wait(5000, function()
		return tasks[3].status == "SUCCESS"
	end, 10),
	"shell task did not finish"
)

local select, input, notify = vim.ui.select, vim.ui.input, vim.notify
local messages, selections, destination = {}, 0, nil
vim.notify = function(message)
	messages[#messages + 1] = message
end
-- Exercise the real TaskAction command, including its task and action pickers.
vim.ui.select = function(items, opts, callback)
	selections = selections + 1
	if opts.kind == "overseer_task" then
		for _, item in ipairs(items) do
			if item.id == tasks[2].id then
				callback(item)
				return
			end
		end
		error("second project task missing")
	end
	eq(opts.kind, "overseer_task_options", "task action picker")
	local found = false
	for _, action in ipairs(items) do
		found = found or action.name == "restart"
	end
	assert(found, "original task restart action was lost")
	callback(nil)
end
feed("<leader>oA")
eq(selections, 2, "independent task action key")
for key, description in pairs({
	["<leader>ot"] = "Build and Test (CMake)",
	["<leader>oD"] = "Build and Debug Target (CMake)",
	["<leader>oT"] = "Select Test Preset (CMake)",
	["<leader>tq"] = "Failed Tests (Trouble)",
}) do
	eq(vim.fn.maparg(key, "n", false, true).desc, description, "retained key " .. key)
end

local captured_input
local selected_index = 2
vim.ui.select = function(items, opts, callback)
	local selected
	for _, task in ipairs(items) do
		assert(opts.format_item(task):find(task.cwd, 1, true), "project must be visible in task picker")
		if task == tasks[selected_index] then
			selected = task
		end
	end
	assert(selected, "selected task missing")
	callback(selected)
end
vim.ui.input = function(_, callback)
	captured_input = callback
end
-- Select B while its output window is hidden and an unrelated A buffer is active.
local unrelated = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(unrelated)
vim.api.nvim_buf_set_lines(unrelated, 0, -1, false, { "unrelated editor content" })
vim.cmd.cd(root .. "/a")
local old_output = vim.api.nvim_buf_get_lines(tasks[2]:get_bufnr(), 0, -1, false)
eq({ old_output[1], old_output[2] }, { "b output", root .. "/b" }, "real process output")
feed("<leader>oE")
assert(captured_input, "export key did not ask for a destination")
-- Changing cwd or task fields during the prompt cannot replace the snapshot.
local old_command, old_cwd = vim.deepcopy(tasks[2].cmd), tasks[2].cwd
tasks[2].cwd, tasks[2].cmd = root .. "/a", { "different", "run" }
vim.bo[tasks[2]:get_bufnr()].modifiable = true
vim.api.nvim_buf_set_lines(tasks[2]:get_bufnr(), 0, -1, false, { "replacement output" })
destination = root .. "/task b.json"
captured_input(destination)
local raw = table.concat(vim.fn.readfile(destination), "\n")
local result = vim.json.decode(raw)
eq(result.task.command, old_command, "original command boundaries")
eq(result.task.cwd, old_cwd, "original project")
eq(result.task.exit_code, 7, "original failure code")
eq(result.task.status, "FAILURE", "original failure status")
eq(result.output_lines, old_output, "selected task buffer only, including Overseer's exit annotation")
assert(not raw:find("not-exported-env-sentinel", 1, true), "environment leaked into output export")
assert(not raw:find("unrelated editor content", 1, true), "export read another buffer")
assert(result.output_scope:find("retained", 1, true), "export must not promise a complete stream")
eq(vim.uv.fs_stat(destination).mode % 512, 384, "private file mode")
eq(vim.api.nvim_buf_get_lines(unrelated, 0, -1, false), { "unrelated editor content" }, "editor not modified")
tasks[2].cwd, tasks[2].cmd = old_cwd, old_command

selected_index = 3
feed("<leader>oE")
captured_input(root .. "/shell.json")
local shell_result = vim.json.decode(table.concat(vim.fn.readfile(root .. "/shell.json"), "\n"))
eq(shell_result.task.command, shell_command, "shell command representation")
eq(shell_result.output_lines[1], "shell output", "ephemeral task output")
eq(shell_result.task.exit_code, 0, "success exit code")
selected_index = 2

local function attempt(path)
	captured_input = nil
	feed("<leader>oE")
	assert(captured_input)
	captured_input(path)
end
-- Refuse existing content, links (including dangling), directories and relative paths.
attempt(destination)
eq(table.concat(vim.fn.readfile(destination), "\n"), raw, "existing output never overwritten")
local target = root .. "/user-data"
vim.fn.writefile({ "user data" }, target)
assert(vim.uv.fs_symlink(target, root .. "/linked.json"))
attempt(root .. "/linked.json")
eq(vim.fn.readfile(target), { "user data" }, "symlink target unchanged")
assert(vim.uv.fs_symlink(root .. "/absent-user-data", root .. "/dangling.json"))
attempt(root .. "/dangling.json")
assert(not vim.uv.fs_stat(root .. "/absent-user-data"), "dangling target created")
attempt(root .. "/b")
assert(vim.uv.fs_stat(root .. "/b").type == "directory")
feed("<leader>oE")
local raced = root .. "/created-during-prompt.json"
vim.fn.writefile({ "new user content" }, raced)
captured_input(raced)
eq(vim.fn.readfile(raced), { "new user content" }, "destination created during prompt is preserved")
attempt("relative-task.json")
assert(not vim.uv.fs_stat(root .. "/a/relative-task.json"))
attempt(nil)
attempt("")
eq(vim.fn.glob(root .. "/.task-output-*", false, true), {}, "no temporary export remnants")

-- Available-task ownership is checked again after an asynchronous selection.
local select_later
vim.ui.select = function(_, _, callback)
	select_later = callback
end
captured_input = nil
feed("<leader>oE")
tasks[2]:dispose(true)
select_later(tasks[2])
assert(not captured_input, "disposed task must not open a destination prompt")
assert(messages[#messages]:find("no longer available", 1, true))
tasks[1]:dispose(true)
tasks[3]:dispose(true)
vim.ui.select, vim.ui.input, vim.notify = select, input, notify
print("TASK_OUTPUT_COMPLETE: real tasks, key dispatch, cross-project snapshot and exclusive private export")
