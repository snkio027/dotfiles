; extends
(lifetime
  (identifier) @type.lifetime)

; `crate` names a path root elsewhere, but introduces a declaration here.
(extern_crate_declaration
  [(crate) "as"] @keyword.import
  (#set! priority 101))

; The current parser recovers the external-item `safe` modifier as an ERROR
; identifier. Never color ordinary variables, function names or raw identifiers.
(foreign_mod_item
  body: (declaration_list
    [
      (function_signature_item (ERROR . (identifier) @keyword.modifier .))
      (static_item (ERROR . (identifier) @keyword.modifier .))
    ])
  (#eq? @keyword.modifier "safe")
  (#set! priority 101))
