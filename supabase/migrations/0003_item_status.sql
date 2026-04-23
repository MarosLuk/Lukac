-- Travel mode: track per-stop status so the mobile app can check-in / skip.

alter table public.itinerary_items
  add column if not exists status text not null default 'pending',
  add column if not exists completed_at timestamptz;

-- Lightweight CHECK instead of a dedicated enum — keeps the migration simple
-- and still rejects typos.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'itinerary_items_status_check'
  ) then
    alter table public.itinerary_items
      add constraint itinerary_items_status_check
      check (status in ('pending', 'done', 'skipped'));
  end if;
end $$;

create index if not exists itinerary_items_status_idx
  on public.itinerary_items (itinerary_id, status);
