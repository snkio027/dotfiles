; extends

; These tokens are not always inside the qualifier/storage nodes captured by
; upstream (e.g. inline namespaces, extern templates and if consteval).
; static_assert is a declaration, not a callable.
([
  "alignas" "const" "consteval" "constexpr" "constinit" "extern" "inline"
  "mutable" "register" "static" "static_assert" "thread_local" "volatile"
] @keyword
  (#not-has-ancestor? @keyword attribute_declaration attribute_specifier preproc_def preproc_function_def preproc_call)
  (#set! priority 101))

; Unexpanded declaration/namespace macros can recover reserved words as
; identifiers, types, members or labels. Match whole reserved words only:
; contextual identifiers (final/override/module/import) and operator names are
; deliberately excluded. Attributes and macro definitions retain their roles.
; 101 beats erroneous TS captures (100), below clangd inactive code (125).
([
  (identifier) (type_identifier) (field_identifier)
  (namespace_identifier) (statement_identifier)
] @keyword
  (#any-of? @keyword
    "alignas" "alignof" "asm" "break" "case" "catch" "class" "concept"
    "const" "consteval" "constexpr" "constinit" "const_cast" "continue"
    "co_await" "co_return" "co_yield" "decltype" "default" "delete" "do"
    "dynamic_cast" "else" "enum" "explicit" "export" "extern" "for"
    "friend" "goto" "if" "inline" "mutable" "namespace" "new" "noexcept"
    "private" "protected" "public" "register" "reinterpret_cast" "requires"
    "return" "sizeof" "static" "static_assert" "static_cast" "struct"
    "switch" "template" "thread_local" "throw" "try" "typedef" "typeid"
    "typename" "union" "using" "virtual" "volatile" "while")
  (#not-has-ancestor? @keyword attribute_declaration attribute_specifier preproc_def preproc_function_def preproc_call)
  (#not-has-parent? @keyword preproc_ifdef preproc_elifdef preproc_defined)
  (#set! priority 101))

; Primitive spellings must not become user-defined types during recovery.
; In particular the current C++ grammar represents wchar_t as type_identifier.
([
  (identifier) (type_identifier) (field_identifier) (namespace_identifier)
] @type.builtin
  (#any-of? @type.builtin
    "auto" "bool" "char" "char8_t" "char16_t" "char32_t" "double" "float"
    "int" "long" "short" "signed" "unsigned" "void" "wchar_t")
  (#not-has-ancestor? @type.builtin attribute_declaration attribute_specifier preproc_def preproc_function_def preproc_call)
  (#not-has-parent? @type.builtin preproc_ifdef preproc_elifdef preproc_defined)
  (#set! priority 101))

; Keep the entire special-member name callable, including ~ and operator=.
; 128 is above LSP typemod (127); the clangd adapter keeps inactive tokens above
; these special-member overrides. Ordinary operators are untouched.
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
