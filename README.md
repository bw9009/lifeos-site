# Life — landing page

Pre-launch page with waitlist capture. Stdlib only; runs anywhere.

> **Session notes go in the NOTES section at the bottom of this file**,
> written as you go rather than once at the end. Same rule as the other
> repos — see `life/CLAUDE.md`, "keep the README's NOTES section
> current". `HANDOFF.md` in the `life` repo is retired.

```bash
python3 server.py --port 8000     # serve
python3 server.py --count         # how many signups
python3 server.py --export > list.csv
```

Emails land in `waitlist.jsonl` (gitignored — never commit your list).
Plain file on purpose: greppable, backup-able, and importable into any mail
tool without an API key or an account to log into.

## What's here

- Hook: "Type like a maniac. Leave organized."
- Live typing demo showing the **actual** classifications the app produces
- Expandable "See what you can throw at it" section
- Privacy/offline positioning
- $4.99 a month or $29.99 a year, 30-day free trial, early-access members free
- Two signup forms (top and bottom), both wired

## Before it goes live

1. **Buy a domain.** `.os` is not a registrable TLD — two-letter TLDs are
   reserved for country codes. Use `lifeos.app`, `getlifeos.com`, etc.
2. **Add an OG image** (1200×630). Links shared without one look broken.
3. **Put it behind HTTPS.** Cloudflare Tunnel or a $5 VPS with Caddy is the
   quickest path; browsers flag plain-HTTP forms as insecure and signups die.
4. **Decide the name.** "Life OS" is crowded — the term comes from Notion
   template culture and several products already use it. Ranking for it will
   be expensive. The differentiator worth naming around is "you don't format
   your thoughts, it does."

## Honest note on claims

The page says thoughts stay on-device and sorting is instant. That is true
of the current build — parsing is local, deterministic, and needs no network.
**Keep it true.** If a cloud model is ever added, this copy has to change
first, not after.

---

# NOTES

Newest first. Write as you go, not once at the end.

## 2026-08-17 — promo codes are off as a programme

The promo link was deleted and the offer is now **free to everyone for
30 days**. `PROMOCODES` stays bound, but its empty pool is no longer an
open item: **do not seed it**, and do not re-raise
`scripts/seed-promo-codes.sh` as work. Honour a code for anyone who says
they were promised one.

## Standing — the Cloudflare traps

Full writeup in `CLOUDFLARE.md`. The two that will cost you hours:

- **Pages KV bindings are per-environment.** `PROMOCODES` was bound to
  neither, so `env.PROMOCODES` was always undefined and the issue path
  returned at its guard on every signup, silently, exactly as written.
  The function was correct the whole time. All three namespaces are now
  bound to BOTH environments.
- **Fail-open hides a missing binding.** Both Functions are written so a
  secondary system can't break a primary one. That is right and should
  stay — but it means a missing binding produces no error any human ever
  sees. When a best-effort feature seems inert, check the binding before
  reading a line of code.
- **`wrangler kv key list` WITHOUT `--remote` reads a LOCAL simulated
  namespace** and cheerfully returns `[]`, which looks exactly like "the
  write went to the wrong namespace." Always pass `--remote`.

**Leftover:** a smoke-test row is still in KV — `apprequests`, the key
starting `req:` containing `smoketest@example.com`. Deleting it via the
API returned `Authentication error [code: 10000]` on the *keys* endpoint
despite the token showing `workers_kv (write)`; four approaches, same
error. Still undeleted.
