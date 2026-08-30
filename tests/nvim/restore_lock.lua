local snapshot = assert(vim.env.DOTFILES_LAZY_LOCK_SNAPSHOT, "DOTFILES_LAZY_LOCK_SNAPSHOT is required")
local active_lock = vim.fn.stdpath("config") .. "/lazy-lock.json"

local function read_all(path)
	local file = assert(io.open(path, "rb"))
	local contents = assert(file:read("*a"))
	file:close()
	return contents
end

local expected = read_all(snapshot)
local active = assert(io.open(active_lock, "wb"))
assert(active:write(expected))
active:close()

assert(read_all(active_lock) == expected, "Active lazy-lock.json does not match the committed snapshot")

-- Lazy's cold-start installer loads and then rewrites an in-memory lock table
-- before Ex commands run. Force restore to reload the committed snapshot.
local lock = require("lazy.manage.lock")
lock.lock = {}
lock._loaded = false

print("Committed Lazy lock snapshot restored")
