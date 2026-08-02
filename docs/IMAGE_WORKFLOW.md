# Image Workflow

How this repository makes and uses images: terms, the chain, and the
rules every image obeys. Settled in the 2026-08-01 design discussion.
The physics reading at the end is a shared shorthand, not normative.

## Terms

| Label | Name | What it is |
| --- | --- | --- |
| A | OS원본 | The image fetched from upstream. In code, a `BASE_IMAGE_NAME` whose `BASE_URL` is non-empty. |
| B | OS골든 | An OS image carrying the settings we need, usable as it stands. |
| C | VM 디스크 | A copy of B (B') after the purpose work; the VM's own disk. |
| ′ (prime) | 사본 | A' / B' mark a same-kind copy under preparation. Prime, not star or dagger — those carry other meanings (dual, adjoint). |

## Chain

```
A (OS원본) ──copy──▶ A' ──prepare──▶ B (OS골든)
```

A' is the copy. The preparation runs on A' only; A is never written to.

Settled consequence: A and B are independent, so re-fetching, moving, or
removing A cannot break B, and rebuilding B cannot disturb A.

## B to VM (settled 2026-08-01)

Same shape as A to B: copy first, prepare on the copy.

```
B (OS골든) ──copy──▶ B' ──prepare (purpose work)──▶ VM disk
```

B' is the copy and is the VM's own disk. The purpose work — what
iocrunner / ethercat provisioning does today — runs on B' only. B is
read, never written, never held by a running VM.

## What this resolves

B is held by no VM, which removes the root under three issues:

- #24 (M6.2) — libvirt claimed the backing file's ownership when a
  consumer started; with no backing chain there is no file to claim
- #25 (M1.6) — consumers held the golden so it could not be rebaked;
  the in-use guard (`protect_output_consumers`) and its first-transition
  refusal become unnecessary on this stretch
- #2 (M1.4) — rebaking B cannot disturb any VM already made from it
- the bake's flatten step (`qemu-img convert`) disappears: the disk is
  independent from birth

Cost, stated once: a VM disk grows from the current overlay (~106 M
observed) to the full size of B (several GB), and the purpose work runs
per VM instead of once per bake. Owner direction: disk and time costs
are reviewed later, not in this design round.

## Identity by pair (settled 2026-08-01)

Every image we produce carries its identity in two places made together:

- the file name holds a unique timestamp / hash;
- a creation-record file sits beside the image with the same values.

Verification is the pair agreeing. If either half is missing, or the
values disagree, the image is ignored. Neither half alone can lie, so
forgetting to delete one is safe — a stale record points at nothing
that matches it.

The pair rule applies only to images we make (B, VM disks). A (fetched
upstream) is out of scope: its identity is its source and checksum.

This covers the two problems left open above:

- "did this run make this VM" — answered by the creation record beside
  the VM disk, which names its maker; a domain merely existing never
  decides it (the root of #29 and the in-use misreport)
- where provenance lives with no purpose golden — the record file
  beside B carries what the manifest/sidecar carries today

## Naming is defined once (settled 2026-08-01)

The design renames everything we produce (timestamp / hash in the file
name), so the naming rule is being redefined anyway. It is defined in
ONE place from the start, and every consumer — provisioning and bake
alike — calls that one place.

This absorbs #7 (M3.2): today `create_vm.bash` and the bake scripts
each compute `VM_NAME` and disk paths on their own, two copies that
must agree. The approved resolver plan (`plan20260723_234700`) wanted
to extract that computation; the new naming scheme starts extracted,
so #7 is resolved by the redesign rather than as separate work.

## Build VMs are always fresh by construction (settled 2026-08-01)

The working VM that prepares an image gets its name from the same
one-place naming rule, so it too carries the run's timestamp / hash.
Names never collide across runs, so a leftover VM from an earlier run
can never be reused by accident — every run creates its own fresh VM.

Fresh-input enforcement (`-F` / `require_fresh_input`) becomes
unnecessary: there is nothing to force when reuse is structurally
impossible. The two bakes' opposite assumptions (M1.8) disappear with
it; M1.8 closes as superseded by this design. What remains of it is
housekeeping — when to remove leftover VMs — not correctness.

## A is kept (settled 2026-08-01)

A stays after B exists — owner's words: "받아온 이미지는 그냥 두고".
Deleting A was raised by the assistant and rejected. A is read-only
ground; nothing we make ever writes to it.

## Current code, for contrast

No B exists today. `rocky8`, `debian13`, and the five `epics-env-*` types
boot straight from A. The only baked images are `iocrunner-<os>.qcow2` and
`ethercat-<os>.qcow2`, and both are produced by layering onto A and then
flattening with `qemu-img convert`, not by copying.

## Physics reading (2026-08-01, shared shorthand)

A second language for the same structure, agreed between the owner and
the assistant as a private shorthand — the design stands on the plain
terms above; this section is how the two of us recall it.

- A is the vacuum: the ground everything is defined on and nothing acts
  upon. That A is kept and never written to is not a policy but what a
  vacuum is.
- B is a particle created from that vacuum. The preparation is the
  creation operator; the working VM that performs it is a virtual
  particle — it exists only while mediating A' → B and appears in no
  final state. A leftover build VM is an unclosed internal line.
- C's are many particles of the same species, and identical particles
  are indistinguishable — "which one is mine" has no answer for
  unlabeled VMs, which was the root of this month's loop (#29, the
  in-use misreport). The pair rule breaks exchange symmetry with
  labels: timestamp / hash plus creation record make the particles
  distinguishable.
- Each C evolves its own history from birth (an excited state); the
  record captures only the birth conditions, never the later state.
  Annihilation (clean) returns it to vacuum, leaving the record.
- The purpose work is a set of operators applied to the particle,
  classified as packages (what was installed) and configuration (what
  was changed) — today's manifest already records that operator list.
- The old backing chain was entanglement: a local operation on a
  consumer (starting it) changed the base's state (ownership, #24,
  #25). Copying separates the system into a product state — local
  operations stay local. Full copies are allowed because images are
  classical information; no-cloning does not apply.

In equations:

```
|0⟩ = A                          the vacuum, never acted on

|B⟩ = P |0⟩                      preparation P as creation operator,
                                 applied to the copy A', mediated by a
                                 virtual (build) VM

P   = Π_k O_k ,  O_k ∈ {pkg, cfg}   the operator product the record keeps

|C_i⟩ = W_i |B⟩ ,  i = (t_i, h_i)   purpose work W on the copy B';
                                 the label i (timestamp, hash) is what
                                 makes identical particles distinguishable

valid(X)  ⟺  name(X) ≡ record(X)    the pair rule; either half alone ⇒ ignore

old:  |golden, C_1, C_2, …⟩  entangled — not separable, one file shared
new:  |B⟩ ⊗ |C_1⟩ ⊗ |C_2⟩ ⊗ …   product state — local stays local

a |C_i⟩ = |0⟩ + record_i         clean returns to vacuum; the record survives
```
