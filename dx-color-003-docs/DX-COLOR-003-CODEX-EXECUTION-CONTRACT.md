# DX-COLOR-003 — Codex Execution Contract

- **Document ID:** DX-COLOR-003-CODEX
- **Audience:** Codex implementation agent
- **Status:** Normative

---

## 1. Mission

Implement DX-COLOR-003 exactly as specified by the architecture, implementation, test, and C4 visual documents.

The goal is not to “make the theme prettier”.

The goal is to:

1. make the semantic architecture modular and evidence-driven;
2. preserve current behavior during refactoring;
3. add a separately reviewable C4 visual profile;
4. prevent provider quirks from leaking into the semantic domain.

---

## 2. Mandatory reading

Before editing:

```text
DX-COLOR-003-ARCHITECTURE.md
DX-COLOR-003-IMPLEMENTATION-PLAN.md
DX-COLOR-003-TEST-EVIDENCE-SPEC.md
DX-COLOR-003-C4-VISUAL-SPEC.md
```

Then inspect the actual repository baseline.

Do not implement from the documents alone if the current repository has moved.

---

## 3. Source-of-truth order

When sources disagree:

```text
1. current repository facts
2. normative architecture/test documents
3. observed runtime evidence
4. upstream provider documentation/source
5. inference
```

Inference must never silently override runtime evidence.

---

## 4. Absolute prohibitions

Codex MUST NOT:

- switch the default colorscheme away from Catppuccin;
- add TokyoNight as a dependency;
- copy TokyoNight's palette wholesale;
- combine architecture extraction and C4 visual changes in one commit;
- add speculative LSP typemod matrices;
- introduce a new `Dx*` role because an external provider happens to use a token/modifier name;
- add raw source HEX values in adapter/binding files;
- map an ambiguous generic LSP token to a more precise semantic role without evidence;
- weaken/remove existing sentinels merely to make tests pass;
- silently remove provider/client isolation;
- claim universal CVD safety;
- claim remote CI PASS before the current HEAD has actually passed;
- merge a PR unless explicitly authorized by the user.

---

## 5. Architecture extraction rule

M1 is a refactor.

Expected semantic/rendering behavior:

```text
before == after
```

If a visual difference appears during M1:

> stop and treat it as a defect.

Do not “accept the improvement”.

Visual improvement belongs to M3.

---

## 6. Provider-rule admission rule

Before adding any provider-specific rule, answer all of:

```text
What exact source token is affected?
What exact Tree-sitter capture exists?
What exact LSP server emitted the token?
What exact LSP type was emitted?
What modifiers were emitted?
What distinction does the provider preserve or lose?
Why is the chosen authority correct?
Which sentinel proves it?
```

If any answer is unknown, gather evidence first.

---

## 7. New-role admission rule

A new role requires a semantic definition with no external vocabulary.

Rejected definition:

```text
DxStaticVariable:
"a variable with LSP static modifier"
```

Potentially acceptable definition:

```text
DxModuleBinding:
"a value binding whose scope/storage is non-local to the current function/block and belongs to a module, namespace, type, or persistent storage domain"
```

Even an acceptable definition still requires evidence before implementation.

---

## 8. Layer-selection rule

When a visual defect is reported, classify it before editing.

```text
Wrong thing classified?
-> Adapter / binding / authority

Right role, wrong appearance?
-> Visual profile

Selection/reference/cursor/inlay noise?
-> UI bindings

Server sent unexpected token?
-> Evidence / adapter

Tree-sitter capture missing?
-> query/binding
```

Do not change palette values to hide a semantic-classification bug.

---

## 9. Runtime evidence commands

Use the project's existing probe/test mechanisms first.

Useful direct probes may include:

```vim
:Inspect
:InspectTree
:lua print(vim.inspect(vim.inspect_pos(...)))
```

and:

```lua
vim.lsp.semantic_tokens.get_at_pos(...)
```

Raw observations must be attached to new adapter decisions.

---

## 10. Upstream research rule

When exact provider behavior matters, inspect upstream source or authoritative documentation.

Examples:

```text
clangd semantic token taxonomy
ZLS semantic token modifiers
rust-analyzer semantic token extensions
Neovim semantic highlight group behavior
```

Do not assume different servers interpret identical modifier names identically.

---

## 11. Provider identity limitation

Static Neovim highlight groups encode filetype/token/modifier, not necessarily server identity.

Current design assumes one primary semantic-token provider per relevant filetype.

Do not build a custom dynamic extmark renderer to solve a hypothetical multi-provider future.

If that requirement actually appears, stop and request a new architecture decision.

---

## 12. C4 implementation rule

C4 starts opt-in.

Default remains C3.1.

C4 changes visual projection only.

Adapters and authority decisions must remain unchanged unless an independently proven bug is discovered. Such a bug requires a separate commit/PR.

---

## 13. Test modification rule

A test may be changed only when:

```text
the architecture contract intentionally changed
or
the visual-profile contract intentionally changed
or
new runtime evidence adds a new valid case
```

Do not relax tests because the implementation fails them.

When retiring a C3-specific visual invariant, replace it with the C4 invariant that expresses the new design intent.

---

## 14. Commit discipline

Preferred commits:

```text
refactor(theme): extract semantic bindings and provider adapters
test(theme): expand binding-topology evidence
feat(theme): add opt-in C4 airy visual profile
style(theme): make C4 airy the default profile
```

Do not squash unrelated concerns locally before review if that hides implementation history needed for inspection.

---

## 15. PR discipline

Each PR description must state:

```text
Base SHA
Head SHA
scope
changed files
design invariants
evidence added
tests run
remote CI status
known limitations
explicit non-goals
```

If the PR is architecture-only, explicitly state:

```text
Intended visual delta: NONE
```

If it is visual-only, explicitly state:

```text
Semantic authority delta: NONE
```

---

## 16. Stop conditions

Stop implementation and report instead of guessing if:

- current main materially differs from the documented baseline;
- two providers attach and conflict in the same test buffer;
- an upstream token cannot be attributed to the expected client;
- a proposed role cannot be described independently of provider vocabulary;
- C4 requires changing semantic authority to look acceptable;
- an existing sentinel contradicts the proposed architecture;
- CI failure appears unrelated to the current change and cannot be safely attributed.

---

## 17. Required completion report

Final report must include:

```text
STATUS: PASS / BLOCKED / REVIEW READY

Base:
Head:
Branch:

Architecture changes:
Visual changes:
Authority changes:
Role changes:

Evidence:
- ...

Tests:
- Tier-1:
- fixtures:
- Tier-2A:
- Tier-2B:
- CI:

Visual acceptance:
- pending / pass / reject

Known limitations:
- ...

Not performed:
- merge
- unrelated cleanup
- speculative mappings
```

---

## 18. Definition of success

Success means the resulting system can answer these questions independently:

```text
What does this token mean?
Which producer provided the evidence?
Which producer has foreground authority?
Which DX role represents the meaning?
How should that role look in this visual profile?
```

If those questions collapse into one large mappings table again, the refactor has failed.
