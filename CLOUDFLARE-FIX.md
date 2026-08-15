# Handoff to local Claude — Cloudflare KV bindings never reach production

Written 2026-08-15 by the Cowork (cloud) session. I could not finish this
myself: I have no Cloudflare credentials, the dashboard's current UI does
not match either its own docs or DEPLOY.md, and Barret was not at a
restart point. Everything below is either verified or explicitly labelled
as a guess — please keep that distinction when you work it.

## The symptom, in Barret's words

> "this new one i just set up and the last one i set up (i now deleted
> that one) only show up in preview not production"

Concretely:

| KV namespace | Binding var | Status |
|---|---|---|
| `waitlist` | `WAITLIST` | **works in production** — signups land, confirmed by Barret |
| `promocodes` | `PROMOCODES` | never worked in production; namespace since **deleted** |
| `apprequests` | `APPREQUESTS` | just created for the new `/build/` form; preview only |

So one binding works and every one added since does not. That asymmetry
is the whole puzzle — whatever was done for `WAITLIST` was done
differently, or at a time when the project was configured differently.

## What is VERIFIED

- The Pages project exists and production Functions execute.
  `/api/waitlist` works in production. (I briefly concluded the opposite
  from a WebFetch of that URL returning the homepage — that was a **bad
  inference**, the fetch had normalised the URL to `/`. Do not repeat
  that test; it proves nothing.)
- `functions/api/waitlist.js` reads `env.WAITLIST` and returns
  `{"error":"not configured"}` with a 500 when the binding is absent.
  `functions/api/app-request.js` (new, mine) follows the same contract
  with `env.APPREQUESTS`. That 500 is your diagnostic.
- Barret's dashboard shows "Workers & Pages" with, in his words, "no
  product under that though". I never got a look at the actual screen —
  the Chrome extension was waiting on a site-permission prompt for
  `dash.cloudflare.com` that was never approved.

## What is a GUESS — verify, do not assume

1. **Bindings are per-environment.** Cloudflare's docs say bindings can
   be set for production and preview separately, and that a redeploy is
   required before one takes effect. If `APPREQUESTS` was added only to
   the preview list, production would behave exactly as observed. This
   is my leading theory.
2. **Production branch mismatch.** The repo's branch is `master`;
   Cloudflare commonly defaults the production branch to `main`. If they
   disagree, every deployment is a preview deployment. This would ALSO
   produce the symptom — but it is weakened by `WAITLIST` working in
   production, which implies production deployments do exist. Check it
   anyway, cheaply, before spending time elsewhere.
3. **The redeploy was skipped.** Adding a binding and not redeploying
   looks identical to not adding it.

## DO NOT recite menu paths at Barret

This is the single most useful thing in this document. I burned real time
telling him to go to "Settings → Functions → KV namespace bindings" and
similar, and none of it matched his screen. He said, accurately:

> "your instructions are off...like the names and locations of things
> arent right that is what makes this hard"

Cloudflare merged Pages into Workers and renamed things; the docs lag the
dashboard. **Look at the real screen before telling him where to click.**

## How to actually see it

In rough order of preference:

1. **The Cloudflare MCP servers.** I added five of them to
   `~/Library/Application Support/Claude/claude_desktop_config.json`
   (backup alongside it at `claude_desktop_config.json.bak-precloudflare`).
   They load on the next desktop-app restart. `cloudflare-bindings` is
   the relevant one — it reads bindings directly, no UI archaeology. If
   the app has been restarted since 2026-08-15, try this FIRST.
2. **Chrome.** Have him approve the `dash.cloudflare.com` permission in
   the Claude side panel, then read the page.
3. **Screenshots.** Ask for the bindings screen and the deployments list.
4. **Wrangler.** `npx wrangler pages project list` / `... deployment list`
   will show project name, production branch, and bindings without any
   dashboard at all. Needs `wrangler login` (opens a browser). This is
   probably the fastest path if he is willing.

## The fix, once you can see it

Make `APPREQUESTS` → the `apprequests` namespace exist in the
**production** binding set, matching however `WAITLIST` is configured —
diff the two, that comparison is the answer. Then redeploy production.

If `PROMOCODES` is wanted again, the namespace was deleted and must be
recreated, then re-seeded (`scripts/seed-promo-codes.sh`) with
`pool:android` / `pool:ios`. Note the promo path also needs
`RESEND_API_KEY` set, or codes get reserved but no email goes out.

## How to verify the fix

Against **production**, not a preview URL:

```
curl -s -X POST https://barretops.com/api/app-request \
  -H 'Content-Type: application/json' \
  -d '{"email":"test@example.com","problem":"binding test","budget":"Under $5k"}'
```

- `{"ok":true}` — bound and working.
- `{"error":"not configured"}` — binding still missing on production.
- `{"error":"missing required"}` — the Function IS running and bound;
  you sent a bad payload. Still a success signal for the binding.
- A 404 or an HTML page — the deployment/route isn't live at all, which
  points back to guess 2.

That test writes one junk row, `req:<timestamp>:test@example.com`. Delete
it from the KV browser afterwards.

## Context: what I changed in this repo (all committed, NOT pushed)

- `a2501b5` — new `/beta/`: one page covering iPhone TestFlight and the
  Android two-step. Uses the real mechanism from `life/index.html:434`,
  the `life-app-testers+subscribe@googlegroups.com` mailto, where the
  visitor's own send both joins the group and authorises their account.
- `15ce186` — new `/build/`: custom-app intake form, backed by
  `functions/api/app-request.js`; nav links and sitemap updated;
  DEPLOY.md documents the `APPREQUESTS` binding step.

`/build/` falls back to a `mailto` on any non-200, so leads are not lost
while the binding is broken — they just arrive as email instead of KV.

## Still open, unrelated to Cloudflare

- Barret's LinkedIn post is drafted but blocked on him pasting the text
  of an older unsent post that begins "I made a thing…". Not on disk
  anywhere I could find.
- In the `life` repo: 106 pre-existing test failures on master, an 18px
  RenderFlex overflow at `main.dart:3993`, a row rendering two
  checkboxes at once, and low-contrast text on the confirmation card.
- Android SDK is not installed on this Mac; the `.aab` cannot be built
  here. Barret wants it installed, main disk vs MACSTORAGE undecided.

## House rule, learned the hard way this session

Commit freely. **Never upload a build to Apple or Google** — that is
Barret's step, every time. See the standing rule in the `life` repo's
CLAUDE.md.
