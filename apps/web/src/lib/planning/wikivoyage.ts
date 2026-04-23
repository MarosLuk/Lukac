// Wikivoyage free API. We fetch the "Understand" intro (as city summary) and
// parse the first handful of "See" list items as highlights. Best-effort: if
// the page doesn't exist or the parse fails, we return nulls (planner still works).

const UA = "travel-planner-mvp/0.1 (local-dev)";
const API = "https://en.wikivoyage.org/w/api.php";

export interface WikivoyageData {
  summary: string | null;
  highlights: string[];
}

export async function fetchWikivoyage(city: string): Promise<WikivoyageData> {
  // 1) Resolve best-matching page title.
  const searchUrl = new URL(API);
  searchUrl.search = new URLSearchParams({
    action: "query",
    list: "search",
    srsearch: city,
    srlimit: "1",
    format: "json",
    origin: "*",
  }).toString();

  const searchRes = await fetch(searchUrl, { headers: { "User-Agent": UA } });
  if (!searchRes.ok) return { summary: null, highlights: [] };
  const searchJson = (await searchRes.json()) as {
    query?: { search?: Array<{ title: string }> };
  };
  const title = searchJson.query?.search?.[0]?.title;
  if (!title) return { summary: null, highlights: [] };

  // 2) Fetch page intro (plaintext, first paragraph).
  const extractUrl = new URL(API);
  extractUrl.search = new URLSearchParams({
    action: "query",
    prop: "extracts",
    exintro: "1",
    explaintext: "1",
    titles: title,
    format: "json",
    origin: "*",
  }).toString();
  const extractRes = await fetch(extractUrl, { headers: { "User-Agent": UA } });
  let summary: string | null = null;
  if (extractRes.ok) {
    const extractJson = (await extractRes.json()) as {
      query?: { pages?: Record<string, { extract?: string }> };
    };
    const pages = extractJson.query?.pages ?? {};
    const firstPage = Object.values(pages)[0];
    const extract = firstPage?.extract?.trim();
    if (extract) summary = extract.split("\n\n")[0]!.slice(0, 700);
  }

  // 3) Highlights from "See" section — parse the wikitext of that section.
  const highlights = await fetchSeeHighlights(title).catch(() => [] as string[]);

  return { summary, highlights: highlights.slice(0, 8) };
}

async function fetchSeeHighlights(title: string): Promise<string[]> {
  // Get sections index.
  const secUrl = new URL(API);
  secUrl.search = new URLSearchParams({
    action: "parse",
    page: title,
    prop: "sections",
    format: "json",
    origin: "*",
  }).toString();
  const secRes = await fetch(secUrl, { headers: { "User-Agent": UA } });
  if (!secRes.ok) return [];
  const secJson = (await secRes.json()) as {
    parse?: { sections?: Array<{ index: string; line: string }> };
  };
  const seeSec = secJson.parse?.sections?.find((s) => /^see\b/i.test(s.line));
  if (!seeSec) return [];

  // Fetch that section as wikitext.
  const wtUrl = new URL(API);
  wtUrl.search = new URLSearchParams({
    action: "parse",
    page: title,
    section: seeSec.index,
    prop: "wikitext",
    format: "json",
    origin: "*",
  }).toString();
  const wtRes = await fetch(wtUrl, { headers: { "User-Agent": UA } });
  if (!wtRes.ok) return [];
  const wtJson = (await wtRes.json()) as { parse?: { wikitext?: { "*": string } } };
  const wt = wtJson.parse?.wikitext?.["*"] ?? "";

  // Wikivoyage "See" items typically start with a * and use the {{see}} template,
  // e.g. `* {{see | name=Torre de Belém | ...}}`. Fall back to plain * lines.
  const highlights: string[] = [];
  const lineRe = /^\*+\s*(.+)$/gm;
  let m: RegExpExecArray | null;
  while ((m = lineRe.exec(wt)) !== null) {
    const raw = m[1]!;
    const nameMatch = /name=([^|}\n]+)/i.exec(raw);
    const name = (nameMatch ? nameMatch[1]! : raw)
      .replace(/\{\{[^}]*\}\}/g, "")
      .replace(/\[\[([^|\]]+\|)?([^\]]+)\]\]/g, "$2")
      .replace(/''+/g, "")
      .replace(/<[^>]+>/g, "")
      .trim();
    if (name && name.length < 120) highlights.push(name);
    if (highlights.length >= 20) break;
  }
  return highlights;
}
