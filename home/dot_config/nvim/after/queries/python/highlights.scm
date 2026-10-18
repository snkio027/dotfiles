; extends

; Python 3.15 lazy imports are not recognized by the current parser. Recover
; only a lone ERROR identifier immediately before an import (or its block).
; A normal `lazy` expression/assignment, including one before an import on a
; new line, is not an ERROR and must retain its ordinary identity.
(_
  (ERROR . (identifier) @keyword.import .)
  .
  [
    (import_statement)
    (import_from_statement)
    (block . [(import_statement) (import_from_statement)])
  ]
  (#eq? @keyword.import "lazy")
  (#set! priority 101))
