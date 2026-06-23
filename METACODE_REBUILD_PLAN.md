# MetaCode (Avocado / 1P) Rebuild & Compliance Plan

Process playbook for handling the tasks affected by the AAI provenance policy.

## Why this exists
Per the AAI policy **"Model Role in Task Creation – Provenance & Quality Risk
Assessment"** (Saurabh Pathak, with Oliver Rickard), third-party models
(Claude / Codex) may **NOT**:
- do problem discovery / ideation,
- author or substantially rewrite `instruction.md` (mechanical edits only, and
  even those only for 1P),
- generate Docker container contents that the model-under-test sees,
- have their outputs "laundered" through a 1P model (Avocado) for edits.

A batch of tasks in this repo was built end-to-end by a **3P (Claude) agent
pipeline** and has been **withdrawn** (folders deleted; committed to `main`).

> This document is a **process** playbook only. It deliberately does **not**
> re-supply the withdrawn task ideas or instruction content — those were
> 3P-originated and must not be reused (token-laundering rule). Re-originate
> every idea from your own domain expertise.

## Hard compliance rules (apply to every task)
| Action | Avocado (1P / MetaCode) |
|---|---|
| Orchestration (git / docker / CLI), pipeline state | ✅ Allowed |
| Write the Dockerfile itself | ✅ Allowed |
| `task.toml` / config / README / watermarks | ✅ Allowed |
| `instruction.md` | ⚠️ **Mechanical edits only** (typos, formatting, wording you already drafted) — never authoring/substantial rewrite |
| Docker container contents (what model sees) | ✅ With **human in the driver's seat**; start from real code, no 1-shot codebases |
| Tests / oracle `solve.sh` | ✅ With **human in the driver's seat**; human-curated |
| Problem discovery / ideation | ❌ Never — the problem must originate from you |
| Reusing any 3P-generated content | ❌ Never (token laundering) |

## Per-task workflow (repeat for each task)
1. **Ideate (human only).** Pick a problem from your real domain expertise and
   write it in your own words first.
2. **Scaffold (Avocado allowed).** Create the T-Bench 2.0 skeleton:
   `environment/Dockerfile`, `task.toml`, `README.md`, `tests/test.sh`,
   `solution/solve.sh` stubs. Canary line in every code/script/data file.
3. **`instruction.md` (you write; Avocado mechanical only).** You author the
   spec content; Avocado may only fix typos/formatting.
4. **Container contents (you in driver's seat).** For debug/SWE-style tasks,
   start from real code; do not 1-shot-generate a codebase. Drive Avocado.
5. **Tests + oracle (you curate; Avocado assists mechanically).** Ensure deep
   tests (edge cases, failure modes); oracle passes, naive fails.
6. **Validate.** `docker build` + `solve.sh` + `test.sh` → reward 1 (oracle) /
   0 (naive); or local. Keep verifiers network-free where possible.
7. **Submit + validate on codimango.** Check pass/fail balance (target ~1–2/5),
   novelty, and that Provenance reads CLEAN.

## Tasks to handle

### A. Keep — `instruction.md` to be reworked (HUMAN-authored)
- `degree-day-energy`
- `psychrometrics-library`

> ⚠️ **Compliance note:** Policy allows Avocado only **mechanical** edits to
> `instruction.md`. A substantial rewrite must be **done by you (human)**;
> Avocado is limited to typos/formatting/wording you already drafted. Do not
> have Avocado re-author instruction content from calibration feedback.
> Also re-confirm provenance of these two — if any earlier 3P assistance
> touched instructions/ideas, flag for review.

### B. Withdrawn (deleted) — rebuild ONLY if a human re-originates the idea
These 9 were 3P-built and removed from the repo. **Do not copy them back.**
If you still want a task in one of these areas, re-derive the idea, the
instructions, and the code yourself from scratch (Avocado may assist only in
the allowed roles above):

| Withdrawn task | Domain | Language explored |
|---|---|---|
| refrigerant-cycle | refrigeration | Ruby |
| psychro-process-sim | psychrometrics | Python |
| air-state-normalizer | psychrometrics | Python |
| refrig-sim-debug | refrigeration | Ruby |
| altitude-hvac-pipeline | high-altitude HVAC | R |
| chiller-plant-discovery | commercial HVAC | Julia |
| building-energy-scale | commercial HVAC | Python |
| aircraft-ecs-altitude | aircraft ECS / altitude | Rust |
| commercial-vav-debug | commercial HVAC | Go |

> The table above is a **record of what was removed**, not a spec to reuse.

### C. Untouched (compliant / out of scope)
- `thermostat-heatpump` — leave as is.
- `homebidder` — keep (confirm status on codimango).

## Escalation
Borderline provenance questions → **Oliver Rickard** / **Saurabh Pathak**.
Automation proposals must go through the LAMA / approval process before scaling.
