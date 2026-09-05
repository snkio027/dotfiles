--- M2C-A pre-init trace for native LSP activation provenance.
--- This file is loaded with --cmd before the production init.lua executes.

if _G.DX_M2C_ENABLE_TRACE ~= nil then
	error("M2C enable trace was installed more than once")
end

local original_enable = vim.lsp.enable
_G.DX_M2C_ENABLE_TRACE = {}

vim.lsp.enable = function(names, enabled)
	local caller = debug.getinfo(2, "Sl") or {}
	local requested = type(names) == "table" and names or { names }
	for _, name in ipairs(requested) do
		_G.DX_M2C_ENABLE_TRACE[#_G.DX_M2C_ENABLE_TRACE + 1] = {
			name = name,
			enabled = enabled ~= false,
			source = (caller.source or "unknown"):gsub("^@", ""),
			line = caller.currentline or -1,
		}
	end
	return original_enable(names, enabled)
end
