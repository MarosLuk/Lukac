// Nominatim geocoder. Free, no key. Must set a real User-Agent per their ToS,
// and we must respect their 1 req/s rate limit (fine for on-demand trip creation).

const UA = "travel-planner-mvp/0.1 (local-dev)";

export interface GeocodeResult {
  displayName: string;
  lat: number;
  lng: number;
  /** south, west, north, east */
  bbox: { south: number; west: number; north: number; east: number };
  country: string | null;
  city: string;
}

export async function geocode(destination: string): Promise<GeocodeResult | null> {
  const url = new URL("https://nominatim.openstreetmap.org/search");
  url.searchParams.set("q", destination);
  url.searchParams.set("format", "jsonv2");
  url.searchParams.set("limit", "1");
  url.searchParams.set("addressdetails", "1");
  url.searchParams.set("accept-language", "en");

  const res = await fetch(url, {
    headers: { "User-Agent": UA, Accept: "application/json" },
  });
  if (!res.ok) throw new Error(`Nominatim ${res.status}`);

  const arr = (await res.json()) as Array<{
    lat: string;
    lon: string;
    display_name: string;
    boundingbox: [string, string, string, string]; // [south, north, west, east]
    address?: { country?: string; city?: string; town?: string; village?: string };
    name?: string;
  }>;

  const hit = arr[0];
  if (!hit) return null;

  const [south, north, west, east] = hit.boundingbox.map(Number) as [
    number,
    number,
    number,
    number,
  ];
  const addr = hit.address ?? {};
  const city = addr.city ?? addr.town ?? addr.village ?? hit.name ?? destination;

  return {
    displayName: hit.display_name,
    lat: Number(hit.lat),
    lng: Number(hit.lon),
    bbox: { south, west, north, east },
    country: addr.country ?? null,
    city,
  };
}

export function slugifyCity(city: string, country: string | null): string {
  const base = [city, country].filter(Boolean).join(" ");
  return base
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}
