import { Router } from 'express';
import { z } from 'zod';
import { query } from '../../db.js';
import { ah, parse } from '../../util.js';
import { audit } from '../log.js';
import { requirePerm } from '../auth.js';

const r = Router();

const filters = z.object({
  admin: z.string().uuid().optional(),
  action: z.string().max(60).optional(),
  q: z.string().max(80).optional(),
  from: z.string().datetime({ offset: true }).optional(),
  to: z.string().datetime({ offset: true }).optional(),
  page: z.coerce.number().int().min(1).max(100000).default(1),
});

function where(f) {
  const w = [];
  const a = [];
  const add = (sql, v) => { a.push(v); w.push(sql.replaceAll('?', `$${a.length}`)); };
  if (f.admin) add('admin_id = ?', f.admin);
  if (f.action) add('action like ?', `${f.action.replace(/[%_]/g, '')}%`);
  if (f.from) add('created_at >= ?', f.from);
  if (f.to) add('created_at <= ?', f.to);
  if (f.q?.trim()) add("(target_label ilike ? or admin_name ilike ? or details::text ilike ?)", `%${f.q.trim().replace(/[%_]/g, ' ')}%`);
  const sql = w.join(' and ');
  return { clause: sql ? `where ${sql}` : '', args: a };
}

const fix = where;

const shape = (l) => ({
  id: Number(l.id), adminId: l.admin_id, adminName: l.admin_name, action: l.action,
  targetType: l.target_type, targetId: l.target_id, targetLabel: l.target_label,
  details: l.details, ip: l.ip, createdAt: l.created_at,
});

r.get('/logs', requirePerm('logs'), ah(async (req, res) => {
  const f = parse(filters, req.query);
  const { clause, args } = fix(f);
  const total = await query(`select count(*)::int as n from admin_logs ${clause}`, args);
  const { rows } = await query(`select * from admin_logs ${clause} order by id desc limit 50 offset ${(f.page - 1) * 50}`, args);
  res.json({ total: total.rows[0].n, logs: rows.map(shape) });
}));

r.get('/logs/actions', requirePerm('logs'), ah(async (_req, res) => {
  const { rows } = await query('select distinct action from admin_logs order by action');
  res.json({ actions: rows.map((x) => x.action) });
}));

const csvCell = (v) => {
  let s = v == null ? '' : typeof v === 'object' ? JSON.stringify(v) : String(v);
  if (/^[=+\-@]/.test(s)) s = `'${s}`; // stops spreadsheets from running a cell as a formula
  return `"${s.replace(/"/g, '""')}"`;
};

r.get('/logs/export', requirePerm('logs'), ah(async (req, res) => {
  const f = parse(filters, req.query);
  const { clause, args } = fix(f);
  const { rows } = await query(`select * from admin_logs ${clause} order by id desc limit 10000`, args);
  const head = ['time (UTC)', 'admin', 'action', 'target type', 'target', 'details', 'ip'];
  const csv = [head.map(csvCell).join(',')]
    .concat(rows.map((l) => [new Date(l.created_at).toISOString(), l.admin_name, l.action, l.target_type, l.target_label ?? l.target_id, l.details, l.ip].map(csvCell).join(',')))
    .join('\r\n');
  await audit(req, 'logs.export', { details: { rows: rows.length, filters: f } });
  res.json({ csv, rows: rows.length });
}));

export default r;
