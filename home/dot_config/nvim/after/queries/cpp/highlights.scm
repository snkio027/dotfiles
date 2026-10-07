; extends

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
