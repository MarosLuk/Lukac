import { z } from "zod";
import { PoiCategory } from "./trip";

export const City = z.object({
  id: z.string().uuid(),
  slug: z.string(),
  name: z.string(),
  country: z.string().nullable(),
  lat: z.number(),
  lng: z.number(),
  bbox: z.object({
    south: z.number(),
    west: z.number(),
    north: z.number(),
    east: z.number(),
  }),
  summary: z.string().nullable(),
  highlights: z.array(z.string()).default([]),
});
export type City = z.infer<typeof City>;

export const Poi = z.object({
  id: z.string().uuid(),
  cityId: z.string().uuid(),
  source: z.enum(["osm", "wikivoyage"]),
  name: z.string(),
  category: PoiCategory,
  subcategory: z.string().nullable(),
  lat: z.number(),
  lng: z.number(),
  tags: z.record(z.string(), z.unknown()).default({}),
  openingHours: z.string().nullable(),
  website: z.string().nullable(),
  wikipedia: z.string().nullable(),
  score: z.number(),
  estimatedCostEur: z.number().nullable(),
  estimatedDurationMin: z.number().int().nullable(),
});
export type Poi = z.infer<typeof Poi>;

export const TravelMode = z.enum(["walk", "transit", "taxi", "drive"]);
export type TravelMode = z.infer<typeof TravelMode>;

/** A single routing option for one leg (one stop → next). */
export const TravelOption = z.object({
  mode: TravelMode,
  minutes: z.number().int().nonnegative(),
  distanceKm: z.number().nonnegative(),
  costEur: z.number().nonnegative().default(0),
  /** Human-readable extra info, e.g. "~1 transfer", or a concrete line like "Bus 15E". */
  note: z.string().nullable().default(null),
  /** Data quality: 'routed' = real street network, 'estimated' = heuristic, 'transit_api' = real transit provider. */
  source: z.enum(["routed", "estimated", "transit_api"]).default("estimated"),
});
export type TravelOption = z.infer<typeof TravelOption>;

/**
 * Travel leg between two consecutive stops. `options` lists every mode we
 * could compute; `recommendedIndex` points at the one we picked as default.
 * For back-compat (older drafts) `mode`/`minutes`/`distanceKm` mirror
 * `options[recommendedIndex]` when present.
 */
export const TravelLeg = z.object({
  options: z.array(TravelOption).default([]),
  recommendedIndex: z.number().int().nonnegative().default(0),
  // Mirrors for older clients / readability.
  mode: TravelMode.optional(),
  minutes: z.number().int().nonnegative().optional(),
  distanceKm: z.number().nonnegative().optional(),
});
export type TravelLeg = z.infer<typeof TravelLeg>;

export function recommendedOption(leg: TravelLeg | null): TravelOption | null {
  if (!leg) return null;
  return leg.options[leg.recommendedIndex] ?? leg.options[0] ?? null;
}

export const ItineraryItemStatus = z.enum(["pending", "done", "skipped"]);
export type ItineraryItemStatus = z.infer<typeof ItineraryItemStatus>;

export const ItineraryItem = z.object({
  id: z.string().uuid(),
  itineraryId: z.string().uuid(),
  dayIndex: z.number().int().nonnegative(),
  sortIndex: z.number().int().nonnegative(),
  poiId: z.string().uuid().nullable(),
  title: z.string(),
  category: PoiCategory,
  lat: z.number().nullable(),
  lng: z.number().nullable(),
  startMinutes: z.number().int().min(0).max(60 * 24),
  durationMinutes: z.number().int().positive(),
  costEur: z.number().nonnegative(),
  isMustHave: z.boolean(),
  note: z.string().nullable(),
  travelFromPrev: TravelLeg.nullable(),
  status: ItineraryItemStatus.default("pending"),
  completedAt: z.string().nullable().default(null),
});
export type ItineraryItem = z.infer<typeof ItineraryItem>;

export const ItineraryItemPatch = z.object({
  status: ItineraryItemStatus.optional(),
  note: z.string().max(500).nullable().optional(),
});
export type ItineraryItemPatch = z.infer<typeof ItineraryItemPatch>;

export const Itinerary = z.object({
  id: z.string().uuid(),
  tripId: z.string().uuid(),
  ownerId: z.string().uuid(),
  status: z.enum(["draft", "ready"]),
  totalCost: z.number(),
  generatedAt: z.string(),
  items: z.array(ItineraryItem).default([]),
});
export type Itinerary = z.infer<typeof Itinerary>;

export function formatMinutesOfDay(mins: number): string {
  const h = Math.floor(mins / 60);
  const m = mins % 60;
  return `${h.toString().padStart(2, "0")}:${m.toString().padStart(2, "0")}`;
}

/**
 * Computes which 0-based day of the trip corresponds to today.
 * Returns -1 when today is before the trip, `days` when after.
 */
export function currentDayIndex(
  startDate: string,
  endDate: string,
  today: Date = new Date(),
): number {
  const start = new Date(`${startDate}T00:00:00Z`).getTime();
  const todayUtc = Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate());
  const diffDays = Math.floor((todayUtc - start) / 86_400_000);
  const endDays = Math.floor(
    (new Date(`${endDate}T00:00:00Z`).getTime() - start) / 86_400_000,
  );
  if (diffDays < 0) return -1;
  if (diffDays > endDays) return endDays + 1;
  return diffDays;
}
