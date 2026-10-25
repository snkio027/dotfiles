-- Use normal file opens and the configured servers, never a manual :set ft.
require("lazy").load({ plugins = { "nvim-lspconfig" } })
local root, buffers, existing = vim.fn.tempname(), {}, {}
local original_buf = vim.api.nvim_get_current_buf()
for _, client in ipairs(vim.lsp.get_clients()) do
	existing[client.id] = true
end
local names = {
	"compose.yaml",
	"compose.yml",
	"docker-compose.yaml",
	"docker-compose.yml",
	"compose.override.yaml",
	"compose.prod.yml",
	"docker-compose.override.yml",
	"docker-compose.dev.yaml",
}
local function open(name)
	local path = root .. "/" .. name
	vim.fn.writefile({ "services:", "  app:", "    image: alpine:latest" }, path)
	vim.cmd.edit(vim.fn.fnameescape(path))
	local buf = vim.api.nvim_get_current_buf()
	buffers[#buffers + 1] = buf
	return buf
end
local function attached(buf, name)
	local found
	assert(
		vim.wait(10000, function()
			for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf, name = name })) do
				if client.initialized then
					found = client
					return true
				end
			end
		end, 50),
		"COMPOSE_LSP_NOT_ATTACHED: " .. name
	)
	return found
end
local ok, err = xpcall(function()
	vim.fn.mkdir(root, "p")
	root = assert(vim.uv.fs_realpath(root))
	for _, name in ipairs(names) do
		assert(vim.filetype.match({ filename = root .. "/" .. name }) == "yaml.docker-compose", name)
	end
	for _, name in ipairs({ "config.yaml", "decompose.yaml", "my-compose.yaml", "compose.yml.txt" }) do
		assert(vim.filetype.match({ filename = root .. "/" .. name }) ~= "yaml.docker-compose", name)
	end
	local main = open("compose.yaml")
	assert(vim.bo[main].filetype == "yaml.docker-compose", "COMPOSE_FILETYPE_MISSING")
	local compose = attached(main, "docker_compose_language_service")
	assert(compose.config.root_dir == root, "COMPOSE_ROOT_MISMATCH")
	attached(main, "yamlls") -- general YAML support is preserved
	local override = open("compose.override.yaml")
	assert(attached(override, "docker_compose_language_service").id == compose.id)
	local plain = open("config.yaml")
	assert(vim.bo[plain].filetype == "yaml")
	attached(plain, "yamlls")
	assert(#vim.lsp.get_clients({ bufnr = plain, name = "docker_compose_language_service" }) == 0)
end, debug.traceback)
for _, buf in ipairs(buffers) do
	vim.api.nvim_buf_delete(buf, { force = true })
end
for _, client in ipairs(vim.lsp.get_clients()) do
	if not existing[client.id] then
		client:stop(true)
	end
end
if vim.api.nvim_buf_is_valid(original_buf) then
	vim.api.nvim_set_current_buf(original_buf)
end
vim.fn.delete(root, "rf")
assert(ok, err)
print("Compose contract passed: file detection, native LSP attachment, overrides and plain YAML isolation")
