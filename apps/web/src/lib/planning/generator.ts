import type {
  Poi,
  Trip,
  MustHaveItem,
  TravelStyle,
  PoiCategory,
  TravelLeg,
  FoodPreferences,
  PriceLevel,
} from "@tp/shared";
import { isOpenThroughout } from "./openingHours";
import { buildTravelOptions } from "./travelOptions";

export interface DraftItem {
  dayIndex: number;
  sortIndex: number;
  poiId: string | null;
  title: string;
  category: PoiCategory;
  lat: number | null;
  lng: number | null;
  startMinutes: number;
  durationMinutes: number;
  costEur: number;
  isMustHave: boolean;
  note: string | null;
  travelFromPrev: TravelLeg | null;
}

export interface DraftItinerary {
  items: DraftItem[];
  totalCost: number;
  unplacedMustHaves: MustHaveItem[];
}

// Per-day activity window in minutes from midnight.
const DAY_START: Record<TravelStyle, number> = {
  relaxed: 10 * 60,
  balanced: 9 * 60,
  packed: 8 * 60,
};
const DAY_END: Record<TravelStyle, number> = {
  relaxed: 20 * 60,
  balanced: 21 * 60,
  packed: 22 * 60,
};

// How aggressively to fill a day (hours of activity).
const TARGET_ACTIVE_MIN: Record<TravelStyle, number> = {
  relaxed: 5 * 60,
  balanced: 7 * 60,
  packed: 9 * 60,
};

// Walking speed: 4.5 km/h → ~13.3 min/km. We use Haversine for distance.
const MIN_PER_KM_WALK = 13.3;

// Per-meal budget defaults per price level (EUR per person).
// Used both to filter food POIs (estimated_cost_eur) and to count towards the
// trip budget. Override possible via FoodPreferences.avgPricePerMealEur.
const MEAL_BUDGET: Record<PriceLevel, number> = {
  budget: 12,
  mid: 25,
  fine: 50,
};

// Meal slot labels; start times are advisory (scheduler places them in order).
const MEAL_SLOTS = {
  breakfast: { startMin: 9 * 60, durationMin: 45 },
  lunch: { startMin: 13 * 60, durationMin: 75 },
  dinner: { startMin: 19 * 60 + 30, durationMin: 90 },
} as const;
type MealSlot = keyof typeof MEAL_SLOTS;

export async function generateItinerary(
  trip: Trip,
  pois: Poi[],
  options?: { dailyBudgetEur?: number | null },
): Promise<DraftItinerary> {
  const days = dayCount(trip.startDate, trip.endDate);
  const dailyBudget = options?.dailyBudgetEur ?? trip.totalBudget / days;
  const items: DraftItem[] = [];
  const unplacedMustHaves: MustHaveItem[] = [];

  // Filter POIs by user preferences (if any). Food is always allowed when
  // mealsPerDay > 0 even if food isn't in preferredCategories.
  const foodPrefs = trip.foodPreferences;
  const foodAllowedRegardless = foodPrefs.mealsPerDay > 0 || foodPrefs.includeBreakfast;
  const preferred = new Set(trip.preferredCategories);
  const weighted = pois
    .filter(
      (p) =>
        preferred.size === 0 ||
        preferred.has(p.category) ||
        (foodAllowedRegardless && p.category === "food"),
    )
    .sort((a, b) => b.score - a.score);

  // Turn user-specified must-haves into synthetic "anchor" candidates.
  const mustHaveAnchors: (MustHaveItem & { matchedPoi?: Poi })[] = trip.mustHaves.map((m) => {
    const matched = findBestMatch(m, pois);
    return { ...m, matchedPoi: matched };
  });

  // Available pool: high-scoring POIs minus the ones already used as must-haves.
  const usedPoiIds = new Set(
    mustHaveAnchors.flatMap((m) => (m.matchedPoi ? [m.matchedPoi.id] : [])),
  );
  const pool = weighted.filter((p) => !usedPoiIds.has(p.id));
  const consumed = new Set<string>();

  // Distribute must-haves across days (one per day until they run out).
  const plannedDays: Array<{ dayItems: PlanItem[]; budgetUsed: number }> = Array.from(
    { length: days },
    () => ({ dayItems: [], budgetUsed: 0 }),
  );

  mustHaveAnchors.forEach((m, i) => {
    const dayIndex = i % days;
    const anchor = buildMustHavePlanItem(m);
    if (!anchor) {
      unplacedMustHaves.push(m);
      return;
    }
    plannedDays[dayIndex]!.dayItems.push(anchor);
    plannedDays[dayIndex]!.budgetUsed += anchor.costEur;
  });

  // Pre-book meal slots for every day so the plan actually includes food the
  // way the user asked for (0..3 meals, cuisine filter, price level).
  const mealSlotsToUse: MealSlot[] = buildMealSlotList(foodPrefs);
  if (mealSlotsToUse.length > 0) {
    const foodPool = pool.filter(
      (p) => p.category === "food" && !consumed.has(p.id) && matchesFoodPrefs(p, foodPrefs),
    );
    for (let day = 0; day < days; day++) {
      const dayState = plannedDays[day]!;
      const dayDate = addDaysIso(trip.startDate, day);
      // Pick a centroid so "which restaurant" prefers nearby ones.
      const anchored = dayState.dayItems.filter((i) => i.lat != null && i.lng != null);
      const centroid = anchored.length
        ? { lat: avg(anchored.map((i) => i.lat!)), lng: avg(anchored.map((i) => i.lng!)) }
        : null;
      for (const slot of mealSlotsToUse) {
        const slotCfg = MEAL_SLOTS[slot];
        const startDate = new Date(`${dayDate}T00:00:00`);
        startDate.setMinutes(slotCfg.startMin);
        const endDate = new Date(startDate.getTime() + slotCfg.durationMin * 60_000);
        const picked = pickMealPoi(foodPool, centroid, consumed, foodPrefs, {
          startDate,
          endDate,
        });
        const mealItem = buildMealPlanItem(slot, picked, foodPrefs);
        dayState.dayItems.push(mealItem);
        dayState.budgetUsed += mealItem.costEur;
      }
    }
  }

  // Fill each day with POIs. We cluster by proximity to existing day anchors
  // when present, otherwise by overall score. Simple greedy — good enough for MVP.
  for (let day = 0; day < days; day++) {
    const dayState = plannedDays[day]!;
    const dayStart = DAY_START[trip.style];
    const dayEnd = DAY_END[trip.style];
    const target = TARGET_ACTIVE_MIN[trip.style];

    // Compute "anchor centroid" if day has must-haves with coords.
    const anchored = dayState.dayItems.filter((i) => i.lat != null && i.lng != null);
    const centroid = anchored.length
      ? {
          lat: avg(anchored.map((i) => i.lat!)),
          lng: avg(anchored.map((i) => i.lng!)),
        }
      : null;

    // Candidate scoring: base score + proximity bonus + meal-slot bonuses.
    const candidates = pool
      .filter((p) => !consumed.has(p.id))
      .map((p) => {
        let s = p.score;
        if (centroid) {
          const km = haversineKm(centroid, { lat: p.lat, lng: p.lng });
          s += Math.max(0, 0.3 - km * 0.03); // closer = higher
        }
        return { poi: p, score: s };
      })
      .sort((a, b) => b.score - a.score);

    // Track whether we've placed any food stop — used to avoid stacking cafés
    // when the day is still short. Final start times are assigned below.
    let addedLunch = dayState.dayItems.some((i) => i.category === "food");

    let usedMinutes = dayState.dayItems.reduce((a, b) => a + b.durationMinutes, 0);

    for (const c of candidates) {
      if (usedMinutes >= target) break;
      if (dayState.budgetUsed + (c.poi.estimatedCostEur ?? 0) > dailyBudget * 1.1) continue;

      // Prefer food at lunchtime, skip if we already placed one and another would crowd.
      if (c.poi.category === "food" && addedLunch && usedMinutes < target * 0.7) continue;

      const duration = c.poi.estimatedDurationMin ?? 60;
      if (duration + usedMinutes > target + 60) continue;

      const item: PlanItem = {
        poiId: c.poi.id,
        title: c.poi.name,
        category: c.poi.category,
        lat: c.poi.lat,
        lng: c.poi.lng,
        durationMinutes: duration,
        costEur: c.poi.estimatedCostEur ?? 0,
        isMustHave: false,
        openingHours: c.poi.openingHours,
      };
      dayState.dayItems.push(item);
      dayState.budgetUsed += item.costEur;
      usedMinutes += duration;
      if (item.category === "food") addedLunch = true;
      consumed.add(c.poi.id);
      if (dayState.dayItems.length >= 8) break;
    }

    // Keep meal-slot items anchored to their slot times; NN-sort the rest and
    // slot them in-between. This guarantees breakfast → (misc) → lunch →
    // (misc) → dinner instead of letting geography reorder meals off-clock.
    const ordered = orderDayItems(dayState.dayItems);

    // Assign start times given day window + travel legs, respecting opening hours.
    const dayDate = addDaysIso(trip.startDate, day);
    let cursor = dayStart;
    const finalItems: DraftItem[] = [];
    let prevPlaced: PlanItem | null = null;
    let sortCounter = 0;
    for (const it of ordered) {
      let leg: TravelLeg | null = null;
      let tentativeCursor = cursor;
      if (prevPlaced) {
        if (prevPlaced.lat != null && it.lat != null) {
          // Real routing: walk + drive via OSRM, plus heuristic transit/taxi.
          leg = await buildTravelOptions(
            { lat: prevPlaced.lat, lng: prevPlaced.lng! },
            { lat: it.lat, lng: it.lng! },
          );
          tentativeCursor = cursor + (leg.minutes ?? 10);
        } else {
          tentativeCursor = cursor + 10;
        }
      }
      // If this is a meal with a preferred slot time, respect it roughly —
      // push the clock forward (never backward, we don't unvisit a prior stop).
      if (it.preferredStartMin != null && tentativeCursor < it.preferredStartMin - 30) {
        tentativeCursor = it.preferredStartMin;
      }

      if (tentativeCursor + it.durationMinutes > dayEnd) break;

      const startDate = new Date(`${dayDate}T00:00:00`);
      startDate.setMinutes(tentativeCursor);
      const endDate = new Date(startDate.getTime() + it.durationMinutes * 60_000);

      // Skip non-must-have stops that would fall in a closed window; must-haves
      // get placed anyway (user explicitly asked for them) and we leave a note.
      if (!it.isMustHave && !isOpenThroughout(it.openingHours, { startDate, endDate })) {
        continue;
      }

      finalItems.push({
        dayIndex: day,
        sortIndex: sortCounter++,
        poiId: it.poiId,
        title: it.title,
        category: it.category,
        lat: it.lat,
        lng: it.lng,
        startMinutes: tentativeCursor,
        durationMinutes: it.durationMinutes,
        costEur: it.costEur,
        isMustHave: it.isMustHave,
        note:
          it.isMustHave && !isOpenThroughout(it.openingHours, { startDate, endDate })
            ? "May be closed — double-check opening hours."
            : (it.note ?? null),
        travelFromPrev: leg,
      });
      cursor = tentativeCursor + it.durationMinutes;
      prevPlaced = it;
    }

    items.push(...finalItems);
  }

  const totalCost = items.reduce((a, b) => a + b.costEur, 0);
  return { items, totalCost, unplacedMustHaves };
}

// --- helpers ---

interface PlanItem {
  poiId: string | null;
  title: string;
  category: PoiCategory;
  lat: number | null;
  lng: number | null;
  durationMinutes: number;
  costEur: number;
  isMustHave: boolean;
  openingHours: string | null;
  /** Soft target start time (meal slots). Scheduler nudges toward this when present. */
  preferredStartMin?: number;
  /** Optional meal label rendered as a note. */
  note?: string | null;
}

function buildMealSlotList(prefs: FoodPreferences): MealSlot[] {
  const slots: MealSlot[] = [];
  if (prefs.includeBreakfast) slots.push("breakfast");
  if (prefs.mealsPerDay >= 1) slots.push("lunch");
  if (prefs.mealsPerDay >= 2) slots.push("dinner");
  return slots;
}

function matchesFoodPrefs(p: Poi, prefs: FoodPreferences): boolean {
  // Cuisine filter (case-insensitive, matches OSM `cuisine=a;b;c` tag).
  if (prefs.cuisines.length > 0) {
    const rawCuisine = ((p.tags.cuisine ?? p.tags.food ?? "") as string).toLowerCase();
    const tagSet = new Set(rawCuisine.split(/[;,\s]+/).filter(Boolean));
    const match = prefs.cuisines.some((c) =>
      Array.from(tagSet).some((t) => t.includes(c.toLowerCase())),
    );
    if (!match) return false;
  }
  return true;
}

function pickMealPoi(
  foodPool: Poi[],
  centroid: { lat: number; lng: number } | null,
  consumed: Set<string>,
  prefs: FoodPreferences,
  window?: { startDate: Date; endDate: Date },
): Poi | null {
  const maxCost = prefs.avgPricePerMealEur ?? MEAL_BUDGET[prefs.priceLevel] * 1.4;
  let best: { p: Poi; s: number } | null = null;
  for (const p of foodPool) {
    if (consumed.has(p.id)) continue;
    const cost = p.estimatedCostEur ?? MEAL_BUDGET[prefs.priceLevel];
    if (cost > maxCost) continue;
    // If we know when we want to eat, prefer places open at that time. Places
    // without opening_hours data are kept as candidates — conservative default.
    if (window && !isOpenThroughout(p.openingHours, window)) continue;
    let s = p.score;
    if (centroid) {
      const km = haversineKm(centroid, { lat: p.lat, lng: p.lng });
      s += Math.max(0, 0.3 - km * 0.03);
    }
    if (!best || s > best.s) best = { p, s };
  }
  if (best) consumed.add(best.p.id);
  return best?.p ?? null;
}

function buildMealPlanItem(
  slot: MealSlot,
  picked: Poi | null,
  prefs: FoodPreferences,
): PlanItem {
  const mealBudget = prefs.avgPricePerMealEur ?? MEAL_BUDGET[prefs.priceLevel];
  const slotCfg = MEAL_SLOTS[slot];
  if (picked) {
    return {
      poiId: picked.id,
      title: picked.name,
      category: "food",
      lat: picked.lat,
      lng: picked.lng,
      durationMinutes: picked.estimatedDurationMin ?? slotCfg.durationMin,
      costEur: picked.estimatedCostEur ?? mealBudget,
      isMustHave: false,
      openingHours: picked.openingHours,
      preferredStartMin: slotCfg.startMin,
      note: `${capitalize(slot)} · cuisine: ${pickCuisineLabel(picked, prefs)}`,
    };
  }
  // Fallback placeholder when no matching restaurant was found.
  return {
    poiId: null,
    title: `${capitalize(slot)} (pick a spot)`,
    category: "food",
    lat: null,
    lng: null,
    durationMinutes: slotCfg.durationMin,
    costEur: mealBudget,
    isMustHave: false,
    openingHours: null,
    preferredStartMin: slotCfg.startMin,
    note: `Unplanned ${slot} — add your own or edit preferences.`,
  };
}

function pickCuisineLabel(p: Poi, prefs: FoodPreferences): string {
  const raw = ((p.tags.cuisine ?? p.tags.food ?? "") as string).toLowerCase();
  if (raw) return raw.split(/[;,]/)[0]!.trim();
  return prefs.cuisines[0] ?? "local";
}

function capitalize(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

function buildMustHavePlanItem(m: MustHaveItem & { matchedPoi?: Poi }): PlanItem | null {
  if (m.matchedPoi) {
    return {
      poiId: m.matchedPoi.id,
      title: m.matchedPoi.name,
      category: m.matchedPoi.category,
      lat: m.matchedPoi.lat,
      lng: m.matchedPoi.lng,
      durationMinutes: m.matchedPoi.estimatedDurationMin ?? 75,
      costEur: m.estimatedCost ?? m.matchedPoi.estimatedCostEur ?? 0,
      isMustHave: true,
      openingHours: m.matchedPoi.openingHours,
    };
  }
  return {
    poiId: null,
    title: m.title,
    category: m.category ?? "sightseeing",
    lat: null,
    lng: null,
    durationMinutes: 75,
    costEur: m.estimatedCost ?? 0,
    isMustHave: true,
    openingHours: null,
  };
}

function findBestMatch(m: MustHaveItem, pois: Poi[]): Poi | undefined {
  const q = m.title.toLowerCase();
  let best: { poi: Poi; score: number } | undefined;
  for (const p of pois) {
    const name = p.name.toLowerCase();
    let s = 0;
    if (name === q) s = 1;
    else if (name.includes(q) || q.includes(name)) s = 0.6;
    else {
      const overlap = q
        .split(/\s+/)
        .filter((t) => t.length > 3 && name.includes(t)).length;
      s = overlap * 0.2;
    }
    if (s > 0 && (!best || s > best.score)) best = { poi: p, score: s };
  }
  return best && best.score >= 0.2 ? best.poi : undefined;
}

function orderDayItems(items: PlanItem[]): PlanItem[] {
  const anchored = items
    .filter((i) => i.preferredStartMin != null)
    .sort((a, b) => (a.preferredStartMin ?? 0) - (b.preferredStartMin ?? 0));
  const free = items.filter((i) => i.preferredStartMin == null);

  // If no anchors, fall back to plain NN.
  if (anchored.length === 0) return orderByNearestNeighbor(free);

  // Split `free` into buckets between each pair of anchors using whichever
  // coord is available to minimise walking within each bucket.
  const out: PlanItem[] = [];
  let pool = [...free];
  for (let i = 0; i < anchored.length; i++) {
    const cur = anchored[i]!;
    const next = anchored[i + 1];
    // Items to place before `cur`: ideally close to cur's position.
    const bucket: PlanItem[] = [];
    const centroid =
      cur.lat != null ? { lat: cur.lat, lng: cur.lng! } : null;
    // Heuristic: pull one or two nearest POIs before each anchor, rest saved
    // for later anchors. Keeps days from cramming everything pre-breakfast.
    const maxBefore = i === 0 ? 1 : 2;
    const takeCount = Math.min(
      maxBefore,
      Math.ceil(pool.length / Math.max(1, anchored.length - i)),
    );
    for (let k = 0; k < takeCount && pool.length > 0; k++) {
      const idx = centroid
        ? pickClosestIndex(pool, centroid)
        : 0;
      bucket.push(pool.splice(idx, 1)[0]!);
    }
    out.push(...orderByNearestNeighbor(bucket));
    out.push(cur);
    if (!next) out.push(...orderByNearestNeighbor(pool));
  }
  return out;
}

function pickClosestIndex(pool: PlanItem[], centroid: { lat: number; lng: number }): number {
  let best = 0;
  let bestKm = Infinity;
  for (let i = 0; i < pool.length; i++) {
    const p = pool[i]!;
    if (p.lat == null) continue;
    const km = haversineKm(centroid, { lat: p.lat, lng: p.lng! });
    if (km < bestKm) {
      bestKm = km;
      best = i;
    }
  }
  return best;
}

function orderByNearestNeighbor(items: PlanItem[]): PlanItem[] {
  if (items.length <= 1) return items;
  const mustFirst = items.findIndex((i) => i.isMustHave);
  const start = mustFirst >= 0 ? mustFirst : 0;
  const ordered: PlanItem[] = [];
  const remaining = [...items];
  ordered.push(remaining.splice(start, 1)[0]!);
  while (remaining.length) {
    const last = ordered[ordered.length - 1]!;
    let nextIdx = 0;
    if (last.lat != null) {
      let bestKm = Infinity;
      for (let i = 0; i < remaining.length; i++) {
        const r = remaining[i]!;
        if (r.lat == null) continue;
        const km = haversineKm(
          { lat: last.lat!, lng: last.lng! },
          { lat: r.lat, lng: r.lng! },
        );
        if (km < bestKm) {
          bestKm = km;
          nextIdx = i;
        }
      }
    }
    ordered.push(remaining.splice(nextIdx, 1)[0]!);
  }
  return ordered;
}

function addDaysIso(startIso: string, days: number): string {
  const d = new Date(`${startIso}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

function dayCount(start: string, end: string): number {
  const s = new Date(`${start}T00:00:00Z`).getTime();
  const e = new Date(`${end}T00:00:00Z`).getTime();
  return Math.max(1, Math.round((e - s) / 86_400_000) + 1);
}

function avg(xs: number[]): number {
  return xs.reduce((a, b) => a + b, 0) / xs.length;
}

function haversineKm(
  a: { lat: number; lng: number },
  b: { lat: number; lng: number },
): number {
  const R = 6371;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const sa =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(sa));
}

function toRad(deg: number): number {
  return (deg * Math.PI) / 180;
}

function round1(n: number): number {
  return Math.round(n * 10) / 10;
}
