-- Pure inspection and restart ownership boundaries; no clangd process required.
local status = require("config.clangd_status")
local root =
	assert(vim.uv.fs_realpath(assert(vim.uv.fs_mkdtemp(assert(vim.uv.os_tmpdir()) .. "/clangd-status-unit-XXXXXX"))))
local clients, get_clients, cmake = {}, vim.lsp.get_clients, package.loaded["cmake-tools"]
local initial = vim.api.nvim_get_current_buf()
local buf = vim.api.nvim_create_buf(false, true)
local other = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(buf, root .. "/main.cpp")
vim.bo[buf].buftype = ""
vim.bo[buf].filetype = "cpp"
vim.api.nvim_set_current_buf(buf)
local function write(path, lines)
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	vim.fn.writefile(lines, path)
end
local function database(directory, records)
	write(directory .. "/compile_commands.json", { vim.json.encode(records) })
end
local function fake(config)
	return {
		id = 73,
		root_dir = root,
		initialized = true,
		config = config or { root_dir = root, cmd = { "clangd" } },
		is_stopped = function()
			return false
		end,
		_restart = function() end,
	}
end
vim.lsp.get_clients = function(filter)
	assert(filter.name == "clangd" and filter.bufnr == buf)
	return clients
end
local ok, err = xpcall(function()
	write(root .. "/main.cpp", { "int main() {}" })
	write(root .. "/.cxx.toml", { "schema = 1" })
	write(root .. "/.clangd", { "CompileFlags:", "  CompilationDatabase: None" })
	clients = { fake() }
	local view = status.snapshot()
	assert(#view.clients == 1 and #view.clients[1].databases == 0)
	assert(view.clients[1].managed_default_exists == false)
	assert(table.concat(status.lines(view), "\n"):find("effective database not exposed", 1, true))
	assert(not status.snapshot(-55).applicable)
	local source = root .. "/main.cpp"
	local db = root .. "/db"
	database(db, {
		{ directory = root, file = "main.cpp", arguments = { "clang++", "-std=c++23", "-DVALUE=1", "-c", "main.cpp" } },
		{ directory = root, file = source, command = "clang++ -DVALUE=2 -c main.cpp" },
		{ directory = root, file = "other.cpp", arguments = { "wrong-compiler" } },
	})
	clients[1].config.cmd = { "clangd", "--compile-commands-dir", db }
	view = status.snapshot(buf)
	local inputs = view.clients[1].databases
	assert(#inputs == 1 and inputs[1].source == "command-line override" and #inputs[1].records == 2)
	assert(inputs[1].records[1].compiler == "clang++" and inputs[1].records[2].compiler == nil)
	assert(inputs[1].records[2].command == "clang++ -DVALUE=2 -c main.cpp")
	clients[1].config.cmd = { "clangd", "--compile-commands-dir=relative" }
	view = status.snapshot(buf)
	assert(view.clients[1].databases[1].path == nil and view.clients[1].databases[1].records == nil)
	clients[1].config.cmd = { "clangd" }
	clients[1].config.init_options = { compilationDatabasePath = db }
	assert(status.snapshot(buf).clients[1].databases[1].source == "initialization override")
	clients[1].config._dotfiles_clangd_database = { root = root, path = db }
	assert(status.snapshot(buf).clients[1].databases[1].source == "managed startup pin")
	package.loaded["cmake-tools"] = {
		get_config = function()
			return {
				cwd = root,
				configure_preset = "alt",
				build_preset = "build-alt",
				build_directory = { filename = root .. "/build/alt" },
			}
		end,
	}
	view = status.snapshot(buf)
	assert(view.cmake.same_project and view.cmake.configure == "alt")
	assert(view.clients[1].databases[1].directory == db, "CMake selection replaced clangd database evidence")
	package.loaded["cmake-tools"] = {
		get_config = function()
			return { cwd = root .. "/other", configure_preset = "wrong" }
		end,
	}
	view = status.snapshot(buf)
	assert(not view.cmake.same_project and view.cmake.configure == nil)
	local lines = table.concat(status.lines(view), "\n")
	assert(lines:find("another project", 1, true) and not lines:find("wrong", 1, true))
	-- No nearest-name/header guess and no unbounded/non-file reads.
	vim.api.nvim_buf_set_name(buf, root .. "/external.hpp")
	assert(#status.snapshot(buf).clients[1].databases[1].records == 0)
	vim.api.nvim_buf_set_name(buf, source)
	write(db .. "/compile_commands.json", { "invalid JSON" })
	assert(status.snapshot(buf).clients[1].databases[1].note == "invalid compilation database")
	local fd = assert(vim.uv.fs_open(db .. "/compile_commands.json", "w", 384))
	assert(vim.uv.fs_ftruncate(fd, 4 * 1024 * 1024 + 1))
	vim.uv.fs_close(fd)
	assert(status.snapshot(buf).clients[1].databases[1].note:find("larger than", 1, true))
	vim.fn.delete(db .. "/compile_commands.json")
	assert(vim.fn.system({ "mkfifo", db .. "/compile_commands.json" }) == "")
	assert(status.snapshot(buf).clients[1].databases[1].note == "not a regular file")
	vim.fn.delete(db .. "/compile_commands.json")
	local duplicate = {}
	for _ = 1, 10 do
		duplicate[#duplicate + 1] = { directory = root, file = source, arguments = { "clang++" } }
	end
	database(db, duplicate)
	view = status.snapshot(buf)
	assert(#view.clients[1].databases[1].records == 8 and view.clients[1].databases[1].note:find("first 8", 1, true))
	-- Restart only the selected source's unique, supported native client.
	clients = { fake() }
	local restarted = 0
	clients[1]._restart = function(self, timeout)
		assert(self == clients[1] and timeout == 123)
		restarted = restarted + 1
	end
	clients[1].exit_timeout = 123
	assert(status.refresh(buf))
	assert(restarted == 1)
	vim.api.nvim_set_current_buf(other)
	assert(not status.refresh(buf))
	assert(restarted == 1)
	vim.api.nvim_set_current_buf(buf)
	clients = {}
	assert(not status.refresh(buf))
	clients = { fake(), fake() }
	assert(not status.refresh(buf))
	clients = { fake() }
	clients[1]._restart = nil
	assert(not status.refresh(buf))
	clients = { fake() }
	clients[1].initialized = false
	assert(not status.refresh(buf))
	clients = { fake() }
	clients[1]._handle_restart = function() end
	assert(not status.refresh(buf))
	clients = { fake() }
	clients[1].config.root_dir = root .. "/foreign"
	assert(not status.refresh(buf))
	clients = { fake() }
	clients[1].root_dir = function() end
	clients[1].config.root_dir = function() end
	assert(not status.refresh(buf))
	clients = { fake() }
	clients[1].config.init_options = false
	clients[1].config._dotfiles_clangd_database = true
	assert(#status.snapshot(buf).clients[1].databases == 0)
	assert(status.refresh(buf))
	-- Re-evaluate only our unchanged inferred option. Explicit values survive.
	for _, explicit in ipairs({ false, true }) do
		clients = {
			fake({
				root_dir = root,
				cmd = { "clangd", "--compile-commands-dir=/cli" },
				init_options = {
					compilationDatabasePath = explicit and "/explicit" or db,
					preserve = true,
				},
				_dotfiles_clangd_database = { root = root, path = db },
			}),
		}
		clients[1]._restart = function(self)
			assert(self.config.init_options.compilationDatabasePath == (explicit and "/explicit" or nil))
			assert(self.config.init_options.preserve and self.config.cmd[2] == "--compile-commands-dir=/cli")
		end
		assert(status.refresh(buf))
	end
	clients = { fake() }
	local original = clients[1].config
	clients[1]._restart = function()
		error("native restart rejected")
	end
	local success, why = status.refresh(buf)
	assert(not success and why:find("native restart rejected", 1, true) and clients[1].config == original)
end, debug.traceback)
vim.lsp.get_clients = get_clients
package.loaded["cmake-tools"] = cmake
vim.api.nvim_set_current_buf(initial)
vim.api.nvim_buf_delete(buf, { force = true })
vim.api.nvim_buf_delete(other, { force = true })
vim.fn.delete(root, "rf")
assert(ok, err)
print("CLANGD_STATUS_CONTRACT_COMPLETE")
