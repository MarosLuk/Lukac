import { useCallback, useEffect, useState } from "react";
import {
  View,
  Text,
  StyleSheet,
  ActivityIndicator,
  Pressable,
  Linking,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { Stack, useLocalSearchParams } from "expo-router";
import { WebView } from "react-native-webview";
import { getPoi, previewUrl, type PoiDetail } from "../../src/lib/pois";

export default function PoiPreviewScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const [poi, setPoi] = useState<PoiDetail | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [webError, setWebError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!id) return;
    setLoading(true);
    setError(null);
    try {
      const p = await getPoi(id);
      if (!p) setError("POI not found");
      else setPoi(p);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Load failed");
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    void load();
  }, [load]);

  if (loading) {
    return (
      <SafeAreaView style={styles.container}>
        <Stack.Screen options={{ title: "Preview" }} />
        <View style={styles.center}>
          <ActivityIndicator />
        </View>
      </SafeAreaView>
    );
  }
  if (error || !poi) {
    return (
      <SafeAreaView style={styles.container}>
        <Stack.Screen options={{ title: "Preview" }} />
        <View style={styles.center}>
          <Text style={styles.error}>{error ?? "Not found"}</Text>
        </View>
      </SafeAreaView>
    );
  }

  const url = previewUrl(poi);

  return (
    <SafeAreaView style={styles.container} edges={["bottom"]}>
      <Stack.Screen options={{ title: poi.name }} />
      <View style={styles.metaBar}>
        <Text style={styles.metaTitle} numberOfLines={1}>
          {poi.name}
        </Text>
        <Text style={styles.metaSub} numberOfLines={1}>
          {poi.category}
          {poi.estimated_cost_eur != null ? ` · ~€${poi.estimated_cost_eur}` : ""}
          {poi.estimated_duration_min ? ` · ${poi.estimated_duration_min}m visit` : ""}
        </Text>
        {poi.opening_hours && (
          <Text style={styles.metaHours} numberOfLines={2}>
            Hours: {poi.opening_hours}
          </Text>
        )}
        <Pressable onPress={() => Linking.openURL(url)} style={styles.openExternal}>
          <Text style={styles.openExternalText}>Open in browser ↗</Text>
        </Pressable>
      </View>

      {webError ? (
        <View style={styles.center}>
          <Text style={styles.error}>This page refused to embed.</Text>
          <Pressable onPress={() => Linking.openURL(url)} style={styles.cta}>
            <Text style={styles.ctaText}>Open in browser</Text>
          </Pressable>
        </View>
      ) : (
        <WebView
          source={{ uri: url }}
          style={{ flex: 1 }}
          originWhitelist={["*"]}
          onError={(e) => setWebError(e.nativeEvent.description)}
          startInLoadingState
          renderLoading={() => (
            <View style={styles.center}>
              <ActivityIndicator />
            </View>
          )}
        />
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: "#f8fafc" },
  center: { flex: 1, alignItems: "center", justifyContent: "center", padding: 16, gap: 8 },
  error: { color: "#dc2626" },
  metaBar: { padding: 12, backgroundColor: "white", borderBottomWidth: 1, borderBottomColor: "#e2e8f0" },
  metaTitle: { fontSize: 16, fontWeight: "700" },
  metaSub: { color: "#475569", fontSize: 12, marginTop: 2 },
  metaHours: { color: "#64748b", fontSize: 11, marginTop: 4, fontStyle: "italic" },
  openExternal: { marginTop: 8, alignSelf: "flex-start" },
  openExternalText: { color: "#0284c7", fontWeight: "600", fontSize: 13 },
  cta: {
    backgroundColor: "#0284c7",
    paddingHorizontal: 18,
    paddingVertical: 10,
    borderRadius: 8,
  },
  ctaText: { color: "white", fontWeight: "600" },
});
