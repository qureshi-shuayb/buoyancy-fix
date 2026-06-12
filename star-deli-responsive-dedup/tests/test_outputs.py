"""
Grader for the Star Deli responsive-dedup refactor task.

The agent must collapse a page whose markup is duplicated 4x (one block per
breakpoint) into a SINGLE responsive block, preserving how it looks AND behaves
at every breakpoint:
  - mobile shows products ABOVE the hero; larger shows hero first
  - a "Call to order" bar appears only on mobile
  - a "Free delivery" promo appears only on desktop
  - the hero image is hidden on mobile

Robust grading = dedup (structural) + visual regression + behavioral checks
(conditional visibility + ordering), all behavior-preserving and deterministic.
Text-based locators are used so the checks don't depend on the agent's class names.
"""

import re
from pathlib import Path
from PIL import Image, ImageChops
import numpy as np
from playwright.sync_api import sync_playwright

AGENT = Path("/app/index.html")
REF = Path("/reference/index.html")
SHOTS = Path("/tmp/shots"); SHOTS.mkdir(exist_ok=True)

VIEWPORTS = [
    {"name": "mobile",  "width": 375,  "height": 900},   # <=480
    {"name": "tablet",  "width": 600,  "height": 900},   # 481-768
    {"name": "laptop",  "width": 900,  "height": 900},   # 769-1024
    {"name": "desktop", "width": 1440, "height": 900},   # >=1025
]
MAX_DIFF_RATIO = 0.06

UNIQUE_CONTENT = ["Sernik", "Pączki", "Makowiec", "Baked Fresh Every Morning"]
CALL_TEXT = "Call to order"
PROMO_TEXT = "Free delivery"


def _read(p: Path) -> str:
    return p.read_text(encoding="utf-8")


# ---------------- existence ----------------

def test_agent_file_exists():
    assert AGENT.exists(), f"Agent output not found at {AGENT}"

def test_reference_exists():
    assert REF.exists(), f"Reference not found at {REF}"


# ---------------- de-duplication ----------------

def test_content_not_duplicated():
    html = _read(AGENT)
    offenders = {s: html.count(s) for s in UNIQUE_CONTENT if html.count(s) != 1}
    assert not offenders, (
        f"Content still duplicated (expected exactly 1 of each): {offenders}. "
        f"The 4 per-breakpoint copies must be collapsed into a single block."
    )

def test_no_per_breakpoint_duplicate_containers():
    html = _read(AGENT)
    n_cards = len(re.findall(r"<article\b", html, re.IGNORECASE))
    assert n_cards == 3, (
        f"Expected 3 product cards in a single block, found {n_cards}. "
        f"Duplicate per-breakpoint copies appear to remain."
    )

def test_uses_media_queries():
    n = len(re.findall(r"@media", _read(AGENT).lower()))
    assert n >= 2, f"Found {n} @media rules; a responsive single block needs media queries."


# ---------------- helpers ----------------

def _vis(page, text):
    """True if ANY element containing `text` is visible (robust to duplicates)."""
    loc = page.get_by_text(text, exact=False)
    return any(loc.nth(i).is_visible() for i in range(loc.count()))

def _y(page, text):
    """Top y of the first VISIBLE element containing `text` (hidden dupes skipped)."""
    loc = page.get_by_text(text, exact=False)
    for i in range(loc.count()):
        bb = loc.nth(i).bounding_box()
        if bb is not None:
            return bb["y"]
    raise AssertionError(f"No visible element containing {text!r}")


# ---------------- behavioral: conditional visibility ----------------

def test_conditional_visibility():
    expect = {
        375:  {"call": True,  "promo": False},
        600:  {"call": False, "promo": False},
        900:  {"call": False, "promo": False},
        1440: {"call": False, "promo": True},
    }
    bad = []
    with sync_playwright() as p:
        b = p.chromium.launch()
        for w, exp in expect.items():
            ctx = b.new_context(viewport={"width": w, "height": 900})
            pg = ctx.new_page(); pg.goto(f"file://{AGENT}", wait_until="networkidle")
            call_v = _vis(pg, CALL_TEXT); promo_v = _vis(pg, PROMO_TEXT)
            if call_v != exp["call"]:
                bad.append(f'{w}px: "Call to order" visible={call_v}, expected {exp["call"]}')
            if promo_v != exp["promo"]:
                bad.append(f'{w}px: "Free delivery" visible={promo_v}, expected {exp["promo"]}')
            ctx.close()
        b.close()
    assert not bad, "Conditional visibility wrong:\n  " + "\n  ".join(bad)


# ---------------- behavioral: per-breakpoint ordering ----------------

def test_ordering_per_breakpoint():
    errs = []
    with sync_playwright() as p:
        b = p.chromium.launch()
        # mobile: products (Sernik) ABOVE hero
        ctx = b.new_context(viewport={"width": 375, "height": 900})
        pg = ctx.new_page(); pg.goto(f"file://{AGENT}", wait_until="networkidle")
        if not (_y(pg, "Sernik") < _y(pg, "Baked Fresh Every Morning")):
            errs.append("mobile: products must render ABOVE the hero")
        ctx.close()
        # desktop: hero ABOVE products
        ctx = b.new_context(viewport={"width": 1440, "height": 900})
        pg = ctx.new_page(); pg.goto(f"file://{AGENT}", wait_until="networkidle")
        if not (_y(pg, "Baked Fresh Every Morning") < _y(pg, "Sernik")):
            errs.append("desktop: hero must render ABOVE the products")
        ctx.close()
        b.close()
    assert not errs, "Ordering wrong:\n  " + "\n  ".join(errs)


# ---------------- visual regression ----------------

def _diff_ratio(a: Path, b: Path) -> float:
    i1 = Image.open(a).convert("RGB"); i2 = Image.open(b).convert("RGB")
    if i1.size != i2.size:
        w = min(i1.width, i2.width); h = min(i1.height, i2.height)
        i1 = i1.resize((w, h)); i2 = i2.resize((w, h))
    d = np.array(ImageChops.difference(i1, i2))
    return np.count_nonzero(np.any(d > 10, axis=2)) / d[:, :, 0].size

def _render(browser, path: Path, w: int, h: int, out: Path):
    ctx = browser.new_context(viewport={"width": w, "height": h}, device_scale_factor=1)
    pg = ctx.new_page(); pg.goto(f"file://{path}", wait_until="networkidle")
    pg.wait_for_timeout(300)
    pg.screenshot(path=str(out), full_page=True)
    ctx.close()

def test_visual_regression_all_viewports():
    results = {}
    with sync_playwright() as p:
        browser = p.chromium.launch()
        for vp in VIEWPORTS:
            nm, w, h = vp["name"], vp["width"], vp["height"]
            rb = SHOTS / f"ref_{nm}.png"; ra = SHOTS / f"agent_{nm}.png"
            _render(browser, REF, w, h, rb); _render(browser, AGENT, w, h, ra)
            r = _diff_ratio(rb, ra); results[nm] = r
            print(f"{nm} ({w}x{h}): diff={r:.4f} (max {MAX_DIFF_RATIO})")
        browser.close()
    fails = {k: round(v, 4) for k, v in results.items() if v > MAX_DIFF_RATIO}
    assert not fails, (
        f"Visual regression failed at {fails}. The refactor must render like the "
        f"original at every breakpoint (max {MAX_DIFF_RATIO*100:.0f}% diff)."
    )
