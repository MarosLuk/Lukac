import type { Trip, MustHaveItem, PoiCategory, FoodPreferences } from "@tp/shared";
import { DEFAULT_FOOD_PREFERENCES } from "@tp/shared";

export interface TripRow {
  id: string;
  owner_id: string;
  destination: string;
  start_date: string;
  end_date: string;
  currency: string;
  total_budget: number;
  travelers: number;
  style: string;
  preferred_categories: string[];
  must_haves: MustHaveItem[];
  food_preferences: FoodPreferences | null;
  notes: string | null;
  created_at: string;
  updated_at: string;
}

export function rowToTrip(row: TripRow): Trip {
  return {
    id: row.id,
    ownerId: row.owner_id,
    destination: row.destination,
    startDate: row.start_date,
    endDate: row.end_date,
    currency: row.currency as Trip["currency"],
    totalBudget: Number(row.total_budget),
    travelers: row.travelers,
    style: row.style as Trip["style"],
    preferredCategories: row.preferred_categories as PoiCategory[],
    mustHaves: row.must_haves ?? [],
    foodPreferences: row.food_preferences ?? DEFAULT_FOOD_PREFERENCES,
    notes: row.notes,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}
