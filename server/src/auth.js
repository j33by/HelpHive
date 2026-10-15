import { createRemoteJWKSet, decodeProtectedHeader, jwtVerify } from 'jose';
import { config } from './config.js';
import { UUID_RE } from './util.js';

const issuer = `${config.supabaseUrl}/auth/v1`;
const jwks = createRemoteJWKSet(new URL(`${issuer}/.well-known/jwks.json`), {
  cooldownDuration: 30_000,
});
const hmacKey = config.supabaseJwtSecret
  ? new TextEncoder().encode(config.supabaseJwtSecret)
  : null;

const ASYMMETRIC = ['ES256', 'RS256', 'EdDSA'];

/**
 * Every route except /health runs behind this. The token must be a live Supabase
 * session JWT for a signed-in (non-anonymous) user. The algorithm list is pinned per
 * key type so a token cannot pick its own verification method.
 */
export async function requireAuth(req, res, next) {
  const match = /^Bearer ([\w-]+\.[\w-]+\.[\w-]+)$/.exec(req.headers.authorization || '');
  if (!match) return res.status(401).json({ error: 'Please sign in again.' });

  try {
    const token = match[1];
    const { alg } = decodeProtectedHeader(token);
    const useHmac = alg === 'HS256';
    if (useHmac && !hmacKey) throw new Error('HS256 token but no secret configured');

    const { payload } = await jwtVerify(token, useHmac ? hmacKey : jwks, {
      issuer,
      audience: 'authenticated',
      algorithms: useHmac ? ['HS256'] : ASYMMETRIC,
    });

    if (payload.role !== 'authenticated' || typeof payload.sub !== 'string' || !UUID_RE.test(payload.sub)) {
      throw new Error('not a user session');
    }
    req.user = { id: payload.sub.toLowerCase() };
    next();
  } catch {
    res.status(401).json({ error: 'Your session has expired. Please sign in again.' });
  }
}
