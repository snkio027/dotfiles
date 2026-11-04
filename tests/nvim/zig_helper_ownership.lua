-- Exclusive helper creation must tolerate short writes and clean partial files.
local module = require("config.zig_test")
local root = assert(vim.uv.fs_mkdtemp(vim.fs.joinpath(assert(vim.uv.os_tmpdir()), "zig-helper-XXXXXX")))
root = assert(vim.uv.fs_realpath(root))
local uv = vim.uv
local write, open, clock = uv.fs_write, uv.fs_open, uv.hrtime
local seen, fd_seen
local ok, err = xpcall(function()
	local content = "complete helper contents"
	uv.fs_write = function(fd, bytes, offset)
		return write(fd, bytes:sub(1, 2), offset)
	end
	local owner = module._helper_create(root, content)
	assert(table.concat(vim.fn.readfile(owner.path), "\n") == content, "ZIG_SHORT_HELPER_WRITE")
	module._helper_remove(owner)
	assert(not uv.fs_stat(owner.path), "ZIG_OWNED_HELPER_NOT_REMOVED")
	uv.fs_open = function(path, flags, mode)
		local fd, failure = open(path, flags, mode)
		if flags == "wx" then
			seen, fd_seen = path, fd
		end
		return fd, failure
	end
	local calls = 0
	uv.fs_write = function(fd, bytes, offset)
		calls = calls + 1
		if calls == 1 then
			return write(fd, bytes:sub(1, 2), offset)
		end
		return nil, "injected write failure"
	end
	assert(not pcall(module._helper_create, root, content), "ZIG_HELPER_WRITE_FAILURE_IGNORED")
	assert(seen and not uv.fs_stat(seen), "ZIG_PARTIAL_HELPER_LEFT_BEHIND")
	assert(not uv.fs_fstat(fd_seen), "ZIG_HELPER_FD_LEFT_OPEN")
	uv.fs_write, uv.fs_open = write, open
	uv.hrtime = function()
		return 123456
	end
	local collision = root .. "/.dotfiles-neotest-123456.zig"
	vim.fn.writefile({ "USER FILE" }, collision)
	assert(not pcall(module._helper_create, root, content), "ZIG_EXISTING_HELPER_OVERWRITTEN")
	assert(vim.fn.readfile(collision)[1] == "USER FILE", "ZIG_EXISTING_HELPER_CHANGED")
end, debug.traceback)
uv.fs_write, uv.fs_open, uv.hrtime = write, open, clock
assert(ok, err)
print("ZIG_HELPER_OWNERSHIP_COMPLETE")
