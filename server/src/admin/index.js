import express, { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { HttpError } from '../util.js';
import { publicRoutes, sessionRoutes } from './routes/session.js';
import dashboard from './routes/dashboard.js';
import users from './routes/users.js';
import content from './routes/content.js';
import announcements from './routes/announcements.js';
import control from './routes/control.js';
import logs from './routes/logs.js';
import inbox from './routes/inbox.js';
import team from './routes/team.js';

/**
 * Everything under /admin. It has its own sign-in (admins are not Supabase users),
 * its own body parser and its own rate limit, and never touches the app's auth.
 */
const router = Router();
router.use(express.json({ limit: '64kb' }));
router.use(rateLimit({ windowMs: 10 * 60_000, limit: 3000, standardHeaders: true, legacyHeaders: false }));
router.use(publicRoutes);
router.use(sessionRoutes); // from here on everything needs an admin session
router.use(rateLimit({
  windowMs: 60_000,
  limit: 120,
  keyGenerator: (req) => req.admin.id,
  skip: (req) => req.method === 'GET',
  message: { error: 'Slow down: too many changes in a minute.' },
}));
for (const sub of [dashboard, users, content, announcements, control, logs, inbox, team]) router.use(sub);
router.use((_req, _res, next) => next(new HttpError(404, 'Not found.')));

export default router;
