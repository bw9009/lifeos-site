# Life — landing page

Pre-launch page with waitlist capture. Stdlib only; runs anywhere.

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
