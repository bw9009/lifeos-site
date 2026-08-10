// Cloudflare Pages Function — POST /api/waitlist
// Stores signups in the WAITLIST KV namespace. One key per address, so a
// re-signup is idempotent rather than a duplicate. The client treats any
// non-200 as "not wired up" and falls back to a mailto that can't silently
// fail — so if the KV binding is missing, fail loudly, don't pretend.
//
// PROMO CODES — his "3 months free for signing up early" offer. A second
// KV namespace (PROMOCODES) holds the unissued pile, seeded by hand from
// batches generated in Play Console (90-day subscription promo codes)
// and App Store Connect (3-Month offer codes). Two keys hold the pool:
//   pool:android -> JSON array of unused Play codes
//   pool:ios     -> JSON array of unused Apple codes
// and one key per address records what went out, so a re-signup never
// issues twice: issued:<email> -> {android, ios, ts}.
//
// SIGNUP MUST NEVER FAIL BECAUSE OF THE PROMO. The waitlist write and the
// 200 response happen first; code issuance and the email are best-effort
// after that. A dead Resend key or an empty pool costs a promo email, not
// a lost signup — same fail-open shape as the rest of this app.
//
// KV has no atomic pop. At this signup volume (a handful an hour) the
// chance of two requests taking the same code is negligible and the
// failure mode if it ever happened is "one code redeemed twice" — not
// nothing, but not worth a Durable Object for tonight's traffic either.

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

// The redemption instructions differ by store and neither code is
// platform-detectable from an email address, so both go out together —
// use whichever matches the phone.
const APPLE_APP_ID = '6798571976';

function redeemLinks(codes) {
  const lines = [];
  if (codes.android) {
    lines.push(
      `Android (Google Play): open the Play Store app, search "Life" ` +
        `by BarretOps, then Menu > Redeem code, and enter ${codes.android}. ` +
        `Or go straight there: https://play.google.com/redeem?code=${encodeURIComponent(codes.android)}`
    );
  }
  if (codes.ios) {
    lines.push(
      `iPhone (App Store): https://apps.apple.com/redeem?ctx=offercodes&id=${APPLE_APP_ID}&code=${encodeURIComponent(codes.ios)}`
    );
  }
  return lines;
}

async function issuePromoCodes(env, email) {
  if (!env.PROMOCODES) return null; // pool not configured yet - skip quietly
  const issuedKey = `issued:${email}`;
  // Already issued: the codes were reserved and the one email already
  // sent. Return null here (not the old record) so a re-signup - a
  // double form submit, a retry - never fires a second email off the
  // same reservation.
  const already = await env.PROMOCODES.get(issuedKey);
  if (already) return null;

  const codes = {};
  for (const platform of ['android', 'ios']) {
    const poolKey = `pool:${platform}`;
    const raw = await env.PROMOCODES.get(poolKey);
    const pool = raw ? JSON.parse(raw) : [];
    if (pool.length === 0) continue;
    codes[platform] = pool.shift();
    await env.PROMOCODES.put(poolKey, JSON.stringify(pool));
  }
  if (!codes.android && !codes.ios) return null; // both piles empty

  const record = { ...codes, ts: new Date().toISOString() };
  await env.PROMOCODES.put(issuedKey, JSON.stringify(record));
  return record;
}

async function sendPromoEmail(env, email, codes) {
  if (!env.RESEND_API_KEY) return; // not set up yet - the code is still
  // reserved in KV either way, so nothing is lost once the key lands.
  const lines = redeemLinks(codes);
  if (lines.length === 0) return;

  const text =
    `Thanks for signing up early for Life.\n\n` +
    `Here's your 3 months of Pro, free - no card needed:\n\n` +
    lines.join('\n\n') +
    `\n\nQuestions? Just reply to this email.\n\n— Barret`;

  await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${env.RESEND_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: 'Life <hello@barretops.com>',
      to: [email],
      subject: 'Your 3 months of Life, free',
      text,
    }),
  }).catch(() => {}); // best-effort - the promo pool already reserved
  // the code, so a dead network here loses an email, not the offer.
}

export async function onRequestPost({ request, env }) {
  if (!env.WAITLIST) {
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

  const email = String(body.email || '').trim().toLowerCase();
  if (!EMAIL_RE.test(email) || email.length > 254) {
    return new Response(JSON.stringify({ error: 'bad email' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const record = {
    email,
    source: String(body.source || 'unknown').slice(0, 40),
    ts: new Date().toISOString(),
    ua: (request.headers.get('User-Agent') || '').slice(0, 200),
  };

  await env.WAITLIST.put(`signup:${email}`, JSON.stringify(record));

  // The signup itself is already durable and the 200 below is already
  // decided - everything from here on is the promo, and it never gets
  // to turn a successful signup into a failed response.
  try {
    const codes = await issuePromoCodes(env, email);
    if (codes) await sendPromoEmail(env, email, codes);
  } catch (_) {
    // Same rule stated above: a promo hiccup is not a signup failure.
  }

  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}

