-- Real clangd edits first; injected replies exercise fail-closed boundaries.
local includes = require("config.clangd_includes")
local saved_buf = vim.api.nvim_get_current_buf()
local select, notify = vim.ui.select, vim.notify
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
root = assert(vim.uv.fs_realpath(root))
local function write(name, lines)
	vim.fn.writefile(lines, root .. "/" .. name)
end
write("first.hpp", { "#pragma once", "struct First {};" })
write("second.hpp", { "#pragma once", "struct Second {};" })
write("bridge.hpp", { '#include "first.hpp"', '#include "second.hpp"' })
write(".clangd", { "CompileFlags:", "  Add: [-std=c++23]", "Diagnostics:", "  MissingIncludes: Strict" })
local source = { '#include "bridge.hpp"', "First first;", "Second second;", "// 多字节结尾" }
write("main.cpp", source)
-- A separate translation unit keeps dependency symbols in the background
-- index after the pasted file loses all includes. A fallback-only command has
-- no such guarantee: its dynamic preamble index can disappear on that edit.
write("index.cpp", { '#include "bridge.hpp"', "First index_anchor;" })
local commands = {}
for _, file in ipairs({ "main.cpp", "index.cpp" }) do
	commands[#commands + 1] = {
		directory = root,
		file = root .. "/" .. file,
		arguments = { "clang++", "-std=c++23", "-c", root .. "/" .. file },
	}
end
write("compile_commands.json", { vim.json.encode(commands) })
local buf = vim.fn.bufadd(root .. "/main.cpp")
vim.fn.bufload(buf)
vim.api.nvim_set_current_buf(buf)
local publish
local id = assert(vim.lsp.start({
	name = "clangd",
	cmd = vim.deepcopy(vim.lsp.config.clangd.cmd),
	root_dir = root,
	handlers = {
		["textDocument/publishDiagnostics"] = function(err, result, ctx, config)
			if result and vim.uri_to_fname(result.uri) == root .. "/main.cpp" then
				publish = result
			end
			vim.lsp.handlers["textDocument/publishDiagnostics"](err, result, ctx, config)
		end,
	},
}, {
	bufnr = buf,
	reuse_client = function()
		return false
	end,
}))
local client = assert(vim.lsp.get_client_by_id(id))
local request = client.request
local choices, choose, notice, done
vim.ui.select = function(items, opts, callback)
	assert(opts.prompt:find("公开头文件", 1, true), "missing public-header warning")
	choices, choose, done = items, callback, true
end
vim.notify = function(message)
	notice, done = message, true
end
local function wait(predicate, label)
	assert(vim.wait(10000, predicate, 20), "include action timeout: " .. label)
end
local function lines()
	return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end
local function ready()
	local reply = assert(client:request_sync("textDocument/documentSymbol", {
		textDocument = vim.lsp.util.make_text_document_params(buf),
	}, 10000, buf))
	assert(not reply.err, vim.inspect(reply.err))
	local version = vim.lsp.util.buf_versions[buf]
	wait(function()
		return publish and publish.version == version
	end, "current diagnostics")
end
local function invoke()
	choices, choose, notice, done = nil, nil, nil, false
	includes.choose()
	wait(function()
		return done
	end, "action response")
end
local function find(header)
	for _, choice in ipairs(choices or {}) do
		if #choice.edits == 1 and choice.edits[1].newText:find(header, 1, true) then
			return choice
		end
	end
	error("missing real include choice " .. header .. ": " .. vim.inspect({ choices, notice }))
end
local ok, err = xpcall(function()
	wait(function()
		return client.initialized
	end, "initialize")
	ready()
	invoke()
	local first = vim.deepcopy(find('"first.hpp"'))
	find('"second.hpp"')
	assert(vim.deep_equal(lines(), source), "request applied edits without confirmation")
	choose(nil)
	assert(vim.deep_equal(lines(), source), "cancel edited source")
	invoke()
	choose(find('"first.hpp"'))
	assert(table.concat(lines(), "\n"):find('#include "first.hpp"', 1, true), "real include not applied")
	ready()
	vim.cmd.undo()
	assert(vim.deep_equal(lines(), source), "one undo must restore the entire include action")
	ready()
	invoke()
	choose(find('"first.hpp"'))
	ready()
	invoke()
	for _, choice in ipairs(choices or {}) do
		for _, edit in ipairs(choice.edits) do
			assert(not edit.newText:find('"first.hpp"', 1, true), "duplicate include offered")
		end
	end
	choose(find('"second.hpp"'))
	ready()
	invoke()
	assert(choices == nil and notice, "no-op must not offer non-include actions")
	assert(vim.deep_equal(vim.fn.readfile(root .. "/main.cpp"), source), "action saved the file")
	wait(function()
		local result = client:request_sync("workspace/symbol", { query = "index_anchor" }, 1000, buf)
		for _, symbol in ipairs(result and result.result or {}) do
			if symbol.name == "index_anchor" then
				return true
			end
		end
		return false
	end, "independent translation unit indexed")

	-- Simulate pasted uses with every include removed, after the real project
	-- symbols have been indexed. These are unknown-type fixes, not just Strict.
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "First first;", "Second second;" })
	ready()
	invoke()
	choose(find('"first.hpp"'))
	ready()
	invoke()
	choose(find('"second.hpp"'))
	ready()
	assert(#publish.diagnostics == 0, "pasted uses still have diagnostics: " .. vim.inspect(publish.diagnostics))

	local uri = vim.uri_from_bufnr(buf)
	local version = vim.lsp.util.buf_versions[buf]
	local valid = { title = "insert", kind = "quickfix", edit = { changes = { [uri] = first.edits } } }
	local function reply(action, delayed)
		client.request = function(self, method, params, callback, target)
			if method ~= "textDocument/codeAction" then
				return request(self, method, params, callback, target)
			end
			assert(params.context.only[1] == "quickfix" and params.range.start.line == 0)
			if delayed then
				delayed(callback)
			else
				callback(nil, { action })
			end
			return true, 1
		end
	end
	local function rejected(action, label)
		local before = lines()
		reply(action)
		invoke()
		assert(not choices and notice, label .. " was offered")
		assert(vim.deep_equal(lines(), before), label .. " changed source")
	end
	local cases = {
		{ command = { command = "unsafe" }, edit = valid.edit },
		{ disabled = { reason = "disabled" }, edit = valid.edit },
		{ edit = { changes = { [uri .. ".other"] = first.edits } } },
		{ edit = { documentChanges = { { kind = "delete", uri = uri } } } },
		{
			edit = {
				documentChanges = { { textDocument = { uri = uri, version = version - 1 }, edits = first.edits } },
			},
		},
		{ title = "resolve-only", data = { some = "data" } },
	}
	for _, case in ipairs(cases) do
		rejected(case, vim.inspect(case))
	end
	for _, text in ipairs({ "", "int rewritten;\n", '#include "x"\nrun();\n', '#include "x"' }) do
		local action = vim.deepcopy(valid)
		action.edit.changes[uri][1].newText = text
		rejected(action, "non-insertion")
	end
	local removal = vim.deepcopy(valid)
	removal.edit.changes[uri][1].range["end"].line = removal.edit.changes[uri][1].range.start.line + 1
	rejected(removal, "replacement")
	local foreign = vim.deepcopy(valid)
	foreign.edit.changes[uri .. ".other"] = first.edits
	rejected(foreign, "mixed-file edit")
	local versioned = {
		title = "versioned",
		edit = {
			documentChanges = { { textDocument = { uri = uri, version = version }, edits = first.edits } },
		},
	}
	reply(versioned)
	invoke()
	assert(choices and #choices == 1, "current versioned edits rejected")
	choose(nil)
	local alternatives = { valid, vim.deepcopy(valid) }
	alternatives[2].title = "alternative internal header"
	alternatives[2].edit.changes[uri][1].newText = '#include "impl/first.hpp"\n'
	reply(valid, function(callback)
		callback(nil, alternatives)
	end)
	local unmodified = lines()
	invoke()
	assert(#choices == 2 and vim.deep_equal(lines(), unmodified), "ambiguous headers were auto-selected")
	choose(nil)
	reply(valid, function(callback)
		callback({ message = "injected failure" })
	end)
	invoke()
	assert(not choices and notice:find("injected failure", 1, true), "query error hidden")

	-- Single candidates still require confirmation. No public-header guessing.
	reply(valid)
	invoke()
	assert(choices and #choices == 1, "single action must still prompt")
	local before = lines()
	vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "// edited while choosing" })
	choose(choices[1])
	assert(#lines() == #before + 1 and notice:find("未应用", 1, true), "stale selection applied")
	local callback
	reply(valid, function(cb)
		callback = cb
	end)
	choices, notice = nil, nil
	includes.choose()
	vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "// edited while requesting" })
	callback(nil, { valid })
	assert(not choices and notice:find("丢弃", 1, true), "stale response offered")
	reply(valid)
	invoke()
	local replacement = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_current_buf(replacement)
	choose(choices[1])
	assert(notice:find("未应用", 1, true), "selection after changing buffer applied")
	vim.api.nvim_set_current_buf(buf)
	vim.api.nvim_buf_delete(replacement, { force = true })
end, debug.traceback)
client.request = request
vim.ui.select, vim.notify = select, notify
dofile("tests/nvim/lsp_shutdown.lua")({ client }, "clangd-includes", 10000)
if vim.api.nvim_buf_is_valid(saved_buf) then
	vim.api.nvim_set_current_buf(saved_buf)
end
vim.api.nvim_buf_delete(buf, { force = true })
vim.fn.delete(root, "rf")
assert(ok, err)
print(
	"Clangd include actions passed: real edits, cancellation, undo, duplicate prevention, stale replies, edit boundaries."
)
