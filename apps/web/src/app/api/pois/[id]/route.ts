import { NextResponse } from "next/server";
import { supabaseForRequest } from "@/lib/supabase/request";

export async function GET(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  const supabase = await supabaseForRequest(request);
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json(
      { ok: false, error: { code: "UNAUTHENTICATED", message: "Sign in required" } },
      { status: 401 },
    );
  }

  // POIs are world-readable reference data (RLS "pois_read_all" = true),
  // so any signed-in user can fetch them. The auth check above just keeps
  // the endpoint private for basic abuse protection.
  const { data, error } = await supabase
    .from("pois")
    .select(
      "id,name,category,subcategory,lat,lng,website,wikipedia,opening_hours,estimated_cost_eur,estimated_duration_min,tags",
    )
    .eq("id", id)
    .maybeSingle();
  if (error) {
    return NextResponse.json(
      { ok: false, error: { code: "DB_ERROR", message: error.message } },
      { status: 500 },
    );
  }
  if (!data) {
    return NextResponse.json(
      { ok: false, error: { code: "NOT_FOUND", message: "POI not found" } },
      { status: 404 },
    );
  }

  return NextResponse.json({ ok: true, data: { poi: data } });
}
