# Cloudflare: how this site is actually wired, and the binding trap

Written 2026-08-15. Replaces `CLOUDFLARE-FIX.md`, which described a
problem that is now SOLVED — keep this as reference, not as a to-do.

## The setup, verified from the API (not from docs, not from memory)

| Thing | Value |
|---|---|
| Pages project | `lifeos-site` |
| Account ID | `e557d716a580e9d6a274352707b59837` |
| Domains | `barretops.com`, `www.barretops.com`, `lifeos-site-42y.pages.dev` |
| Production branch | `master` (correct — every deployment is Production) |
| Compatibility date | `2026-08-09` |

KV namespace IDs:

```
WAITLIST     7a00af5c5e6b4deabb1a7906ebbc54b4
APPREQUESTS  38ca900220dc4fc6a9f4a3e78259d8b8
PROMOCODES   5aab2b23509a486d8950266aa98aa3c1
```

## THE TRAP — this is the whole document

**Pages KV bindings are per-environment, and adding one in the dashboard
does not put it on production.** For weeks the config looked like this:

```
production: kv_namespaces = [WAITLIST]                            env_vars = [RESEND_API_KEY]
preview:    kv_namespaces = [APPREQUESTS, WAITLIST]               env_vars = []
```

`WAITLIST` was on production, so signups worked and nothing looked
broken. Everything added afterwards landed on **preview only**.

That single fact explains two separate "mystery" bugs:

1. **`/api/app-request` 500'd in production** — `env.APPREQUESTS`
   undefined, so the guard at the top of the handler fired.
2. **Promo codes never issued, ever, and never errored.** `PROMOCODES`
   was bound to NEITHER environment, so `env.PROMOCODES` was always
   undefined and `issuePromoCodes()` hit its `if (!env.PROMOCODES)
   return null` early-out on every single signup. Silently, by design.
   **This was never a code bug.** Weeks were lost looking at the
   waitlist function; the function was correct the entire time.
   (`RESEND_API_KEY` *was* on production, so the email half was fine —
   there were simply never any codes to send.)

Fixed 2026-08-15: all three namespaces are now bound to **both**
environments, deliberately, so preview can never silently diverge from
production again.

## The fail-open design is why this hid for so long

Both Functions are written to never let a secondary system break a
primary one — `waitlist.js` returns its 200 before promo issuance is
attempted, and swallows anything that goes wrong after. That is the
right design and should stay. But understand the cost: **a missing
binding produces no error anywhere a human will see it.** If a
best-effort feature seems inert, check the binding before you read a
single line of the code.

## How to inspect this WITHOUT the dashboard

The dashboard's menu names no longer match Cloudflare's own docs, which
made this take far longer than it should have. Do not go looking for
"Settings → Functions → KV namespace bindings"; read the API instead.

```
npx -y wrangler@latest login          # one time, opens a browser
npx -y wrangler@latest pages project list
npx -y wrangler@latest pages deployment list --project-name lifeos-site
```

For the bindings themselves — the thing the CLI will not show you —
read the project directly. The OAuth token lives in
`~/Library/Preferences/.wrangler/config/default.toml` as `oauth_token`:

```
GET  https://api.cloudflare.com/client/v4/accounts/<acct>/pages/projects/lifeos-site
     -> result.deployment_configs.{production,preview}.kv_namespaces
PATCH the same URL with {"deployment_configs":{"production":{"kv_namespaces":{...}}}}
GET  .../storage/kv/namespaces?per_page=100      -> namespace titles + ids
POST .../pages/projects/lifeos-site/deployments/<id>/retry
```

That last one is the right way to apply a binding change: **retry
re-runs the same commit with the new bindings attached.** It is a
rebind, not a release — no new code ships. Do NOT reach for
`wrangler pages deploy`, which would upload whatever happens to be in
the working directory and quietly ship unpushed local changes to
production.

Bindings do not take effect until a deployment runs. Adding one and
skipping the redeploy looks exactly like not adding it.

## Verifying from outside

```
curl -s -o /dev/null -w '%{http_code}\n' -X POST https://barretops.com/api/waitlist \
  -H 'Content-Type: application/json' -d '{"email":"not-an-email"}'
```

- `400` (`bad email`) — the Function is running AND bound. Best cheap
  health check there is; it writes nothing.
- `500` (`not configured`) — running, binding missing.
- `405` — no Function at that path. The route isn't deployed (usually:
  the commit that adds it was never pushed).
- `200` on a page that should not exist — that's the fallback, not your
  page. Grep the response for text unique to the real page before
  believing a 200.

Do NOT test liveness by GETting a POST-only endpoint in a browser or a
summarising fetch tool — a redirect to `/` reads as a false negative.
That mistake was made during this session and sent the diagnosis in the
wrong direction for a while.

## Still outstanding

- `PROMOCODES` is bound but its pool is **empty**. It needs
  `pool:android` and `pool:ios` seeded (see `scripts/seed-promo-codes.sh`)
  with real codes generated in Play Console and App Store Connect before
  anything can issue.
- `APPREQUESTS` is bound but `/build/` and `functions/api/app-request.js`
  only go live once those commits are pushed.
