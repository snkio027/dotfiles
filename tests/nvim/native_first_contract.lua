local readiness = dofile("tests/nvim/native_first/readiness.lua")

local function assert_equal(actual, expected, message)
	if not vim.deep_equal(actual, expected) then
		error(("%s\nexpected: %s\nobserved: %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
	end
end

local expected = readiness.expected_semantic_groups({
	{ type = "variable", modifiers = { "declaration", "readonly" } },
}, "cpp")
assert_equal(#expected, 5, "type/mod/typemod group closure")

local complete = readiness.semantic_application(expected, expected)
assert_equal(complete.complete, true, "complete semantic application")
local incomplete = readiness.semantic_application(expected, vim.list_slice(expected, 1, 4))
assert_equal(incomplete.complete, false, "missing semantic group must remain incomplete")

local parser_without_ts = readiness.readiness({
	parser_ready = true,
	treesitter_complete = false,
	raw_token_arrived = true,
	raw_decoded_equal = true,
	semantic_application_complete = true,
})
assert_equal(parser_without_ts.ready, false, "parser without Tree-sitter highlight must not settle")
assert_equal(parser_without_ts.missing, { "treesitter-captures" }, "Tree-sitter readiness reason")

local decoded_without_groups = readiness.readiness({
	parser_ready = true,
	treesitter_complete = true,
	raw_token_arrived = true,
	raw_decoded_equal = true,
	semantic_application_complete = false,
})
assert_equal(decoded_without_groups.ready, false, "decoded token without all application groups must not settle")
assert_equal(decoded_without_groups.missing, { "semantic-application-groups" }, "semantic readiness reason")

local function candidate(group, priority, foreground)
	return { group = group, priority = priority, attributes = { fg = foreground } }
end

assert_equal(
	readiness.authority({ candidate("A", 127, "#AAAAAA") }).status,
	"unique_top_foreground",
	"unique authority"
)
assert_equal(
	readiness.authority({ candidate("A", 127, "#AAAAAA"), candidate("B", 127, "#AAAAAA") }).status,
	"shared_top_foreground",
	"shared-color authority"
)
local ambiguous = readiness.authority({ candidate("A", 127, "#AAAAAA"), candidate("B", 127, "#BBBBBB") })
assert_equal(ambiguous.status, "ambiguous_top_foreground", "different-color equal-priority authority")
assert_equal(ambiguous.foreground, nil, "ambiguous authority must not invent a winner")

print("Native-first readiness contract passed")
