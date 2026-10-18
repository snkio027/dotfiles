; extends

; ZLS labels both user types and primitives as `type`. Only syntactic builtin
; types retain the builtin color above LSP typemod priority (127). Identifiers,
; including qualified types and same-spelled fields, keep semantic authority.
([
  (builtin_type)
  "anyframe"
] @type.builtin
  (#set! priority 128))

; Unsupported inline-asm syntax can disturb subsequent nodes in a valid file.
; Recover only these grammar positions, not arbitrary identifier spellings.
(switch_case
  (identifier) @keyword
  (#eq? @keyword "else")
  (#set! priority 101))

(ERROR
  (block_label (identifier) @keyword)
  (#any-of? @keyword "const" "var")
  (#set! priority 101))
