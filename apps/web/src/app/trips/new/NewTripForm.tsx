"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { TripCreateInput } from "@tp/shared";
import {
  TripPreferencesForm,
  emptyTripPreferences,
  type TripPreferencesValue,
} from "@/components/TripPreferencesForm";

export function NewTripForm() {
  const router = useRouter();
  const [value, setValue] = useState<TripPreferencesValue>(emptyTripPreferences());
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);

    const payload = {
      ...value,
      totalBudget: Number(value.totalBudget),
      travelers: Number(value.travelers),
      notes: value.notes || undefined,
    };
    const parsed = TripCreateInput.safeParse(payload);
    if (!parsed.success) {
      setError(parsed.error.issues.map((i) => i.message).join(", "));
      return;
    }

    setSubmitting(true);
    const res = await fetch("/api/trips", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(parsed.data),
    });
    const body = await res.json();
    setSubmitting(false);

    if (!res.ok || !body.ok) {
      setError(body?.error?.message ?? "Failed to create trip");
      return;
    }
    const tripId = body.data?.id as string | undefined;
    router.push(tripId ? `/trips/${tripId}` : "/trips");
    router.refresh();
  }

  return (
    <form
      onSubmit={onSubmit}
      className="space-y-6 rounded-lg border border-slate-200 bg-white p-6 shadow-sm"
    >
      <TripPreferencesForm value={value} onChange={setValue} />
      {error && <p className="text-sm text-red-600">{error}</p>}
      <div className="flex justify-end">
        <button
          type="submit"
          disabled={submitting}
          className="rounded-md bg-brand-600 px-5 py-2 font-medium text-white hover:bg-brand-700 disabled:opacity-50"
        >
          {submitting ? "Saving..." : "Create trip"}
        </button>
      </div>
    </form>
  );
}
