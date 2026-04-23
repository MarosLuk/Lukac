import { NextResponse } from "next/server";
import { ItineraryItemPatch } from "@tp/shared";
import { supabaseForRequest } from "@/lib/supabase/request";
import { rowToItineraryItem, type ItineraryItemRow } from "@/lib/db/itinerary";

export async function PATCH(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  const supabase = await supabaseForRequest(request);
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json(
      { ok: false, error: { code: "UNAUTHENTICATED", message: "Sign in required" } },
      { status: 401 },
    );
  }

  const json = await request.json().catch(() => null);
  const parsed = ItineraryItemPatch.safeParse(json);
  if (!parsed.success) {
    return NextResponse.json(
      {
        ok: false,
        error: {
          code: "VALIDATION_ERROR",
          message: "Invalid patch",
          details: parsed.error.flatten(),
        },
      },
      { status: 400 },
    );
  }

  const patch: Record<string, unknown> = {};
  if (parsed.data.status !== undefined) {
    patch.status = parsed.data.status;
    patch.completed_at = parsed.data.status === "done" ? new Date().toISOString() : null;
  }
  if (parsed.data.note !== undefined) {
    patch.note = parsed.data.note;
  }

  // RLS on itinerary_items allows updates only when the parent itinerary
  // belongs to auth.uid(), so we don't need to re-check ownership here.
  const { data, error } = await supabase
    .from("itinerary_items")
    .update(patch)
    .eq("id", id)
    .select("*")
    .single();

  if (error || !data) {
    const missing = !data && !error;
    return NextResponse.json(
      {
        ok: false,
        error: {
          code: missing ? "NOT_FOUND" : "DB_ERROR",
          message: error?.message ?? "Not found",
        },
      },
      { status: missing ? 404 : 500 },
    );
  }

  return NextResponse.json({
    ok: true,
    data: { item: rowToItineraryItem(data as ItineraryItemRow) },
  });
}
