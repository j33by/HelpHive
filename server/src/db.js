import pg from 'pg';
import { config } from './config.js';

// timestamptz -> ISO string, keeping microseconds so paging cursors round-trip exactly
pg.types.setTypeParser(1184, (v) => {
  const m = /^(\d{4}-\d\d-\d\d) (\d\d:\d\d:\d\d(?:\.\d+)?)\+00(?::?00)?$/.exec(v);
  return m ? `${m[1]}T${m[2]}Z` : new Date(v).toISOString();
});

const local = /@(localhost|127\.0\.0\.1)/.test(config.databaseUrl);

export const pool = new pg.Pool({
  connectionString: config.databaseUrl,
  ssl: local ? false : { rejectUnauthorized: true },
  max: Number(process.env.PG_POOL_MAX || 8),
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 15_000,
});

pool.on('error', (err) => console.error('pg pool error:', err.message));

export const query = (text, params) => pool.query(text, params);

export async function tx(fn) {
  const client = await pool.connect();
  try {
    await client.query('begin');
    const result = await fn(client);
    await client.query('commit');
    return result;
  } catch (err) {
    await client.query('rollback').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}
