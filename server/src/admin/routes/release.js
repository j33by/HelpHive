import { Router } from 'express';
import { z } from 'zod';
import { ah, HttpError, parse } from '../../util.js';
import { audit } from '../log.js';
import { requirePerm } from '../auth.js';
import { getSettings, saveSettings } from '../settings.js';

/**
 * The version every app (Android, Windows, ...) is compared against. When a
 * person's app is older, it shows a floating "Download New Version" card.
 */
const r = Router();

export const VERSION_RE = /^\d{1,4}\.\d{1,4}(\.\d{1,4})?$/;

const schema = z.object({
  latestVersion: z.string().trim().regex(VERSION_RE, 'Use a version like 1.2.0').or(z.literal('')),
  notes: z.string().trim().max(500).default(''),
  downloadUrl: z.string().trim().url().max(300).refine((u) => u.startsWith('https://'), 'The download link must start with https://'),
  enabled: z.boolean(),
});

r.get('/release', requirePerm('release'), ah(async (_req, res) => {
  res.json({ release: (await getSettings({ fresh: true })).appRelease });
}));

r.put('/release', requirePerm('release'), ah(async (req, res) => {
  const v = parse(schema, req.body);
  const before = (await getSettings({ fresh: true })).appRelease;
  const next = { ...v, updatedAt: new Date().toISOString(), updatedBy: req.admin.name };
  await saveSettings({ appRelease: next }, req.admin.id);
  await audit(req, 'release.update', { details: { before: { latestVersion: before.latestVersion, enabled: before.enabled, downloadUrl: before.downloadUrl }, after: { latestVersion: v.latestVersion, enabled: v.enabled, downloadUrl: v.downloadUrl, notes: v.notes } } });
  res.json({ release: next });
}));

export default r;
