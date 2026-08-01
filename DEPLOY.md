# Getting barretops.com live

Two things need this, and both are blockers:

- **Play Store** requires a publicly reachable privacy policy URL.
- **Google OAuth verification** requires the app homepage *and* privacy
  policy on a domain you control.

GitHub Pages hosts it free with automatic HTTPS. Roughly ten minutes.

## 1. Turn on Pages

github.com/bw9009/lifeos-site → **Settings → Pages**

- Source: **Deploy from a branch**
- Branch: **master**, folder: **/ (root)**
- Save

The `CNAME` file in this repo already sets the custom domain to
`barretops.com`.

## 2. Point DNS at it (Cloudflare)

The domain is already on Cloudflare nameservers, so this is just records.

Cloudflare dashboard → barretops.com → **DNS → Records**. Add four A
records for the apex, all with **Proxy status: DNS only (grey cloud)** —
proxying breaks GitHub's certificate issuance:

| Type | Name | Content |
|---|---|---|
| A | @ | 185.199.108.153 |
| A | @ | 185.199.109.153 |
| A | @ | 185.199.110.153 |
| A | @ | 185.199.111.153 |

And for www:

| Type | Name | Content |
|---|---|---|
| CNAME | www | bw9009.github.io |

## 3. Wait, then force HTTPS

DNS usually propagates in minutes on Cloudflare. Once
`http://barretops.com` loads, go back to **Settings → Pages** and tick
**Enforce HTTPS** (the checkbox only appears after the certificate is
issued — that can take up to an hour).

## Verify

```
https://barretops.com
https://barretops.com/privacy.html      <- give this URL to Play Store
https://barretops.com/terms.html
```

## The waitlist form

**It won't collect emails on GitHub Pages** — Pages is static and
`server.py` doesn't run there. The form detects this and offers a mailto
link instead, so nobody is told they've joined a list they haven't.

To make it collect properly later, either:

- run `server.py` somewhere real (a $5 VPS, or the Le Potato behind a
  Cloudflare Tunnel), or
- add a Cloudflare Worker that writes signups to KV, and point the form's
  `fetch` at it.

Not a launch blocker. The privacy policy being live is.
