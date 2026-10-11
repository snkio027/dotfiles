; extends

; ZLS labels both user types and primitives as `type`. Only syntactic builtin
; types retain the builtin color above LSP typemod priority (127). Identifiers,
; including qualified types and same-spelled fields, keep semantic authority.
([
  (builtin_type)
  "anyframe"
] @type.builtin
  (#set! priority 128))
