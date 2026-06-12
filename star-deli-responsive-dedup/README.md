# star-deli-responsive-dedup

## Description
The agent is given `/app/index.html` — a "Star Deli" Polish bakery landing page whose
markup and CSS have been hand-duplicated **four times**, once per breakpoint
(mobile / tablet / laptop / desktop), with each copy shown via `display:none` toggling
in media queries. The task is to **refactor the page into a single responsive block**
driven by media queries, so the content exists once but still renders the same at every
breakpoint.

This exercises spec-vs-implementation reasoning and responsive CSS: the agent must read
how each of the four copies is styled at its breakpoint and fold those differences into
one set of media queries. A naive approach fails — deleting three copies and keeping one
breaks the layout at the other three viewports, and doing nothing leaves the content
duplicated. Only a genuinely responsive single block satisfies both the de-duplication
and the visual-fidelity checks.

## Completion Rates
| Agent      | Pass rate |
|------------|-----------|
| Oracle     | 1.0 (3/3 local) |
| Sonnet 4.6 | TBD (pending Codimango run) |
| Opus 4.6   | TBD (pending Codimango run) |
| Avocado    | TBD (pending Codimango run) |

Oracle verified locally (oracle Mean 1.000, 3/3 not flaky). Model pass rates will be
populated from the Codimango automated runs.

## Model Analysis
TBD — to be filled from Codimango model runs (per-model passed/failed counts, dominant
failure modes, and why failures reflect responsive-reasoning gaps rather than task-setup
issues).

## Anti-Cheating Analysis
- **Hardcoded outputs:** rendering is verified with Playwright screenshot diffs against a
  frozen `/reference/index.html` baked into the image at build time; output cannot be
  hardcoded to pass.
- **Overfitting to visible tests:** the test suite lives outside `/app` (mounted at verify
  time) and is not visible to the agent during the run.
- **Modifying test files:** the agent only has write access to `/app`; the grader
  (`tests/test_outputs.py`) is not in `/app` and cannot be edited.
- **Bypassing the intended solution:** a dedup check (content must appear exactly once,
  3 cards only) blocks a no-op, while the 4-viewport visual regression blocks
  "keep one copy" — both must pass, which requires a real responsive single block.
