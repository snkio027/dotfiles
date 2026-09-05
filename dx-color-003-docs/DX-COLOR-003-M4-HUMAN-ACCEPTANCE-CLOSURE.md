# DX-COLOR-003 M4 — Human Acceptance Closure

<!-- markdownlint-disable MD013 -->

- **Milestone:** M4 / final human visual decision
- **Accepted candidate:** C4.4 High-Chroma Night
- **Candidate runtime:** `main@65b61ee03bef0bc0bb8bee945d1bbc32a6a829b5`
- **Decision authority:** repository owner / daily editor user
- **Decision:** `PASS`
- **Closure mechanism:** explicit governed protocol waiver

## Decision

C4.4 High-Chroma Night is accepted as the production visual baseline.

This record closes M4 without claiming that the original fixed five-language,
timed acceptance procedure was completed. The repository owner explicitly
chooses the observed iterative A/B evidence as sufficient for the personal
editor configuration and authorizes M5 to retire the C3.1 runtime path.

The exact verdict is:

```text
PASS
```

## Evidence actually observed

The human review used repeated real Neovim sessions and tiled comparisons in
the same terminal environment. The key comparisons controlled window focus and
used the same dense C/C++ source family, diagnostics, font configuration, and
editor UI while evaluating:

```text
C3.1
C4.0 / C4.1 foreground experiments
C4.3 High-Separation Graphite
TokyoNight Night / Storm as perceptual references
C4.4 High-Chroma Night
```

The review established these preferences:

```text
high-chroma, explicit hue families
dark slightly cool canvas
strong local semantic separation
softened neutral body without TokyoNight white glare
readable recessed comments
stable amber callable landmarks
distinct violet / blue / cyan / green / pink axes
```

C4.3 was rejected because its neutral graphite canvas and pastel foreground
distribution reduced scanability for this user. C4.4 retained the DX semantic
architecture while adopting the perceptual topology that won the direct A/B.

## Explicit protocol waiver

The original M3-A acceptance protocol requested:

```text
fixed human matrix: C++23 / Rust / Zig / Python / C
first-impression window: 10 minutes
sustained-editing window: 30-60 minutes
```

The following were not completed as formally recorded evidence:

```text
five-language human matrix          WAIVED
timed 10-minute observation         WAIVED
timed 30-60-minute observation      WAIVED
```

Automated five-language semantic/runtime gates do not substitute for those
human observations. They prove role, authority, provider, graph, and runtime
correctness only.

The waiver is accepted because visual comfort is a user-owned judgment for
this personal configuration, the owner made an explicit final selection after
multiple controlled comparisons, and the omitted observations are disclosed
rather than silently represented as completed.

This waiver is specific to C4.4. It does not weaken future human-acceptance
contracts and cannot be inferred from CI success alone.

## Acceptance answers

Based on the evidence actually observed:

```text
First-impression scanability          PASS
ordinary body comfort                 PASS
type/callable/control landmarks       PASS
comment readability and recession    PASS
operator salience                     PASS
overall color density                 PASS
body-white glare control              PASS
```

The fixed cross-language human-comfort questions remain unmeasured under this
waiver and are not reported as passing.

## Promotion authority

This closure supersedes only the pre-acceptance boundary in the frozen C4.4
candidate record:

```text
C4.4 explicit opt-in                  historical candidate state
C3.1 compatibility default           historical candidate state

C4.4 sole production visual          authorized by this closure
C3.1 executable runtime path         authorized for retirement in M5
```

The earlier M4 evidence record remains unchanged as a truthful snapshot of the
candidate before final acceptance.

## Limits

This decision does not claim:

- universal accessibility or comfort;
- completion of the waived language/time matrix;
- that automated OKLab/contrast gates approve aesthetics;
- that C4.4 can never receive a future issue-driven visual correction.

It does establish enough owner-authorized evidence to promote C4.4 and remove
the obsolete runtime selector and C3.1 compatibility implementation.
