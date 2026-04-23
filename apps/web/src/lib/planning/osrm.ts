// OSRM public demo server. Free, no auth, fair-use only. Supports foot, bike,
// car; no transit (OSRM doesn't do it by design). We use `foot` and `driving`.
// Docs: https://project-osrm.org/docs/v5.24.0/api

const UA = "travel-planner-mvp/0.1 (local-dev)";

const OSRM_BASE = "https://router.project-osrm.org/route/v1";

export type OsrmProfile = "foot" | "driving" | "bike";

export interface OsrmLegResult {
  minutes: number;
  distanceKm: number;
}

/** Returns `null` on any failure so callers can fall back to a heuristic. */
export async function route(
  profile: OsrmProfile,
  from: { lat: number; lng: number },
  to: { lat: number; lng: number },
): Promise<OsrmLegResult | null> {
  const url = `${OSRM_BASE}/${profile}/${from.lng},${from.lat};${to.lng},${to.lat}?overview=false&alternatives=false&steps=false`;
  try {
    const res = await fetch(url, { headers: { "User-Agent": UA } });
    if (!res.ok) return null;
    const json = (await res.json()) as {
      code: string;
      routes?: Array<{ distance: number; duration: number }>;
    };
    if (json.code !== "Ok") return null;
    const first = json.routes?.[0];
    if (!first) return null;
    return {
      minutes: Math.max(1, Math.round(first.duration / 60)),
      distanceKm: Math.round((first.distance / 1000) * 10) / 10,
    };
  } catch {
    return null;
  }
}
