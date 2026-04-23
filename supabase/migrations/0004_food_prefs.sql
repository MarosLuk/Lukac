-- Food preferences for trip planning.
-- Stored as JSONB so we can evolve shape without a migration per tweak.

alter table public.trips
  add column if not exists food_preferences jsonb not null default jsonb_build_object(
    'mealsPerDay', 2,
    'cuisines', '[]'::jsonb,
    'priceLevel', 'mid',
    'avgPricePerMealEur', null,
    'includeBreakfast', false
  );
