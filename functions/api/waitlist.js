// Cloudflare Pages Function — POST /api/waitlist
// Stores signups in the WAITLIST KV namespace. One key per address, so a
// re-signup is idempotent rather than a duplicate. The client treats any
// non-200 as "not wired up" and falls back to a mailto that can't silently
// fail — so if the KV binding is missing, fail loudly, don't pretend.

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

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

  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}
