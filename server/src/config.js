function need(name) {
  const value = process.env[name];
  if (!value) throw new Error(`Missing environment variable ${name}`);
  return value;
}

export const config = {
  port: Number(process.env.PORT || 3000),
  databaseUrl: need('DATABASE_URL'),
  supabaseUrl: need('SUPABASE_URL').replace(/\/+$/, ''),
  supabaseServiceKey: need('SUPABASE_SERVICE_ROLE_KEY'),
  // Only needed for projects that still sign tokens with the legacy HS256 secret.
  supabaseJwtSecret: process.env.SUPABASE_JWT_SECRET || '',
  // Admin app. Leave ADMIN_JWT_SECRET empty and the /admin API stays switched off.
  adminJwtSecret: process.env.ADMIN_JWT_SECRET || '',
  // Optional: creates the first owner on startup when no admin exists yet (handy on hosts without a shell).
  bootstrapEmail: process.env.ADMIN_BOOTSTRAP_EMAIL || '',
  bootstrapPassword: process.env.ADMIN_BOOTSTRAP_PASSWORD || '',
};
