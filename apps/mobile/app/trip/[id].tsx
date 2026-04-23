import { useCallback, useEffect, useMemo, useState } from "react";
import {
  View,
  Text,
  ScrollView,
  StyleSheet,
  ActivityIndicator,
  Pressable,
  RefreshControl,
  Alert,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { Stack, useLocalSearchParams, router } from "expo-router";
import {
  currentDayIndex,
  formatMinutesOfDay,
  tripDurationDays,
  type Itinerary,
  type ItineraryItem,
  type ItineraryItemStatus,
  type Trip,
  type TravelLeg,
  type TravelOption,
} from "@tp/shared";
import { getTripWithItinerary, patchItineraryItem } from "../../src/lib/trips";
import { supabase } from "../../src/lib/supabase";

export default function TripDetailScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const [trip, setTrip] = useState<Trip | null>(null);
  const [itinerary, setItinerary] = useState<Itinerary | null>(null);
  const [loading, setLoading] = useState(true);
  const [generating, setGenerating] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [selectedDay, setSelectedDay] = useState<number | null>(null);
  const [mutatingId, setMutatingId] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!id) return;
    setLoading(true);
    setError(null);
    try {
      const res = await getTripWithItinerary(id);
      if (!res) {
        setError("Trip not found.");
        return;
      }
      setTrip(res.trip);
      setItinerary(res.itinerary);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to load");
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    void load();
  }, [load]);

  // Default the day switcher to today (if within trip dates) once loaded.
  useEffect(() => {
    if (!trip || selectedDay !== null) return;
    const today = currentDayIndex(trip.startDate, trip.endDate);
    const days = tripDurationDays(trip.startDate, trip.endDate);
    const clamped =
      today < 0 ? 0 : today >= days ? days - 1 : today;
    setSelectedDay(clamped);
  }, [trip, selectedDay]);

  async function generate() {
    if (!id) return;
    setGenerating(true);
    setError(null);
    try {
      const { data: sess } = await supabase.auth.getSession();
      const token = sess.session?.access_token;
      if (!token) throw new Error("Not signed in");
      const apiBase = process.env.EXPO_PUBLIC_WEB_API_URL ?? "http://127.0.0.1:3000";
      const res = await fetch(`${apiBase}/api/trips/${id}/generate`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
      });
      const body = await res.json();
      if (!res.ok || !body.ok) throw new Error(body?.error?.message ?? `HTTP ${res.status}`);
      setItinerary(body.data.itinerary as Itinerary);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Generate failed");
    } finally {
      setGenerating(false);
    }
  }

  async function setStatus(item: ItineraryItem, next: ItineraryItemStatus) {
    setMutatingId(item.id);
    try {
      const updated = await patchItineraryItem(item.id, { status: next });
      setItinerary((it) =>
        it
          ? {
              ...it,
              items: it.items.map((i) => (i.id === updated.id ? updated : i)),
            }
          : it,
      );
    } catch (e) {
      Alert.alert("Update failed", e instanceof Error ? e.message : "Unknown error");
    } finally {
      setMutatingId(null);
    }
  }

  const days = trip ? tripDurationDays(trip.startDate, trip.endDate) : 0;
  const today = trip ? currentDayIndex(trip.startDate, trip.endDate) : -1;
  const activeDay = selectedDay ?? 0;
  const dayItems = useMemo(
    () => (itinerary?.items ?? []).filter((i) => i.dayIndex === activeDay),
    [itinerary, activeDay],
  );
  const nowMinutes = useNowMinutes();
  const isToday = trip ? today === activeDay : false;

  if (loading || !trip) {
    return (
      <SafeAreaView style={styles.container}>
        <Stack.Screen options={{ title: "Trip" }} />
        <View style={styles.center}>
          {error ? <Text style={styles.error}>{error}</Text> : <ActivityIndicator />}
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container}>
      <Stack.Screen options={{ title: trip.destination }} />
      <ScrollView
        contentContainerStyle={{ padding: 16, paddingBottom: 40 }}
        refreshControl={<RefreshControl refreshing={false} onRefresh={load} />}
      >
        <Text style={styles.title}>{trip.destination}</Text>
        <Text style={styles.meta}>
          {trip.startDate} → {trip.endDate} · {days} day{days > 1 ? "s" : ""} · budget{" "}
          {trip.totalBudget} {trip.currency}
        </Text>

        <Pressable style={styles.cta} onPress={generate} disabled={generating}>
          {generating ? (
            <ActivityIndicator color="white" />
          ) : (
            <Text style={styles.ctaText}>
              {itinerary ? "Regenerate plan" : "Generate plan"}
            </Text>
          )}
        </Pressable>
        {generating && (
          <Text style={styles.note}>
            First run for a city can take 20–40s (Overpass + Wikivoyage).
          </Text>
        )}
        {error && <Text style={styles.error}>{error}</Text>}

        {itinerary && (
          <>
            <DayPicker
              count={days}
              selected={activeDay}
              today={today}
              startDate={trip.startDate}
              onSelect={setSelectedDay}
            />
            <DayTimeline
              items={dayItems}
              nowMinutes={isToday ? nowMinutes : null}
              mutatingId={mutatingId}
              onSetStatus={setStatus}
            />
          </>
        )}
      </ScrollView>
    </SafeAreaView>
  );
}

function DayPicker({
  count,
  selected,
  today,
  startDate,
  onSelect,
}: {
  count: number;
  selected: number;
  today: number;
  startDate: string;
  onSelect: (i: number) => void;
}) {
  return (
    <ScrollView
      horizontal
      showsHorizontalScrollIndicator={false}
      contentContainerStyle={{ paddingVertical: 16, gap: 8 }}
    >
      {Array.from({ length: count }, (_, i) => {
        const active = i === selected;
        const isToday = i === today;
        return (
          <Pressable
            key={i}
            onPress={() => onSelect(i)}
            style={[
              styles.dayChip,
              active && styles.dayChipActive,
              isToday && !active && styles.dayChipToday,
            ]}
          >
            <Text style={[styles.dayChipLabel, active && styles.dayChipLabelActive]}>
              Day {i + 1}
            </Text>
            <Text style={[styles.dayChipDate, active && styles.dayChipLabelActive]}>
              {addDays(startDate, i).slice(5)}
              {isToday ? " · today" : ""}
            </Text>
          </Pressable>
        );
      })}
    </ScrollView>
  );
}

function DayTimeline({
  items,
  nowMinutes,
  mutatingId,
  onSetStatus,
}: {
  items: ItineraryItem[];
  nowMinutes: number | null;
  mutatingId: string | null;
  onSetStatus: (item: ItineraryItem, next: ItineraryItemStatus) => void;
}) {
  if (items.length === 0) {
    return (
      <View style={styles.empty}>
        <Text style={styles.meta}>No stops for this day.</Text>
      </View>
    );
  }

  // Compute first pending stop relative to "now" → highlighted as "next".
  const nextIdx =
    nowMinutes == null
      ? -1
      : items.findIndex(
          (it) =>
            it.status === "pending" && it.startMinutes + it.durationMinutes >= nowMinutes,
        );

  return (
    <View style={{ marginTop: 4 }}>
      {items.map((it, i) => {
        const done = it.status === "done";
        const skipped = it.status === "skipped";
        const muted = done || skipped;
        const isNow =
          nowMinutes != null &&
          nowMinutes >= it.startMinutes &&
          nowMinutes < it.startMinutes + it.durationMinutes &&
          it.status === "pending";
        const isNext = !isNow && i === nextIdx;

        return (
          <View key={it.id}>
            {it.travelFromPrev && <TravelRow leg={it.travelFromPrev} />}
          <View
            style={[
              styles.stopCard,
              isNow && styles.stopCardNow,
              isNext && styles.stopCardNext,
              muted && styles.stopCardMuted,
            ]}
          >
            <View style={styles.stopRow}>
              <Text style={[styles.stopTime, muted && styles.stopMuted]}>
                {formatMinutesOfDay(it.startMinutes)}
              </Text>
              <View style={{ flex: 1 }}>
                <Pressable
                  onPress={() => it.poiId && router.push(`/poi/${it.poiId}`)}
                  disabled={!it.poiId}
                  style={styles.stopHead}
                >
                  <Text
                    style={[
                      styles.stopTitle,
                      done && { textDecorationLine: "line-through" },
                      muted && styles.stopMuted,
                    ]}
                    numberOfLines={2}
                  >
                    {it.title}
                    {it.poiId ? "  ↗" : ""}
                    {it.isMustHave ? "  ★" : ""}
                  </Text>
                  {isNow && <Tag color="#059669">NOW</Tag>}
                  {isNext && <Tag color="#0284c7">NEXT</Tag>}
                  {done && <Tag color="#64748b">done</Tag>}
                  {skipped && <Tag color="#b45309">skipped</Tag>}
                </Pressable>
                <Text style={[styles.stopMeta, muted && styles.stopMuted]}>
                  {it.durationMinutes}m · {it.category}
                  {it.costEur > 0 ? ` · ~€${it.costEur.toFixed(0)}` : ""}
                  {it.travelFromPrev
                    ? ` · ${it.travelFromPrev.minutes}m ${it.travelFromPrev.mode}`
                    : ""}
                </Text>
                {it.note && <Text style={styles.stopNote}>{it.note}</Text>}

                <View style={styles.actions}>
                  {it.status === "pending" && (
                    <>
                      <ActionButton
                        label="✓ Check in"
                        loading={mutatingId === it.id}
                        onPress={() => onSetStatus(it, "done")}
                      />
                      <ActionButton
                        label="Skip"
                        variant="ghost"
                        loading={mutatingId === it.id}
                        onPress={() => onSetStatus(it, "skipped")}
                      />
                    </>
                  )}
                  {it.status !== "pending" && (
                    <ActionButton
                      label="Undo"
                      variant="ghost"
                      loading={mutatingId === it.id}
                      onPress={() => onSetStatus(it, "pending")}
                    />
                  )}
                </View>
              </View>
            </View>
          </View>
          </View>
        );
      })}
    </View>
  );
}

function TravelRow({ leg }: { leg: TravelLeg }) {
  if (!leg.options || leg.options.length === 0) return null;
  return (
    <View style={styles.travelRow}>
      <View style={styles.travelLine} />
      <View style={styles.travelChips}>
        {leg.options.map((opt, i) => (
          <TravelChip key={i} option={opt} recommended={i === leg.recommendedIndex} />
        ))}
      </View>
    </View>
  );
}

function TravelChip({ option, recommended }: { option: TravelOption; recommended: boolean }) {
  const icon = option.mode === "walk"
    ? "🚶"
    : option.mode === "transit"
      ? "🚌"
      : option.mode === "taxi"
        ? "🚕"
        : "🚗";
  return (
    <View
      style={[
        styles.travelChip,
        recommended && styles.travelChipRecommended,
        option.source === "estimated" && styles.travelChipEstimated,
      ]}
    >
      <Text style={styles.travelIcon}>{icon}</Text>
      <View>
        <Text style={[styles.travelMain, recommended && { color: "#0284c7" }]}>
          {option.minutes}m
          {option.costEur > 0 ? ` · €${option.costEur.toFixed(option.costEur < 10 ? 1 : 0)}` : " · free"}
        </Text>
        <Text style={styles.travelSub}>
          {option.distanceKm}km
          {option.source === "estimated" ? " · est." : ""}
        </Text>
      </View>
    </View>
  );
}

function Tag({ children, color }: { children: React.ReactNode; color: string }) {
  return (
    <View style={[styles.tag, { backgroundColor: color }]}>
      <Text style={styles.tagText}>{children}</Text>
    </View>
  );
}

function ActionButton({
  label,
  onPress,
  loading,
  variant = "solid",
}: {
  label: string;
  onPress: () => void;
  loading: boolean;
  variant?: "solid" | "ghost";
}) {
  return (
    <Pressable
      onPress={onPress}
      disabled={loading}
      style={({ pressed }) => [
        styles.actionBtn,
        variant === "ghost" ? styles.actionBtnGhost : styles.actionBtnSolid,
        pressed && { opacity: 0.7 },
        loading && { opacity: 0.5 },
      ]}
    >
      <Text
        style={variant === "ghost" ? styles.actionBtnTextGhost : styles.actionBtnTextSolid}
      >
        {label}
      </Text>
    </Pressable>
  );
}

function useNowMinutes(): number {
  const [now, setNow] = useState(() => computeNowMinutes());
  useEffect(() => {
    const t = setInterval(() => setNow(computeNowMinutes()), 60_000);
    return () => clearInterval(t);
  }, []);
  return now;
}

function computeNowMinutes(): number {
  const d = new Date();
  return d.getHours() * 60 + d.getMinutes();
}

function addDays(start: string, d: number): string {
  const dt = new Date(`${start}T00:00:00Z`);
  dt.setUTCDate(dt.getUTCDate() + d);
  return dt.toISOString().slice(0, 10);
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: "#f8fafc" },
  center: { flex: 1, alignItems: "center", justifyContent: "center", padding: 24 },
  title: { fontSize: 22, fontWeight: "700", marginBottom: 4 },
  meta: { color: "#475569", fontSize: 13 },
  cta: {
    marginTop: 16,
    backgroundColor: "#0284c7",
    paddingVertical: 12,
    borderRadius: 8,
    alignItems: "center",
  },
  ctaText: { color: "white", fontWeight: "600", fontSize: 15 },
  note: { marginTop: 8, color: "#64748b", fontSize: 12 },
  error: { marginTop: 12, color: "#dc2626" },

  dayChip: {
    paddingVertical: 8,
    paddingHorizontal: 14,
    borderRadius: 10,
    backgroundColor: "white",
    borderWidth: 1,
    borderColor: "#e2e8f0",
    minWidth: 74,
    alignItems: "center",
  },
  dayChipActive: { backgroundColor: "#0284c7", borderColor: "#0284c7" },
  dayChipToday: { borderColor: "#059669" },
  dayChipLabel: { fontWeight: "600", color: "#334155", fontSize: 13 },
  dayChipLabelActive: { color: "white" },
  dayChipDate: { fontSize: 11, color: "#64748b", marginTop: 2 },

  empty: { paddingVertical: 24, alignItems: "center" },

  stopCard: {
    backgroundColor: "white",
    borderRadius: 12,
    marginBottom: 10,
    padding: 12,
    shadowColor: "#000",
    shadowOpacity: 0.04,
    shadowRadius: 4,
    borderLeftWidth: 4,
    borderLeftColor: "#e2e8f0",
  },
  stopCardNow: { borderLeftColor: "#059669", backgroundColor: "#ecfdf5" },
  stopCardNext: { borderLeftColor: "#0284c7" },
  stopCardMuted: { opacity: 0.55 },
  stopRow: { flexDirection: "row", gap: 10 },
  stopTime: { width: 56, fontSize: 13, fontWeight: "600", color: "#0f172a" },
  stopHead: { flexDirection: "row", alignItems: "center", gap: 6, flexWrap: "wrap" },
  stopTitle: { fontSize: 15, fontWeight: "600", color: "#0f172a", flex: 1 },
  stopMeta: { fontSize: 12, color: "#64748b", marginTop: 2 },
  stopMuted: { color: "#94a3b8" },
  stopNote: { fontSize: 12, color: "#b45309", marginTop: 4, fontStyle: "italic" },

  tag: { paddingHorizontal: 6, paddingVertical: 2, borderRadius: 4 },
  tagText: { color: "white", fontSize: 10, fontWeight: "700" },

  actions: { flexDirection: "row", gap: 8, marginTop: 10 },
  actionBtn: { paddingHorizontal: 12, paddingVertical: 6, borderRadius: 6 },
  actionBtnSolid: { backgroundColor: "#0f172a" },
  actionBtnGhost: { borderWidth: 1, borderColor: "#e2e8f0", backgroundColor: "white" },
  actionBtnTextSolid: { color: "white", fontWeight: "600", fontSize: 13 },
  actionBtnTextGhost: { color: "#334155", fontWeight: "600", fontSize: 13 },

  travelRow: { paddingLeft: 16, marginBottom: 8, marginTop: -2 },
  travelLine: {
    position: "absolute",
    left: 22,
    top: 0,
    bottom: 0,
    width: 2,
    backgroundColor: "#cbd5e1",
  },
  travelChips: { flexDirection: "row", flexWrap: "wrap", gap: 6, paddingLeft: 10, paddingVertical: 4 },
  travelChip: {
    flexDirection: "row",
    alignItems: "center",
    gap: 6,
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 8,
    backgroundColor: "white",
    borderWidth: 1,
    borderColor: "#e2e8f0",
  },
  travelChipRecommended: { borderColor: "#0284c7", backgroundColor: "#eff6ff" },
  travelChipEstimated: { borderStyle: "dashed" },
  travelIcon: { fontSize: 14 },
  travelMain: { fontSize: 12, fontWeight: "600", color: "#0f172a" },
  travelSub: { fontSize: 10, color: "#64748b" },
});
