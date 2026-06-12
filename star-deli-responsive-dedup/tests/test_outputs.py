"""
Grader for star-deli-responsive-dedup.

The source (/app/index.html) duplicates the page 3 times (mobile / tablet /
desktop) and has NO laptop tier — the 769-1024px range falls back to the
2-column tablet layout. The agent must collapse the duplication into ONE
responsive block AND add the missing laptop tier (3 columns) by reasoning,
since there is no laptop copy to lift it from.

Checks:
  - dedup (content once, 3 cards, variant classes gone)
  - mobile-first CSS (min-width, no max-width)
  - visual regression vs original at mobile/tablet/desktop (laptop is
    intentionally different, so it is NOT visual-diffed)
  - laptop INFERENCE: 3-column product grid at 900px
  - conditional visibility (mobile call bar / desktop promo)
  - per-breakpoint ordering (mobile products-above-hero; else hero first)
Text-based locators so checks don't depend on the agent's class names.
"""

import re
from pathlib import Path
from PIL import Image, ImageChops
import numpy as np
from playwright.sync_api import sync_playwright

AGENT = Path("/app/index.html")
REF = Path("/reference/index.html")
SHOTS = Path("/tmp/shots"); SHOTS.mkdir(exist_ok=True)

# Visual regression ONLY where the original is the intended target.
# Laptop (900) is intentionally improved (3 cols) vs the original (2 cols),
# so it is verified by rule, not by pixel-diff.
VISUAL_VIEWPORTS = [
    {"name": "mobile",  "width": 375,  "height": 900},
    {"name": "tablet",  "width": 600,  "height": 900},
    {"name": "desktop", "width": 1440, "height": 900},
]
LAPTOP_W = 900
MAX_DIFF_RATIO = 0.06

UNIQUE_CONTENT = ["Sernik", "Pączki", "Makowiec", "Baked Fresh Every Morning"]
CALL_TEXT = "Call to order"
PROMO_TEXT = "Free delivery"


def _read(p): return p.read_text(encoding="utf-8")

def _css(html):
    return "\n".join(re.findall(r"<style[^>]*>(.*?)</style>", html, re.DOTALL | re.IGNORECASE)).lower()


# ---------------- existence ----------------

def test_agent_file_exists():
    assert AGENT.exists(), f"Agent output not found at {AGENT}"

def test_reference_exists():
    assert REF.exists(), f"Reference not found at {REF}"


# ---------------- de-duplication ----------------

def test_content_not_duplicated():
    html = _read(AGENT)
    bad = {s: html.count(s) for s in UNIQUE_CONTENT if html.count(s) != 1}
    assert not bad, f"Content still duplicated (expected exactly 1 each): {bad}"

def test_three_cards_only():
    n = len(re.findall(r"<article\b", _read(AGENT), re.IGNORECASE))
    assert n == 3, f"Expected 3 product cards in a single block, found {n}."

def test_variant_classes_removed():
    """CSS consolidation: the original per-breakpoint variant selectors must be gone."""
    html = _read(AGENT).lower()
    leftover = [c for c in ("v-mobile", "v-tablet", "v-desktop", "v-laptop") if c in html]
    assert not leftover, f"Original duplicated-variant classes still present: {leftover}"


# ---------------- mobile-first ----------------

def test_mobile_first_css():
    """Mobile-first = base styles + min-width media queries (no max-width queries).
    Only the @media *conditions* are inspected, not max-width CSS properties."""
    css = _css(_read(AGENT))
    conditions = " ".join(re.findall(r"@media([^{]*)\{", css))
    assert "@media" in css, "No media queries found"
    assert conditions.count("min-width") >= 2, "Mobile-first CSS must use min-width media queries"
    assert "max-width" not in conditions, "Mobile-first CSS should not use max-width media queries"


# ---------------- helpers ----------------

def _visible(page, text):
    loc = page.get_by_text(text, exact=False)
    return any(loc.nth(i).is_visible() for i in range(loc.count()))

def _box(page, text):
    loc = page.get_by_text(text, exact=False)
    for i in range(loc.count()):
        bb = loc.nth(i).bounding_box()
        if bb is not None:
            return bb
    raise AssertionError(f"No visible element containing {text!r}")


# ---------------- laptop inference: 3 columns ----------------

def test_laptop_is_three_columns():
    """At 900px (laptop) the 3 cards must sit on ONE row = 3 columns.
    The original only has a 2-col tablet layout for this range, so passing
    requires ADDING the missing laptop tier (inference, not copying)."""
    with sync_playwright() as p:
        b = p.chromium.launch()
        ctx = b.new_context(viewport={"width": LAPTOP_W, "height": 900})
        pg = ctx.new_page(); pg.goto(f"file://{AGENT}", wait_until="networkidle")
        ys = [round(_box(pg, t)["y"]) for t in ("Sernik", "Pączki", "Makowiec")]
        xs = [round(_box(pg, t)["x"]) for t in ("Sernik", "Pączki", "Makowiec")]
        ctx.close(); b.close()
    same_row = max(ys) - min(ys) <= 5          # all three aligned on one row
    three_cols = len(set(xs)) == 3              # three distinct columns
    assert same_row and three_cols, (
        f"Laptop (900px) must show products in 3 columns. "
        f"card top-ys={ys}, xs={xs} (need one row + 3 distinct x)."
    )


# ---------------- conditional visibility ----------------

def test_conditional_visibility():
    expect = {375: (True, False), 600: (False, False), 900: (False, False), 1440: (False, True)}
    bad = []
    with sync_playwright() as p:
        b = p.chromium.launch()
        for w, (c, pr) in expect.items():
            ctx = b.new_context(viewport={"width": w, "height": 900})
            pg = ctx.new_page(); pg.goto(f"file://{AGENT}", wait_until="networkidle")
            if _visible(pg, CALL_TEXT) != c:  bad.append(f'{w}px: "Call to order" visible={_visible(pg,CALL_TEXT)}, expected {c}')
            if _visible(pg, PROMO_TEXT) != pr: bad.append(f'{w}px: "Free delivery" visible={_visible(pg,PROMO_TEXT)}, expected {pr}')
            ctx.close()
        b.close()
    assert not bad, "Conditional visibility wrong:\n  " + "\n  ".join(bad)


# ---------------- per-breakpoint ordering ----------------

def test_ordering_per_breakpoint():
    errs = []
    with sync_playwright() as p:
        b = p.chromium.launch()
        ctx = b.new_context(viewport={"width": 375, "height": 900})
        pg = ctx.new_page(); pg.goto(f"file://{AGENT}", wait_until="networkidle")
        if not (_box(pg, "Sernik")["y"] < _box(pg, "Baked Fresh Every Morning")["y"]):
            errs.append("mobile: products must render ABOVE the hero")
        ctx.close()
        for w in (900, 1440):
            ctx = b.new_context(viewport={"width": w, "height": 900})
            pg = ctx.new_page(); pg.goto(f"file://{AGENT}", wait_until="networkidle")
            if not (_box(pg, "Baked Fresh Every Morning")["y"] < _box(pg, "Sernik")["y"]):
                errs.append(f"{w}px: hero must render ABOVE the products")
            ctx.close()
        b.close()
    assert not errs, "Ordering wrong:\n  " + "\n  ".join(errs)


# ---------------- visual regression (mobile/tablet/desktop) ----------------

def _diff(a, b):
    i1 = Image.open(a).convert("RGB"); i2 = Image.open(b).convert("RGB")
    if i1.size != i2.size:
        w = min(i1.width, i2.width); h = min(i1.height, i2.height)
        i1 = i1.resize((w, h)); i2 = i2.resize((w, h))
    d = np.array(ImageChops.difference(i1, i2))
    return np.count_nonzero(np.any(d > 10, axis=2)) / d[:, :, 0].size

def _render(browser, path, w, h, out):
    ctx = browser.new_context(viewport={"width": w, "height": h}, device_scale_factor=1)
    pg = ctx.new_page(); pg.goto(f"file://{path}", wait_until="networkidle")
    pg.wait_for_timeout(300); pg.screenshot(path=str(out), full_page=True); ctx.close()

def test_visual_regression():
    results = {}
    with sync_playwright() as p:
        br = p.chromium.launch()
        for vp in VISUAL_VIEWPORTS:
            nm, w, h = vp["name"], vp["width"], vp["height"]
            ra = SHOTS / f"a_{nm}.png"; rb = SHOTS / f"r_{nm}.png"
            _render(br, AGENT, w, h, ra); _render(br, REF, w, h, rb)
            results[nm] = _diff(ra, rb)
            print(f"{nm} ({w}x{h}): diff={results[nm]:.4f} (max {MAX_DIFF_RATIO})")
        br.close()
    fails = {k: round(v, 4) for k, v in results.items() if v > MAX_DIFF_RATIO}
    assert not fails, f"Visual regression failed at {fails} (max {MAX_DIFF_RATIO})."
