--- DX-COLOR-003 M2C-B explicit Python provider-ownership unit contract.

local function fail(message)
	error("M2C_PROVIDER_OWNERSHIP_CONTRACT_FAILURE: " .. message, 2)
end

local function assert_equal(actual, expected, message)
	if not vim.deep_equal(actual, expected) then
		fail(("%s\n  expected: %s\n  observed: %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
	end
end

local function read(path)
	local lines = vim.fn.readfile(path)
	if vim.v.shell_error ~= 0 then
		fail("could not read " .. path)
	end
	return table.concat(lines, "\n")
end

local function occurrences(text, literal)
	local count = 0
	local start = 1
	while true do
		local found = text:find(literal, start, true)
		if not found then
			return count
		end
		count = count + 1
		start = found + #literal
	end
end

local repo_root = vim.fs.root(0, ".git") or vim.fn.getcwd()
local manifest = dofile(repo_root .. "/tests/nvim/python_provider_ownership_manifest.lua")

assert_equal(manifest.milestone, "M2C-B", "provider-ownership milestone drifted")
assert_equal(manifest.base, "5822ddd8982680912484c3aa6dfd661cca59e634", "M2C-B base drifted")
assert_equal(
	manifest.decision,
	"ADOPT TY AS INTERACTIVE SEMANTIC PROVIDER",
	"approved provider-ownership decision drifted"
)
assert_equal(
	manifest.governance_invariant,
	"Interactive LSP ownership must be explicit.",
	"provider-ownership invariant drifted"
)
assert_equal(manifest.activation, {
	primary = "ty",
	companion = "ruff",
	rollback = "pyright",
	resolved_ty_cmd = { "ty", "server" },
	resolved_ty_filetypes = { "python" },
	automatic_enable_owner = "mason-lspconfig.nvim",
	native_enable_api = "vim.lsp.enable",
}, "declared Python ownership topology drifted")
assert_equal(manifest.production, {
	lazy_server_state = { pyright = "disabled", ruff = "enabled", ty = "enabled" },
	automatic_enable_excluded = { pyright = true, ruff = false, ty = false },
	enable_calls = { pyright = 0, ruff = 1, ty = 1 },
	enabled = { pyright = false, ruff = true, ty = true },
	attached = { "ruff", "ty" },
	semantic_producers = { "ty" },
}, "M2C-B production topology drifted")
assert_equal(manifest.primary_capability_owners, {
	completion = { "ty" },
	hover = { "ty" },
	definition = { "ty" },
	references = { "ty" },
	rename = { "ty" },
}, "primary interactive capability ownership drifted")
assert_equal(manifest.graph, {
	count = 225,
	sha256 = "a2db03bf6a138c0784d74277adf6f7ee706a5398336305385ced7d3725c0dedf",
	historical_count = 221,
	historical_sha256 = "05ff81df9019ace7bee14a494db1a9e39c7d18426f3b78bae1ef3012a068a276",
}, "highlight graph oracle drifted")

local options = read(repo_root .. "/home/dot_config/nvim/lua/config/options.lua")
assert_equal(occurrences(options, 'vim.g.lazyvim_python_lsp = "ty"'), 1, "Ty must be selected exactly once")
assert_equal(
	occurrences(options, 'vim.g.lazyvim_python_lsp = "pyright"'),
	0,
	"Pyright must not remain the selected primary LSP"
)
assert_equal(
	occurrences(options, 'vim.g.lazyvim_python_ruff = "ruff"'),
	1,
	"Ruff companion selection must remain explicit"
)

local toolchain = read(repo_root .. "/home/dot_config/nvim/lua/plugins/toolchain.lua")
for _, tool in ipairs({ "pyright", "ruff", "ty" }) do
	assert_equal(
		occurrences(toolchain, ('\n  "%s",\n'):format(tool)),
		1,
		tool .. " must appear exactly once in the Mason tool inventory"
	)
end
assert_equal(
	occurrences(toolchain, "Ty owns interactive Python language intelligence"),
	1,
	"Ty interactive ownership comment is missing"
)
assert_equal(occurrences(toolchain, '{ "ty", "check" }'), 1, "explicit whole-project Ty check drifted")

local python_config = read(repo_root .. "/home/dot_config/nvim/lua/plugins/python.lua")
if python_config:find("servers%s*=%s*{.-ty%s*=") then
	fail("M2C-B must use the LazyVim ownership seam, not a custom Ty server entry")
end
if not python_config:find("servers%s*=%s*{.-pyright%s*=") then
	fail("Pyright rollback configuration must remain available")
end

local lock = vim.json.decode(read(repo_root .. "/home/dot_config/nvim/lazy-lock.json"))
for plugin, commit in pairs(manifest.locked_plugins) do
	local entry = lock[plugin]
	assert_equal(entry and entry.commit, commit, "locked provider dependency drifted: " .. plugin)
end

local color_manifest = dofile(repo_root .. "/tests/nvim/color_manifest.lua")
local python = color_manifest.languages and color_manifest.languages.python
assert_equal(python and python.lsp, { "ty" }, "Python color contract must start only the selected primary LSP")
assert_equal(python and python.evidence_client, "ty", "Python evidence client must be Ty")
assert_equal(python and python.evidence_clients, {
	{ name = "ruff", semantic_tokens = false },
	{ name = "ty", semantic_tokens = true },
}, "Python evidence-provider topology drifted")

local m2ca = read(repo_root .. "/dx-color-003-docs/DX-COLOR-003-M2C-PYTHON-PROVIDER-OWNERSHIP.md")
if not m2ca:find("ADOPT TY AS INTERACTIVE SEMANTIC PROVIDER", 1, true) then
	fail("frozen M2C-A evidence record lost its approved decision")
end
local m2cb = read(repo_root .. "/dx-color-003-docs/DX-COLOR-003-M2C-B-PYTHON-PROVIDER-CORRECTION.md")
for _, required in ipairs({
	"Ty = primary interactive Python LSP",
	"Ruff = lint/fix/code-action companion",
	"Pyright = installed rollback asset; explicitly disabled",
	"a2db03bf6a138c0784d74277adf6f7ee706a5398336305385ced7d3725c0dedf",
}) do
	if not m2cb:find(required, 1, true) then
		fail("M2C-B behavior record is missing: " .. required)
	end
end

print("M2C-B explicit Python provider-ownership unit contract passed.")
