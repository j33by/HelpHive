import { z } from 'zod';

export class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

// express 4 does not catch rejected promises on its own
export const ah = (fn) => (req, res, next) =>
  Promise.resolve(fn(req, res, next)).catch(next);

export const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const uuid = z
  .string()
  .regex(UUID_RE, 'Invalid id')
  .transform((s) => s.toLowerCase());

export const reactionKind = z.enum(['like', 'love', 'haha', 'wow', 'sad']);

export const text = (max) =>
  z
    .string()
    .transform((s) => s.trim())
    .pipe(z.string().min(1, 'Write something first').max(max, `Keep it under ${max} characters`));

export const cursor = z.string().datetime({ offset: true }).optional();

export function parse(schema, data) {
  const result = schema.safeParse(data);
  if (!result.success) {
    throw new HttpError(400, result.error.issues[0]?.message || 'Invalid request');
  }
  return result.data;
}

export const iso = (v) => (v instanceof Date ? v.toISOString() : v ?? null);
