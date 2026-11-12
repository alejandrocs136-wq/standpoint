// StandPoint · delete-account (Supabase Edge Function)
// Deletes a person's videos and then his account, together, on the server. If the videos can't be deleted,
// nothing is deleted, so a player's videos never outlive his account.
// Deploy: Supabase → Edge Functions → Deploy a new function → Via Editor → name it exactly "delete-account" → paste → Deploy.
// It needs no secrets of its own: Supabase gives every function the project's URL and keys.
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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Use POST" }, 405);

  // 1. Who is asking? (Checked with Supabase, not taken from the request)
  const asUser = createClient(URL, ANON, { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } }, auth: { persistSession: false } });
  const { data: who, error: whoErr } = await asUser.auth.getUser();
  if (whoErr || !who?.user) return json({ error: "Sign in first" }, 401);
  const uid = who.user.id;

  // 2. Would it leave a club with players and no admin? Stop and say so.
  const chk = await asUser.rpc("delete_check");
  if (chk.error) return json({ error: chk.error.message }, 400);
  if (Array.isArray(chk.data) && chk.data.length) {
    return json({ error: "Make another coach an admin of " + chk.data.map((c: { name: string }) => c.name).join(", ") + " first. Then you can delete your account.", clubs: chk.data }, 409);
  }

  // 3. Delete every video in his folder. Any failure stops everything.
  const admin = createClient(URL, SERVICE, { auth: { persistSession: false } });
  for (let round = 0; round < 50; round++) {
    const { data: files, error: listErr } = await admin.storage.from("videos").list(uid, { limit: 100 });
    if (listErr) return json({ error: "Couldn't reach your videos, so nothing was deleted. Try again." }, 500);
    const paths = (files ?? []).filter((f) => f.id).map((f) => `${uid}/${f.name}`);
    if (!paths.length) break;
    const { error: rmErr } = await admin.storage.from("videos").remove(paths);
    if (rmErr) return json({ error: "Couldn't delete your videos, so nothing was deleted. Try again." }, 500);
  }

  // 4. Delete the account (the same database rules as before: clubs only he was in go with him)
  const del = await asUser.rpc("delete_me");
  if (del.error) return json({ error: del.error.message }, 400);
  return json({ ok: true });
});
