; extends

; Word-only pragma operands are preprocessor metadata, not C declarations.
; Upstream injects C/C++ into preproc_arg and can misread a vendor prefix as a
; type. Leave strings/expressions to upstream; 101 beats the injected TS type
; (100) but stays below semantic tokens and inactive-code highlighting (125).
((preproc_call
   directive: (preproc_directive) @_directive
   argument: (preproc_arg) @attribute)
  (#lua-match? @_directive "^#%s*pragma$")
  (#not-lua-match? @attribute "[^%w_%s]")
  (#set! priority 101))

; Doxygen line/bang comments are documentation too. C++ inherits this query.
; Exclude //// and /*** separators; stay below clangd inactive-code tokens.
((comment) @comment.documentation
  (#lua-match? @comment.documentation "^//[!/]")
  (#not-lua-match? @comment.documentation "^////")
  (#set! priority 101))

((comment) @comment.documentation
  (#lua-match? @comment.documentation "^/[*][*!]")
  (#not-lua-match? @comment.documentation "^/[*][*][*]")
  (#set! priority 101))
