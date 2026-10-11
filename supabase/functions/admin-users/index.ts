// Phase 4 of the 2026-10-11 hardening spec: account lifecycle through the
// real Supabase Auth Admin API instead of this repo's old habit of writing
// into auth.users/auth.identities by hand (see
// `admin_create_profile`/`admin_delete_profile` in supabase/migrations).
// The service-role key lives only as this function's secret — never in the
// client or in a migration.
//
// Deploy (Thomas, after reviewing this file):
//   supabase functions deploy admin-users --project-ref xfcmumvfaknprmgisaar
//   supabase secrets set SUPABASE_SERVICE_ROLE_KEY=<service role key> --project-ref xfcmumvfaknprmgisaar
// SUPABASE_URL and SUPABASE_ANON_KEY are already provided to every Edge
// Function by the platform; only the service-role key needs setting.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "Not signed in" }, 401);

  // Service-role client for every data operation (bypasses RLS — this
  // function is the access-control boundary, same role the SECURITY
  // DEFINER SQL functions play today) plus verifying who the caller is.
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: callerAuth, error: callerErr } = await admin.auth.getUser(token);
  if (callerErr || !callerAuth.user) return json({ error: "Not signed in" }, 401);
  const callerId = callerAuth.user.id;

  const { data: caller } = await admin
    .from("profiles")
    .select("id, department_id, departments:department_id(is_operator, is_it)")
    .eq("id", callerId)
    .maybeSingle();
  const callerDept = caller?.departments as { is_operator: boolean; is_it: boolean } | null;
  const isOperator = callerDept?.is_operator ?? false;
  const isAdmin = isOperator || (callerDept?.is_it ?? false);
  if (!isAdmin) return json({ error: "Only an Operator or IT can do this" }, 403);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid request body" }, 400);
  }
  const action = body.action as string | undefined;

  async function departmentIsAdminTier(departmentId: string | null | undefined) {
    if (!departmentId) return false;
    const { data } = await admin
      .from("departments")
      .select("is_operator, is_it")
      .eq("id", departmentId)
      .maybeSingle();
    return Boolean(data?.is_operator || data?.is_it);
  }

  // Phase 5: the same admin_audit table the SQL admin functions log into
  // (via log_admin_audit()) — inserted directly since this function runs
  // with the service-role client, outside any user JWT auth.uid() context.
  async function audit(
    auditAction: string,
    targetId: string | null,
    before: Record<string, unknown> | null,
    after: Record<string, unknown> | null,
  ) {
    await admin.from("admin_audit").insert({
      actor_id: callerId,
      action: auditAction,
      target_type: "profile",
      target_id: targetId,
      before,
      after,
    });
  }

  try {
    switch (action) {
      case "create": {
        const username = String(body.username ?? "").trim().toLowerCase();
        const password = String(body.password ?? "");
        const displayName = String(body.displayName ?? "").trim();
        const departmentId = (body.departmentId as string | null) ?? null;
        let role = (body.role as string) === "manager" ? "manager" : "member";

        if (!username) return json({ error: "Username cannot be empty" }, 400);
        if (password.length < 6) return json({ error: "Password must be at least 6 characters" }, 400);
        if (!displayName) return json({ error: "Enter a name" }, 400);

        const targetAdminTier = await departmentIsAdminTier(departmentId);
        if (targetAdminTier && !isOperator) {
          return json({ error: "Only an Operator can create accounts in the Operator or IT department" }, 403);
        }
        if (targetAdminTier) role = "manager";

        const syntheticEmail = `${username}@procheck.local`;
        const { data: created, error: createErr } = await admin.auth.admin.createUser({
          email: syntheticEmail,
          password,
          email_confirm: true,
          user_metadata: { username, display_name: displayName },
          app_metadata: { provider: "email", providers: ["email"], procheck_provisioned: true },
        });

        let userId: string;
        if (createErr) {
          // Retry-safe create: if a previous attempt already made the auth
          // user but failed before finishing the profile, resume from the
          // existing profile instead of erroring the retry out.
          const alreadyExists = /already.*registered|already.*exists/i.test(createErr.message ?? "");
          if (!alreadyExists) return json({ error: createErr.message }, 400);
          const { data: existing } = await admin
            .from("profiles")
            .select("id")
            .eq("username", username)
            .maybeSingle();
          if (!existing) return json({ error: `Username "${username}" is already taken` }, 400);
          userId = existing.id;
        } else {
          userId = created.user.id;
        }

        const { error: updateErr } = await admin
          .from("profiles")
          .update({ role, department_id: departmentId, is_active: true })
          .eq("id", userId);
        if (updateErr) return json({ error: updateErr.message }, 400);

        await audit("create_account", userId, null, { username, role, departmentId });
        return json({ userId });
      }

      case "reset_password": {
        const userId = String(body.userId ?? "");
        const password = String(body.password ?? "");
        if (!userId) return json({ error: "Missing userId" }, 400);
        if (password.length < 6) return json({ error: "Password must be at least 6 characters" }, 400);

        const { data: target } = await admin
          .from("profiles")
          .select("department_id")
          .eq("id", userId)
          .maybeSingle();
        if (!target) return json({ error: "Account not found" }, 404);
        if (await departmentIsAdminTier(target.department_id) && !isOperator) {
          return json({ error: "Only an Operator can reset a password in the Operator or IT department" }, 403);
        }

        const { error } = await admin.auth.admin.updateUserById(userId, { password });
        if (error) return json({ error: error.message }, 400);

        await audit("reset_password", userId, null, null);
        return json({ ok: true });
      }

      case "deactivate":
      case "reactivate": {
        const userId = String(body.userId ?? "");
        if (!userId) return json({ error: "Missing userId" }, 400);
        if (userId === callerId) return json({ error: `Cannot ${action} your own account` }, 400);

        const { data: target } = await admin
          .from("profiles")
          .select("department_id, departments:department_id(is_operator, is_it)")
          .eq("id", userId)
          .maybeSingle();
        if (!target) return json({ error: "Account not found" }, 404);
        const targetDept = target.departments as { is_operator: boolean; is_it: boolean } | null;
        if (targetDept?.is_operator) {
          return json({ error: "The Operator account cannot be deactivated" }, 400);
        }
        if (targetDept?.is_it && !isOperator) {
          return json({ error: "Only an Operator can deactivate or reactivate an IT account" }, 403);
        }

        const banDuration = action === "deactivate" ? "876000h" : "none";
        const { error } = await admin.auth.admin.updateUserById(userId, { ban_duration: banDuration });
        if (error) return json({ error: error.message }, 400);

        const { error: updateErr } = await admin
          .from("profiles")
          .update({ is_active: action === "reactivate" })
          .eq("id", userId);
        if (updateErr) return json({ error: updateErr.message }, 400);

        await audit(
          action === "deactivate" ? "deactivate_account" : "reactivate_account",
          userId,
          { is_active: action === "deactivate" },
          { is_active: action === "reactivate" },
        );
        return json({ ok: true });
      }

      default:
        return json({ error: `Unknown action "${action}"` }, 400);
    }
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
