import type {
  Itinerary,
  ItineraryItem,
  ItineraryItemStatus,
  PoiCategory,
  TravelLeg,
} from "@tp/shared";

export interface ItineraryRow {
  id: string;
  trip_id: string;
  owner_id: string;
  status: string;
  total_cost: number;
  generated_at: string;
  meta: Record<string, unknown>;
}

export interface ItineraryItemRow {
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

export function rowToItineraryItem(row: ItineraryItemRow): ItineraryItem {
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

export function rowToItinerary(
  row: ItineraryRow,
  items: ItineraryItemRow[],
): Itinerary {
  return {
    id: row.id,
    tripId: row.trip_id,
    ownerId: row.owner_id,
    status: row.status as Itinerary["status"],
    totalCost: Number(row.total_cost),
    generatedAt: row.generated_at,
    items: items.map(rowToItineraryItem),
  };
}
