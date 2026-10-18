; extends

; Unexpanded namespace/declaration macros can make the parser recover reserved
; enum/class tokens as identifiers. Repair only those ERROR children, not type
; names or macro bodies. Default TS priority stays below clangd inactive code.
((ERROR (identifier) @keyword.type)
  (#any-of? @keyword.type "enum" "class"))

; A macro-wrapped class can recover its first alias as a declaration whose
; type is the reserved word using. Only repair that type slot, not the alias
; name. 101 beats the erroneous @type (100), below inactive-code tokens (125).
((declaration type: (type_identifier) @keyword)
  (#eq? @keyword "using")
  (#set! priority 101))

; Keep the entire special-member name callable, including ~ and operator=.
; 128 is one above LSP typemod priority (127); ordinary operators are untouched.
((destructor_name) @function.method
  (#set! priority 128))

((operator_name "=") @function.method
  (#set! priority 128))

; clangd omits constructorOrDestructor on a delegating initializer. Only match
; the enclosing constructor's own name, not a base/member initializer or a
; capitalized call. Qualified out-of-class definitions use the terminal name.
((function_definition
   declarator: (function_declarator
     declarator: [
       (identifier) @_constructor
       (qualified_identifier name: (identifier) @_constructor)
     ])
   (field_initializer_list
     (field_initializer (field_identifier) @function.call)))
  (#eq? @_constructor @function.call)
  (#set! priority 128))
