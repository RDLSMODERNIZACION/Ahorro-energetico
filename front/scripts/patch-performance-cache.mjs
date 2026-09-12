import { readFileSync, writeFileSync } from "node:fs";

const pagePath = new URL("../app/page.tsx", import.meta.url);
const panelPath = new URL("../app/invoice-analysis-panel.tsx", import.meta.url);

let page = readFileSync(pagePath, "utf8");
if (!page.includes("// FRONT_PERF_CACHE_V1")) {
  const start = page.indexOf("async function api<T>(");
  const endNeedle = "\n}\n\nfunction dashboardPowerDemand";
  const end = page.indexOf(endNeedle, start);
  if (start < 0 || end < 0) {
    throw new Error("Could not locate api() helper in page.tsx");
  }

  const replacement = `// FRONT_PERF_CACHE_V1\nconst API_GET_TTL_MS = 60_000;\nconst apiGetCache = new Map<string, { expiresAt: number; value: unknown }>();\nconst apiInflight = new Map<string, Promise<unknown>>();\n\nasync function api<T>(\n  path: string,\n  session: Session,\n  init?: RequestInit,\n): Promise<T> {\n  const method = String(init?.method || \"GET\").toUpperCase();\n  const retryable = method === \"GET\";\n  const cacheKey = session.user?.id ? session.user.id + \"::\" + path : path;\n\n  if (retryable) {\n    const cached = apiGetCache.get(cacheKey);\n    if (cached && cached.expiresAt > Date.now()) return cached.value as T;\n    const pending = apiInflight.get(cacheKey);\n    if (pending) return pending as Promise<T>;\n  } else {\n    apiGetCache.clear();\n    apiInflight.clear();\n  }\n\n  const run = async (): Promise<T> => {\n    let lastError: Error | undefined;\n    for (let attempt = 0; attempt < (retryable ? 3 : 1); attempt++) {\n      try {\n        const response = await fetch(API + path, {\n          ...init,\n          cache: \"no-store\",\n          headers: {\n            Authorization: \"Bearer \" + session.access_token,\n            ...(init?.body instanceof FormData\n              ? {}\n              : { \"Content-Type\": \"application/json\" }),\n            ...(init?.headers || {}),\n          },\n        });\n        if (response.ok) {\n          if (response.status === 204) return undefined as T;\n          const value = (await response.json()) as T;\n          if (retryable) {\n            apiGetCache.set(cacheKey, {\n              expiresAt: Date.now() + API_GET_TTL_MS,\n              value,\n            });\n          }\n          return value;\n        }\n        const body = await response.text();\n        const error = new Error(body || \"Error \" + response.status);\n        if (!retryable || ![500, 502, 503, 504].includes(response.status))\n          throw error;\n        lastError = error;\n      } catch (error) {\n        lastError =\n          error instanceof Error ? error : new Error(\"Error de conexión\");\n        if (!retryable) throw lastError;\n      }\n      if (attempt < 2)\n        await new Promise((resolve) => setTimeout(resolve, 350 * (attempt + 1)));\n    }\n    throw lastError || new Error(\"No se pudo consultar la API\");\n  };\n\n  if (!retryable) return run();\n  const promise = run();\n  apiInflight.set(cacheKey, promise as Promise<unknown>);\n  try {\n    return await promise;\n  } finally {\n    apiInflight.delete(cacheKey);\n  }\n}`;

  page = page.slice(0, start) + replacement + page.slice(end + 2);
  writeFileSync(pagePath, page, "utf8");
  console.log("Applied frontend GET cache and in-flight request deduplication.");
} else {
  console.log("Frontend request cache already applied.");
}

let panel = readFileSync(panelPath, "utf8");
if (!panel.includes("// INVOICE_PANEL_PERF_V1")) {
  const markerNeedle = `const money = new Intl.NumberFormat("es-AR", {\n  style: "currency",\n  currency: "ARS",\n  maximumFractionDigits: 0,\n});`;
  if (!panel.includes(markerNeedle)) {
    throw new Error("Could not locate money formatter in invoice-analysis-panel.tsx");
  }
  panel = panel.replace(
    markerNeedle,
    markerNeedle + `\n\n// INVOICE_PANEL_PERF_V1\nconst advancedTariffCache = new Map<string, AdvancedTariffHistoryResponse>();\nconst advancedTariffInflight = new Map<string, Promise<AdvancedTariffHistoryResponse>>();`,
  );

  const selectedNeedle = `  const selected =\n    history.find((i) => periodOf(i) === selectedPeriod) || invoice;`;
  if (!panel.includes(selectedNeedle)) {
    throw new Error("Could not locate selected invoice lookup for memoization");
  }
  panel = panel.replace(
    selectedNeedle,
    `  const selected = useMemo(\n    () => history.find((i) => periodOf(i) === selectedPeriod) || invoice,\n    [history, selectedPeriod, invoice],\n  );`,
  );

  const sortedNeedle = `  const sorted = [...history].sort((a, b) =>\n    periodOf(a).localeCompare(periodOf(b)),\n  );`;
  if (!panel.includes(sortedNeedle)) {
    throw new Error("Could not locate sorted history block for memoization");
  }
  panel = panel.replace(
    sortedNeedle,
    `  const sorted = useMemo(\n    () => [...history].sort((a, b) => periodOf(a).localeCompare(periodOf(b))),\n    [history],\n  );`,
  );

  const effectStart = panel.indexOf(`  useEffect(() => {\n    let cancelled = false;\n    async function loadTariffHistory()`);
  const effectEndNeedle = `\n  }, [selected.meter_id]);`;
  const effectEnd = panel.indexOf(effectEndNeedle, effectStart);
  if (effectStart < 0 || effectEnd < 0) {
    throw new Error("Could not locate advanced tariff history effect");
  }

  const effectReplacement = `  useEffect(() => {\n    let cancelled = false;\n    async function loadTariffHistory() {\n      setAdvancedTariffReady(false);\n      try {\n        const meterId = selected.meter_id;\n        const cached = advancedTariffCache.get(meterId);\n        if (cached) {\n          if (!cancelled) {\n            setAdvancedTariffHistory(cached);\n            setAdvancedTariffReady(true);\n          }\n          return;\n        }\n\n        const { data } = await supabase.auth.getSession();\n        if (!data.session || !meterId) {\n          if (!cancelled) {\n            setAdvancedTariffHistory(null);\n            setAdvancedTariffReady(true);\n          }\n          return;\n        }\n\n        let pending = advancedTariffInflight.get(meterId);\n        if (!pending) {\n          pending = fetch(API + \"/api/meters/\" + meterId + \"/tariff-saving-history\", {\n            cache: \"no-store\",\n            headers: { Authorization: \"Bearer \" + data.session.access_token },\n          }).then(async (response) => {\n            if (!response.ok) throw new Error(await response.text());\n            const json = (await response.json()) as AdvancedTariffHistoryResponse;\n            advancedTariffCache.set(meterId, json);\n            return json;\n          });\n          advancedTariffInflight.set(meterId, pending);\n          pending.finally(() => advancedTariffInflight.delete(meterId));\n        }\n\n        const json = await pending;\n        if (!cancelled) setAdvancedTariffHistory(json);\n      } catch {\n        if (!cancelled) setAdvancedTariffHistory(null);\n      } finally {\n        if (!cancelled) setAdvancedTariffReady(true);\n      }\n    }\n    loadTariffHistory();\n    return () => {\n      cancelled = true;\n    };\n  }, [selected.meter_id]);`;

  panel =
    panel.slice(0, effectStart) +
    effectReplacement +
    panel.slice(effectEnd + effectEndNeedle.length);

  writeFileSync(panelPath, panel, "utf8");
  console.log("Applied invoice panel memoization and tariff-history cache.");
} else {
  console.log("Invoice panel performance patch already applied.");
}
