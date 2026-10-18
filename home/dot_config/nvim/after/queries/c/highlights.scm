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
