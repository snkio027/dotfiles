-- Exercise the final Conform config with the installed SQLFluff executable.
require("lazy").load({ plugins = { "conform.nvim" } })
local conform = require("conform")
local root, buffers = vim.fn.tempname(), {}
local original_cwd = vim.fn.getcwd()
local function write(path, lines)
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	vim.fn.writefile(lines, path)
end
local function buffer(path, sql)
	write(path, { sql })
	local buf = vim.api.nvim_create_buf(false, false)
	buffers[#buffers + 1] = buf
	vim.api.nvim_buf_set_name(buf, path)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { sql })
	vim.api.nvim_set_option_value("filetype", "sql", { buf = buf })
	return buf
end
local function format(buf, expected)
	local failure, finished
	conform.format({ bufnr = buf, async = false, timeout_ms = 10000 }, function(err)
		failure, finished = err, true
	end)
	assert(finished and not failure, "SQL_FORMAT_FAILED: " .. tostring(failure))
	assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), expected), "SQL_DIALECT_OUTPUT_MISMATCH")
end
local ok, err = xpcall(function()
	local config = conform.get_formatter_config("sqlfluff")
	assert(config and config.require_cwd, "SQL_PROJECT_CONFIG_GUARD_MISSING")
	assert(vim.tbl_contains(config.args, "$FILENAME"), "SQL_BUFFER_CONTEXT_MISSING")
	local postgres = "select distinct on (id) id::integer,value from events order by id;"
	local tsql = "select top(1)[value] from[events];"
	write(root .. "/pg/.sqlfluff", { "[sqlfluff]", "dialect = postgres" })
	write(root .. "/ms/pyproject.toml", { "[tool.sqlfluff.core]", 'dialect = "tsql"' })
	local pg = buffer(root .. "/pg/src/query.sql", postgres)
	local ms = buffer(root .. "/ms/src/query.sql", tsql)
	vim.fn.chdir(root .. "/pg") -- formatting another project must not inherit this dialect
	local pg_expected = { "select distinct on (id)", "    id::integer,", "    value", "from events", "order by id;" }
	format(pg, pg_expected)
	format(ms, { "select top (1) [value] from [events];" })
	vim.api.nvim_buf_set_lines(pg, 0, -1, false, { postgres })
	format(pg, pg_expected)

	write(root .. "/pg/nested/.sqlfluff", { "[sqlfluff]", "dialect = tsql" })
	format(buffer(root .. "/pg/nested/query.sql", tsql), { "select top (1) [value] from [events];" })

	local plain = buffer(root .. "/plain/query.sql", "select  1;")
	assert(not conform.get_formatter_info("sqlfluff", plain).available, "SQL_UNCONFIGURED_PROJECT_FORMATTED")
	local failure
	conform.format({ bufnr = plain, async = false }, function(error)
		failure = error
	end)
	assert(failure == "No formatters available for buffer", tostring(failure))
	assert(vim.api.nvim_buf_get_lines(plain, 0, 1, false)[1] == "select  1;")

	-- A project file with no dialect is not permission to silently choose ANSI.
	write(root .. "/unspecified/.sqlfluff", { "[sqlfluff]", "max_line_length = 100" })
	local missing = buffer(root .. "/unspecified/query.sql", "select  1;")
	conform.format({ bufnr = missing, async = false, timeout_ms = 10000 }, function(error)
		failure = error
	end)
	assert(failure, "SQL_MISSING_DIALECT_SILENT_FALLBACK")
	assert(vim.api.nvim_buf_get_lines(missing, 0, 1, false)[1] == "select  1;")
end, debug.traceback)
vim.fn.chdir(original_cwd)
for _, buf in ipairs(buffers) do
	vim.api.nvim_buf_delete(buf, { force = true })
end
vim.fn.delete(root, "rf")
assert(ok, err)
print("SQL formatting contract passed: real project dialects, nested/cross-project buffers and missing config/dialect")
