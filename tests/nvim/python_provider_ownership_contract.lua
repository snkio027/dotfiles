--- DX-COLOR-003 M2C-A repository-intent and evidence-topology contract.

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

assert_equal(manifest.milestone, "M2C-A", "provider-ownership milestone drifted")
assert_equal(manifest.base, "21ba070d713d4f2275f44222c177de5c3a88b4ac", "M2C-A base drifted")

local allowed_decisions = {
	["KEEP TY CLI-ONLY"] = true,
	["ADOPT TY AS INTERACTIVE SEMANTIC PROVIDER"] = true,
	["DEFER PROVIDER OWNERSHIP"] = true,
}
if not allowed_decisions[manifest.decision] then
	fail("provider decision is not one of the three authorized outcomes")
end
assert_equal(
	manifest.decision,
	"ADOPT TY AS INTERACTIVE SEMANTIC PROVIDER",
	"M2C-A final provider-ownership decision drifted"
)
assert_equal(
	manifest.governance_invariant,
	"Interactive LSP ownership must be explicit.",
	"M2C-A governance conclusion drifted"
)

local options = read(repo_root .. "/home/dot_config/nvim/lua/config/options.lua")
assert_equal(
	occurrences(options, 'vim.g.lazyvim_python_lsp = "pyright"'),
	1,
	"repository intent must select Pyright exactly once"
)
assert_equal(
	occurrences(options, 'vim.g.lazyvim_python_ruff = "ruff"'),
	1,
	"repository intent must select Ruff exactly once"
)

local toolchain = read(repo_root .. "/home/dot_config/nvim/lua/plugins/toolchain.lua")
assert_equal(occurrences(toolchain, '\n  "ty",\n'), 1, "Ty must appear exactly once in the Mason tool list")
assert_equal(
	occurrences(toolchain, "ty is intentionally an on-demand whole-project check for now"),
	1,
	"Ty CLI-only repository intent is missing"
)
assert_equal(occurrences(toolchain, '{ "ty", "check" }'), 1, "Ty CLI invocation drifted")

local python_config = read(repo_root .. "/home/dot_config/nvim/lua/plugins/python.lua")
if python_config:find("servers%s*=%s*{.-ty%s*=") then
	fail("M2C-A must not add a production Ty server configuration")
end

local lock = vim.json.decode(read(repo_root .. "/home/dot_config/nvim/lazy-lock.json"))
for plugin, commit in pairs(manifest.locked_plugins) do
	local entry = lock[plugin]
	assert_equal(entry and entry.commit, commit, "locked provider-provenance dependency drifted: " .. plugin)
end

local exclusion = dofile(repo_root .. "/tests/nvim/fixtures/python_provider_ty_exclusion.lua")
assert_equal(#exclusion, 1, "test-only Ty exclusion must contain one plugin override")
assert_equal(exclusion[1][1], "neovim/nvim-lspconfig", "test-only exclusion targets the wrong plugin")
assert_equal(exclusion[1].opts, { servers = { ty = { enabled = false } } }, "test-only exclusion must disable only Ty")

local m2a = dofile(repo_root .. "/tests/nvim/color_manifest.lua")
local python = m2a.languages and m2a.languages.python
assert_equal(python and python.evidence_client, "pyright", "M2A configured Python client drifted")
assert_equal(python and python.evidence_clients, {
	{ name = "pyright", semantic_tokens = false },
	{ name = "ruff", semantic_tokens = false },
	{ name = "ty", semantic_tokens = true },
}, "M2A observed Python provider topology drifted")

local doc = read(repo_root .. "/dx-color-003-docs/DX-COLOR-003-M2C-PYTHON-PROVIDER-OWNERSHIP.md")
if not doc:find("ADOPT TY AS INTERACTIVE SEMANTIC PROVIDER", 1, true) then
	fail("M2C-A evidence record does not contain the final decision")
end

print("M2C-A provider-ownership unit contract passed; decision: " .. manifest.decision)
