import Link from "next/link";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { rowToTrip, type TripRow } from "@/lib/db/mappers";
import { tripDurationDays } from "@tp/shared";

export default async function TripsPage() {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login?next=/trips");

  const { data } = await supabase
    .from("trips")
    .select("*")
    .eq("owner_id", user.id)
    .order("start_date", { ascending: false });

  const trips = ((data ?? []) as TripRow[]).map(rowToTrip);

  return (
    <main className="space-y-6">
      <header className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">My trips</h1>
        <Link
          href="/trips/new"
          className="rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white hover:bg-brand-700"
        >
          New trip
        </Link>
      </header>

      {trips.length === 0 ? (
        <p className="text-slate-600">No trips yet. Start by creating one.</p>
      ) : (
        <ul className="space-y-3">
          {trips.map((t) => {
            const days = tripDurationDays(t.startDate, t.endDate);
            return (
              <li key={t.id}>
                <Link
                  href={`/trips/${t.id}`}
                  className="block rounded-lg border border-slate-200 bg-white p-4 shadow-sm hover:border-brand-600 hover:shadow"
                >
                  <div className="flex items-center justify-between">
                    <div>
                      <h2 className="text-lg font-semibold">{t.destination}</h2>
                      <p className="text-sm text-slate-600">
                        {t.startDate} → {t.endDate} · {days} day{days > 1 ? "s" : ""} ·{" "}
                        {t.totalBudget} {t.currency}
                      </p>
                    </div>
                    <span className="rounded-full bg-brand-50 px-2 py-0.5 text-xs font-medium text-brand-700">
                      {t.style}
                    </span>
                  </div>
                </Link>
              </li>
            );
          })}
        </ul>
      )}
    </main>
  );
}
