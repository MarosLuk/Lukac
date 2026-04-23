import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { rowToTrip, type TripRow } from "@/lib/db/mappers";
import {
  rowToItinerary,
  type ItineraryItemRow,
  type ItineraryRow,
} from "@/lib/db/itinerary";
import { TripDetailClient } from "./TripDetailClient";

export default async function TripDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect(`/login?next=/trips/${id}`);

  const { data: tripRow } = await supabase
    .from("trips")
    .select("*")
    .eq("id", id)
    .eq("owner_id", user.id)
    .maybeSingle();
  if (!tripRow) notFound();

  const trip = rowToTrip(tripRow as TripRow);

  const { data: itinRow } = await supabase
    .from("itineraries")
    .select("*")
    .eq("trip_id", id)
    .order("generated_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  let itinerary = null;
  if (itinRow) {
    const { data: items } = await supabase
      .from("itinerary_items")
      .select("*")
      .eq("itinerary_id", (itinRow as ItineraryRow).id)
      .order("day_index", { ascending: true })
      .order("sort_index", { ascending: true });
    itinerary = rowToItinerary(
      itinRow as ItineraryRow,
      (items ?? []) as ItineraryItemRow[],
    );
  }

  return (
    <main className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <Link href="/trips" className="text-sm text-brand-600 hover:underline">
            ← All trips
          </Link>
          <h1 className="mt-1 text-2xl font-bold">{trip.destination}</h1>
          <p className="text-sm text-slate-600">
            {trip.startDate} → {trip.endDate} · budget {trip.totalBudget} {trip.currency} · {trip.style}
          </p>
        </div>
      </div>
      <TripDetailClient trip={trip} initialItinerary={itinerary} />
    </main>
  );
}
