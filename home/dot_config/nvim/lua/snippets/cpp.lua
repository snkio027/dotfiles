local luasnip = require("luasnip")

local function snippet(trigger, description, lines)
  return luasnip.parser.parse_snippet(
    { trig = trigger, name = description, dscr = description },
    table.concat(lines, "\n")
  )
end

return {
  luasnip.parser.parse_snippet(
    {
      trig = "forr",
      name = "Safe reverse iterator loop",
      dscr = "Iterate in reverse without unsigned underflow",
      priority = 2000,
    },
    table.concat({
      "for (auto ${1:it} = ${2:container}.rbegin(); ${1:it} != ${2:container}.rend(); ++${1:it}) {",
      "\t${0}",
      "}",
    }, "\n")
  ),
  snippet("tfn", "Function template", {
    "template <typename ${1:T}>",
    "${2:void} ${3:function_name}(${1:T} ${4:value}) {",
    "\t${0}",
    "}",
  }),
  snippet("tclass", "Class template (struct)", {
    "template <typename ${1:T}>",
    "struct ${2:Box} {",
    "\t${1:T} ${3:value};",
    "\t${0}",
    "};",
  }),
  snippet("tusing", "Alias template", {
    "template <typename ${1:T}>",
    "using ${2:Alias} = ${1:T};${0}",
  }),
  snippet("concept", "Concept with a type requirement", {
    "template <typename ${1:T}>",
    "concept ${2:HasValueType} = requires {",
    "\ttypename ${1:T}::${3:value_type};",
    "};${0}",
  }),
  snippet("requires", "Requires-expression (add a semicolon when defining a concept)", {
    "requires (${1:T} ${2:value}) {",
    "\t${2:value}.${3:size}();",
    "\t${0}",
    "}",
  }),
  snippet("ifce", "Compile-time conditional", {
    "if constexpr (${1:condition}) {",
    "\t${0}",
    "}",
  }),
  snippet("tpack", "Forwarding parameter pack and fold (requires <utility> and a callable)", {
    "template <typename... ${1:Args}>",
    "void ${2:visit_all}(${1:Args}&&... ${3:args}) {",
    "\t(static_cast<void>(${4:consume}(std::forward<${1:Args}>(${3:args}))), ...);",
    "\t${0}",
    "}",
  }),
  snippet("tspec", "Explicit class specialization (requires a primary template)", {
    "template <>",
    "struct ${1:Box}<${2:int}> {",
    "\t${0}",
    "};",
  }),
}
