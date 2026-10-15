import express from 'express';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import { config } from './config.js';
import { pool } from './db.js';
import { requireAuth } from './auth.js';
import { HttpError } from './util.js';
import comments from './routes/comments.js';
import messages from './routes/messages.js';
import notifications from './routes/notifications.js';
import events from './routes/events.js';
import account from './routes/account.js';

const app = express();
app.disable('x-powered-by');
app.set('trust proxy', 1); // Render terminates TLS in front of us
app.use(helmet());
app.use(express.json({ limit: '16kb' }));

// Unauthenticated, only so the app can wake a sleeping free-tier instance.
app.get('/health', (_req, res) => res.json({ ok: true }));

// Cheap per-IP ceiling before any token work happens.
app.use(rateLimit({ windowMs: 10 * 60_000, limit: 800, standardHeaders: true, legacyHeaders: false }));

app.use(requireAuth);

// Writes are limited per signed-in user.
const writes = rateLimit({
  windowMs: 60_000,
  limit: 45,
  keyGenerator: (req) => req.user.id,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Slow down a little and try again in a minute.' },
});
app.use((req, res, next) => (req.method === 'GET' ? next() : writes(req, res, next)));

app.use(comments);
app.use(messages);
app.use(notifications);
app.use(events);
app.use(account);

app.use((_req, res) => res.status(404).json({ error: 'Not found.' }));

// eslint-disable-next-line no-unused-vars
app.use((err, _req, res, _next) => {
  if (err instanceof HttpError) return res.status(err.status).json({ error: err.message });
  if (err?.type === 'entity.parse.failed') return res.status(400).json({ error: 'Invalid request body.' });
  if (err?.type === 'entity.too.large') return res.status(413).json({ error: 'Request too large.' });
  console.error('unhandled:', err?.message || err);
  res.status(500).json({ error: 'Something went wrong on our side.' });
});

const server = app.listen(config.port, () => console.log(`HelpHive API listening on :${config.port}`));

function shutdown() {
  server.close(() => pool.end().finally(() => process.exit(0)));
  setTimeout(() => process.exit(0), 8000).unref();
}
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

export { app };
