"use client";

import { useEffect, useState, type FormEvent } from "react";
import { supabase } from "./lib/supabase";
import { consumptionPeriod } from "./lib/power-history";

type Invoice = { id: string; meter_id: string; invoice_number?: string; billing_period?: string; period_start: string; period_end: string };
type Schedule = { id: string; resolution_number: string; consumption_month: string; billing_month: string; source_document_path?: string };
type Document = { id: string; name: string; path?: string; consumption: string; billing: string; kind: "consumption" | "tariff"; note?: string };
const bucket = "energy-documents";
const month = (date?: string) => String(date || "").slice(0, 7);

export function MeterDocuments({ organizationId, meterId, selected, history, controls }: {
  organizationId: string; meterId: string; selected: Invoice; history: Invoice[];
  controls: Array<{ id: string; meter_id: string; change_type: string; effective_period: string; details?: Record<string, unknown> }>;
}) {
  const [all, setAll] = useState(false);
  const [documents, setDocuments] = useState<Document[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [revision, setRevision] = useState(0);
  const [busy, setBusy] = useState(false);
  const [kind, setKind] = useState<"consumption" | "tariff">("consumption");
  const [period, setPeriod] = useState(consumptionPeriod(selected));
  const [billing, setBilling] = useState(month(selected.billing_period));
  const [file, setFile] = useState<File | null>(null);
  const consumption = consumptionPeriod(selected);
  const ownHistory = history.filter((row) => row.meter_id === meterId);
  const historyKey = ownHistory.map((row) => row.id).sort().join(",");
  const controlKey = JSON.stringify(controls.filter((row) => row.meter_id === meterId));
  const prefix = `${organizationId}/${meterId}/documents`;
  const tariffPrefix = `${organizationId}/tariff-documents`;
  useEffect(() => { setPeriod(consumption); setBilling(month(selected.billing_period)); setFile(null); }, [consumption, selected.billing_period, meterId]);

  useEffect(() => {
    let cancelled = false;
    setLoading(true); setError(""); setDocuments([]);
    async function list(folder: string, type: Document["kind"]) {
      const result: Document[] = [];
      for (let offset = 0; ; offset += 100) {
        const { data, error } = await supabase.storage.from(bucket).list(folder, { limit: 100, offset, sortBy: { column: "name", order: "asc" } });
        if (error) throw error;
        for (const entry of data || []) {
          if (!entry.id) continue;
          const parts = entry.name.split("__");
          if (parts.length < 4 || !/^\d{4}-\d{2}$/.test(parts[0])) continue;
          result.push({ id: entry.id, path: `${folder}/${entry.name}`, consumption: parts[0], billing: parts[1], name: parts.slice(3).join("__"), kind: type });
        }
        if ((data || []).length < 100) return result;
      }
    }
    async function load() {
      const results = await Promise.allSettled([
        list(prefix, "consumption"), list(tariffPrefix, "tariff"),
        supabase.from("invoices").select("id,document_path").eq("organization_id", organizationId).eq("meter_id", meterId),
        supabase.from("tariff_schedules").select("id,resolution_number,consumption_month,billing_month,source_document_path").eq("provider", "EPEN"),
      ] as const);
      if (cancelled) return;
      const failures: string[] = [];
      const docs: Document[] = [];
      const uploaded = results.slice(0, 2).flatMap((r) => { if (r.status === "fulfilled") return r.value as Document[]; failures.push(r.reason?.message || "No se pudieron listar los archivos"); return []; });
      docs.push(...uploaded);
      const invoiceResult = results[2];
      if (invoiceResult.status === "fulfilled" && !invoiceResult.value.error) {
        const paths = new Map((invoiceResult.value.data || []).map((r: {id: string; document_path?: string}) => [r.id, r.document_path]));
        for (const invoice of ownHistory) {
          const path = paths.get(invoice.id);
          if (!path && uploaded.some((d) => d.kind === "consumption" && d.consumption === consumptionPeriod(invoice) && d.billing === month(invoice.billing_period))) continue;
          docs.push({ id: invoice.id, name: `Factura ${invoice.invoice_number || month(invoice.billing_period)}`, path: typeof path === "string" && path.startsWith(`${organizationId}/`) ? path : undefined, consumption: consumptionPeriod(invoice), billing: month(invoice.billing_period), kind: "consumption", note: !path ? "Datos cargados · PDF pendiente de adjuntar" : undefined });
        }
      } else failures.push("No se pudieron consultar los adjuntos de facturas");
      const scheduleResult = results[3];
      if (scheduleResult.status === "fulfilled" && !scheduleResult.value.error) {
        const periods = new Set(ownHistory.map(consumptionPeriod));
        for (const schedule of (scheduleResult.value.data || []) as Schedule[]) {
          const period = month(schedule.consumption_month);
          if (!periods.has(period) || uploaded.some((d) => d.kind === "tariff" && d.consumption === period && d.billing === month(schedule.billing_month))) continue;
          const path = schedule.source_document_path;
          docs.push({ id: schedule.id, name: `Cuadro tarifario · Resolución ${schedule.resolution_number}`, path: path?.startsWith(`${organizationId}/`) ? path : undefined, consumption: period, billing: month(schedule.billing_month), kind: "tariff", note: "Cuadro compartido para los medidores de la organización" });
        }
      } else failures.push("No se pudieron consultar los cuadros tarifarios");
      for (const control of controls.filter((r) => r.meter_id === meterId)) {
        const value = (control.change_type === "tariff" ? control.details?.agreement : control.details?.attachment) as {path?: string; name?: string} | undefined;
        if (value?.path?.startsWith(`${organizationId}/`)) docs.push({ id: control.id, name: value.name || "Comprobante de mejora", path: value.path, consumption: month(control.effective_period), billing: "", kind: control.change_type === "tariff" ? "tariff" : "consumption", note: "Comprobante de mejora · período efectivo" });
      }
      setDocuments(docs.sort((a, b) => b.consumption.localeCompare(a.consumption) || a.name.localeCompare(b.name)));
      setError(failures.join(". ")); setLoading(false);
    }
    load().catch((e) => { if (!cancelled) { setError(e.message || "No se pudieron cargar los archivos"); setLoading(false); } });
    return () => { cancelled = true; };
  // History identity and control content trigger refresh without reloading on unrelated renders.
  }, [organizationId, meterId, historyKey, controlKey, revision]);

  async function open(doc: Document, download: boolean) {
    if (!doc.path) return;
    setError("");
    const { data, error } = await supabase.storage.from(bucket).createSignedUrl(doc.path, 120, download ? { download: doc.name } : undefined);
    if (error || !data?.signedUrl) { setError("No se pudo abrir el archivo. Puede faltar el PDF o no tener acceso."); return; }
    const link = document.createElement("a"); link.href = data.signedUrl; link.target = "_blank"; link.rel = "noopener noreferrer"; link.click();
  }
  async function upload(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!file || busy) return;
    if (file.size > 25 * 1024 * 1024) { setError("El archivo debe pesar hasta 25 MB."); return; }
    setBusy(true); setError("");
    const form = event.currentTarget;
    try {
      const hash = Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", await file.arrayBuffer()))).map((b) => b.toString(16).padStart(2, "0")).join("");
      const safeName = file.name.replace(/[^a-zA-Z0-9.áéíóúñÁÉÍÓÚÑ _()-]/g, "_").replaceAll("__", "_");
      const path = `${kind === "tariff" ? tariffPrefix : prefix}/${period}__${billing}__${hash.slice(0, 20)}__${safeName}`;
      const { error } = await supabase.storage.from(bucket).upload(path, file, { contentType: file.type || "application/octet-stream", upsert: false });
      if (error) throw error;
      setFile(null); form.reset(); setRevision((r) => r + 1);
    } catch (e) { setError(e instanceof Error ? e.message : "No se pudo adjuntar el archivo"); }
    finally { setBusy(false); }
  }
  return <section className="invoice-analysis-panel meter-documents">
    <div className="meter-documents-heading"><h3>Archivos del medidor</h3><label>Mostrar <select value={all ? "all" : "month"} onChange={(e) => setAll(e.target.value === "all")}><option value="month">Mes de consumo seleccionado · {consumption}</option><option value="all">Todo el historial</option></select></label></div>
    {error && <p role="alert">{error}</p>}
    {loading ? <p>Cargando archivos…</p> : <div className="meter-documents-groups">{(["consumption", "tariff"] as const).map((group) => {
      const visible = documents.filter((d) => d.kind === group && (all || d.consumption === consumption));
      return <div key={group}><h4>{group === "consumption" ? "Facturas y consumos" : "Cuadros tarifarios y convenios"}</h4>{!visible.length && <p>No hay archivos para este período.</p>}<ul>{visible.map((doc) => <li key={doc.id}><strong>{doc.name}</strong><small>Consumo: {doc.consumption || "S/D"}{doc.billing && ` · Facturación: ${doc.billing}`}</small>{doc.note && <small>{doc.note}</small>}{doc.path ? <div><button type="button" onClick={() => open(doc, false)}>Abrir</button><button type="button" onClick={() => open(doc, true)}>Descargar</button></div> : <small>PDF no disponible. Podés adjuntarlo debajo.</small>}</li>)}</ul></div>;
    })}</div>}
    <details><summary>Adjuntar archivo</summary><form className="meter-documents-upload" onSubmit={upload}>
      <label>Apartado<select value={kind} onChange={(e) => setKind(e.target.value as typeof kind)}><option value="consumption">Facturas y consumos</option><option value="tariff">Cuadro tarifario (compartido)</option></select></label>
      <label>Mes de consumo<input type="month" required value={period} onChange={(e) => setPeriod(e.target.value)}/></label>
      <label>Período de factura<input type="month" required value={billing} onChange={(e) => setBilling(e.target.value)}/></label>
      <label>Archivo<input key={`${meterId}-${consumption}`} type="file" required accept=".pdf,.csv,.xlsx,.xls,.doc,.docx,image/*" onChange={(e) => setFile(e.target.files?.[0] || null)}/></label>
      <button type="submit" disabled={busy || !file}>{busy ? "Guardando…" : "Guardar archivo"}</button>
      <small>Adjuntar conserva el documento; no modifica consumos, precios ni cálculos.</small>
    </form></details>
  </section>;
}
