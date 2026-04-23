import { supabase } from "./supabase";

export interface PoiDetail {
  id: string;
  name: string;
  category: string;
  subcategory: string | null;
  lat: number;
  lng: number;
  website: string | null;
  wikipedia: string | null;
  opening_hours: string | null;
  estimated_cost_eur: number | null;
  estimated_duration_min: number | null;
  tags: Record<string, string>;
}

export async function getPoi(id: string): Promise<PoiDetail | null> {
  const { data, error } = await supabase
    .from("pois")
    .select(
      "id,name,category,subcategory,lat,lng,website,wikipedia,opening_hours,estimated_cost_eur,estimated_duration_min,tags",
    )
    .eq("id", id)
    .maybeSingle();
  if (error) throw error;
  return (data as PoiDetail | null) ?? null;
}

/**
 * Pick the best URL to open in the in-app WebView:
 *   - Official website (tags.website / contact:website) if present
 *   - Wikipedia article (translated from OSM `wikipedia=lang:Title`)
 *   - Wikivoyage search as a generic fallback
 */
export function previewUrl(poi: PoiDetail): string {
  if (poi.website) return poi.website;
  if (poi.wikipedia) return wikipediaUrl(poi.wikipedia);
  return `https://en.wikivoyage.org/wiki/Special:Search?search=${encodeURIComponent(poi.name)}`;
}

function wikipediaUrl(value: string): string {
  if (/^https?:\/\//.test(value)) return value;
  const [lang, ...rest] = value.split(":");
  const page = encodeURIComponent(rest.join(":").replace(/ /g, "_"));
  return `https://${lang || "en"}.wikipedia.org/wiki/${page}`;
}
