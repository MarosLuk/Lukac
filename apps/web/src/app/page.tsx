import Link from "next/link";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { SignOutButton } from "@/components/SignOutButton";

export default async function HomePage() {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  return (
    <main className="space-y-8">
      <header className="flex items-center justify-between">
        <h1 className="text-3xl font-bold">Travel Planner</h1>
        {user ? (
          <div className="flex items-center gap-3 text-sm">
            <span className="text-slate-600">{user.email}</span>
            <SignOutButton />
          </div>
        ) : (
          <Link
            href="/login"
            className="rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white hover:bg-brand-700"
          >
            Sign in
          </Link>
        )}
      </header>

      <section className="rounded-lg border border-slate-200 bg-white p-6 shadow-sm">
        <h2 className="text-xl font-semibold">Plan your next trip</h2>
        <p className="mt-2 text-slate-600">
          Enter a destination, dates, and a budget. We&apos;ll draft a day-by-day
          plan around must-see stops and the activities you love.
        </p>
        <div className="mt-4 flex gap-3">
          <Link
            href={user ? "/trips/new" : "/login?next=/trips/new"}
            className="rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white hover:bg-brand-700"
          >
            Start a new trip
          </Link>
          {user && (
            <Link
              href="/trips"
              className="rounded-md border border-slate-300 bg-white px-4 py-2 text-sm font-medium hover:bg-slate-50"
            >
              My trips
            </Link>
          )}
        </div>
      </section>
    </main>
  );
}
