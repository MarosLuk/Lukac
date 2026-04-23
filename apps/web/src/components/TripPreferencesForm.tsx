"use client";

import { useState } from "react";
import {
  COMMON_CUISINES,
  DEFAULT_FOOD_PREFERENCES,
  type CurrencyCode,
  type FoodPreferences,
  type MustHaveItem,
  type PoiCategory,
  type PriceLevel,
  type TravelStyle,
} from "@tp/shared";

export type TripPreferencesValue = {
  destination: string;
  startDate: string;
  endDate: string;
  currency: CurrencyCode;
  totalBudget: number;
  travelers: number;
  style: TravelStyle;
  preferredCategories: PoiCategory[];
  mustHaves: MustHaveItem[];
  foodPreferences: FoodPreferences;
  notes: string;
};

const CATEGORIES: PoiCategory[] = [
  "sightseeing",
  "museum",
  "food",
  "nightlife",
  "nature",
  "shopping",
  "experience",
  "viewpoint",
];

const PRICE_LABELS: Record<PriceLevel, string> = {
  budget: "Budget (< €15 / meal)",
  mid: "Mid (€15–35 / meal)",
  fine: "Fine (€35+ / meal)",
};

export function TripPreferencesForm({
  value,
  onChange,
  compact = false,
}: {
  value: TripPreferencesValue;
  onChange: (next: TripPreferencesValue) => void;
  compact?: boolean;
}) {
  const [mustHaveDraft, setMustHaveDraft] = useState("");
  const [cuisineDraft, setCuisineDraft] = useState("");

  function patch<K extends keyof TripPreferencesValue>(key: K, v: TripPreferencesValue[K]) {
    onChange({ ...value, [key]: v });
  }
  function patchFood<K extends keyof FoodPreferences>(key: K, v: FoodPreferences[K]) {
    onChange({ ...value, foodPreferences: { ...value.foodPreferences, [key]: v } });
  }
  function togglePreferred(cat: PoiCategory) {
    const set = new Set(value.preferredCategories);
    set.has(cat) ? set.delete(cat) : set.add(cat);
    patch("preferredCategories", Array.from(set));
  }
  function toggleCuisine(c: string) {
    const set = new Set(value.foodPreferences.cuisines);
    set.has(c) ? set.delete(c) : set.add(c);
    patchFood("cuisines", Array.from(set));
  }
  function addMustHave() {
    const t = mustHaveDraft.trim();
    if (!t) return;
    patch("mustHaves", [...value.mustHaves, { title: t }]);
    setMustHaveDraft("");
  }
  function addCuisine() {
    const t = cuisineDraft.trim().toLowerCase();
    if (!t) return;
    const set = new Set(value.foodPreferences.cuisines);
    set.add(t);
    patchFood("cuisines", Array.from(set));
    setCuisineDraft("");
  }

  return (
    <div className={compact ? "space-y-5" : "space-y-6"}>
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="Destination">
          <input
            required
            value={value.destination}
            onChange={(e) => patch("destination", e.target.value)}
            className="input"
            placeholder="Lisbon, Portugal"
          />
        </Field>
        <Field label="Travelers">
          <input
            type="number"
            min={1}
            max={20}
            value={value.travelers}
            onChange={(e) => patch("travelers", Number(e.target.value) || 1)}
            className="input"
          />
        </Field>
        <Field label="Start date">
          <input
            type="date"
            required
            value={value.startDate}
            onChange={(e) => patch("startDate", e.target.value)}
            className="input"
          />
        </Field>
        <Field label="End date">
          <input
            type="date"
            required
            value={value.endDate}
            onChange={(e) => patch("endDate", e.target.value)}
            className="input"
          />
        </Field>
        <Field label="Total budget">
          <input
            type="number"
            min={1}
            value={value.totalBudget}
            onChange={(e) => patch("totalBudget", Number(e.target.value) || 0)}
            className="input"
          />
        </Field>
        <Field label="Currency">
          <select
            value={value.currency}
            onChange={(e) => patch("currency", e.target.value as CurrencyCode)}
            className="input"
          >
            <option value="EUR">EUR</option>
            <option value="USD">USD</option>
            <option value="GBP">GBP</option>
            <option value="CZK">CZK</option>
          </select>
        </Field>
        <Field label="Travel style">
          <select
            value={value.style}
            onChange={(e) => patch("style", e.target.value as TravelStyle)}
            className="input"
          >
            <option value="relaxed">Relaxed</option>
            <option value="balanced">Balanced</option>
            <option value="packed">Packed</option>
          </select>
        </Field>
      </div>

      <Field label="What do you like doing?">
        <div className="flex flex-wrap gap-2">
          {CATEGORIES.map((cat) => {
            const active = value.preferredCategories.includes(cat);
            return (
              <button
                type="button"
                key={cat}
                onClick={() => togglePreferred(cat)}
                className={
                  "rounded-full border px-3 py-1 text-sm capitalize transition " +
                  (active
                    ? "border-brand-600 bg-brand-50 text-brand-700"
                    : "border-slate-300 bg-white text-slate-700 hover:bg-slate-50")
                }
              >
                {cat}
              </button>
            );
          })}
        </div>
      </Field>

      <Field label="Food preferences">
        <div className="space-y-4 rounded-md border border-slate-200 bg-slate-50 p-4">
          <div className="grid gap-3 sm:grid-cols-3">
            <label className="text-sm">
              Meals / day
              <select
                value={value.foodPreferences.mealsPerDay}
                onChange={(e) => patchFood("mealsPerDay", Number(e.target.value) as 0 | 1 | 2 | 3)}
                className="input mt-1"
              >
                <option value={0}>0 (skip)</option>
                <option value={1}>1 (lunch)</option>
                <option value={2}>2 (lunch + dinner)</option>
                <option value={3}>3 (all)</option>
              </select>
            </label>
            <label className="text-sm">
              Price level
              <select
                value={value.foodPreferences.priceLevel}
                onChange={(e) => patchFood("priceLevel", e.target.value as PriceLevel)}
                className="input mt-1"
              >
                {(Object.keys(PRICE_LABELS) as PriceLevel[]).map((p) => (
                  <option key={p} value={p}>
                    {PRICE_LABELS[p]}
                  </option>
                ))}
              </select>
            </label>
            <label className="text-sm">
              Override per-meal budget
              <input
                type="number"
                min={0}
                step={1}
                value={value.foodPreferences.avgPricePerMealEur ?? ""}
                onChange={(e) =>
                  patchFood(
                    "avgPricePerMealEur",
                    e.target.value === "" ? null : Number(e.target.value),
                  )
                }
                className="input mt-1"
                placeholder="auto"
              />
            </label>
          </div>
          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={value.foodPreferences.includeBreakfast}
              onChange={(e) => patchFood("includeBreakfast", e.target.checked)}
            />
            Include breakfast in the plan
          </label>
          <div>
            <p className="mb-2 text-xs font-medium uppercase tracking-wide text-slate-500">
              Cuisines (pick any)
            </p>
            <div className="flex flex-wrap gap-2">
              {COMMON_CUISINES.map((c) => {
                const active = value.foodPreferences.cuisines.includes(c);
                return (
                  <button
                    type="button"
                    key={c}
                    onClick={() => toggleCuisine(c)}
                    className={
                      "rounded-full border px-2.5 py-0.5 text-xs capitalize " +
                      (active
                        ? "border-brand-600 bg-brand-50 text-brand-700"
                        : "border-slate-300 bg-white text-slate-700 hover:bg-slate-50")
                    }
                  >
                    {c}
                  </button>
                );
              })}
            </div>
            {value.foodPreferences.cuisines.filter(
              (c) => !(COMMON_CUISINES as readonly string[]).includes(c),
            ).length > 0 && (
              <div className="mt-2 flex flex-wrap gap-1 text-xs text-slate-600">
                Custom:{" "}
                {value.foodPreferences.cuisines
                  .filter((c) => !(COMMON_CUISINES as readonly string[]).includes(c))
                  .map((c) => (
                    <button
                      key={c}
                      type="button"
                      onClick={() => toggleCuisine(c)}
                      className="rounded-full border border-brand-600 bg-brand-50 px-2 py-0.5 text-brand-700"
                    >
                      {c} ×
                    </button>
                  ))}
              </div>
            )}
            <div className="mt-2 flex gap-2">
              <input
                value={cuisineDraft}
                onChange={(e) => setCuisineDraft(e.target.value)}
                placeholder="Add other (e.g. fado-tavern)"
                className="input text-sm"
              />
              <button
                type="button"
                onClick={addCuisine}
                className="rounded-md border border-slate-300 bg-white px-3 text-xs font-medium hover:bg-slate-50"
              >
                Add
              </button>
            </div>
          </div>
        </div>
      </Field>

      <Field label="Must-have experiences">
        <div className="flex gap-2">
          <input
            value={mustHaveDraft}
            onChange={(e) => setMustHaveDraft(e.target.value)}
            placeholder="e.g. Torre de Belém"
            className="input flex-1"
          />
          <button
            type="button"
            onClick={addMustHave}
            className="rounded-md border border-slate-300 bg-white px-3 text-sm font-medium hover:bg-slate-50"
          >
            Add
          </button>
        </div>
        {value.mustHaves.length > 0 && (
          <ul className="mt-3 space-y-2">
            {value.mustHaves.map((m, i) => (
              <li
                key={i}
                className="flex items-center justify-between rounded-md bg-slate-100 px-3 py-1.5 text-sm"
              >
                <span>{m.title}</span>
                <button
                  type="button"
                  onClick={() =>
                    patch(
                      "mustHaves",
                      value.mustHaves.filter((_, idx) => idx !== i),
                    )
                  }
                  className="text-xs text-slate-500 hover:text-red-600"
                >
                  remove
                </button>
              </li>
            ))}
          </ul>
        )}
      </Field>

      <Field label="Notes (optional)">
        <textarea
          rows={3}
          value={value.notes}
          onChange={(e) => patch("notes", e.target.value)}
          className="input"
          placeholder="Anything the planner should know"
        />
      </Field>

      <style jsx>{`
        .input {
          border-radius: 0.375rem;
          border: 1px solid rgb(203 213 225);
          padding: 0.5rem 0.75rem;
          width: 100%;
          background: white;
        }
      `}</style>
    </div>
  );
}

export function emptyTripPreferences(): TripPreferencesValue {
  return {
    destination: "",
    startDate: "",
    endDate: "",
    currency: "EUR",
    totalBudget: 500,
    travelers: 1,
    style: "balanced",
    preferredCategories: [],
    mustHaves: [],
    foodPreferences: { ...DEFAULT_FOOD_PREFERENCES },
    notes: "",
  };
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="block">
      <span className="mb-1 block text-sm font-medium text-slate-700">{label}</span>
      {children}
    </label>
  );
}
