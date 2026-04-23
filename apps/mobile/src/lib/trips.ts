import { supabase } from "./supabase";
import type {
  Trip,
  PoiCategory,
  MustHaveItem,
  Itinerary,
  ItineraryItem,
  ItineraryItemStatus,
  TravelLeg,
  FoodPreferences,
} from "@tp/shared";
import { DEFAULT_FOOD_PREFERENCES } from "@tp/shared";

interface TripRow {
  id: string;
  owner_id: string;
  destination: string;
  start_date: string;
  end_date: string;
  currency: string;
  total_budget: number;
  travelers: number;
  style: string;
  preferred_categories: string[];
  must_haves: MustHaveItem[];
  food_preferences: FoodPreferences | null;
  notes: string | null;
  created_at: string;
  updated_at: string;
}

function rowToTrip(row: TripRow): Trip {
  return {
    id: row.id,
    ownerId: row.owner_id,
    destination: row.destination,
    startDate: row.start_date,
    endDate: row.end_date,
    currency: row.currency as Trip["currency"],
    totalBudget: Number(row.total_budget),
    travelers: row.travelers,
    style: row.style as Trip["style"],
    preferredCategories: row.preferred_categories as PoiCategory[],
    mustHaves: row.must_haves ?? [],
    foodPreferences: row.food_preferences ?? DEFAULT_FOOD_PREFERENCES,
    notes: row.notes,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export async function listTrips(): Promise<Trip[]> {
  const { data, error } = await supabase
    .from("trips")
    .select("*")
    .order("start_date", { ascending: false });
  if (error) throw error;
  return ((data ?? []) as TripRow[]).map(rowToTrip);
}

interface ItineraryRow {
  id: string;
  trip_id: string;
  owner_id: string;
  status: string;
  total_cost: number;
  generated_at: string;
}

interface ItineraryItemRow {
  id: string;
  itinerary_id: string;
  day_index: number;
  sort_index: number;
  poi_id: string | null;
  title: string;
  category: string;
  lat: number | null;
  lng: number | null;
  start_minutes: number;
  duration_minutes: number;
  cost_eur: number;
  is_must_have: boolean;
  note: string | null;
  travel_from_prev: TravelLeg | null;
  status: string;
  completed_at: string | null;
}

export interface TripWithItinerary {
  trip: Trip;
  itinerary: Itinerary | null;
}

export async function getTripWithItinerary(
  tripId: string,
): Promise<TripWithItinerary | null> {
  const { data: tripRow, error: tripErr } = await supabase
    .from("trips")
    .select("*")
    .eq("id", tripId)
    .maybeSingle();
  if (tripErr) throw tripErr;
  if (!tripRow) return null;
  const trip = rowToTrip(tripRow as TripRow);

  const { data: itinRow } = await supabase
    .from("itineraries")
    .select("*")
    .eq("trip_id", tripId)
    .order("generated_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (!itinRow) return { trip, itinerary: null };

  const { data: items } = await supabase
    .from("itinerary_items")
    .select("*")
    .eq("itinerary_id", (itinRow as ItineraryRow).id)
    .order("day_index", { ascending: true })
    .order("sort_index", { ascending: true });

  const itinerary: Itinerary = {
    id: (itinRow as ItineraryRow).id,
    tripId: (itinRow as ItineraryRow).trip_id,
    ownerId: (itinRow as ItineraryRow).owner_id,
    status: (itinRow as ItineraryRow).status as Itinerary["status"],
    totalCost: Number((itinRow as ItineraryRow).total_cost),
    generatedAt: (itinRow as ItineraryRow).generated_at,
    items: ((items ?? []) as ItineraryItemRow[]).map(
      (row): ItineraryItem => ({
        id: row.id,
        itineraryId: row.itinerary_id,
        dayIndex: row.day_index,
        sortIndex: row.sort_index,
        poiId: row.poi_id,
        title: row.title,
        category: row.category as PoiCategory,
        lat: row.lat,
        lng: row.lng,
        startMinutes: row.start_minutes,
        durationMinutes: row.duration_minutes,
        costEur: Number(row.cost_eur),
        isMustHave: row.is_must_have,
        note: row.note,
        travelFromPrev: row.travel_from_prev,
        status: row.status as ItineraryItemStatus,
        completedAt: row.completed_at,
      }),
    ),
  };

  return { trip, itinerary };
}

export async function patchItineraryItem(
  itemId: string,
  patch: { status?: ItineraryItemStatus; note?: string | null },
): Promise<ItineraryItem> {
  const updates: Record<string, unknown> = {};
  if (patch.status !== undefined) {
    updates.status = patch.status;
    updates.completed_at =
      patch.status === "done" ? new Date().toISOString() : null;
  }
  if (patch.note !== undefined) updates.note = patch.note;

  const { data, error } = await supabase
    .from("itinerary_items")
    .update(updates)
    .eq("id", itemId)
    .select("*")
    .single();
  if (error || !data) throw error ?? new Error("Update failed");
  const row = data as ItineraryItemRow;
  return {
    id: row.id,
    itineraryId: row.itinerary_id,
    dayIndex: row.day_index,
    sortIndex: row.sort_index,
    poiId: row.poi_id,
    title: row.title,
    category: row.category as PoiCategory,
    lat: row.lat,
    lng: row.lng,
    startMinutes: row.start_minutes,
    durationMinutes: row.duration_minutes,
    costEur: Number(row.cost_eur),
    isMustHave: row.is_must_have,
    note: row.note,
    travelFromPrev: row.travel_from_prev,
    status: row.status as ItineraryItemStatus,
    completedAt: row.completed_at,
  };
}
