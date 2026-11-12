// StandPoint · notify-staff (Supabase Edge Function)
// Emails StandPoint staff when someone files a report or starts a new club, so nobody has to keep checking Admin.
// The email says only that something is waiting. The details stay in the app's Admin tab, never in email.
// Deploy: Supabase → Edge Functions → Deploy a new function → Via Editor → name it exactly "notify-staff" → paste → Deploy.
// Secrets (Edge Functions → Secrets): RESEND_API_KEY, STAFF_EMAIL (who gets the alerts),
// and optionally FROM_EMAIL. Without a verified domain in Resend, leave FROM_EMAIL out: Resend's test sender
// can only email the address that owns the Resend account, so use that as STAFF_EMAIL.
import { createClient } from "npm:@supabase/supabase-js@2";

const env = (k: string) => Deno.env.get(k) ?? "";
const firstKey = (j: string) => { try { const o = JSON.parse(j); return (o.default ?? Object.values(o)[0] ?? "") as string; } catch { return ""; } };
const URL = env("SUPABASE_URL");
const ANON = env("SUPABASE_ANON_KEY") || firstKey(env("SUPABASE_PUBLISHABLE_KEYS"));
const SERVICE = env("SUPABASE_SERVICE_ROLE_KEY") || firstKey(env("SUPABASE_SECRET_KEYS"));
const ORIGIN = env("ALLOWED_ORIGIN") || "*";
const cors = {
  "Access-Control-Allow-Origin": ORIGIN,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
const RECENT = 60 * 60 * 1000; // only alert about things from the last hour

async function send(subject: string, text: string) {
  const key = env("RESEND_API_KEY"), to = env("STAFF_EMAIL");
  if (!key || !to) return false;
  const r = await fetch(env("RESEND_URL") || "https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from: env("FROM_EMAIL") || "StandPoint <onboarding@resend.dev>", to: [to], subject, text }),
  });
  return r.ok;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Use POST" }, 405);
  const asUser = createClient(URL, ANON, { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } }, auth: { persistSession: false } });
  const { data: who } = await asUser.auth.getUser();
  if (!who?.user) return json({ error: "Sign in first" }, 401);
  const { kind, id } = await req.json().catch(() => ({}));
  if (!["report", "club"].includes(kind) || typeof id !== "string") return json({ error: "Bad request" }, 400);
  const admin = createClient(URL, SERVICE, { auth: { persistSession: false } });

  if (kind === "report") {
    const { data: r } = await admin.from("reports").select("id, reporter_id, reason, org_name, created_at, notified_at").eq("id", id).maybeSingle();
    // Only the person who filed it can trigger the alert, once, and only for a fresh report
    if (!r || r.reporter_id !== who.user.id || r.notified_at || Date.now() - Date.parse(r.created_at) > RECENT) return json({ ok: true, sent: false });
    const sent = await send("StandPoint: a new report needs a look",
      "A new report was filed" + (r.org_name ? " about someone at " + r.org_name : "") + ".\n\nOpen StandPoint, tap Open Admin, and read it under Reports. Every report gets a first look within 24 hours.\n\nThe details are only in the app, never in email.");
    if (sent) await admin.from("reports").update({ notified_at: new Date().toISOString() }).eq("id", id);
    return json({ ok: true, sent });
  }

  const { data: o } = await admin.from("orgs").select("id, name, type, created_by, created_at, approved, staff_notified_at").eq("id", id).maybeSingle();
  if (!o || o.created_by !== who.user.id || o.approved || o.staff_notified_at || Date.now() - Date.parse(o.created_at) > RECENT) return json({ ok: true, sent: false });
  const sent = await send("StandPoint: a new club to approve",
    `${o.name} (${o.type}) was just started on StandPoint.\n\nOpen StandPoint, tap Open Admin, and check it under Clubs. Players can't join until it's approved.`);
  if (sent) await admin.from("orgs").update({ staff_notified_at: new Date().toISOString() }).eq("id", id);
  return json({ ok: true, sent });
});
