import { NextResponse } from "next/server";
import { TripUpdateInput } from "@tp/shared";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { supabaseForRequest } from "@/lib/supabase/request";
import { rowToTrip, type TripRow } from "@/lib/db/mappers";
import {
  rowToItinerary,
  type ItineraryItemRow,
  type ItineraryRow,
} from "@/lib/db/itinerary";

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json(
      { ok: false, error: { code: "UNAUTHENTICATED", message: "Sign in required" } },
      { status: 401 },
    );
  }

  const { data: tripRow, error: tripErr } = await supabase
    .from("trips")
    .select("*")
    .eq("id", id)
    .eq("owner_id", user.id)
    .maybeSingle();
  if (tripErr) {
    return NextResponse.json(
      { ok: false, error: { code: "DB_ERROR", message: tripErr.message } },
      { status: 500 },
    );
  }
  if (!tripRow) {
    return NextResponse.json(
      { ok: false, error: { code: "NOT_FOUND", message: "Trip not found" } },
      { status: 404 },
    );
  }

  const { data: itinRow } = await supabase
    .from("itineraries")
    .select("*")
    .eq("trip_id", id)
    .order("generated_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  let itinerary = null;
  if (itinRow) {
    const { data: items } = await supabase
      .from("itinerary_items")
      .select("*")
      .eq("itinerary_id", (itinRow as ItineraryRow).id)
      .order("day_index", { ascending: true })
      .order("sort_index", { ascending: true });
    itinerary = rowToItinerary(
      itinRow as ItineraryRow,
      (items ?? []) as ItineraryItemRow[],
    );
  }

  return NextResponse.json({
    ok: true,
    data: { trip: rowToTrip(tripRow as TripRow), itinerary },
  });
}

export async function PATCH(
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

  const json = await request.json().catch(() => null);
  const parsed = TripUpdateInput.safeParse(json);
  if (!parsed.success) {
    return NextResponse.json(
      {
        ok: false,
        error: {
          code: "VALIDATION_ERROR",
          message: "Invalid patch",
          details: parsed.error.flatten(),
        },
      },
      { status: 400 },
    );
  }
  const input = parsed.data;

  const updates: Record<string, unknown> = {};
  if (input.destination !== undefined) updates.destination = input.destination;
  if (input.startDate !== undefined) updates.start_date = input.startDate;
  if (input.endDate !== undefined) updates.end_date = input.endDate;
  if (input.currency !== undefined) updates.currency = input.currency;
  if (input.totalBudget !== undefined) updates.total_budget = input.totalBudget;
  if (input.travelers !== undefined) updates.travelers = input.travelers;
  if (input.style !== undefined) updates.style = input.style;
  if (input.preferredCategories !== undefined)
    updates.preferred_categories = input.preferredCategories;
  if (input.mustHaves !== undefined) updates.must_haves = input.mustHaves;
  if (input.foodPreferences !== undefined)
    updates.food_preferences = input.foodPreferences;
  if (input.notes !== undefined) updates.notes = input.notes;

  if (Object.keys(updates).length === 0) {
    return NextResponse.json(
      { ok: false, error: { code: "EMPTY_PATCH", message: "Nothing to update" } },
      { status: 400 },
    );
  }

  const { data, error } = await supabase
    .from("trips")
    .update(updates)
    .eq("id", id)
    .eq("owner_id", user.id)
    .select("*")
    .single();

  if (error || !data) {
    const missing = !data && !error;
    return NextResponse.json(
      {
        ok: false,
        error: {
          code: missing ? "NOT_FOUND" : "DB_ERROR",
          message: error?.message ?? "Not found",
        },
      },
      { status: missing ? 404 : 500 },
    );
  }

  return NextResponse.json({
    ok: true,
    data: { trip: rowToTrip(data as TripRow) },
  });
}
