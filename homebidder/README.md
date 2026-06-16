# homebidder

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
| Oracle | TBD (pending Codimango run) |
| Sonnet 4.6 | TBD |
| Opus 4.6 | TBD |
| Avocado | TBD |

Reference logic validated locally (26/26 grader checks pass against a dependency-free
mirror of the reference). Model rates to be populated from Codimango runs.

## Model Analysis
TBD - from Codimango model runs.

## Anti-Cheating Analysis
- Hardcoded outputs: server-generated UUIDs + a virtual clock the test drives make responses depend on prior state, not constants.
- Overfitting to visible tests: the grader runs out-of-process over HTTP and is not in /app; the agent never sees it during the solve.
- Modifying test files: the agent only writes its app under /app; tests live in /tests and are not editable.
- Bypassing the intended solution: correctness requires the full coupled behavior (lock + cascade + party-aware actions + clock expiry); partial CRUD fails many checks.
