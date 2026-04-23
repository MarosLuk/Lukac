// Thin wrapper around the `opening_hours` npm package. Parser is strict and
// throws on malformed OSM strings, which are common in the wild — we degrade
// gracefully to "open" when parsing fails so we never block planning.

// eslint-disable-next-line @typescript-eslint/no-require-imports
const OpeningHours = require("opening_hours") as new (
  value: string,
  nominatim_object?: unknown,
  optional_conf_parm?: unknown,
) => { getState(at?: Date): boolean; getNextChange(at?: Date): Date | undefined };

export interface Interval {
  startDate: Date;
  endDate: Date;
}

/**
 * Returns true if the POI is open for the entire [start, end] interval.
 * - If `oh` is null/empty we assume open (most POIs have no data).
 * - If parsing fails we assume open (never reject on parser bugs).
 */
export function isOpenThroughout(oh: string | null, interval: Interval): boolean {
  if (!oh) return true;
  let parser: { getState(at?: Date): boolean; getNextChange(at?: Date): Date | undefined };
  try {
    parser = new OpeningHours(oh);
  } catch {
    return true;
  }

  if (!parser.getState(interval.startDate)) return false;

  // Walk forward; if the next state change happens before endDate, we'd close
  // mid-visit. For the typical < 3h visit window this is cheap.
  let cursor = interval.startDate;
  let guard = 0;
  while (cursor < interval.endDate && guard < 20) {
    const next = parser.getNextChange(cursor);
    if (!next) return true; // no further changes — assume open
    if (next >= interval.endDate) return true;
    if (!parser.getState(next)) return false;
    cursor = new Date(next.getTime() + 60_000);
    guard++;
  }
  return true;
}
