// Creates (or resets) an admin account:
//   node --env-file=.env scripts/create-admin.js you@example.com "Your Name" owner
// The password is typed in the terminal (shown as *). Roles: owner, admin, moderator.
import readline from 'node:readline';
import { query, pool } from '../src/db.js';
import { hashPassword } from '../src/admin/auth.js';

const [email, name = 'Admin', role = 'owner'] = process.argv.slice(2);
if (!email || !['owner', 'admin', 'moderator'].includes(role)) {
  console.error('Usage: node --env-file=.env scripts/create-admin.js <email> "<Display name>" [owner|admin|moderator]');
  process.exit(1);
}

const rl = readline.createInterface({ input: process.stdin, output: process.stdout, terminal: true });
let muted = false;
rl._writeToOutput = (s) => {
  if (!muted) return rl.output.write(s);
  if (s.includes('\n') || s.includes('\r')) rl.output.write(s);
  else rl.output.write('*'.repeat(Math.max(0, s.length)));
};
const password = await new Promise((resolve) => {
  rl.question('Password (min 10 characters): ', (v) => { rl.close(); resolve(v); });
  muted = true;
});
console.log('');
if (password.length < 10) {
  console.error('Too short.');
  process.exit(1);
}

await query(
  `insert into admins (email, display_name, role, password_hash)
   values ($1, $2, $3, $4)
   on conflict (lower(email)) do update set display_name = excluded.display_name, role = excluded.role,
     password_hash = excluded.password_hash, disabled = false, failed_attempts = 0, locked_until = null`,
  [email.trim().toLowerCase(), name, role, await hashPassword(password)],
);
console.log(`Saved ${email} as ${role}.`);
await pool.end();
