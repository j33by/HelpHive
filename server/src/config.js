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
};
