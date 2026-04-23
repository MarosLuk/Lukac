import { z } from "zod";

export const CurrencyCode = z.enum(["EUR", "USD", "GBP", "CZK"]);
export type CurrencyCode = z.infer<typeof CurrencyCode>;

export const TravelStyle = z.enum([
  "relaxed",
  "balanced",
  "packed",
]);
export type TravelStyle = z.infer<typeof TravelStyle>;

export const PoiCategory = z.enum([
  "sightseeing",
  "museum",
  "food",
  "nightlife",
  "nature",
  "shopping",
  "experience",
  "viewpoint",
  "other",
]);
export type PoiCategory = z.infer<typeof PoiCategory>;

export const MustHaveItem = z.object({
  id: z.string().uuid().optional(),
  title: z.string().min(1).max(120),
  note: z.string().max(500).optional(),
  estimatedCost: z.number().nonnegative().optional(),
  category: PoiCategory.optional(),
});
export type MustHaveItem = z.infer<typeof MustHaveItem>;

export const PriceLevel = z.enum(["budget", "mid", "fine"]);
export type PriceLevel = z.infer<typeof PriceLevel>;

// OSM `cuisine=` tag vocabulary, plus a couple of aggregates. Free-form string
// so rare ones still round-trip; the UI offers a curated pick list.
export const COMMON_CUISINES = [
  "local",
  "italian",
  "french",
  "spanish",
  "portuguese",
  "greek",
  "japanese",
  "chinese",
  "thai",
  "indian",
  "mexican",
  "american",
  "vegetarian",
  "vegan",
  "seafood",
  "pizza",
  "burger",
  "sushi",
  "bbq",
  "cafe",
] as const;

export const FoodPreferences = z.object({
  /** 0–3 sit-down meals per day. 0 = no scheduled food (street food / self-serve). */
  mealsPerDay: z.number().int().min(0).max(3).default(2),
  /** Preferred cuisines. Empty = any. Matched against OSM `cuisine=` tag (case-insensitive). */
  cuisines: z.array(z.string().min(1).max(40)).default([]),
  /** Rough price bracket; planner translates to per-meal budget. */
  priceLevel: PriceLevel.default("mid"),
  /** Optional user override of per-meal budget in EUR (per person). */
  avgPricePerMealEur: z.number().positive().max(500).nullable().default(null),
  /** True = keep breakfast slot even when mealsPerDay=2 (hotel breakfast handled separately). */
  includeBreakfast: z.boolean().default(false),
});
export type FoodPreferences = z.infer<typeof FoodPreferences>;

export const DEFAULT_FOOD_PREFERENCES: FoodPreferences = {
  mealsPerDay: 2,
  cuisines: [],
  priceLevel: "mid",
  avgPricePerMealEur: null,
  includeBreakfast: false,
};

export const TripCreateInput = z
  .object({
    destination: z.string().min(2).max(120),
    startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
    endDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
    currency: CurrencyCode.default("EUR"),
    totalBudget: z.number().positive(),
    travelers: z.number().int().positive().max(20).default(1),
    style: TravelStyle.default("balanced"),
    preferredCategories: z.array(PoiCategory).default([]),
    mustHaves: z.array(MustHaveItem).default([]),
    foodPreferences: FoodPreferences.default(DEFAULT_FOOD_PREFERENCES),
    notes: z.string().max(1000).optional(),
  })
  .refine((v) => v.endDate >= v.startDate, {
    message: "endDate must be on or after startDate",
    path: ["endDate"],
  });
export type TripCreateInput = z.infer<typeof TripCreateInput>;

/** PATCH body for /api/trips/[id]. All fields optional; date pair must stay valid. */
export const TripUpdateInput = z
  .object({
    destination: z.string().min(2).max(120).optional(),
    startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
    endDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
    currency: CurrencyCode.optional(),
    totalBudget: z.number().positive().optional(),
    travelers: z.number().int().positive().max(20).optional(),
    style: TravelStyle.optional(),
    preferredCategories: z.array(PoiCategory).optional(),
    mustHaves: z.array(MustHaveItem).optional(),
    foodPreferences: FoodPreferences.optional(),
    notes: z.string().max(1000).nullable().optional(),
  })
  .refine(
    (v) => !(v.startDate && v.endDate) || v.endDate >= v.startDate,
    { message: "endDate must be on or after startDate", path: ["endDate"] },
  );
export type TripUpdateInput = z.infer<typeof TripUpdateInput>;

export const Trip = z.object({
  id: z.string().uuid(),
  ownerId: z.string().uuid(),
  destination: z.string(),
  startDate: z.string(),
  endDate: z.string(),
  currency: CurrencyCode,
  totalBudget: z.number(),
  travelers: z.number(),
  style: TravelStyle,
  preferredCategories: z.array(PoiCategory),
  mustHaves: z.array(MustHaveItem),
  foodPreferences: FoodPreferences,
  notes: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type Trip = z.infer<typeof Trip>;
