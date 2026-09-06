local M = {}

local function copy_sorted(values)
	local result = vim.deepcopy(values or {})
	table.sort(result)
	return result
end

function M.expected_semantic_groups(tokens, filetype, priorities)
	priorities = priorities or { type = 125, modifier = 126, typemod = 127 }
	local groups = {}
	for _, token in ipairs(tokens or {}) do
		groups[#groups + 1] = {
			group = ("@lsp.type.%s.%s"):format(token.type, filetype),
			priority = priorities.type,
		}
		for _, modifier in ipairs(token.modifiers or {}) do
			groups[#groups + 1] = {
				group = ("@lsp.mod.%s.%s"):format(modifier, filetype),
				priority = priorities.modifier,
			}
			groups[#groups + 1] = {
				group = ("@lsp.typemod.%s.%s.%s"):format(token.type, modifier, filetype),
				priority = priorities.typemod,
			}
		end
	end
	table.sort(groups, function(left, right)
		return left.group < right.group
	end)
	return groups
end

local function group_keys(groups)
	local result = {}
	for _, item in ipairs(groups or {}) do
		result[#result + 1] = ("%s@%d"):format(item.group, item.priority)
	end
	return copy_sorted(result)
end

function M.semantic_application(expected, applied)
	local expected_keys = group_keys(expected)
	local applied_keys = group_keys(applied)
	return {
		complete = vim.deep_equal(expected_keys, applied_keys),
		expected = expected_keys,
		applied = applied_keys,
	}
end

function M.readiness(state)
	local missing = {}
	if not state.parser_ready then
		missing[#missing + 1] = "parser"
	end
	if not state.treesitter_complete then
		missing[#missing + 1] = "treesitter-captures"
	end
	if not state.raw_token_arrived then
		missing[#missing + 1] = "raw-semantic-token"
	end
	if not state.raw_decoded_equal then
		missing[#missing + 1] = "raw-decoded-equality"
	end
	if not state.semantic_application_complete then
		missing[#missing + 1] = "semantic-application-groups"
	end
	return { ready = #missing == 0, missing = missing }
end

function M.authority(candidates)
	if #candidates == 0 then
		return { status = "no_foreground", top = {} }
	end
	local top_priority = candidates[1].priority
	local top = {}
	local foregrounds = {}
	for _, candidate in ipairs(candidates) do
		if candidate.priority == top_priority then
			top[#top + 1] = candidate
			foregrounds[candidate.attributes.fg] = true
		end
	end
	local colors = vim.tbl_keys(foregrounds)
	table.sort(colors)
	if #top == 1 then
		return { status = "unique_top_foreground", top_priority = top_priority, foreground = colors[1], top = top }
	end
	if #colors == 1 then
		return { status = "shared_top_foreground", top_priority = top_priority, foreground = colors[1], top = top }
	end
	return { status = "ambiguous_top_foreground", top_priority = top_priority, foregrounds = colors, top = top }
end

return M
