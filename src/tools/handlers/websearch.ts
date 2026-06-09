/**
 * WEBSEARCH tool handlers: fetch_url, search_sap_web
 * - fetch_url: Extracts readable content from a URL via Tavily Extract API.
 * - search_sap_web: Searches SAP Help, SAP Community and SAP Notes via Tavily Search API.
 * Returns compact results (title + URL + snippet) to minimize token usage.
 */

import type { ADTClient } from "abap-adt-api";
import type { ToolResult } from "../../types.js";
import { S_FetchUrl, S_SearchSapWeb } from "../../schemas.js";
import { cfg } from "../../config.js";

function ok(text: string): ToolResult { return { content: [{ type: "text", text }] }; }
function err(text: string): ToolResult { return { content: [{ type: "text", text }], isError: true }; }

interface TavilyResult {
  title: string;
  url: string;
  content: string;
  score: number;
}

interface TavilyResponse {
  results: TavilyResult[];
  query: string;
}

const SOURCE_DOMAINS: Record<string, string[]> = {
  help:      ["help.sap.com"],
  community: ["community.sap.com"],
  notes:     ["me.sap.com", "launchpad.support.sap.com"],
};

const SOURCE_LABELS: Record<string, string> = {
  help:      "SAP Help",
  community: "SAP Community",
  notes:     "SAP Notes/KBA",
};

async function tavilySearch(
  query: string,
  includeDomains: string[],
  maxResults: number,
): Promise<TavilyResult[]> {
  const resp = await fetch("https://api.tavily.com/search", {
    method: "POST",
    signal: AbortSignal.timeout(15_000),
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      api_key: cfg.tavilyApiKey,
      query,
      max_results: maxResults,
      include_domains: includeDomains,
      search_depth: "basic",
    }),
  });

  if (!resp.ok) {
    const body = await resp.text().catch(() => "");
    throw new Error(`Tavily API HTTP ${resp.status}: ${body.slice(0, 200)}`);
  }

  const data = (await resp.json()) as TavilyResponse;
  return data.results ?? [];
}

function formatResults(source: string, items: TavilyResult[]): string {
  if (items.length === 0) return `### ${SOURCE_LABELS[source]}\nKeine Treffer.`;

  const lines = items.map((item, i) =>
    `${i + 1}. **${item.title}**\n   ${item.url}\n   ${item.content.replace(/\n/g, " ").trim().slice(0, 200)}`
  );
  return `### ${SOURCE_LABELS[source]} (${items.length} Treffer)\n\n${lines.join("\n\n")}`;
}

// ── fetch_url handler ─────────────────────────────────────────────────────────

interface TavilyExtractResult {
  url: string;
  raw_content: string;
}

interface TavilyExtractResponse {
  results: TavilyExtractResult[];
  failed_results?: { url: string; error: string }[];
}

export async function handleFetchUrl(_client: ADTClient, args: Record<string, unknown>): Promise<ToolResult> {
  if (!cfg.tavilyApiKey) {
    return err(
      "Tavily API nicht konfiguriert. " +
      "Bitte TAVILY_API_KEY in der .env setzen.\n" +
      "Setup: https://tavily.com/ → Sign up → API Key kopieren.\n" +
      "Free Tier: 1000 Searches/Monat."
    );
  }

  const p = S_FetchUrl.parse(args);
  const maxLen = 15000;

  // Strategy 1: Try Tavily Extract API first
  try {
    const resp = await fetch("https://api.tavily.com/extract", {
      method: "POST",
      signal: AbortSignal.timeout(30_000),
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        api_key: cfg.tavilyApiKey,
        urls: [p.url],
      }),
    });

    if (resp.ok) {
      const data = (await resp.json()) as TavilyExtractResponse;
      if (data.results && data.results.length > 0) {
        const content = data.results[0].raw_content;
        if (content && content.trim().length > 0) {
          const truncated = content.length > maxLen
            ? content.slice(0, maxLen) + `\n\n--- [Inhalt gekürzt: ${content.length} → ${maxLen} Zeichen] ---`
            : content;
          return ok(`# Inhalt von: ${p.url}\n\n${truncated}`);
        }
      }
    }
  } catch { /* Extract failed, try fallback */ }

  // Strategy 2: Fallback — use Tavily Search with URL as query + include_raw_content
  try {
    const domain = new URL(p.url).hostname;
    const resp = await fetch("https://api.tavily.com/search", {
      method: "POST",
      signal: AbortSignal.timeout(20_000),
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        api_key: cfg.tavilyApiKey,
        query: p.url,
        max_results: 3,
        include_domains: [domain],
        search_depth: "advanced",
        include_raw_content: true,
      }),
    });

    if (resp.ok) {
      const data = (await resp.json()) as { results: Array<{ url: string; title: string; raw_content?: string; content: string }> };
      // Find the exact URL match or best match
      const exact = data.results?.find(r => r.url === p.url || r.url.includes(p.url.split("?")[0]));
      const best = exact ?? data.results?.[0];
      if (best) {
        const content = best.raw_content || best.content;
        if (content && content.trim().length > 0) {
          const truncated = content.length > maxLen
            ? content.slice(0, maxLen) + `\n\n--- [Inhalt gekürzt: ${content.length} → ${maxLen} Zeichen] ---`
            : content;
          return ok(`# Inhalt von: ${best.url}\n**${best.title}**\n\n${truncated}`);
        }
      }
    }
  } catch { /* Search fallback also failed */ }

  return err(
    `URL konnte nicht gelesen werden: ${p.url}\n\n` +
    `Mögliche Ursachen:\n` +
    `- Die Seite blockiert automatisierte Zugriffe\n` +
    `- Die Seite benötigt JavaScript-Rendering das nicht unterstützt wird\n` +
    `- Netzwerkfehler\n\n` +
    `Tipp: Versuche search_sap_web mit relevanten Suchbegriffen statt der direkten URL.`
  );
}

// ── search_sap_web handler ────────────────────────────────────────────────────

export async function handleSearchSapWeb(_client: ADTClient, args: Record<string, unknown>): Promise<ToolResult> {
  if (!cfg.tavilyApiKey) {
    return err(
      "Tavily API nicht konfiguriert. " +
      "Bitte TAVILY_API_KEY in der .env setzen.\n" +
      "Setup: https://tavily.com/ → Sign up → API Key kopieren.\n" +
      "Free Tier: 1000 Searches/Monat."
    );
  }

  const p = S_SearchSapWeb.parse(args);
  const sources = p.sources ?? ["help", "community", "notes"];
  const maxResults = p.maxResults ?? 5;

  // Enrich query with SAP ABAP context
  const enrichedQuery = `SAP ABAP ${p.query}`;

  // Run all source searches in parallel
  const results = await Promise.allSettled(
    sources.map(async (source) => {
      const domains = SOURCE_DOMAINS[source];
      if (!domains) return { source, items: [] as TavilyResult[] };
      const items = await tavilySearch(enrichedQuery, domains, maxResults);
      return { source, items };
    })
  );

  const sections: string[] = [];
  let totalHits = 0;

  for (const result of results) {
    if (result.status === "fulfilled") {
      const { source, items } = result.value;
      totalHits += items.length;
      sections.push(formatResults(source, items));
    } else {
      sections.push(`### Fehler\n${result.reason}`);
    }
  }

  if (totalHits === 0) {
    return ok(
      `# SAP Web Search: "${p.query}"\n\nKeine Treffer gefunden.\n\n` +
      `**Tipps:**\n- Andere Suchbegriffe verwenden\n- Fehlermeldung kürzen\n- Englische Begriffe probieren`
    );
  }

  return ok(
    `# SAP Web Search: "${p.query}"\n\n${sections.join("\n\n---\n\n")}\n\n` +
    `---\n🔍 ${totalHits} Treffer aus ${sources.map(s => SOURCE_LABELS[s]).join(", ")}`
  );
}
