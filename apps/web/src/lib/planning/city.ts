import type { SupabaseClient } from "@supabase/supabase-js";
import type { City, Poi } from "@tp/shared";
import { geocode, slugifyCity } from "./geocode";
import { fetchOsmPois, type RawPoi } from "./overpass";
import { fetchWikivoyage } from "./wikivoyage";

// How long cached POIs are considered fresh. Tweakable; OSM doesn't change
// often and we're running free-tier so err on the side of long caching.
const CACHE_TTL_DAYS = 30;

interface CityRow {
  id: string;
  slug: string;
  name: string;
  country: string | null;
  lat: number;
  lng: number;
  bbox_south: number;
  bbox_west: number;
  bbox_north: number;
  bbox_east: number;
  summary: string | null;
  highlights: string[] | null;
  fetched_at: string;
}

interface PoiRow {
  id: string;
  city_id: string;
  source: string;
  source_ref: string;
  name: string;
  category: string;
  subcategory: string | null;
  lat: number;
  lng: number;
  tags: Record<string, unknown>;
  opening_hours: string | null;
  website: string | null;
  wikipedia: string | null;
  score: number;
  estimated_cost_eur: number | null;
  estimated_duration_min: number | null;
  fetched_at: string;
}

function rowToCity(row: CityRow): City {
  return {
    id: row.id,
    slug: row.slug,
    name: row.name,
    country: row.country,
    lat: row.lat,
    lng: row.lng,
    bbox: {
      south: row.bbox_south,
      west: row.bbox_west,
      north: row.bbox_north,
      east: row.bbox_east,
    },
    summary: row.summary,
    highlights: row.highlights ?? [],
  };
}

function rowToPoi(row: PoiRow): Poi {
  return {
    id: row.id,
    cityId: row.city_id,
    source: row.source as Poi["source"],
    name: row.name,
    category: row.category as Poi["category"],
    subcategory: row.subcategory,
    lat: row.lat,
    lng: row.lng,
    tags: row.tags,
    openingHours: row.opening_hours,
    website: row.website,
    wikipedia: row.wikipedia,
    score: row.score,
    estimatedCostEur: row.estimated_cost_eur != null ? Number(row.estimated_cost_eur) : null,
    estimatedDurationMin: row.estimated_duration_min,
  };
}

/** Returns the city + its POIs, fetching + caching if not already in DB or stale. */
export async function getCityWithPois(
  supabase: SupabaseClient,
  destination: string,
): Promise<{ city: City; pois: Poi[] } | null> {
  // 1. Geocode first so we have a canonical slug before looking up cache.
  const geo = await geocode(destination);
  if (!geo) return null;
  const slug = slugifyCity(geo.city, geo.country);

  // 2. Look up existing city row.
  const { data: existing } = await supabase
    .from("cities")
    .select("*")
    .eq("slug", slug)
    .maybeSingle();

  let cityRow: CityRow | null = existing as CityRow | null;
  const now = Date.now();
  const stale =
    !cityRow ||
    now - new Date(cityRow.fetched_at).getTime() > CACHE_TTL_DAYS * 864e5;

  if (stale) {
    const wiki = await fetchWikivoyage(geo.city).catch(() => ({
      summary: null,
      highlights: [] as string[],
    }));
    const upsertPayload = {
      slug,
      name: geo.city,
      country: geo.country,
      lat: geo.lat,
      lng: geo.lng,
      bbox_south: geo.bbox.south,
      bbox_west: geo.bbox.west,
      bbox_north: geo.bbox.north,
      bbox_east: geo.bbox.east,
      summary: wiki.summary,
      highlights: wiki.highlights,
      fetched_at: new Date().toISOString(),
    };
    const { data: upserted, error } = await supabase
      .from("cities")
      .upsert(upsertPayload, { onConflict: "slug" })
      .select("*")
      .single();
    if (error) throw error;
    cityRow = upserted as CityRow;

    // Refresh POIs whenever city is (re)fetched.
    const raw = await fetchOsmPois(geo.bbox);
    if (raw.length) await upsertPois(supabase, cityRow.id, raw);
  }

  if (!cityRow) return null;

  const { data: poiRows, error: poiErr } = await supabase
    .from("pois")
    .select("*")
    .eq("city_id", cityRow.id)
    .order("score", { ascending: false })
    .limit(300);
  if (poiErr) throw poiErr;

  return {
    city: rowToCity(cityRow),
    pois: ((poiRows ?? []) as PoiRow[]).map(rowToPoi),
  };
}

async function upsertPois(
  supabase: SupabaseClient,
  cityId: string,
  raw: RawPoi[],
): Promise<void> {
  const rows = raw.map((p) => ({
    city_id: cityId,
    source: "osm",
    source_ref: p.sourceRef,
    name: p.name,
    category: p.category,
    subcategory: p.subcategory,
    lat: p.lat,
    lng: p.lng,
    tags: p.tags,
    opening_hours: p.openingHours,
    website: p.website,
    wikipedia: p.wikipedia,
    score: p.score,
    estimated_cost_eur: p.estimatedCostEur,
    estimated_duration_min: p.estimatedDurationMin,
    fetched_at: new Date().toISOString(),
  }));

  // Chunk to keep payloads reasonable (pg default row limit is generous but keep it tidy).
  const chunkSize = 200;
  for (let i = 0; i < rows.length; i += chunkSize) {
    const chunk = rows.slice(i, i + chunkSize);
    const { error } = await supabase
      .from("pois")
      .upsert(chunk, { onConflict: "city_id,source,source_ref" });
    if (error) throw error;
  }
}
