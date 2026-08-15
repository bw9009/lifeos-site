// Cloudflare Pages Function — POST /api/app-request
// Custom-app-build intake from /build/. Same shape as waitlist.js on
// purpose: one KV key per submission, fail loudly if the binding is
// missing so the client can fall back to mailto rather than silently
// dropping a lead.
//
// SETUP (mirrors DEPLOY.md's waitlist steps):
//   Workers & Pages -> KV -> Create namespace -> `apprequests`
//   Pages project -> Settings -> Functions -> KV namespace bindings ->
//     variable name `APPREQUESTS` -> select it -> redeploy
//
// Keys are `req:<iso-timestamp>:<email>` rather than one-per-email: a
// business that asks twice about two different apps is two real leads,
// not a duplicate to overwrite. Read them in the KV browser, newest
// last by key sort.
//
// The notification email is best-effort, exactly like the promo email
// in waitlist.js. A dead Resend key must never turn a captured lead
// into a failed submission — the KV write is the durable part and it
// happens first.

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const NOTIFY_TO = 'support@barretops.com';

// Everything the form sends, in the order it's useful to read, with the
// cap each field is trimmed to. Anything not on this list is dropped —
// keeps a junk POST from filling KV with arbitrary keys.
const FIELDS = [
  ['name',         'Name',                  120],
  ['business',     'Business',              160],
  ['industry',     'What the business does', 200],
  ['email',        'Email',                 254],
  ['phone',        'Phone',                  40],
  ['city',         'City',                  120],
  ['problem',      'The manual problem',    4000],
  ['does',         'What it should do',     4000],
  ['today',        'How they handle it now',4000],
  ['users',        'Who uses it',            80],
  ['platform',     'Platforms',              80],
  ['distribution', 'Distribution',           80],
  ['tools',        'Existing tools',        400],
  ['budget',       'Budget',                 80],
  ['timeline',     'Timeline',               80],
  ['support',      'Support expectation',    80],
  ['notes',        'Notes',                 4000],
  ['heard',        'How they found me',     200],
];

function clean(body) {
  const out = {};
  for (const [key, , cap] of FIELDS) {
    const v = String(body[key] == null ? '' : body[key]).trim();
    if (v) out[key] = v.slice(0, cap);
  }
  return out;
}

function asText(rec) {
  return FIELDS
    .map(([key, label]) => `${label}: ${rec[key] || '—'}`)
    .join('\n\n');
}

async function notify(env, rec) {
  if (!env.RESEND_API_KEY) return;
  await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${env.RESEND_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: 'BarretOps <hello@barretops.com>',
      to: [NOTIFY_TO],
      reply_to: rec.email,
      subject: `App request — ${rec.business || rec.name} (${rec.budget || 'no budget given'})`,
      text: asText(rec),
    }),
  }).catch(() => {}); // lead is already in KV; a dead network loses the
  // ping, not the lead.
}

export async function onRequestPost({ request, env }) {
  if (!env.APPREQUESTS) {
    return new Response(JSON.stringify({ error: 'not configured' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return new Response(JSON.stringify({ error: 'bad json' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // Honeypot: the form ships a hidden field no human fills in. Return a
  // clean 200 so the bot thinks it worked and doesn't retry, but write
  // nothing.
  if (String(body._website || '').trim()) {
    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const rec = clean(body);
  const email = (rec.email || '').toLowerCase();
  if (!EMAIL_RE.test(email)) {
    return new Response(JSON.stringify({ error: 'bad email' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }
  // The two questions that make a lead workable. Everything else can be
  // chased in a reply; these can't.
  if (!rec.problem || !rec.budget) {
    return new Response(JSON.stringify({ error: 'missing required' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  rec.email = email;
  rec.ts = new Date().toISOString();
  rec.ua = (request.headers.get('User-Agent') || '').slice(0, 200);

  await env.APPREQUESTS.put(`req:${rec.ts}:${email}`, JSON.stringify(rec));

  try {
    await notify(env, rec);
  } catch (_) {
    // Stated above: a notification hiccup is not a submission failure.
  }

  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}
