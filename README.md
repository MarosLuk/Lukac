# Travel Planner

MVP for planning trips — web (Next.js) for building the plan, mobile (Expo / React Native) for using it on the road. **Runs 100% locally** — no cloud accounts required. Local Supabase stack (Postgres + Auth + Studio) spins up in Docker.

## Phases

1. **Foundation** ← *you are here*. Monorepo, auth, trip CRUD, basic UI on web + mobile.
2. **Planning engine** — POI fetch (Overpass + Wikivoyage), Claude curation, day-by-day itinerary generator, web editor.
3. **Travel mode (mobile)** — today view, offline cache, map with route, push notifications.

## Layout

```
apps/
  web/              # Next.js 15, App Router, Tailwind
  mobile/           # Expo Router (React Native)
packages/
  shared/           # Shared TS types + zod schemas
supabase/
  config.toml       # Local stack config
  migrations/       # SQL migrations (applied on supabase start)
scripts/
  sync-local-env.sh # Writes local Supabase keys into apps/*/.env*
.bin/
  supabase          # Pinned Supabase CLI (gitignored)
```

## Prerequisites

- Node 20+
- [Docker](https://docs.docker.com/engine/install/) (Supabase stack runs in containers)
- The Supabase CLI is pinned in `.bin/supabase` — no brew/global install needed.

## First-time setup

```bash
# 1. Install workspace deps
pnpm install

# 2. Boot local Supabase (pulls images first time, ~3-5 min),
#    applies supabase/migrations/0001_init.sql, and writes
#    apps/web/.env.local + apps/mobile/.env with local API URL + anon key.
pnpm db:start
```

That's it. When it finishes you'll have:

| Service    | URL                            |
|------------|--------------------------------|
| API        | http://127.0.0.1:54321         |
| Studio     | http://127.0.0.1:54323         |
| Inbucket   | http://127.0.0.1:54324         |
| Postgres   | postgresql://postgres:postgres@127.0.0.1:54322/postgres |

## Daily workflow

```bash
pnpm db:start       # boot Supabase (re-run safe; also re-syncs env files)
pnpm web            # Next.js on http://localhost:3000
pnpm mobile         # Expo dev tools; press "i" for iOS sim, "a" for Android
```

Other helpers:

```bash
pnpm db:stop        # stop all Supabase containers
pnpm db:reset       # drop DB and re-apply migrations (wipes data)
pnpm db:studio      # open Supabase Studio in browser
pnpm db:status      # show running services + keys
pnpm env:sync       # re-write .env files from current supabase status
pnpm typecheck      # tsc on all workspaces
```

## Auth (local)

Email/password via local Supabase Auth. Email confirmations are **off** in `supabase/config.toml` so signup returns a session immediately.

Any test email works (`demo@example.com` / `demopass123`). Mail sent by the stack goes to Inbucket at http://127.0.0.1:54324.

## Mobile on a physical phone

`127.0.0.1` resolves to the phone's own localhost, not the Mac. If you run Expo Go on a real device:

1. Find your Mac's LAN IP: `ipconfig getifaddr en0`
2. Edit `apps/mobile/.env` and replace `127.0.0.1` with that IP.
3. Restart Expo.

Simulators (iOS Simulator, Android Emulator via `adb reverse`) work out of the box.

## Data ownership + RLS

Every trip row has `owner_id = auth.users.id`. Four RLS policies (`trips_select_own` / `trips_insert_own` / `trips_update_own` / `trips_delete_own`) enforce that each user only sees + mutates their own trips. The migration is the source of truth — see [supabase/migrations/0001_init.sql](supabase/migrations/0001_init.sql).

## What's next (Phase 2)

- POI data layer (Overpass + Wikivoyage) with Supabase-side cache.
- Itinerary generator: time-windowed scheduling, must-have anchoring, budget allocation.
- Claude-powered curation / narrative ("why this place").
- Web editor: day columns, drag-and-drop reordering, regeneration.
