"use client";

import { useEffect, useState } from "react";

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

export function PoiPreviewModal({
  poiId,
  onClose,
}: {
  poiId: string | null;
  onClose: () => void;
}) {
  const [poi, setPoi] = useState<PoiDetail | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [iframeFailed, setIframeFailed] = useState(false);

  useEffect(() => {
    if (!poiId) {
      setPoi(null);
      setError(null);
      setIframeFailed(false);
      return;
    }
    setLoading(true);
    setError(null);
    fetch(`/api/pois/${poiId}`)
      .then(async (r) => {
        const body = await r.json();
        if (!r.ok || !body.ok) {
          throw new Error(body?.error?.message ?? `HTTP ${r.status}`);
        }
        setPoi(body.data.poi as PoiDetail);
      })
      .catch((e) => setError(e instanceof Error ? e.message : "Load failed"))
      .finally(() => setLoading(false));
  }, [poiId]);

  useEffect(() => {
    if (!poiId) return;
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [poiId, onClose]);

  if (!poiId) return null;

  const previewUrl = poi ? pickPreviewUrl(poi) : null;
  const osmUrl = poi
    ? `https://www.openstreetmap.org/?mlat=${poi.lat}&mlon=${poi.lng}#map=18/${poi.lat}/${poi.lng}`
    : null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-stretch justify-end bg-slate-900/40"
      onClick={onClose}
    >
      <div
        className="flex h-full w-full max-w-2xl flex-col bg-white shadow-xl"
        onClick={(e) => e.stopPropagation()}
      >
        <header className="flex items-center justify-between border-b border-slate-200 px-5 py-3">
          <div className="min-w-0">
            <h2 className="truncate text-lg font-semibold">
              {poi?.name ?? (loading ? "Loading…" : "POI")}
            </h2>
            {poi && (
              <p className="text-xs text-slate-500">
                {poi.category}
                {poi.subcategory ? ` · ${poi.subcategory}` : ""}
                {poi.estimated_cost_eur != null ? ` · ~€${poi.estimated_cost_eur}` : ""}
              </p>
            )}
          </div>
          <button
            onClick={onClose}
            className="rounded-md border border-slate-200 px-2 py-1 text-sm text-slate-600 hover:bg-slate-50"
          >
            Close
          </button>
        </header>

        {error && <div className="p-4 text-sm text-red-600">{error}</div>}

        {poi && (
          <div className="flex-1 overflow-hidden">
            {previewUrl && !iframeFailed ? (
              <iframe
                src={previewUrl}
                title={poi.name}
                className="h-full w-full border-0"
                referrerPolicy="no-referrer"
                sandbox="allow-scripts allow-forms allow-same-origin allow-popups allow-popups-to-escape-sandbox"
                onError={() => setIframeFailed(true)}
              />
            ) : (
              <div className="space-y-4 p-5 text-sm text-slate-700">
                <p>
                  No preview available inline
                  {iframeFailed ? " (website refused to embed)" : ""}.
                </p>
                <ul className="space-y-2">
                  {poi.website && (
                    <li>
                      <LinkRow label="Official website" url={poi.website} />
                    </li>
                  )}
                  {poi.wikipedia && (
                    <li>
                      <LinkRow
                        label="Wikipedia"
                        url={wikipediaUrl(poi.wikipedia)}
                      />
                    </li>
                  )}
                  {osmUrl && (
                    <li>
                      <LinkRow label="Open in OpenStreetMap" url={osmUrl} />
                    </li>
                  )}
                </ul>
                {poi.opening_hours && (
                  <div className="rounded-md bg-slate-50 p-3 text-xs text-slate-600">
                    <span className="font-semibold">Opening hours:</span> {poi.opening_hours}
                  </div>
                )}
              </div>
            )}
          </div>
        )}

        <footer className="border-t border-slate-200 bg-slate-50 px-5 py-3 text-xs text-slate-500">
          {previewUrl ? (
            <a
              href={previewUrl}
              target="_blank"
              rel="noreferrer"
              className="font-medium text-brand-600 hover:underline"
            >
              Open full page ↗
            </a>
          ) : (
            "No embedded preview available"
          )}
        </footer>
      </div>
    </div>
  );
}

function LinkRow({ label, url }: { label: string; url: string }) {
  return (
    <a
      href={url}
      target="_blank"
      rel="noreferrer"
      className="flex items-center justify-between rounded-md border border-slate-200 bg-white px-3 py-2 hover:border-brand-600"
    >
      <span className="font-medium text-slate-700">{label}</span>
      <span className="text-xs text-slate-500">{url.replace(/^https?:\/\//, "")}</span>
    </a>
  );
}

function pickPreviewUrl(poi: PoiDetail): string | null {
  if (poi.website) return poi.website;
  if (poi.wikipedia) return wikipediaUrl(poi.wikipedia);
  return null;
}

function wikipediaUrl(value: string): string {
  // OSM stores wikipedia tags as "en:Article Title" or a full URL.
  if (/^https?:\/\//.test(value)) return value;
  const [lang, ...rest] = value.split(":");
  const title = rest.join(":");
  const page = encodeURIComponent(title.replace(/ /g, "_"));
  return `https://${lang || "en"}.wikipedia.org/wiki/${page}`;
}
