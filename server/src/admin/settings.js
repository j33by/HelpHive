import { query } from '../db.js';

/** Built-in reasons an admin can start from. They can be edited in Settings > Reason templates. */
export const DEFAULT_TEMPLATES = {
  warn: [
    { label: 'Respect other members', text: 'Please keep your posts and comments respectful. Insults and personal attacks are not allowed in HelpHive.' },
    { label: 'Off-topic', text: 'Your recent posts are not about asking for or offering help. Please keep HelpHive on topic.' },
  ],
  restrict: [
    { label: 'Spam', text: 'Posting repeated or promotional content that is not related to helping neighbours.' },
    { label: 'Harassment', text: 'Harassing or targeting other members in posts or comments.' },
    { label: 'Inappropriate content', text: 'Sharing content that does not follow the HelpHive community guidelines.' },
    { label: 'Misleading information', text: 'Posting information that is false or misleading and could affect others.' },
  ],
  ban: [
    { label: 'Repeated violations', text: 'Repeated violations of the community guidelines after earlier warnings and restrictions.' },
    { label: 'Scam or fraud', text: 'Using HelpHive to scam, defraud or mislead other members.' },
    { label: 'Threats or hate', text: 'Threatening, abusing or spreading hate against other members.' },
    { label: 'Impersonation', text: 'Pretending to be another person or organisation.' },
  ],
  strike: [
    { label: 'Guideline violation', text: 'A post or comment broke the community guidelines.' },
    { label: 'Spam', text: 'Spam or repeated promotional posting.' },
    { label: 'Disrespectful behaviour', text: 'Disrespectful or abusive behaviour towards another member.' },
  ],
  delete_post: [
    { label: 'Spam or advertising', text: 'The post was spam or advertising.' },
    { label: 'Inappropriate content', text: 'The post contained content that is not allowed in HelpHive.' },
    { label: 'Misleading', text: 'The post contained misleading or unsafe information.' },
    { label: 'Personal information', text: 'The post shared personal information that should not be public.' },
  ],
  delete_comment: [
    { label: 'Harassment', text: 'The comment was abusive or targeted another member.' },
    { label: 'Spam', text: 'The comment was spam or advertising.' },
    { label: 'Off-topic', text: 'The comment was off-topic and disrupted the conversation.' },
  ],
  unrestrict: [
    { label: 'Reviewed', text: 'After review, the restriction was lifted early.' },
    { label: 'Mistake', text: 'The restriction was applied by mistake.' },
  ],
  unban: [
    { label: 'Appeal accepted', text: 'Your appeal was reviewed and accepted.' },
    { label: 'Mistake', text: 'The ban was applied by mistake. We are sorry for the trouble.' },
  ],
  remove_strike: [
    { label: 'Reviewed', text: 'After review, the strike was removed.' },
    { label: 'Mistake', text: 'The strike was issued by mistake.' },
  ],
  email_change: [
    { label: 'Account recovery', text: 'The email on your account was updated at your request.' },
    { label: 'Security', text: 'The email on your account was updated to protect your account.' },
  ],
  password_change: [
    { label: 'Account recovery', text: 'Your password was reset at your request. Sign in with the new password and change it.' },
    { label: 'Security', text: 'Your password was reset to protect your account. Sign in with the new password and change it.' },
  ],
  account_delete: [
    { label: 'Requested by user', text: 'The account was deleted at the owner’s request.' },
    { label: 'Severe violation', text: 'The account was removed for a severe violation of the community guidelines.' },
  ],
  undo: [
    { label: 'Applied by mistake', text: 'This action was applied by mistake.' },
    { label: 'Reviewed', text: 'After review, this action was reversed.' },
  ],
};

export const DEFAULTS = {
  restrictBaseHours: 24,      // 1st restriction 24h, 2nd 48h, 3rd 72h ...
  restrictMaxHours: 720,
  strikeAutoRestrictAt: 3,    // 0 = off
  strikeAutoBanAt: 0,         // 0 = off
  notifyRestricted: false,    // send notices to people who are restricted at that moment
  sessionIdleMinutes: 30,
  templates: DEFAULT_TEMPLATES,
};

let cache = { at: 0, value: DEFAULTS };

export async function getSettings({ fresh = false } = {}) {
  if (!fresh && Date.now() - cache.at < 20_000) return cache.value;
  let rows = [];
  try {
    ({ rows } = await query('select key, value from admin_settings'));
  } catch {
    return DEFAULTS;
  }
  const stored = Object.fromEntries(rows.map((r) => [r.key, r.value]));
  const value = {
    ...DEFAULTS,
    ...stored,
    templates: { ...DEFAULT_TEMPLATES, ...(stored.templates ?? {}) },
  };
  cache = { at: Date.now(), value };
  return value;
}

export async function saveSettings(patch, adminId) {
  for (const [key, value] of Object.entries(patch)) {
    await query(
      `insert into admin_settings (key, value, updated_by) values ($1, $2::jsonb, $3)
       on conflict (key) do update set value = excluded.value, updated_at = now(), updated_by = excluded.updated_by`,
      [key, JSON.stringify(value), adminId],
    );
  }
  cache.at = 0;
  return getSettings({ fresh: true });
}

/** The text a person reads. The admin app shows the same envelopes as a live preview. */
export const ENVELOPES = {
  warn: 'You received a warning from the HelpHive team.\n\nReason: {reason}',
  restrict: 'Your account is restricted for {duration}. You can still read HelpHive, but you cannot post, comment, react, message or edit your profile until {until}.\n\nReason: {reason}',
  unrestrict: 'Your restriction has been lifted. You can use HelpHive normally again.\n\nNote from the team: {reason}',
  ban: 'Your account has been banned.\n\nReason: {reason}',
  unban: 'Your account has been reinstated. Welcome back.\n\nNote from the team: {reason}',
  strike: 'You received a strike on your account ({count} so far).\n\nReason: {reason}',
  remove_strike: 'A strike was removed from your account ({count} left).\n\nNote from the team: {reason}',
  delete_post: 'The HelpHive team removed one of your posts.\n\nReason: {reason}',
  delete_comment: 'The HelpHive team removed one of your comments.\n\nReason: {reason}',
  email_change: 'The email address on your account was changed by the HelpHive team.\n\nReason: {reason}',
  password_change: 'Your password was changed by the HelpHive team.\n\nReason: {reason}',
  revert: 'The HelpHive team reversed an earlier action on your account: {summary}.\n\nNote from the team: {reason}',
};

export const fill = (tpl, vars) => tpl.replace(/\{(\w+)\}/g, (_, k) => String(vars[k] ?? ''));

export const hoursLabel = (h) => `${h} hour${h === 1 ? '' : 's'}`;

export const fmtUntil = (iso) =>
  new Date(iso).toLocaleString('en-US', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'UTC' }) + ' UTC';
