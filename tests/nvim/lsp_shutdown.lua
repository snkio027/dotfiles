-- Test-only retirement gate. is_stopped() becomes true when stop is requested;
-- registry removal happens after Neovim processes the transport's on_exit.
return function(clients, label, timeout_ms)
	for _, client in ipairs(clients) do
		client:stop(false)
	end
	local stopped, wait_reason = vim.wait(timeout_ms, function()
		for _, client in ipairs(clients) do
			if vim.lsp.get_client_by_id(client.id) then
				return false
			end
		end
		return true
	end, 20)
	if not stopped then
		local pending = {}
		for _, client in ipairs(clients) do
			if vim.lsp.get_client_by_id(client.id) then
				pending[#pending + 1] = {
					id = client.id,
					name = client.name,
					initialized = client.initialized,
					stop_requested = client:is_stopped(),
					transport_closing = client.rpc.is_closing(),
					requests = client.requests,
				}
			end
		end
		error(("LSP_SHUTDOWN_TIMEOUT [%s] wait=%s: %s"):format(label, wait_reason, vim.inspect(pending)))
	end
end
