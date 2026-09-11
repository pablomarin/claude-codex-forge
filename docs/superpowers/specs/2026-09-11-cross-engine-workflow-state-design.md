# Cross-Engine Workflow State Command Design

## Problem

The Forge 6.2 candidate requires every active workflow to read canonical state before each action and
to initialize workflow identity, receipt paths, and local evidence directories at activation. The
Claude adapter can fall back to native Read/Write tools, but Codex CLI exposes shell and patch tools
only. At the same time, `check-bash-safety` deliberately blocks direct shell reads of
`.forge/local/state.md` and common shell writes under `.forge/local/`. The documented workflow is
therefore not executable through Codex's supported surface, and the live Claude-to-Codex smoke test
stopped at that boundary.

The existing test suite missed the contradiction because its host-switch fixtures edit state with
unhooked `sed` and create directories directly. Those tests prove receipt semantics, not installed
host capability.

## Decision

Add one bounded Forge-owned workflow-state command with Bash 3.2 and Windows PowerShell 5.1 twins
behind the same argument contract:

```text
workflow-state show
workflow-state activate --host <claude|codex> --workflow <new-feature|fix-bug|quick-fix> \
  --task <slug> --base-ref <ref> --phase <single-line-value> --next-step <single-line-value>
workflow-state checkpoint --host <claude|codex> --phase <single-line-value> \
  --next-step <single-line-value> [--begin-review]
```

Both implementations infer the physical repository worktree from the current directory. Callers do
not pass state paths, evidence paths, Git-common paths, base SHAs, candidate identifiers, receipt
paths, or review iteration numbers.

### `show`

`show` resolves canonical state through the existing `state-path` helper and writes it to standard
output without mutation. It fails closed for missing, legacy, malformed, or symlinked V6 state.

### `activate`

`activate`:

1. resolves the physical Git worktree and Git-common directory;
2. validates the host, workflow name, task slug, base ref, phase, and next-step values;
3. resolves the base ref to an immutable commit SHA;
4. rejects an already-active different workflow unless its phase is exactly `complete` and its next
   step is exactly `none`;
5. replaces the Identity, Workflow, and six task-derived Receipts table values for the requested
   task, leaving the independently allocated `Council receipt` row untouched;
6. initializes `Review iteration` to `0` and the helper-owned `First certified iteration` anchor to
   `none` only for a new activation;
7. creates only `.forge/local/evidence/<task>` and `.forge/local/reviews/<task>`; and
8. publishes state with a same-directory temporary file and atomic rename.

Re-running the identical activation while the workflow is non-terminal is idempotent and preserves
the current review iteration. Re-running it with a different host may update only
`Last active host`; its workflow, task, base, phase, next step, receipt paths, and iteration must
already match. Any activation from a terminal `complete`/`none` state starts a new workflow—even
when the workflow and task slug are reused—and initializes its iteration to zero. Completion uses no fourth verb:
`checkpoint --phase complete --next-step none` is the terminal transition. This state is not
shipping authorization; the existing receipt and promotion gates remain authoritative.

An exact in-flight V6.1 placeholder bundle is the one compatibility exception: when command,
worktree identity, base identity, phase, and next step already match, `activate` may adopt the
literal `<integer>` review value and six literal `<task-id>` receipt paths by replacing them with
iteration `0`, anchor `none`, and the derived task paths. Any partially populated or non-identical
state remains blocked; adoption never guesses prior review progress.

The workflow-specific checklist remains canonical prose in the workflow document and is installed
in state by the host's normal file-edit capability after activation. This keeps the helper from
becoming a workflow runtime while still making the previously impossible state and directory
operations portable.

### `checkpoint`

`checkpoint` requires an active supported workflow. It updates only `Last active host`, `Phase`, and
`Next step`. With `--begin-review`, it additionally increments the existing non-negative integer
`Review iteration` by exactly one. Without the flag, the iteration is preserved. It never accepts a
candidate or receipt path and preserves every other byte outside those table values.

Before changing the iteration, `checkpoint` validates the current paired review receipts. The first
valid pair records the current iteration in `First certified iteration`; that anchor is derived,
cannot be supplied by the caller, and never advances. The convergence breaker uses the anchor even
after a later candidate mutation makes the old pair stale, so its post-certification round limit
cannot silently reset.

All caller-supplied table values reject CR, LF, `|`, and leading or trailing whitespace. Task slugs
reject absolute paths, dot segments, separators, and characters outside lowercase ASCII letters,
digits, and single hyphens. Base refs reject option-like, revision-expression, and traversal forms.
Literal backslash sequences remain literal. Both platform writers normalize canonical state to
UTF-8 without BOM and LF line endings, and `show` emits the stored bytes without console transcoding.

Malformed state, duplicate target fields, unexpected existing values, invalid task paths, and
symlinked canonical state locations fail closed without changing state. Both mutation verbs hash
the state after reading and recheck that hash immediately before atomic replacement. A mismatch
fails closed instead of overwriting a concurrent edit. The already-accepted no-lock model retains a
small race after the check; overlapping sessions must still coordinate.

## Safety-Hook Contract

The literal helper invocation contains `.forge/hooks/lib/workflow-state`, not a protected
`.forge/local` path, so the existing high-risk and local-state checks can evaluate it normally. No
early bypass or general exception is added. Behavioral safety tests pin that the exact helper
commands are allowed while the hook's existing targeted inline `cat`, `rg`, `mkdir`, redirect, and
common mutation forms remain blocked. The documented variable-indirection and exotic-writer
residuals remain out of scope; this change does not claim the safety hook is a complete shell parser.

Canonical workflow prose tells both host adapters to invoke the installed helper as their first
post-discovery action. In the Forge source checkout only, tests and maintainers may use the tracked
`hooks/lib` path when the installed path does not exist.

The Stop advisory keys off an active V6 workflow command, not a populated candidate path. It
therefore reports missing or stale final evidence from activation onward, including while upgraded
V6.1 placeholder paths have not yet been adopted. The advisory remains non-blocking; ship gates
remain authoritative.

## Compatibility

The command operates only on canonical V6 state. It performs the exact V6.1 placeholder adoption
described above, but does not read or migrate V5 state and does not change full-refresh ownership
rules. Existing strict final receipts, exact-candidate promotion, candidate-mutation invalidation,
reviewer routing, and the no-lock coordination model are unchanged.

The new platform twins are Forge-managed V6 files and must be installed by upgrade.

## Verification

Automated behavioral tests must prove:

- `show` returns the canonical state;
- `activate` derives physical identity and base SHA, creates only the two owned directories, fills
  the six task-derived receipt paths, leaves the Council receipt untouched, and initializes
  iteration zero;
- identical activation preserves a later iteration, conflicting active activation fails without
  mutation, and a terminal `complete`/`none` checkpoint permits a new activation;
- `checkpoint` changes only its three allowlisted fields;
- `--begin-review` increments by exactly one and never accepts an arbitrary iteration;
- the first valid paired review is anchored once and later review rounds cannot reset the breaker;
- an identical V6.1 placeholder bundle is adopted while partial or conflicting bundles fail closed;
- invalid hosts, workflows, slugs, refs, pipe/CR/LF/outer-whitespace values, duplicate fields,
  malformed V6 state, legacy-only state, and symlinks fail closed;
- newline-bearing slugs are rejected before path construction, literal backslashes survive, and
  CRLF input is normalized to LF;
- a state hash mismatch immediately before publication fails without overwriting the concurrent
  edit;
- runtime continuation hooks point both hosts to `workflow-state show` rather than the blocked
  direct-read route;
- the Stop advisory reports an active workflow even before candidate receipt paths are populated;
- the safety hook permits literal helper invocations and retains its documented targeted local-state
  blocks;
- Bash and PowerShell expose the same verbs, options, validation messages, and side effects; and
- setup installs both files into `.forge/hooks/lib/`.

The decisive release qualification is an installed disposable worktree with normal hooks: Claude
must activate before discretionary investigation or tracked mutation, and a fresh Codex process
must `show` and `checkpoint` the same state. The base SHA, review iteration, exact next step,
candidate fingerprint, and index tree must survive the switch except for the explicitly allowed
checkpoint fields. Direct local shell access must remain denied, and a later candidate mutation
must stale its bound receipts.

PowerShell execution remains a separate compatible-host qualification. When `pwsh` is unavailable
locally, static parity is reported as such and is not represented as Windows runtime proof.
