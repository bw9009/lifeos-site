#!/usr/bin/env python3
"""Stamp ONE navigation bar into every page.

WHY THIS EXISTS. The site is plain static HTML with `.nojekyll`, so
there is no include mechanism and every page carried its own copy of
the header. They drifted, badly: on 2026-08-21 there were FIVE
different navs and five pages with none at all. `/build/` was missing
EnvelopePrint, `/company/` was missing Beta and Build, and `/life/` -
the flagship product page - had no header whatsoever, so anyone
landing there from a store listing had no way to reach anything else.

Barret: *"the header is not present on all pages and where it is it
doesnt always match... they should all have all the pages on the
header and all pages should have the header"*.

The fix is a single source (`scripts/nav.html`) stamped into every
page, rather than nine files kept in agreement by hand. Hand-patching
would have fixed today and reset the clock on the same drift.

WHY A SCRIPT AND NOT JAVASCRIPT. A nav injected at runtime is invisible
to crawlers and to anyone whose JS has not loaded yet, on a site whose
entire job is being found. Stamping keeps the HTML static and the
markup real; the cost is remembering to run it, which is what the
marker comments and the check mode are for.

    python3 scripts/sync-nav.py          # rewrite every page
    python3 scripts/sync-nav.py --check  # fail if any page is stale

Pages are found by walking for index.html plus the loose *.html at the
root, so a new page picks this up automatically the moment it exists -
no list here to forget to update.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NAV = (ROOT / "scripts" / "nav.html").read_text().strip()

# Directories that are not part of the site.
# v2/ is an unlinked draft - nothing on the site points at it, so
# stamping it would be editing work in progress.
SKIP = {".git", ".github", "img", "scripts", "functions", "node_modules",
        "v2"}

# `build/` is a real PAGE here (the "get a custom app" form), not a
# build output directory - do not let the name fool a future cleanup.
MARKERS = re.compile(r"<!--NAV-->.*?<!--/NAV-->", re.S)

# A page that has never been stamped: match its existing <nav> element,
# whatever shape it is in, so the first run adopts it rather than
# leaving a duplicate behind.
EXISTING_NAV = re.compile(r"<nav>.*?</nav>", re.S)


def pages():
    for p in sorted(ROOT.rglob("*.html")):
        if any(part in SKIP for part in p.relative_to(ROOT).parts):
            continue
        yield p


def restamp(text: str) -> str | None:
    """The page with the canonical nav, or None if it already has it."""
    if MARKERS.search(text):
        out = MARKERS.sub(lambda _: NAV, text, count=1)
    elif EXISTING_NAV.search(text):
        out = EXISTING_NAV.sub(lambda _: NAV, text, count=1)
    else:
        # No nav at all. It goes immediately after <body>, or after the
        # beta banner when that is the first thing in the body, so the
        # banner stays at the very top where it was put on purpose.
        m = re.search(r"<body[^>]*>\s*(<a href=\"https://testflight[^<]*</a>)?",
                      text)
        if not m:
            return None
        at = m.end()
        out = text[:at] + "\n\n" + NAV + "\n" + text[at:]
    return None if out == text else out


def main() -> int:
    check = "--check" in sys.argv
    stale = []
    for p in pages():
        text = p.read_text()
        out = restamp(text)
        if out is None:
            continue
        stale.append(p.relative_to(ROOT))
        if not check:
            p.write_text(out)

    if not stale:
        print("nav: every page matches scripts/nav.html")
        return 0
    verb = "STALE" if check else "updated"
    for s in stale:
        print(f"nav {verb}: {s}")
    return 1 if check else 0


if __name__ == "__main__":
    raise SystemExit(main())
