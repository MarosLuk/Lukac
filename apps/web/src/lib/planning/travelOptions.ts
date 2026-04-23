import type { TravelLeg, TravelOption } from "@tp/shared";
import { route } from "./osrm";

// Rough European-city defaults. Override later per-city (config.toml or a
// `cities.transport_profile` column) once we have data.
const TRANSIT_FARE_EUR = 2; // single ride
const TAXI_BASE_EUR = 3.5;
const TAXI_PER_KM_EUR = 1.3;
const TAXI_PER_MIN_EUR = 0.2; // crude time surcharge (idling in traffic)

/** Walking speed fallback when OSRM is down (4.5 km/h → ~13.3 min/km). */
const MIN_PER_KM_WALK = 13.3;
/** Driving speed fallback — urban average 30 km/h → 2 min/km. */
const MIN_PER_KM_DRIVE = 2;

export interface LatLng {
  lat: number;
  lng: number;
}

/**
 * Compute every reasonable travel option between two stops.
 * Network-bound (OSRM) — run once per leg during itinerary generation, then persisted.
 *
 * MHD/transit line numbers are a separate problem: OSM has stops but no
 * timetables. We emit a best-effort estimate and flag source="estimated".
 * A future hook reads GOOGLE_MAPS_API_KEY and, if present, calls Directions
 * to replace the transit entry with real line numbers (source="transit_api").
 */
export async function buildTravelOptions(from: LatLng, to: LatLng): Promise<TravelLeg> {
  const [walk, drive] = await Promise.all([
    route("foot", from, to),
    route("driving", from, to),
  ]);

  const distanceKm =
    walk?.distanceKm ?? drive?.distanceKm ?? haversineKm(from, to);
  const walkMin = walk?.minutes ?? Math.max(5, Math.round(distanceKm * MIN_PER_KM_WALK));
  const driveMin = drive?.minutes ?? Math.max(3, Math.round(distanceKm * MIN_PER_KM_DRIVE));

  const walkSource: TravelOption["source"] = walk ? "routed" : "estimated";
  const driveSource: TravelOption["source"] = drive ? "routed" : "estimated";

  const options: TravelOption[] = [];

  options.push({
    mode: "walk",
    minutes: walkMin,
    distanceKm,
    costEur: 0,
    note: null,
    source: walkSource,
  });

  // Transit: only useful past ~1km. Assume slightly slower than driving in
  // city traffic (stops + transfer buffer). Coverage varies — we flag as
  // estimate until replaced by a real transit API.
  if (distanceKm >= 1) {
    const transitMin = Math.max(10, Math.round(driveMin * 1.3) + 6); // +6 min waiting/transfer
    options.push({
      mode: "transit",
      minutes: transitMin,
      distanceKm,
      costEur: TRANSIT_FARE_EUR,
      note: "Estimate — real line numbers require a transit API (e.g. Google Directions).",
      source: "estimated",
    });
  }

  // Taxi/rideshare: practical past ~500m (nobody calls a cab for 3 blocks).
  if (distanceKm >= 0.5) {
    const taxiCost =
      TAXI_BASE_EUR + distanceKm * TAXI_PER_KM_EUR + driveMin * TAXI_PER_MIN_EUR;
    options.push({
      mode: "taxi",
      minutes: driveMin + 4, // +4 min pickup
      distanceKm,
      costEur: Math.round(taxiCost * 10) / 10,
      note: null,
      source: driveSource,
    });
  }

  const recommendedIndex = pickRecommended(options, distanceKm);
  const rec = options[recommendedIndex]!;
  return {
    options,
    recommendedIndex,
    mode: rec.mode,
    minutes: rec.minutes,
    distanceKm: rec.distanceKm,
  };
}

/**
 * Heuristic:
 *  - < 1.5 km → walk
 *  - 1.5–6 km → transit if available, else taxi
 *  - > 6 km → taxi (fastest for 2-traveler trip where transit transfer pain > money)
 * Tweakable later based on trip.style and trip.travelers.
 */
function pickRecommended(options: TravelOption[], distanceKm: number): number {
  const findIdx = (mode: TravelOption["mode"]) => options.findIndex((o) => o.mode === mode);
  const walk = findIdx("walk");
  const transit = findIdx("transit");
  const taxi = findIdx("taxi");
  if (distanceKm < 1.5) return walk;
  if (distanceKm < 6 && transit >= 0) return transit;
  if (taxi >= 0) return taxi;
  return walk;
}

function haversineKm(a: LatLng, b: LatLng): number {
  const R = 6371;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return Math.round(2 * R * Math.asin(Math.sqrt(s)) * 10) / 10;
}
