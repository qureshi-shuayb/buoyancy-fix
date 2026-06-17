# Scope — Contingency-Graph Upgrade for `homebidder`

Goal: add the one ingredient Homebidder is missing — a **genuine algorithmic core** —
so the task produces an *on-topic domain-logic split* (the balance criterion:
`pass≥1 AND fail≥1` per model, failures on **real core logic**, not crashes or gotchas).

This mirrors the proven lever from `legal-matters-api` (#1 dependency graph w/ transitive
cycle detection + completion-blocking + cascade), domain-adapted to real-estate
**contingent offers**.

---

## Why this (and not what we tried before)
Everything added so far (budget invariant, edge cases, more 409s) was *more locally-simple
rules* — frontier models ace those → both 5/5 (no split). The two "gaps" we did get
(`counter_on_expired`, budget-on-expiry) were **ambiguity**, which is explicitly "what NOT
to do" (gotchas → false negatives, punishes the strong model). A graph algorithm with
interacting invariants creates many *plausible-but-subtly-wrong* implementations →
models split on capability, not luck.

---

## The mechanic: contingent offers
Real-estate-standard: a buyer's offer can be **contingent on the sale of another listing**
(typically the buyer's current home). The offer can't be accepted until that listing sells,
and if that listing can never sell, the offer dies.

### Data-model change
`Offer` gains an optional field:
- `contingent_on: string | null` — a `listing_id` that must reach **SOLD** before this offer
  may be accepted. Default `null` (no contingency). Set **only** at `POST /offers`
  (counters do **not** inherit/carry contingency — keeps the negotiation chain bounded).

Dependency graph **G**: nodes = listings; for every **PENDING** offer on listing `L` with
`contingent_on = D`, there is a directed edge `L → D` ("L's sale depends on D selling").

---

## Rules (the core)

**R1 — create validation (`POST /offers` with `contingent_on`)**
- `contingent_on` must reference an existing listing, else **400**.
- `contingent_on` may not equal the offer's own `listing_id` (self-loop), else **409**.

**R2 — transitive cycle detection** ⭐ the algorithmic core
- Creating the offer must not introduce a cycle in **G** (considering existing PENDING edges
  + the new `L → D` edge). Direct *and* transitive cycles → **409**.
  - e.g. offer on A contingent on B, offer on B contingent on C, new offer on C contingent
    on A → 409.
- This is the spot naive implementations get wrong (check direct only, miss transitive).

**R3 — accept-block while contingency unmet**
- `accept` on an offer whose `contingent_on` listing is **not SOLD** → **409**.
- Once the depended-on listing is SOLD, the offer becomes acceptable normally.

**R4 — cascade-reject when a contingency can never be satisfied**
- When a listing `D` becomes **ARCHIVED** (it can never sell), every PENDING offer with
  `contingent_on = D` is set to **REJECTED**.
- Define transitivity explicitly (see Open Decision #2).

**R5 — natural expiry still applies** — contingent offers expire on the virtual clock like any
other (already handled by global expiry).

---

## Where models will plausibly-but-subtly go wrong (the split surface)
1. **Cycle detection: direct-only vs transitive** (R2) — the headline differentiator.
2. **Cycle graph scope**: edges from PENDING offers only (REJECTED/EXPIRED don't constrain).
3. **Accept-check precedence** (R3 vs existing party/lock/expiry checks) — must be pinned in
   the spec to avoid an *ambiguity* trap (lesson learned: precedence must be explicit).
4. **Cascade scope** (R4): direct dependents only vs transitive; PENDING only.
5. **"Satisfied" = SOLD specifically**, not AVAILABLE/PENDING/any non-archived state.
6. **Self-contingency** and **unknown listing** status codes (409 vs 400).

These are *reasoning* errors, not rule-volume — exactly what separates frontier models.

---

## Open design decisions (need your call before building)
1. **Depend on a listing vs another offer.** Recommended: **listing** (`contingent_on` a
   listing_id). Listings are stable anchors; offer→offer is messy because counters constantly
   reject/replace offers. *Recommend listing.*
2. **Cascade transitivity (R4).** Two options:
   - (a) **One-level** (simplest, still tests cascade): archiving D rejects offers directly
     contingent on D.
   - (b) **Transitive death**: define a listing as "dead" if ARCHIVED; an offer contingent on
     a dead listing is rejected; if that leaves a listing unable to ever sell it does *not*
     auto-die (no listing auto-archive). True multi-level propagation only occurs through
     multiple archives. *Given (b) isn't deeply transitive anyway, recommend (a) for cascade
     and let **R2 cycle detection** carry the transitive-reasoning load.*
3. **Status code for unmet contingency on accept** (R3): recommend **409** (state conflict),
   consistent with other accept guards.

---

## Test plan (~10–13 new black-box tests; all deterministic)
- `test_contingent_offer_create_ok` — offer with valid `contingent_on` → 201, field echoed.
- `test_contingent_unknown_listing_400`.
- `test_contingent_self_409`.
- `test_cycle_direct_409` — A→B, B→A.
- `test_cycle_transitive_409` — A→B→C→A (**the key discriminator**).
- `test_no_cycle_diamond_ok` — A→B, A→C, B→D, C→D (not a cycle) → 201.
- `test_accept_blocked_until_dependency_sold_409` — accept contingent offer while dep not SOLD → 409.
- `test_accept_allowed_after_dependency_sold_200` — sell the dep listing, then accept → 200.
- `test_archive_dependency_cascade_rejects_409/state` — archive dep → contingent offers REJECTED.
- `test_contingency_precedence_*` — verify R3 ordering vs party/expired guards (pin precedence).
- `test_rejected_edge_not_in_cycle_graph` — a REJECTED contingent offer doesn't block a new cycle-free edge.
- (Existing 46 stay; `mk_offer` helper gains optional `contingent_on=None`.)

Target: **46 → ~57 tests**.

---

## Reference (`solve.sh`) work
- Add `contingent_on` to `Offer` + accept it in `POST /offers`.
- Build `committedGraph()` / `hasPath(from, to)` over PENDING edges for **R2** transitive
  cycle detection (DFS/BFS).
- `POST /offers`: R1 + R2 (place after existing validation; before budget check — pin order).
- `accept`: R3 guard (pin precedence relative to party/lock/expired/budget).
- `archive`: R4 cascade-reject of dependents (extend the existing archive cascade).
- Keep it honest (no shortcuts), build via tsc.

I'll validate the whole suite against the dependency-free **Node mirror** (as before) so
**oracle stays 3/3** before pushing.

---

## Calibration plan (the actual goal)
After build → push → revalidate and read the 5×5:
- **Success = a split:** at least one of {opus, avocado} lands `1–4/5` with failures on the
  **cycle/cascade/accept-block core** (e.g., a model that does direct-only cycle detection
  fails `test_cycle_transitive_409`). Oracle 3/3, AI Accept retained.
- If **both still 5/5** → add R4 transitivity / a second graph invariant (composition trap).
- If **a model fails on ambiguity/crash** (not core logic) → fix the spec precedence (don't
  ship a gotcha).

Honest odds: meaningfully better than our prior attempts (~50–60%) because this is the same
lever that demonstrably produced a split on the sibling legal task — but it still needs the
empirical recalibration loop.

---

## Effort / risk
- **Effort:** real feature — spec section + `solve.sh` graph logic + ~11 tests + mirror
  re-verify + 1–2 recalibration cycles. Larger than any single change so far.
- **Risk:** the precedence/ambiguity trap (mitigated by pinning exact check order in the spec);
  cycle-detection bugs in the reference (mitigated by the mirror run).
- **Reuses:** all existing harness, oracle flow, spec, and the 46 passing tests.

---

## Recommended go/no-go
Build with: **listing-level dependency, one-level cascade (R4a), transitive cycle detection
(R2) as the core, accept-block 409 (R3), precedence pinned in spec.** Then recalibrate.
Confirm decisions #1–#3 above and I'll implement.
