-- Planning engine: POI cache + itineraries
-- Run via `supabase migration up` / automatically on `supabase start`

create table if not exists public.cities (
  id uuid primary key default uuid_generate_v4(),
  slug text not null unique,          -- e.g. "lisbon-portugal"
  name text not null,                 -- e.g. "Lisbon"
  country text,
  lat double precision not null,
  lng double precision not null,
  bbox_south double precision not null,
  bbox_west double precision not null,
  bbox_north double precision not null,
  bbox_east double precision not null,
  summary text,                       -- short description (Wikivoyage-derived)
  highlights jsonb not null default '[]'::jsonb,
  fetched_at timestamptz not null default now()
);

create index if not exists cities_slug_idx on public.cities (slug);

create table if not exists public.pois (
  id uuid primary key default uuid_generate_v4(),
  city_id uuid not null references public.cities(id) on delete cascade,
  source text not null,               -- 'osm' | 'wikivoyage'
  source_ref text not null,           -- e.g. "node/123" for OSM
  name text not null,
  category text not null,             -- normalized: sightseeing|museum|food|viewpoint|...
  subcategory text,                   -- osm tag value, e.g. "attraction" or "restaurant"
  lat double precision not null,
  lng double precision not null,
  tags jsonb not null default '{}'::jsonb,    -- raw OSM tags
  opening_hours text,                          -- OSM opening_hours string
  website text,
  wikipedia text,
  score real not null default 0,     -- 0..1 popularity/quality heuristic
  estimated_cost_eur numeric(10, 2), -- rough per-person cost (nullable)
  estimated_duration_min int,        -- rough visit duration in minutes
  fetched_at timestamptz not null default now(),
  unique (city_id, source, source_ref)
);

create index if not exists pois_city_idx on public.pois (city_id, score desc);
create index if not exists pois_city_cat_idx on public.pois (city_id, category, score desc);

-- POIs are shared read-only reference data (cache). No user-level RLS needed.
alter table public.cities enable row level security;
alter table public.pois enable row level security;

drop policy if exists "cities_read_all" on public.cities;
create policy "cities_read_all" on public.cities for select using (true);

drop policy if exists "pois_read_all" on public.pois;
create policy "pois_read_all" on public.pois for select using (true);

-- Writes to pois/cities go through the service role from API routes only.

create table if not exists public.itineraries (
  id uuid primary key default uuid_generate_v4(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'draft',   -- 'draft' | 'ready'
  total_cost numeric(12, 2) not null default 0,
  generated_at timestamptz not null default now(),
  meta jsonb not null default '{}'::jsonb
);

create index if not exists itineraries_trip_idx on public.itineraries (trip_id);

create table if not exists public.itinerary_items (
  id uuid primary key default uuid_generate_v4(),
  itinerary_id uuid not null references public.itineraries(id) on delete cascade,
  day_index int not null,                  -- 0-based from trip start
  sort_index int not null,                 -- order within day
  poi_id uuid references public.pois(id) on delete set null,
  title text not null,                      -- denormalized so items work if POI is deleted
  category text not null,
  lat double precision,
  lng double precision,
  start_minutes int not null,              -- minutes after 00:00 local
  duration_minutes int not null,
  cost_eur numeric(10, 2) not null default 0,
  is_must_have boolean not null default false,
  note text,
  travel_from_prev jsonb                    -- { mode, minutes, distance_km } for route to this stop
);

create index if not exists itinerary_items_order_idx
  on public.itinerary_items (itinerary_id, day_index, sort_index);

alter table public.itineraries enable row level security;
alter table public.itinerary_items enable row level security;

drop policy if exists "itineraries_own" on public.itineraries;
create policy "itineraries_own"
  on public.itineraries for all
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

drop policy if exists "itinerary_items_own" on public.itinerary_items;
create policy "itinerary_items_own"
  on public.itinerary_items for all
  using (
    exists (
      select 1 from public.itineraries it
      where it.id = itinerary_id and it.owner_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.itineraries it
      where it.id = itinerary_id and it.owner_id = auth.uid()
    )
  );
