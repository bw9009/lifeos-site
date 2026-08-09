# Deploying barretops.com — Cloudflare Pages

The site moved OFF GitHub Pages (it was static there and the waitlist
could never work). It now targets **Cloudflare Pages**, where
`functions/api/waitlist.js` runs as a real endpoint at `/api/waitlist`.

## One-time setup (dashboard, ~10 minutes)

1. **Create the Pages project.**
   Cloudflare dashboard → Workers & Pages → Create → Pages →
   Connect to Git → pick `bw9009/lifeos-site`, branch `master`.
   Build settings: framework **None**, build command **(empty)**,
   output directory **/** (root). Deploy.

2. **Create the KV namespace for signups.**
   Workers & Pages → KV → Create namespace → name it `waitlist`.

3. **Bind it to the Pages project.**
   The Pages project → Settings → Functions → KV namespace bindings →
   Add: variable name `WAITLIST` → select the `waitlist` namespace.
   Redeploy (Deployments → Retry) so the binding takes.

4. **Move the domain.**
   The Pages project → Custom domains → add `barretops.com` and
   `www.barretops.com`. Because DNS is already on Cloudflare, it
   rewrites the records itself — this is what actually takes the site
   off GitHub's servers.

5. **Clean up GitHub Pages.**
   github.com/bw9009/lifeos-site → Settings → Pages → disable.
   The `CNAME` file is harmless to Pages either way; leave it or drop it.

## Reading the waitlist

Workers & Pages → KV → `waitlist` → the keys are `signup:<email>`, each
value JSON with email, source form, timestamp, user agent.

## The tester group

Play closed testing authorizes by Google Group membership. The site's
Step 1 button and the post-signup nudge both point at
`<group>+subscribe@googlegroups.com` — the visitor's own send joins the
group AND authorizes their account. The address lives in ONE constant,
`GROUP_SUBSCRIBE` in `life/index.html`, plus the Step 1 button href.

## Verify after deploy

```
https://barretops.com                    — loads from Pages, not GitHub
https://barretops.com/privacy.html      — Play Store requirement
curl -X POST https://barretops.com/api/waitlist \
  -H 'Content-Type: application/json' \
  -d '{"email":"test@example.com","source":"curl"}'   — {"ok":true}
```

`server.py` remains for local preview only: `python3 server.py --port 8000`.
