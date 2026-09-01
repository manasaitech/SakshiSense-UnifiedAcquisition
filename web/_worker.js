const COOKIE_NAME = 'sakshi_acquisition_auth';
const SESSION_SECONDS = 8 * 60 * 60;

const encoder = new TextEncoder();

function toBase64Url(bytes) {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function fromBase64Url(value) {
  const padded = value.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((value.length + 3) % 4);
  const binary = atob(padded);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

async function hmac(secret, value) {
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign', 'verify'],
  );
  return crypto.subtle.sign('HMAC', key, encoder.encode(value));
}

async function secureEqual(left, right) {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) difference |= left[index] ^ right[index];
  return difference === 0;
}

async function validSession(request, env) {
  if (!env.AUTH_SECRET) return false;
  const cookie = request.headers.get('Cookie') || '';
  const match = cookie.match(new RegExp(`(?:^|;\\s*)${COOKIE_NAME}=([^;]+)`));
  if (!match) return false;
  const [expiryText, signature] = match[1].split('.');
  const expiry = Number(expiryText);
  if (!Number.isFinite(expiry) || expiry < Math.floor(Date.now() / 1000)) return false;
  const expected = new Uint8Array(await hmac(env.AUTH_SECRET, expiryText));
  try {
    return await secureEqual(expected, fromBase64Url(signature));
  } catch (_) {
    return false;
  }
}

function loginPage(error = '') {
  const message = error ? `<p class="error">${error}</p>` : '';
  return new Response(`<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Unified Acquisition — Login</title>
<style>
*{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;background:#07111f;color:#edf5ff;font:16px system-ui,sans-serif}
main{width:min(92vw,390px);padding:32px;border:1px solid #243956;border-radius:18px;background:#0d1b2e;box-shadow:0 20px 70px #0006}
h1{margin:0 0 8px;font-size:24px}p{color:#a9bad0;line-height:1.5}label{display:block;margin:22px 0 8px;color:#d8e5f5;font-size:14px}
input{width:100%;padding:13px 14px;border:1px solid #3d5877;border-radius:9px;background:#081323;color:#fff;font-size:20px;letter-spacing:.35em}button{width:100%;margin-top:18px;padding:13px;border:0;border-radius:9px;background:#4fd1a5;color:#06131f;font-weight:700;font-size:16px;cursor:pointer}.error{color:#ff9c9c;margin-bottom:0}
</style></head><body><main><h1>Unified Acquisition</h1><p>Enter the session access passcode to continue.</p>${message}<form method="post" action="/__auth"><label for="passcode">Passcode</label><input id="passcode" name="passcode" type="password" inputmode="numeric" autocomplete="current-password" required autofocus><button type="submit">Continue</button></form></main></body></html>`, {
    status: error ? 401 : 200,
    headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' },
  });
}

export default {
  async fetch(request, env) {
    if (!env.ACCESS_CODE || !env.AUTH_SECRET) {
      return new Response('Authentication is not configured.', { status: 503 });
    }
    const url = new URL(request.url);

    if (url.pathname === '/__auth' && request.method === 'POST') {
      const form = await request.formData();
      const supplied = String(form.get('passcode') || '');
      const suppliedDigest = new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(supplied)));
      const expectedDigest = new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(env.ACCESS_CODE)));
      if (!(await secureEqual(suppliedDigest, expectedDigest))) return loginPage('Incorrect passcode.');
      const expiry = String(Math.floor(Date.now() / 1000) + SESSION_SECONDS);
      const signature = toBase64Url(new Uint8Array(await hmac(env.AUTH_SECRET, expiry)));
      return new Response(null, { status: 302, headers: {
        Location: '/',
        'Set-Cookie': `${COOKIE_NAME}=${expiry}.${signature}; Max-Age=${SESSION_SECONDS}; Path=/; HttpOnly; Secure; SameSite=Lax`,
        'Cache-Control': 'no-store',
      } });
    }
    if (url.pathname === '/__logout') {
      return new Response(null, { status: 302, headers: {
        Location: '/login',
        'Set-Cookie': `${COOKIE_NAME}=; Max-Age=0; Path=/; HttpOnly; Secure; SameSite=Lax`,
      } });
    }
    if (!(await validSession(request, env))) return loginPage();
    return env.ASSETS.fetch(request);
  },
};
