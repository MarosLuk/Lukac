import type { PoiCategory } from "@tp/shared";

// OpenStreetMap Overpass API — free, public, rate-limited.
// We query for high-signal tourism + food tags inside a bbox.

const ENDPOINT = "https://overpass-api.de/api/interpreter";
const UA = "travel-planner-mvp/0.1 (local-dev)";

export interface OverpassElement {
  type: "node" | "way" | "relation";
  id: number;
  lat?: number;
  lon?: number;
  center?: { lat: number; lon: number };
  tags?: Record<string, string>;
}

export interface RawPoi {
  sourceRef: string;
  name: string;
  category: PoiCategory;
  subcategory: string | null;
  lat: number;
  lng: number;
  tags: Record<string, string>;
  openingHours: string | null;
  website: string | null;
  wikipedia: string | null;
  score: number;
  estimatedCostEur: number | null;
  estimatedDurationMin: number | null;
}

export async function fetchOsmPois(bbox: {
  south: number;
  west: number;
  north: number;
  east: number;
}): Promise<RawPoi[]> {
  const { south, west, north, east } = bbox;
  // `nwr` = nodes + ways + relations. We filter by tag and return centers for ways/relations.
  const query = `
[out:json][timeout:45];
(
  nwr["tourism"~"^(attraction|museum|gallery|viewpoint|artwork|theme_park|zoo|aquarium)$"](${south},${west},${north},${east});
  nwr["historic"~"^(castle|monument|memorial|ruins|archaeological_site|fort|monastery|church)$"](${south},${west},${north},${east});
  nwr["amenity"~"^(restaurant|cafe|bar|pub|biergarten|ice_cream)$"](${south},${west},${north},${east});
  nwr["leisure"~"^(park|garden|nature_reserve)$"](${south},${west},${north},${east});
);
out center tags 400;
  `.trim();

  const res = await fetch(ENDPOINT, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      "User-Agent": UA,
    },
    body: new URLSearchParams({ data: query }).toString(),
  });
  if (!res.ok) throw new Error(`Overpass ${res.status}: ${await res.text()}`);

  const payload = (await res.json()) as { elements: OverpassElement[] };
  const out: RawPoi[] = [];

  for (const el of payload.elements) {
    const tags = el.tags ?? {};
    const name = tags.name ?? tags["name:en"];
    if (!name) continue;

    const lat = el.lat ?? el.center?.lat;
    const lon = el.lon ?? el.center?.lon;
    if (lat == null || lon == null) continue;

    const classified = classify(tags);
    if (!classified) continue;

    out.push({
      sourceRef: `${el.type}/${el.id}`,
      name,
      category: classified.category,
      subcategory: classified.subcategory,
      lat,
      lng: lon,
      tags,
      openingHours: tags.opening_hours ?? null,
      website: tags.website ?? tags["contact:website"] ?? null,
      wikipedia: tags.wikipedia ?? null,
      score: scorePoi(tags, classified.category),
      estimatedCostEur: classified.estimatedCostEur,
      estimatedDurationMin: classified.estimatedDurationMin,
    });
  }

  // Dedup: same (name, rounded coord) — OSM often has multi-geometry duplicates.
  const seen = new Map<string, RawPoi>();
  for (const p of out) {
    const key = `${p.name.toLowerCase()}@${p.lat.toFixed(3)},${p.lng.toFixed(3)}`;
    const prev = seen.get(key);
    if (!prev || prev.score < p.score) seen.set(key, p);
  }
  return Array.from(seen.values()).sort((a, b) => b.score - a.score);
}

interface Classification {
  category: PoiCategory;
  subcategory: string | null;
  estimatedCostEur: number | null;
  estimatedDurationMin: number | null;
}

function classify(tags: Record<string, string>): Classification | null {
  const tourism = tags.tourism;
  const historic = tags.historic;
  const amenity = tags.amenity;
  const leisure = tags.leisure;

  if (tourism === "museum" || tourism === "gallery") {
    return {
      category: "museum",
      subcategory: tourism,
      estimatedCostEur: 12,
      estimatedDurationMin: 90,
    };
  }
  if (tourism === "viewpoint") {
    return {
      category: "viewpoint",
      subcategory: "viewpoint",
      estimatedCostEur: 0,
      estimatedDurationMin: 30,
    };
  }
  if (tourism === "attraction" || tourism === "artwork") {
    return {
      category: "sightseeing",
      subcategory: tourism,
      estimatedCostEur: null,
      estimatedDurationMin: 45,
    };
  }
  if (tourism === "theme_park" || tourism === "zoo" || tourism === "aquarium") {
    return {
      category: "experience",
      subcategory: tourism,
      estimatedCostEur: 25,
      estimatedDurationMin: 180,
    };
  }
  if (historic) {
    return {
      category: "sightseeing",
      subcategory: historic,
      estimatedCostEur: historic === "castle" || historic === "monastery" ? 10 : 0,
      estimatedDurationMin: 60,
    };
  }
  if (amenity === "restaurant" || amenity === "pub" || amenity === "biergarten") {
    return {
      category: "food",
      subcategory: amenity,
      estimatedCostEur: 20,
      estimatedDurationMin: 75,
    };
  }
  if (amenity === "cafe" || amenity === "ice_cream") {
    return {
      category: "food",
      subcategory: amenity,
      estimatedCostEur: 7,
      estimatedDurationMin: 30,
    };
  }
  if (amenity === "bar") {
    return {
      category: "nightlife",
      subcategory: amenity,
      estimatedCostEur: 15,
      estimatedDurationMin: 90,
    };
  }
  if (leisure) {
    return {
      category: "nature",
      subcategory: leisure,
      estimatedCostEur: 0,
      estimatedDurationMin: 60,
    };
  }
  return null;
}

// Rough popularity heuristic from OSM tag richness. 0..1.
function scorePoi(tags: Record<string, string>, category: PoiCategory): number {
  let s = 0;
  if (tags.wikipedia || tags.wikidata) s += 0.5;
  if (tags.website || tags["contact:website"]) s += 0.1;
  if (tags.opening_hours) s += 0.1;
  if (tags.image || tags["wikimedia_commons"]) s += 0.1;
  if (tags.stars) s += 0.1;
  if (tags.heritage || tags["heritage:operator"]) s += 0.2;
  if (tags.fee === "no") s += 0.05;

  // Category base weight so museums/sights rank above random cafes.
  const base: Record<PoiCategory, number> = {
    sightseeing: 0.25,
    museum: 0.25,
    viewpoint: 0.2,
    experience: 0.2,
    nature: 0.15,
    food: 0.05,
    nightlife: 0.05,
    shopping: 0.05,
    other: 0,
  };
  s += base[category] ?? 0;

  return Math.min(1, s);
}
