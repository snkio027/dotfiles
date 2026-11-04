-- Pure settings validation: no language server, Cargo, debugger or package startup.
local context = require("config.rust_context")
local module = "rustaceanvim.config.server"
local previous_loader = package.loaded[module]
local defaults = {
	["rust-analyzer"] = {
		cargo = { allFeatures = false, features = { "inherited" }, extraEnv = { PRESERVE = "yes" } },
		check = { command = "clippy", allTargets = true, extraArgs = { "--no-deps" } },
		runnables = { extraArgs = { "--locked", "--target", "old-target", "--target=older-target", "--offline" } },
		hover = { memoryLayout = { enable = true } },
	},
}
local original = vim.deepcopy(defaults)
local fallback = vim.deepcopy(defaults)
local loader_calls = {}
package.loaded[module] = {
	load_rust_analyzer_settings = function(root, opts)
		loader_calls[#loader_calls + 1] = { root = root, defaults = opts.default_settings }
		-- Like the native loader, fallback returns shared config rather than a copy.
		return opts.default_settings or fallback
	end,
}
local fixture = vim.fn.tempname()
vim.fn.mkdir(fixture, "p")
fixture = assert(vim.uv.fs_realpath(fixture))
local function project(name, text)
	local root = fixture .. "/" .. name
	vim.fn.mkdir(root .. "/.nvim", "p")
	if text then
		vim.fn.writefile({ text }, root .. "/.nvim/rust.json")
	end
	return root
end
local function eq(actual, expected, message)
	assert(vim.deep_equal(actual, expected), message .. ": " .. vim.inspect(actual))
end
local function reject(name, text, expected)
	local root = project(name, text)
	local ok, err = pcall(context.settings, root, defaults)
	assert(not ok and tostring(err):find(expected, 1, true), name .. " accepted invalid settings: " .. tostring(err))
	eq(defaults, original, name .. " mutated input defaults")
end
local clients_module = package.loaded["config.rust_clients"]
local rust_global = vim.g.rustaceanvim
local ok, err = pcall(function()
	local configured, starts = nil, 0
	package.loaded["config.rust_clients"] = {
		setup = function()
			starts = starts + 1
		end,
	}
	local toolchain_file = assert(vim.api.nvim_get_runtime_file("lua/plugins/toolchain.lua", false)[1])
	for _, spec in ipairs(assert(loadfile(toolchain_file))()) do
		if spec[1] == "mrcjkb/rustaceanvim" then
			configured = spec
		end
	end
	assert(configured, "native Rust plugin spec missing")
	vim.g.rustaceanvim = { tools = { hover_actions = { auto_focus = true } }, dap = { custom = "preserved" } }
	configured.init()
	assert(vim.g.rustaceanvim.dap.autoload_configurations == false, "early native global did not disable eager builds")
	local early = vim.deepcopy(vim.g.rustaceanvim)
	local native_merged = vim.tbl_deep_extend("keep", early, { dap = { adapter = "mason-native" } })
	assert(
		native_merged.dap.autoload_configurations == false and native_merged.dap.adapter == "mason-native",
		"native adapter opts replacement lost eager-build policy"
	)
	assert(
		native_merged.dap.custom == "preserved" and native_merged.tools.hover_actions.auto_focus,
		"early native setup replaced custom global options"
	)
	vim.g.rustaceanvim = rust_global
	local config = {
		server = { auto_attach = false },
		dap = { autoload_configurations = true, adapter = "custom", load_rust_automatically = true },
	}
	configured.opts(nil, config)
	assert(config.dap.autoload_configurations == false, "Rust eagerly compiled native debug configurations")
	assert(
		config.dap.adapter == "custom" and config.dap.load_rust_automatically,
		"unrelated native DAP options changed"
	)
	assert(config.server.auto_attach(20) == false and starts == 1, "explicit auto_attach=false was ignored")
	local custom = { server = {
		auto_attach = function(buf)
			return buf == 21
		end,
	} }
	configured.opts(nil, custom)
	assert(
		custom.server.auto_attach(20) == false and custom.server.auto_attach(21) == true,
		"custom auto_attach callback changed"
	)
	assert(custom.dap.autoload_configurations == false)
	package.loaded["config.rust_clients"] = clients_module

	local a = project("a", [[{"features":["tls-rustls"],"noDefaultFeatures":true,"target":"aarch64-apple-darwin"}]])
	local configured = context.settings(a, defaults)["rust-analyzer"]
	eq(configured.cargo.features, { "tls-rustls" }, "Cargo feature override")
	eq(configured.check.features, { "tls-rustls" }, "Clippy feature override")
	assert(configured.cargo.noDefaultFeatures and configured.check.noDefaultFeatures, "default feature policy drift")
	eq(configured.cargo.target, "aarch64-apple-darwin", "Cargo target override")
	eq(configured.check.targets, { "aarch64-apple-darwin" }, "Clippy target override")
	eq(
		configured.runnables.extraArgs,
		{ "--locked", "--offline", "--target", "aarch64-apple-darwin" },
		"native runnable target override"
	)
	eq(configured.cargo.extraEnv, original["rust-analyzer"].cargo.extraEnv, "unrelated Cargo settings lost")
	eq(configured.check.extraArgs, { "--no-deps" }, "unrelated Clippy settings lost")
	eq(configured.hover, original["rust-analyzer"].hover, "unrelated native settings lost")
	eq(defaults, original, "project A mutated native defaults")
	local malformed_args = vim.deepcopy(defaults)
	malformed_args["rust-analyzer"].runnables.extraArgs = { "--locked", "--target" }
	local args_before = vim.deepcopy(malformed_args)
	local args_ok, args_err = pcall(context.settings, a, malformed_args)
	assert(
		not args_ok and tostring(args_err):find("Missing Rust runnable target", 1, true),
		"malformed target accepted"
	)
	eq(malformed_args, args_before, "invalid runnable target mutated defaults")
	assert(loader_calls[#loader_calls].root == a, "loader did not receive target project root")
	assert(loader_calls[#loader_calls].defaults ~= defaults, "loader received shared caller defaults")

	local b = project("b", [[{"features":[],"noDefaultFeatures":false}]])
	local configured_b = context.settings(b, defaults)["rust-analyzer"]
	eq(configured_b.cargo.features, {}, "empty features did not override inherited features")
	eq(configured_b.check.features, {}, "empty check features did not override inherited features")
	assert(configured_b.cargo.noDefaultFeatures == false and configured_b.check.noDefaultFeatures == false)
	assert(configured_b.cargo.target == nil and configured_b.check.targets == nil, "A target leaked into B")
	assert(configured_b.cargo.allFeatures == false, "deprecated allFeatures re-enabled")
	eq(configured_b.runnables, original["rust-analyzer"].runnables, "A runnable target leaked into B")
	configured_b.cargo.features[1] = "mutated-result"
	eq(context.settings(b, defaults)["rust-analyzer"].cargo.features, {}, "returned settings were shared")

	local all = project("all", [[{"features":"all"}]])
	local configured_all = context.settings(all, defaults)["rust-analyzer"]
	assert(configured_all.cargo.features == "all" and configured_all.check.features == "all")
	eq(context.settings(project("empty", "{}"), defaults), original, "empty object changed inherited settings")
	eq(context.settings(project("absent"), defaults), original, "absent project config changed defaults")
	eq(context.settings(nil, defaults), original, "nil project root changed native loader behavior")

	-- Native loader fallback must not let one project mutate global settings.
	context.settings(a, nil)
	eq(fallback, original, "native fallback settings were mutated by project A")
	eq(context.settings(project("fallback"), nil), original, "fallback settings leaked across projects")

	reject("array", "[]", "Invalid Rust project JSON")
	reject("null", "null", "Invalid Rust project JSON")
	reject("malformed", "{", "Invalid Rust project JSON")
	reject("unknown", [[{"command":"echo unsafe"}]], "Unknown Rust project option")
	reject("features-string", [[{"features":"tls-rustls"}]], "Rust features must be an array")
	reject("features-map", [[{"features":{}}]], "Rust features must be an array")
	reject("feature-number", [[{"features":[1]}]], "Invalid Rust feature")
	reject("feature-empty", [[{"features":[""]}]], "Invalid Rust feature")
	reject("default-null", [[{"noDefaultFeatures":null}]], "Rust noDefaultFeatures must be boolean")
	reject("default-number", [[{"features":["good"],"noDefaultFeatures":1}]], "Rust noDefaultFeatures must be boolean")
	reject("target-empty", [[{"target":""}]], "Rust target must be a triple")
	reject("target-list", [[{"target":[]}]], "Rust target must be a triple")
	reject("oversize", string.rep(" ", 65537), "Invalid Rust project settings")

	local directory = project("directory")
	vim.fn.mkdir(directory .. "/.nvim/rust.json")
	local directory_ok, directory_err = pcall(context.settings, directory, defaults)
	assert(not directory_ok and tostring(directory_err):find("Invalid Rust project settings", 1, true))
	local blocked = fixture .. "/not-directory"
	vim.fn.mkdir(blocked)
	vim.fn.writefile({ "not a directory" }, blocked .. "/.nvim")
	local blocked_ok, blocked_err = pcall(context.settings, blocked, defaults)
	assert(not blocked_ok and tostring(blocked_err):find("Cannot read Rust project settings", 1, true))
	eq(defaults, original, "invalid config mutated defaults")
	eq(fallback, original, "invalid config mutated loader fallback")
end)
vim.g.rustaceanvim = rust_global
package.loaded["config.rust_clients"] = clients_module
package.loaded[module] = previous_loader
vim.fn.delete(fixture, "rf")
assert(ok, err)
print("RUST_CONTEXT_COMPLETE")
