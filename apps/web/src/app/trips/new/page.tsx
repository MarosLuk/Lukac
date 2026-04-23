import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { NewTripForm } from "./NewTripForm";

export default async function NewTripPage() {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login?next=/trips/new");

  return (
    <main className="space-y-6">
      <h1 className="text-2xl font-bold">Plan a new trip</h1>
      <NewTripForm />
    </main>
  );
}
