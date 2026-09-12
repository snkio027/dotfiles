local luasnip = require("luasnip")

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
}
