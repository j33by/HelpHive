import { Router } from 'express';
import { z } from 'zod';
import { ah, HttpError, parse } from '../../util.js';
import { audit } from '../log.js';
import { summary } from '../stats.js';

const r = Router();

r.get('/dashboard', ah(async (req, res) => {
  const q = parse(z.object({
    range: z.enum(['24h', '7d', '30d', '90d', '1y']).optional(),
    from: z.string().datetime({ offset: true }).optional(),
    to: z.string().datetime({ offset: true }).optional(),
  }), req.query);
  if (q.from && q.to && new Date(q.to) - new Date(q.from) > 400 * 86_400_000) throw new HttpError(400, 'Pick a range of at most 400 days.');
  let data;
  try {
    data = await summary(q);
  } catch (err) {
    if (err.message === 'bad range') throw new HttpError(400, 'The start of the range must be before its end.');
    console.error('dashboard failed:', err.message);
    throw new HttpError(502, 'Could not build the dashboard. Check the Supabase and Neon connections.');
  }
  res.json(data);
}));

r.post('/dashboard/exported', ah(async (req, res) => {
  await audit(req, 'dashboard.export', { details: { range: req.body?.range ?? null } });
  res.status(204).end();
}));

export default r;
