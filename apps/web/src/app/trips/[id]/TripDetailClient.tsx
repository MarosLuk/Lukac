"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import {
  TripUpdateInput,
  formatMinutesOfDay,
  tripDurationDays,
  type Itinerary,
  type ItineraryItem,
  type Trip,
  type TravelLeg,
  type TravelOption,
} from "@tp/shared";
import {
  TripPreferencesForm,
  type TripPreferencesValue,
} from "@/components/TripPreferencesForm";
import { PoiPreviewModal } from "@/components/PoiPreviewModal";

export function TripDetailClient({
  trip: initialTrip,
  initialItinerary,
}: {
  trip: Trip;
  initialItinerary: Itinerary | null;
}) {
  const router = useRouter();
  const [trip, setTrip] = useState<Trip>(initialTrip);
  const [itinerary, setItinerary] = useState<Itinerary | null>(initialItinerary);
  const [generating, setGenerating] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState(false);
  const [editValue, setEditValue] = useState<TripPreferencesValue>(() =>
    tripToPreferences(initialTrip),
  );
  const [saving, setSaving] = useState(false);
  const [previewPoiId, setPreviewPoiId] = useState<string | null>(null);

  async function generate() {
    setGenerating(true);
    setError(null);
    const res = await fetch(`/api/trips/${trip.id}/generate`, { method: "POST" });
    const body = await res.json();
    setGenerating(false);
    if (!res.ok || !body.ok) {
      setError(body?.error?.message ?? "Failed to generate plan");
      return;
    }
    setItinerary(body.data.itinerary as Itinerary);
  }

  function openEdit() {
    setEditValue(tripToPreferences(trip));
    setEditing(true);
    setError(null);
  }

  async function saveEdit() {
    setError(null);
    const payload = {
      ...editValue,
      totalBudget: Number(editValue.totalBudget),
      travelers: Number(editValue.travelers),
      notes: editValue.notes || null,
    };
    const parsed = TripUpdateInput.safeParse(payload);
    if (!parsed.success) {
      setError(parsed.error.issues.map((i) => i.message).join(", "));
      return;
    }
    setSaving(true);
    const res = await fetch(`/api/trips/${trip.id}`, {
      method: "PATCH",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(parsed.data),
    });
    const body = await res.json();
    setSaving(false);
    if (!res.ok || !body.ok) {
      setError(body?.error?.message ?? "Failed to save");
      return;
    }
    setTrip(body.data.trip as Trip);
    setEditing(false);
    router.refresh();
  }

  const days = tripDurationDays(trip.startDate, trip.endDate);
  const grouped = useMemo(() => groupByDay(itinerary?.items ?? [], days), [itinerary, days]);

  return (
    <section className="space-y-6">
      <div className="flex flex-wrap items-center gap-3 rounded-lg border border-slate-200 bg-white p-4 shadow-sm">
        <div className="flex-1 min-w-0">
          <p className="text-sm text-slate-600">
            {itinerary
              ? `Plan ready · ${itinerary.items.length} stops · ${formatEur(itinerary.totalCost)} estimated`
              : "No plan yet. Generate a draft itinerary from free data sources (OSM + Wikivoyage)."}
          </p>
          <p className="mt-1 text-xs text-slate-500">
            {trip.foodPreferences.mealsPerDay} meal{trip.foodPreferences.mealsPerDay === 1 ? "" : "s"}/day · {trip.foodPreferences.priceLevel}
            {trip.foodPreferences.cuisines.length > 0
              ? ` · ${trip.foodPreferences.cuisines.slice(0, 3).join(", ")}${trip.foodPreferences.cuisines.length > 3 ? "…" : ""}`
              : ""}
          </p>
        </div>
        <button
          onClick={openEdit}
          className="rounded-md border border-slate-300 bg-white px-4 py-2 text-sm font-medium hover:bg-slate-50"
        >
          Edit preferences
        </button>
        <button
          onClick={generate}
          disabled={generating}
          className="rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white hover:bg-brand-700 disabled:opacity-50"
        >
          {generating ? "Generating..." : itinerary ? "Regenerate" : "Generate plan"}
        </button>
      </div>

      {editing && (
        <div className="rounded-lg border border-slate-200 bg-white p-6 shadow-sm">
          <div className="mb-4 flex items-center justify-between">
            <h2 className="text-lg font-semibold">Edit trip preferences</h2>
            <button
              onClick={() => setEditing(false)}
              className="text-sm text-slate-500 hover:text-slate-700"
            >
              Cancel
            </button>
          </div>
          <TripPreferencesForm value={editValue} onChange={setEditValue} compact />
          <div className="mt-6 flex justify-end gap-2">
            <button
              onClick={() => setEditing(false)}
              className="rounded-md border border-slate-300 bg-white px-4 py-2 text-sm font-medium hover:bg-slate-50"
            >
              Cancel
            </button>
            <button
              onClick={saveEdit}
              disabled={saving}
              className="rounded-md bg-brand-600 px-5 py-2 text-sm font-medium text-white hover:bg-brand-700 disabled:opacity-50"
            >
              {saving ? "Saving..." : "Save changes"}
            </button>
          </div>
        </div>
      )}
      {generating && (
        <p className="text-sm text-slate-500">
          Fetching POIs (first time for a city can take 20–40s, subsequent runs use cache)...
        </p>
      )}
      {error && <p className="text-sm text-red-600">{error}</p>}

      {grouped.map((day, i) => {
        const dayDate = addDays(trip.startDate, i);
        return (
          <article
            key={i}
            className="overflow-hidden rounded-lg border border-slate-200 bg-white shadow-sm"
          >
            <header className="flex items-center justify-between border-b border-slate-100 bg-slate-50 px-4 py-3">
              <h2 className="font-semibold">
                Day {i + 1} · {dayDate}
              </h2>
              <span className="text-xs text-slate-500">
                {day.length} stop{day.length === 1 ? "" : "s"}
                {day.length > 0 && ` · ${formatEur(sumCost(day))}`}
              </span>
            </header>
            {day.length === 0 ? (
              <p className="px-4 py-6 text-sm text-slate-500">
                Empty day — generate (or regenerate) the plan to populate.
              </p>
            ) : (
              <ol className="divide-y divide-slate-100">
                {day.map((it) => (
                  <li key={it.id}>
                    {it.travelFromPrev && <TravelStrip leg={it.travelFromPrev} />}
                    <button
                      type="button"
                      disabled={!it.poiId}
                      onClick={() => it.poiId && setPreviewPoiId(it.poiId)}
                      className="flex w-full gap-4 px-4 py-3 text-left transition hover:bg-slate-50 disabled:cursor-default disabled:hover:bg-transparent"
                    >
                      <div className="w-20 shrink-0 text-sm font-medium text-slate-700">
                        {formatMinutesOfDay(it.startMinutes)}
                        <div className="text-xs font-normal text-slate-400">
                          {it.durationMinutes} min
                        </div>
                      </div>
                      <div className="flex-1">
                        <div className="flex items-start justify-between gap-2">
                          <h3 className="font-medium text-slate-900">
                            {it.title}
                            {it.poiId && (
                              <span className="ml-2 text-xs font-normal text-brand-600">
                                preview ↗
                              </span>
                            )}
                          </h3>
                          <div className="flex shrink-0 items-center gap-2">
                            {it.isMustHave && (
                              <span className="rounded-full bg-amber-100 px-2 py-0.5 text-xs font-medium text-amber-800">
                                must-have
                              </span>
                            )}
                            <span className="text-xs text-slate-500">{it.category}</span>
                          </div>
                        </div>
                        {it.note && (
                          <p className="mt-1 text-xs italic text-amber-700">{it.note}</p>
                        )}
                        {it.costEur > 0 && (
                          <p className="mt-1 text-xs text-slate-500">
                            ~{formatEur(it.costEur)} pp
                          </p>
                        )}
                      </div>
                    </button>
                  </li>
                ))}
              </ol>
            )}
          </article>
        );
      })}

      <PoiPreviewModal poiId={previewPoiId} onClose={() => setPreviewPoiId(null)} />
    </section>
  );
}

function TravelStrip({ leg }: { leg: TravelLeg }) {
  if (!leg.options || leg.options.length === 0) return null;
  return (
    <div className="mx-4 flex items-center gap-2 border-l-2 border-dashed border-slate-300 py-2 pl-4">
      {leg.options.map((opt, i) => (
        <TravelPill key={i} option={opt} recommended={i === leg.recommendedIndex} />
      ))}
    </div>
  );
}

function TravelPill({
  option,
  recommended,
}: {
  option: TravelOption;
  recommended: boolean;
}) {
  const icon =
    option.mode === "walk"
      ? "🚶"
      : option.mode === "transit"
        ? "🚌"
        : option.mode === "taxi"
          ? "🚕"
          : "🚗";
  const base = recommended
    ? "border-brand-600 bg-brand-50 text-brand-700"
    : "border-slate-200 bg-white text-slate-700";
  const borderStyle = option.source === "estimated" ? "border-dashed" : "border";
  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-md ${borderStyle} px-2 py-1 text-xs ${base}`}
      title={option.note ?? undefined}
    >
      <span>{icon}</span>
      <span className="font-semibold">
        {option.minutes}m
        {option.costEur > 0 ? ` · €${option.costEur.toFixed(option.costEur < 10 ? 1 : 0)}` : " · free"}
      </span>
      <span className="text-slate-500">{option.distanceKm} km</span>
      {option.source === "estimated" && (
        <span className="text-[10px] uppercase tracking-wide text-slate-400">est</span>
      )}
    </span>
  );
}

function tripToPreferences(trip: Trip): TripPreferencesValue {
  return {
    destination: trip.destination,
    startDate: trip.startDate,
    endDate: trip.endDate,
    currency: trip.currency,
    totalBudget: trip.totalBudget,
    travelers: trip.travelers,
    style: trip.style,
    preferredCategories: trip.preferredCategories,
    mustHaves: trip.mustHaves,
    foodPreferences: trip.foodPreferences,
    notes: trip.notes ?? "",
  };
}

function groupByDay(items: ItineraryItem[], days: number): ItineraryItem[][] {
  const out: ItineraryItem[][] = Array.from({ length: days }, () => []);
  for (const it of items) {
    if (it.dayIndex >= 0 && it.dayIndex < days) out[it.dayIndex]!.push(it);
  }
  return out;
}

function sumCost(items: ItineraryItem[]): number {
  return items.reduce((a, b) => a + b.costEur, 0);
}

function formatEur(n: number): string {
  return `€${n.toFixed(0)}`;
}

function addDays(startIso: string, days: number): string {
  const d = new Date(`${startIso}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}
