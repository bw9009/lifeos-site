#!/usr/bin/env python3
"""
Life OS landing page + waitlist server.

Stdlib only — runs anywhere, including the Le Potato.

    python3 server.py --port 8000
    python3 server.py --export        # print the list as CSV

Emails land in waitlist.jsonl. Deliberately a plain file: a waitlist you
can read, grep, back up and hand to any mail tool beats one locked inside
a service you have to log into.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).parent
WAITLIST = ROOT / "waitlist.jsonl"
EMAIL_RE = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$")

_lock = threading.Lock()

# Crude per-IP throttle. Enough to stop someone holding down enter; not a
# substitute for a real WAF if this ever gets big.
_recent: dict[str, list[float]] = {}
RATE_LIMIT = 5          # signups
RATE_WINDOW = 60.0      # seconds


def _rate_limited(ip: str) -> bool:
    now = time.time()
    hits = [t for t in _recent.get(ip, []) if now - t < RATE_WINDOW]
    _recent[ip] = hits + [now]
    return len(hits) >= RATE_LIMIT


def existing_emails() -> set[str]:
    if not WAITLIST.exists():
        return set()
    out = set()
    for line in WAITLIST.read_text().splitlines():
        try:
            out.add(json.loads(line)["email"].lower())
        except (json.JSONDecodeError, KeyError):
            continue
    return out


def add_email(email: str, source: str, ip: str) -> bool:
    """Returns True if newly added, False if already present."""
    email = email.strip().lower()
    with _lock:
        if email in existing_emails():
            return False
        with WAITLIST.open("a") as f:
            f.write(json.dumps({
                "email": email,
                "source": source,
                "ip": ip,
                "at": datetime.now().isoformat(timespec="seconds"),
            }) + "\n")
    return True


class Handler(BaseHTTPRequestHandler):
    def _send(self, code: int, body: bytes, ctype: str):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _json(self, code: int, obj: dict):
        self._send(code, json.dumps(obj).encode(), "application/json")

    # Google's OAuth verification requires the privacy policy to live on the
    # verified domain and be linked from the homepage, so these are served
    # as first-class pages, not an afterthought.
    PAGES = {
        "/": "index.html",
        "/index.html": "index.html",
        "/privacy": "privacy.html",
        "/privacy.html": "privacy.html",
        "/terms": "terms.html",
        "/terms.html": "terms.html",
    }

    def do_GET(self):
        path = self.path.split("?")[0]

        if path in self.PAGES:
            filename = self.PAGES[path]
            try:
                self._send(200, (ROOT / filename).read_bytes(),
                           "text/html; charset=utf-8")
            except OSError:
                self._send(500, f"{filename} missing".encode(), "text/plain")
            return

        if path == "/healthz":
            self._send(200, b"ok", "text/plain")
            return

        self._send(404, b"not found", "text/plain")

    def do_POST(self):
        if self.path.split("?")[0] != "/api/waitlist":
            self._json(404, {"error": "not found"})
            return

        ip = self.headers.get("X-Forwarded-For", self.client_address[0]).split(",")[0].strip()
        if _rate_limited(ip):
            self._json(429, {"error": "too many requests"})
            return

        try:
            length = int(self.headers.get("Content-Length", 0))
            if length > 4096:
                self._json(413, {"error": "too large"})
                return
            payload = json.loads(self.rfile.read(length) or b"{}")
        except (ValueError, json.JSONDecodeError):
            self._json(400, {"error": "bad request"})
            return

        email = str(payload.get("email", "")).strip()
        if not EMAIL_RE.match(email):
            self._json(400, {"error": "invalid email"})
            return

        added = add_email(email, str(payload.get("source", ""))[:40], ip)
        # A duplicate is still a success from the visitor's point of view —
        # telling them "you're already on it" invites a confused retry.
        self._json(200, {"ok": True, "new": added})

    def log_message(self, *args):
        pass


def export_csv() -> None:
    if not WAITLIST.exists():
        print("no signups yet", file=sys.stderr)
        return
    writer = csv.writer(sys.stdout)
    writer.writerow(["email", "signed_up", "source"])
    seen = set()
    for line in WAITLIST.read_text().splitlines():
        try:
            rec = json.loads(line)
        except json.JSONDecodeError:
            continue
        if rec["email"] in seen:
            continue
        seen.add(rec["email"])
        writer.writerow([rec["email"], rec.get("at", ""), rec.get("source", "")])


def main():
    ap = argparse.ArgumentParser(description="Life OS landing page")
    ap.add_argument("--port", type=int, default=8000)
    ap.add_argument("--host", default="0.0.0.0")
    ap.add_argument("--export", action="store_true", help="dump signups as CSV")
    ap.add_argument("--count", action="store_true", help="how many signups")
    args = ap.parse_args()

    if args.export:
        export_csv()
        return
    if args.count:
        print(f"{len(existing_emails())} signups")
        return

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"Landing page: http://localhost:{args.port}/")
    print(f"Signups so far: {len(existing_emails())}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")


if __name__ == "__main__":
    main()
