# homebidder-v2

## Description
A property-marketplace REST API (TypeScript/Express, in-memory). Users list properties
and make offers; the offer lifecycle drives the listing lifecycle. Sellers accept,
reject, or counter buyer offers. The hard part is an alternating offer/counter chain:
each counter rejects the prior offer and creates a new one with the party flipped
(made_by BUYER <-> SELLER); a seller counter locks the listing (PENDING) so no new
offers or other accepts can happen until the buyer responds; accepting marks the listing
SOLD and cascade-rejects all other offers; and offers expire against a test-controlled
virtual clock (a seller-counter expiring auto-unlocks the listing).

A naive CRUD scaffold won't pass: the two coupled state machines, the lock invariant,
the cascade, the party-aware "who can act" rule, and the lazy clock-driven expiry must
all interact correctly.

## Completion Rates
| Agent | Pass rate |
|-------|-----------|
| Oracle | 3/3 (validated on Codimango) |
| Opus 4.6 (claude-code) | 4/5 |
| GPT-5.5 (codex) | 0/5 |
| Avocado (metacode) | 4/5 |

Codimango validation: **passing** (commit `9190dcb`) — oracle 3/3 with the required
metacode pass/fail balance (4/5). No Sonnet run was performed.

## Model Analysis
All models implement the basic marketplace correctly — user/listing/offer creation
and validation, the seller-counter lock, accept-cascade, party-aware "who can act"
rules, and the counter negotiation direction all pass for every model. The failures
concentrate entirely in the **contingent-offer chain + settlement** mechanics:

- **GPT-5.5 (codex): 0/5.** Passes every basic + offer/counter/lock/cascade test, but
  fails all five trials on the property-chain cases — in particular the
  preemption/backup rule (G3): when a committed (`CHAINED`) offer becomes unaffordable
  at settlement, the sweep must fall back to the first affordable non-contingent backup
  bid and only revert the listing to `AVAILABLE` if none exists. The settlement-sweep +
  gazumping interaction was not reproduced.
- **Opus 4.6: 4/5.** One failure on **mid-chain expiry**: in a `Z → Y → X` chain, when a
  committed offer expires its listing must revert `CHAINED → AVAILABLE`; the attempt
  left it `CHAINED`.

These are genuine reasoning gaps in the coupled state-machine + fixpoint settlement
logic, not task-setup artifacts: the oracle passes 3/3 and every basic check passes for
all models, isolating the failures to the chain/settlement rules.

## Anti-Cheating Analysis
- Hardcoded outputs: server-generated UUIDs + a virtual clock the test drives make responses depend on prior state, not constants.
- Overfitting to visible tests: the grader runs out-of-process over HTTP and is not in /app; the agent never sees it during the solve.
- Modifying test files: the agent only writes its app under /app; tests live in /tests and are not editable.
- Bypassing the intended solution: correctness requires the full coupled behavior (lock + cascade + party-aware actions + clock expiry); partial CRUD fails many checks.

## v2 Clean Redo Note
This v2 scaffold replaces v1 due to policy violation in oracle development using third-party model. Task specification and difficulty calibration preserved from v1. All test tolerances and anti-cheating checks identical to v1. Oracle reimplemented clean using approved models only.
