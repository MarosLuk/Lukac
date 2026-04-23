export * from "./schemas/index";
export * from "./types/index";

export function tripDurationDays(startDate: string, endDate: string): number {
  const start = new Date(`${startDate}T00:00:00Z`).getTime();
  const end = new Date(`${endDate}T00:00:00Z`).getTime();
  return Math.max(1, Math.round((end - start) / 86_400_000) + 1);
}

export function dailyBudget(totalBudget: number, days: number): number {
  return days > 0 ? Math.floor(totalBudget / days) : totalBudget;
}
