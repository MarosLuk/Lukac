import { createClient } from "@supabase/supabase-js";
import { createSupabaseServerClient } from "./server";

/**
 * Returns a Supabase client scoped to the caller of the incoming request.
 *
 * Accepts either:
 *  - Next.js web request with Supabase auth cookies (browser session), OR
 *  - mobile request with an `Authorization: Bearer <access_token>` header.
 *
 * The returned client respects RLS as the authenticated user.
 */
export async function supabaseForRequest(request: Request) {
  const auth = request.headers.get("authorization");
  if (auth?.startsWith("Bearer ")) {
    const token = auth.slice("Bearer ".length).trim();
    const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
    if (!url || !anon) {
      throw new Error("Missing Supabase env vars");
    }
    return createClient(url, anon, {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
  }
  return createSupabaseServerClient();
}
