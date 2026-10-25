-- Exercise the production opts hook, Conform's config discovery and actual
-- buffer formatting. Deterministic formatter functions avoid adding CI tools.
require("lazy").load({ plugins = { "conform.nvim" } })
local conform = require("conform")
local original_ft = conform.formatters_by_ft
local original_formatters = conform.formatters
local original_notify = vim.notify_once
local lsp = require("conform.lsp_format")
local original_lsp = lsp.format
local root, buffers = vim.fn.tempname(), {}
local calls, notices, lsp_calls = {}, {}, 0
local function write(path, text)
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	vim.fn.writefile({ text or "{}" }, path)
end
local function buffer(path)
	write(path, "const value = 1")
	local buf = vim.api.nvim_create_buf(false, false)
	buffers[#buffers + 1] = buf
	vim.api.nvim_buf_set_name(buf, path)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "const value = 1" })
	vim.bo[buf].filetype = "javascript"
	return buf
end
local function expect(buf, formatter)
	calls = {}
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "const value = 1" })
	local selected = conform.list_formatters_for_buffer(buf)
	assert(vim.deep_equal(selected, formatter and { formatter } or {}), vim.inspect(selected))
	local failure
	conform.format({ bufnr = buf, async = false }, function(err)
		failure = err
	end)
	if formatter then
		assert(not failure, failure)
	else
		assert(failure == "No formatters available for buffer", tostring(failure))
	end
	assert(vim.deep_equal(calls, formatter and { formatter } or {}), vim.inspect(calls))
	assert(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == (formatter or "const value = 1"))
	assert(lsp_calls == 0, "Project selection fell back to an LSP formatter")
end

local ok, err = xpcall(function()
	conform.formatters = vim.deepcopy(original_formatters)
	for _, name in ipairs({ "biome-check", "oxfmt", "prettier", "prettierd" }) do
		local native = require("conform.formatters." .. name)
		conform.formatters[name] = {
			inherit = false,
			cwd = native.cwd,
			format = function(_, _, _, callback)
				calls[#calls + 1] = name
				callback(nil, { name })
			end,
		}
	end
	vim.notify_once = function(message)
		notices[#notices + 1] = message
	end
	lsp.format = function()
		lsp_calls = lsp_calls + 1
	end
	local opts = {
		formatters_by_ft = {
			javascript = { "biome-check", "oxfmt", "prettier", lsp_format = "fallback" },
			cpp = { "clang-format" },
			python = function()
				return { "ruff_format" }
			end,
		},
	}
	-- Load the real final hook, so disconnecting it cannot leave a green test.
	for _, spec in ipairs(dofile("home/dot_config/nvim/lua/plugins/toolchain.lua")) do
		if spec[1] == "stevearc/conform.nvim" and type(spec.opts) == "function" then
			spec.opts(nil, opts)
		end
	end
	conform.formatters_by_ft = opts.formatters_by_ft
	assert(vim.deep_equal(conform.list_formatters_for_buffer(buffer(root .. "/blank/file.js")), {}))
	local a = buffer(root .. "/a/src/file.js")
	local b = buffer(root .. "/b/src/file.js")
	write(root .. "/a/.git", "gitdir: unused")
	write(root .. "/b/.git", "gitdir: unused")
	write(root .. "/a/biome.json")
	write(root .. "/b/.oxfmtrc.json")
	expect(a, "biome-check")
	expect(b, "oxfmt")
	expect(a, "biome-check") -- same editor cwd, different projects

	local nested = buffer(root .. "/a/packages/ui/src/file.js")
	write(root .. "/a/packages/ui/package.json", '{"prettier":{"singleQuote":true}}')
	expect(nested, "prettier")
	vim.fn.delete(root .. "/a/packages/ui/package.json")
	expect(nested, "biome-check") -- config changes are not cached
	write(root .. "/a/packages/ui/.prettierrc")
	expect(nested, "prettier")
	write(root .. "/a/packages/ui/.oxfmtrc.json")
	expect(nested, nil)
	assert(#notices > 0 and notices[#notices]:find("Multiple formatter configs", 1, true))
	vim.fn.delete(root .. "/a/packages/ui/.oxfmtrc.json")
	expect(nested, "prettier")

	local no_config = buffer(root .. "/plain/file.js")
	write(root .. "/plain/.git", "gitdir: unused")
	write(root .. "/.prettierrc")
	expect(no_config, nil) -- do not inherit another repository's config
	assert(conform.formatters_by_ft.javascript(no_config).lsp_format == "never")
	vim.bo[no_config].filetype = "cpp"
	assert(vim.deep_equal(conform.list_formatters_for_buffer(no_config), { "clang-format" }))
	vim.bo[no_config].filetype = "python"
	assert(vim.deep_equal(conform.list_formatters_for_buffer(no_config), { "ruff_format" }))

	local policy = require("config.project_format")
	local chain = { "before", "prettier", "prettierd", "oxfmt", "after", timeout_ms = 2000 }
	local snapshot = vim.deepcopy(chain)
	assert(
		vim.deep_equal(
			policy.select(nested, chain),
			{ "before", "prettier", "after", timeout_ms = 2000, lsp_format = "never" }
		)
	)
	assert(vim.deep_equal(chain, snapshot), "Formatter selection mutated the configured pipeline")

	-- A selected but missing executable must not select another formatter/LSP.
	conform.formatters["biome-check"] =
		{ inherit = false, command = "dotfiles-missing-formatter", cwd = require("conform.formatters.biome").cwd }
	local available, uses_lsp = conform.list_formatters_to_run(a)
	assert(#available == 0 and not uses_lsp, "Missing tool caused a silent fallback")
end, debug.traceback)
conform.formatters_by_ft, conform.formatters = original_ft, original_formatters
vim.notify_once, lsp.format = original_notify, original_lsp
for _, buf in ipairs(buffers) do
	vim.api.nvim_buf_delete(buf, { force = true })
end
vim.fn.delete(root, "rf")
assert(ok, err)
print(
	"Project formatting contract passed: one owner, nearest config, conflicts, missing config/tool and project isolation"
)
