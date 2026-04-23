import { NextResponse } from "next/server";
import { supabaseForRequest } from "@/lib/supabase/request";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { rowToTrip, type TripRow } from "@/lib/db/mappers";
import { getCityWithPois } from "@/lib/planning/city";
import { generateItinerary } from "@/lib/planning/generator";
import {
  rowToItinerary,
  type ItineraryItemRow,
  type ItineraryRow,
} from "@/lib/db/itinerary";

// Long-ish: Overpass + Wikivoyage can take 20-40s on cold cache.
export const maxDuration = 60;

export async function POST(
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

  const { data: tripRow } = await supabase
    .from("trips")
    .select("*")
    .eq("id", id)
    .eq("owner_id", user.id)
    .maybeSingle();
  if (!tripRow) {
    return NextResponse.json(
      { ok: false, error: { code: "NOT_FOUND", message: "Trip not found" } },
      { status: 404 },
    );
  }
  const trip = rowToTrip(tripRow as TripRow);

  // City + POI fetch goes via service role (writes to shared cache tables).
  const admin = createSupabaseAdminClient();
  const cityWithPois = await getCityWithPois(admin, trip.destination);
  if (!cityWithPois) {
    return NextResponse.json(
      {
        ok: false,
        error: {
          code: "GEOCODE_FAILED",
          message: `Could not locate "${trip.destination}"`,
        },
      },
      { status: 400 },
    );
  }

  const draft = await generateItinerary(trip, cityWithPois.pois);
  if (draft.items.length === 0) {
    return NextResponse.json(
      {
        ok: false,
        error: {
          code: "NO_POIS",
          message: "No suitable activities found. Try a larger destination or different preferences.",
        },
      },
      { status: 422 },
    );
  }

  // Persist — user session insert so RLS stamps owner_id correctly.
  // Replace previous drafts for this trip to keep "latest" semantics simple.
  await supabase.from("itineraries").delete().eq("trip_id", trip.id);

  const { data: inserted, error: insErr } = await supabase
    .from("itineraries")
    .insert({
      trip_id: trip.id,
      owner_id: user.id,
      status: "ready",
      total_cost: draft.totalCost,
      meta: {
        cityId: cityWithPois.city.id,
        citySummary: cityWithPois.city.summary,
        unplacedMustHaves: draft.unplacedMustHaves,
      },
    })
    .select("*")
    .single();
  if (insErr || !inserted) {
    return NextResponse.json(
      { ok: false, error: { code: "DB_ERROR", message: insErr?.message ?? "Insert failed" } },
      { status: 500 },
    );
  }
  const itineraryId = (inserted as ItineraryRow).id;

  const itemRows = draft.items.map((i) => ({
    itinerary_id: itineraryId,
    day_index: i.dayIndex,
    sort_index: i.sortIndex,
    poi_id: i.poiId,
    title: i.title,
    category: i.category,
    lat: i.lat,
    lng: i.lng,
    start_minutes: i.startMinutes,
    duration_minutes: i.durationMinutes,
    cost_eur: i.costEur,
    is_must_have: i.isMustHave,
    note: i.note,
    travel_from_prev: i.travelFromPrev,
  }));
  const { data: insertedItems, error: itemsErr } = await supabase
    .from("itinerary_items")
    .insert(itemRows)
    .select("*");
  if (itemsErr) {
    return NextResponse.json(
      { ok: false, error: { code: "DB_ERROR", message: itemsErr.message } },
      { status: 500 },
    );
  }

  const itinerary = rowToItinerary(
    inserted as ItineraryRow,
    (insertedItems ?? []) as ItineraryItemRow[],
  );
  return NextResponse.json({ ok: true, data: { itinerary } });
}
