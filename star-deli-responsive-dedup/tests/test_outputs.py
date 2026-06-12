"""
Grader for the Star Deli responsive-dedup refactor task.

The agent must collapse a page whose markup is duplicated 4x (one block per
breakpoint) into a SINGLE responsive block, while preserving how it looks at
every breakpoint.

Two complementary checks make this robust:
  1. De-duplication (structural)  -> the content must appear ONCE, not 4x.
     Without this, an agent could do nothing and still pass visual regression.
  2. Visual regression (Playwright) -> the single block must still render like
     the original at all 4 viewports. Without this, an agent could delete 3
     copies and keep one non-responsive copy.
Only a genuinely responsive single block passes BOTH.
"""

import re
from pathlib import Path
from PIL import Image, ImageChops
import numpy as np
from playwright.sync_api import sync_playwright

AGENT = Path("/app/index.html")
REF = Path("/reference/index.html")
SHOTS = Path("/tmp/shots"); SHOTS.mkdir(exist_ok=True)

# One viewport squarely inside each breakpoint range.
VIEWPORTS = [
    {"name": "mobile",  "width": 375,  "height": 900},   # <=480
    {"name": "tablet",  "width": 600,  "height": 900},   # 481-768
    {"name": "laptop",  "width": 900,  "height": 900},   # 769-1024
    {"name": "desktop", "width": 1440, "height": 900},   # >=1025
]
MAX_DIFF_RATIO = 0.10

# Content that appears exactly once per duplicated copy in the original.
UNIQUE_CONTENT = ["Sernik", "Pączki", "Makowiec", "Baked Fresh Every Morning"]


def _read(p: Path) -> str:
    return p.read_text(encoding="utf-8")


# ---------------- existence ----------------

def test_agent_file_exists():
    assert AGENT.exists(), f"Agent output not found at {AGENT}"

def test_reference_exists():
    assert REF.exists(), f"Reference not found at {REF} (check Dockerfile COPY)"


# ---------------- de-duplication (the core requirement) ----------------

def test_content_not_duplicated():
    """Each piece of content must appear exactly once — proves the 4 copies
    were collapsed into one block."""
    html = _read(AGENT)
    offenders = {}
    for snippet in UNIQUE_CONTENT:
        n = html.count(snippet)
        if n != 1:
            offenders[snippet] = n
    assert not offenders, (
        f"Content is still duplicated (expected exactly 1 of each): {offenders}. "
        f"The 4 per-breakpoint copies must be collapsed into a single block."
    )


def test_no_per_breakpoint_duplicate_containers():
    """The original used 4 sibling variant wrappers. After refactor there must
    not be multiple full copies of the product section."""
    html = _read(AGENT)
    # <article> cards: original has 12 (3 products x 4 copies); single block has 3.
    n_cards = len(re.findall(r"<article\b", html, re.IGNORECASE))
    assert n_cards == 3, (
        f"Expected 3 product cards in a single block, found {n_cards}. "
        f"Duplicate per-breakpoint copies appear to remain."
    )


# ---------------- responsive implementation ----------------

def test_uses_media_queries():
    html = _read(AGENT).lower()
    n = len(re.findall(r"@media", html))
    assert n >= 2, (
        f"Found {n} @media rules; a responsive single block needs media queries "
        f"to adapt across breakpoints."
    )


# ---------------- visual regression (don't break the look) ----------------

def _diff_ratio(a: Path, b: Path) -> float:
    i1 = Image.open(a).convert("RGB"); i2 = Image.open(b).convert("RGB")
    if i1.size != i2.size:
        w = min(i1.width, i2.width); h = min(i1.height, i2.height)
        i1 = i1.resize((w, h)); i2 = i2.resize((w, h))
    d = np.array(ImageChops.difference(i1, i2))
    return np.count_nonzero(np.any(d > 10, axis=2)) / d[:, :, 0].size

def _render(browser, path: Path, w: int, h: int, out: Path):
    ctx = browser.new_context(viewport={"width": w, "height": h}, device_scale_factor=1)
    pg = ctx.new_page()
    pg.goto(f"file://{path}", wait_until="networkidle")
    pg.wait_for_timeout(300)
    pg.screenshot(path=str(out), full_page=True)
    ctx.close()

def test_visual_regression_all_viewports():
    assert AGENT.exists() and REF.exists()
    results = {}
    with sync_playwright() as p:
        browser = p.chromium.launch()
        for vp in VIEWPORTS:
            nm, w, h = vp["name"], vp["width"], vp["height"]
            rb = SHOTS / f"ref_{nm}.png"; ra = SHOTS / f"agent_{nm}.png"
            _render(browser, REF, w, h, rb)
            _render(browser, AGENT, w, h, ra)
            r = _diff_ratio(rb, ra)
            results[nm] = r
            print(f"{nm} ({w}x{h}): diff={r:.4f} (max {MAX_DIFF_RATIO})")
        browser.close()
    fails = {k: round(v, 4) for k, v in results.items() if v > MAX_DIFF_RATIO}
    assert not fails, (
        f"Visual regression failed at {fails}. The refactored page must render "
        f"like the original at every breakpoint (max {MAX_DIFF_RATIO*100:.0f}% diff)."
    )
