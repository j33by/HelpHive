import { query } from '../db.js';

/**
 * Writes one line to the append-only audit log. Every admin action, every
 * sign-in and every profile an admin opens ends up here.
 */
export async function audit(req, action, { targetType = null, targetId = null, targetLabel = null, details = {}, actor = null } = {}) {
  const a = actor ?? req.admin ?? {};
  try {
    await query(
      `insert into admin_logs (admin_id, admin_name, action, target_type, target_id, target_label, details, ip)
       values ($1, $2, $3, $4, $5, $6, $7::jsonb, $8)`,
      [a.id ?? null, a.name ?? '', action, targetType, targetId ? String(targetId) : null, targetLabel, JSON.stringify(details), req.ip ?? null],
    );
  } catch (err) {
    // An action that already happened must not turn into an error, but it must be loud.
    console.error('AUDIT LOG WRITE FAILED:', action, err.message);
  }
}
