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

; Zig doc comments are //! or exactly ///, not //// separators. Their syntax
; owns the foreground above ZLS comment tokens (125/127), including when ZLS
; incorrectly marks a four-slash separator as documentation.
((comment) @comment.documentation
  (#lua-match? @comment.documentation "^//[!/]")
  (#not-lua-match? @comment.documentation "^////")
  (#set! priority 128))
