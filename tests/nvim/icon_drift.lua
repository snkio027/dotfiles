local cases_path = vim.fn.getcwd() .. "/tests/icons/generated_cases.json"
local payload = vim.json.decode(table.concat(vim.fn.readfile(cases_path), "\n"))

require("lazy").load({ plugins = { "mini.icons" } })
local mini_icons = require("mini.icons")
mini_icons.setup({})

local differences = {}
for _, case in ipairs(payload.cases) do
	local glyph, highlight = mini_icons.get("file", case.fixture)
	if glyph ~= case.glyph or highlight ~= case.nvim_highlight then
		table.insert(
			differences,
			("%s: contract=%s/%s upstream=%s/%s"):format(
				case.pattern,
				case.glyph,
				case.nvim_highlight,
				glyph,
				highlight
			)
		)
	end
end

print(("Upstream mini.icons drift %d/%d (informational)"):format(#differences, payload.expected))
for index, difference in ipairs(differences) do
	if index > 20 then
		print(("  ... %d additional differences"):format(#differences - 20))
		break
	end
	print("  " .. difference)
end
