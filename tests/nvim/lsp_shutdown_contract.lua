-- A real Neovim client with an in-process transport: acknowledging shutdown is
-- not exit. This deterministically distinguishes is_stopped() from retirement.
local shutdown = dofile("tests/nvim/lsp_shutdown.lua")
local function start(exit_on_notification)
	local dispatch, closing, requested, exit_sent
	local id = assert(vim.lsp.start({
		name = "shutdown-negative-control",
		cmd = function(callbacks)
			dispatch = callbacks
			return {
				request = function(method, _, callback)
					if method == "initialize" then
						vim.schedule(function()
							callback(nil, { capabilities = {} })
						end)
					elseif method == "shutdown" then
						requested = true
						vim.schedule(function()
							callback(nil, vim.NIL)
						end)
					end
					return true, 1
				end,
				notify = function(method)
					if method == "exit" then
						exit_sent = true
						if exit_on_notification then
							vim.defer_fn(function()
								closing = true
								dispatch.on_exit(0, 0)
							end, 30)
						end
					end
					return true
				end,
				is_closing = function()
					return closing == true
				end,
				terminate = function()
					error("Shutdown gate must not force-stop its clients")
				end,
			}
		end,
	}, { attach = false }))
	local client = assert(vim.lsp.get_client_by_id(id))
	assert(vim.wait(1000, function()
		return client.initialized
	end, 10))
	return client,
		function()
			assert(requested and exit_sent, "shutdown/exit protocol was not exercised")
			dispatch.on_exit(0, 0)
		end
end

local pending, release = start(false)
local ok, err = pcall(shutdown, { pending }, "acknowledged-but-alive", 100)
local still_registered = vim.lsp.get_client_by_id(pending.id) == pending
local reports_stopped = pending:is_stopped()
release()
assert(vim.wait(1000, function()
	return vim.lsp.get_client_by_id(pending.id) == nil
end, 10))
assert(not ok and tostring(err):find("LSP_SHUTDOWN_TIMEOUT", 1, true), tostring(err))
assert(still_registered and reports_stopped, "negative control did not reproduce the false-positive state")
local exited = start(true)
shutdown({ exited }, "delayed-transport-exit", 1000)
assert(vim.lsp.get_client_by_id(exited.id) == nil)
print("LSP shutdown contract passed: stop request is not transport exit.")
