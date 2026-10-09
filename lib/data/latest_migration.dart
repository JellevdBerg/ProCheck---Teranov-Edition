/// The newest file under `supabase/migrations/` as of this build — shown
/// on the Operator developer panel. There's no client-readable table that
/// says what's actually been applied to the connected project (the
/// Supabase CLI's own migration-history table lives outside the schema
/// the app can query, and migrations here are often applied by pasting
/// into the SQL editor rather than via the CLI at all) — this is what the
/// *code* shipped with, not a live read of the database. Update this
/// alongside adding a new migration file.
const latestMigration = '20261009120000_protect_operator_department.sql';
