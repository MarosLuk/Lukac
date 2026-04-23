import { useEffect, useState, useCallback } from "react";
import {
  View,
  Text,
  FlatList,
  StyleSheet,
  RefreshControl,
  ActivityIndicator,
  Pressable,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { Stack, router } from "expo-router";
import { useAuth } from "../src/lib/auth";
import { listTrips } from "../src/lib/trips";
import { tripDurationDays, type Trip } from "@tp/shared";

export default function HomeScreen() {
  const { session, loading: authLoading } = useAuth();
  const [trips, setTrips] = useState<Trip[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!session) return;
    setLoading(true);
    setError(null);
    try {
      setTrips(await listTrips());
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to load");
    } finally {
      setLoading(false);
    }
  }, [session]);

  useEffect(() => {
    void load();
  }, [load]);

  if (authLoading) {
    return (
      <View style={styles.center}>
        <ActivityIndicator />
      </View>
    );
  }

  if (!session) {
    return (
      <SafeAreaView style={styles.container}>
        <Stack.Screen options={{ title: "Travel Planner" }} />
        <View style={styles.center}>
          <Text style={styles.title}>Welcome</Text>
          <Text style={styles.muted}>Sign in to see your trips.</Text>
          <Pressable style={styles.button} onPress={() => router.push("/login")}>
            <Text style={styles.buttonText}>Sign in</Text>
          </Pressable>
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container}>
      <Stack.Screen options={{ title: "My trips" }} />
      <FlatList
        data={trips}
        keyExtractor={(t) => t.id}
        refreshControl={<RefreshControl refreshing={loading} onRefresh={load} />}
        contentContainerStyle={{ padding: 16 }}
        ListEmptyComponent={
          !loading ? (
            <View style={styles.center}>
              <Text style={styles.muted}>
                {error ?? "No trips yet. Create one on the web app."}
              </Text>
            </View>
          ) : null
        }
        renderItem={({ item }) => {
          const days = tripDurationDays(item.startDate, item.endDate);
          return (
            <Pressable
              style={({ pressed }) => [styles.card, pressed && { opacity: 0.7 }]}
              onPress={() => router.push(`/trip/${item.id}`)}
            >
              <Text style={styles.cardTitle}>{item.destination}</Text>
              <Text style={styles.cardMeta}>
                {item.startDate} → {item.endDate} · {days} day{days > 1 ? "s" : ""}
              </Text>
              <Text style={styles.cardMeta}>
                Budget: {item.totalBudget} {item.currency} · {item.style}
              </Text>
            </Pressable>
          );
        }}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: "#f8fafc" },
  center: { flex: 1, alignItems: "center", justifyContent: "center", padding: 24, gap: 8 },
  title: { fontSize: 22, fontWeight: "700" },
  muted: { color: "#64748b", textAlign: "center" },
  button: {
    marginTop: 12,
    backgroundColor: "#0284c7",
    paddingHorizontal: 20,
    paddingVertical: 10,
    borderRadius: 8,
  },
  buttonText: { color: "white", fontWeight: "600" },
  card: {
    backgroundColor: "white",
    padding: 16,
    borderRadius: 12,
    marginBottom: 12,
    shadowColor: "#000",
    shadowOpacity: 0.05,
    shadowRadius: 4,
    elevation: 1,
  },
  cardTitle: { fontSize: 18, fontWeight: "600", marginBottom: 4 },
  cardMeta: { color: "#475569", fontSize: 13, marginTop: 2 },
});
