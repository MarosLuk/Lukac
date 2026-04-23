import { NextResponse } from "next/server";
import { TripCreateInput } from "@tp/shared";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { rowToTrip, type TripRow } from "@/lib/db/mappers";

export async function GET() {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ ok: false, error: { code: "UNAUTHENTICATED", message: "Sign in required" } }, { status: 401 });
  }

  const { data, error } = await supabase
    .from("trips")
    .select("*")
    .eq("owner_id", user.id)
    .order("start_date", { ascending: false });

  if (error) {
    return NextResponse.json({ ok: false, error: { code: "DB_ERROR", message: error.message } }, { status: 500 });
  }

  return NextResponse.json({ ok: true, data: (data as TripRow[]).map(rowToTrip) });
}

export async function POST(request: Request) {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ ok: false, error: { code: "UNAUTHENTICATED", message: "Sign in required" } }, { status: 401 });
  }

  const json = await request.json().catch(() => null);
  const parsed = TripCreateInput.safeParse(json);
  if (!parsed.success) {
    return NextResponse.json(
      { ok: false, error: { code: "VALIDATION_ERROR", message: "Invalid input", details: parsed.error.flatten() } },
      { status: 400 },
    );
  }

  const input = parsed.data;
  const { data, error } = await supabase
    .from("trips")
    .insert({
      owner_id: user.id,
      destination: input.destination,
      start_date: input.startDate,
      end_date: input.endDate,
      currency: input.currency,
      total_budget: input.totalBudget,
      travelers: input.travelers,
      style: input.style,
      preferred_categories: input.preferredCategories,
      must_haves: input.mustHaves,
      food_preferences: input.foodPreferences,
      notes: input.notes ?? null,
    })
    .select("*")
    .single();

  if (error || !data) {
    return NextResponse.json({ ok: false, error: { code: "DB_ERROR", message: error?.message ?? "Insert failed" } }, { status: 500 });
  }

  return NextResponse.json({ ok: true, data: rowToTrip(data as TripRow) }, { status: 201 });
}
