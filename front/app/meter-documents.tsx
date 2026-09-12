"use client";

import { useEffect, useMemo, useState, type FormEvent } from "react";
import { supabase } from "./lib/supabase";
import { consumptionPeriod } from "./lib/power-history";

type Invoice = {
  id: string;
  meter_id: string;
  invoice_number?: string;
  billing_period?: string;
  period_start: string;
  period_end: string;
};

type Schedule = {
  id: string;
  resolution_number: string;
  consumption_month: string;
  billing_month: string;
  source_document_path?: string | null;
};

type Document = {
  id: string;
  name: string;
  path?: string;
  consumption: string;
  billing: string;
  kind: "consumption" | "tariff";
  note?: string;
};

type UploadTarget = "consumption" | "tariff";

const bucket = "energy-documents";
const month = (date?: string) => String(date || "").slice(0, 7);
const prettyMonth = (period: string) => {
  if (!/^\d{4}-\d{2}$/.test(period)) return period || "S/D";
  const [year, value] = period.split("-").map(Number);
  return new Intl.DateTimeFormat("es-AR", { month: "long", year: "numeric" }).format(
    new Date(Date.UTC(year, value - 1, 1)),
  );
};

export function MeterDocuments({
  organizationId,
  meterId,
  selected,
  history,
  controls,
  onPeriod,
}: {
  organizationId: string;
  meterId: string;
  selected: Invoice;
  history: Invoice[];
  controls: Array<{
    id: string;
    meter_id: string;
    change_type: string;
    effective_period: string;
    details?: Record<string, unknown>;
  }>;
  onPeriod?: (period: string) => void;
}) {
  const [documents, setDocuments] = useState<Document[]>([]);
  const [schedules, setSchedules] = useState<Schedule[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [revision, setRevision] = useState(0);
  const [busy, setBusy] = useState(false);
  const [uploadTarget, setUploadTarget] = useState<UploadTarget | null>(null);
  const [file, setFile] = useState<File | null>(null);

  const ownHistory = useMemo(
    () =>
      history
        .filter((row) => row.meter_id === meterId)
        .sort((a, b) => month(a.billing_period || a.period_start).localeCompare(month(b.billing_period || b.period_start))),
    [history, meterId],
  );
  const selectedBilling = month(selected.billing_period || selected.period_start);
  const consumption = consumptionPeriod(selected);
  const prefix = `${organizationId}/${meterId}/documents`;
  const tariffPrefix = `${organizationId}/tariff-documents`;
  const historyKey = ownHistory.map((row) => row.id).join(",");
  const controlKey = JSON.stringify(controls.filter((row) => row.meter_id === meterId));

  const currentIndex = ownHistory.findIndex((row) => row.id === selected.id || month(row.billing_period || row.period_start) === selectedBilling);
  const older = currentIndex > 0 ? ownHistory[currentIndex - 1] : null;
  const newer = currentIndex >= 0 && currentIndex < ownHistory.length - 1 ? ownHistory[currentIndex + 1] : null;

  useEffect(() => {
    setUploadTarget(null);
    setFile(null);
  }, [selected.id, meterId]);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError("");

    async function list(folder: string, type: Document["kind"]) {
      const result: Document[] = [];
      for (let offset = 0; ; offset += 100) {
        const { data, error } = await supabase.storage
          .from(bucket)
          .list(folder, { limit: 100, offset, sortBy: { column: "name", order: "asc" } });
        if (error) throw error;
        for (const entry of data || []) {
          if (!entry.id) continue;
          const parts = entry.name.split("__");
          if (parts.length < 4 || !/^\d{4}-\d{2}$/.test(parts[0])) continue;
          result.push({
            id: entry.id,
            path: `${folder}/${entry.name}`,
            consumption: parts[0],
            billing: parts[1],
            name: parts.slice(3).join("__"),
            kind: type,
          });
        }
        if ((data || []).length < 100) return result;
      }
    }

    async function load() {
      const results = await Promise.allSettled([
        list(prefix, "consumption"),
        list(tariffPrefix, "tariff"),
        supabase
          .from("invoices")
          .select("id,document_path")
          .eq("organization_id", organizationId)
          .eq("meter_id", meterId),
        supabase
          .from("tariff_schedules")
          .select("id,resolution_number,consumption_month,billing_month,source_document_path")
          .eq("provider", "EPEN"),
      ] as const);

      if (cancelled) return;
      const failures: string[] = [];
      const docs: Document[] = [];

      const uploadedInvoiceDocs = results[0].status === "fulfilled" ? results[0].value : [];
      const uploadedTariffDocs = results[1].status === "fulfilled" ? results[1].value : [];
      if (results[0].status === "rejected") failures.push("No se pudieron listar los PDF de facturas");
      if (results[1].status === "rejected") failures.push("No se pudieron listar los cuadros tarifarios");
      docs.push(...uploadedInvoiceDocs, ...uploadedTariffDocs);

      const invoiceResult = results[2];
      if (invoiceResult.status === "fulfilled" && !invoiceResult.value.error) {
        const paths = new Map(
          (invoiceResult.value.data || []).map((row: { id: string; document_path?: string }) => [row.id, row.document_path]),
        );
        for (const invoice of ownHistory) {
          const storedPath = paths.get(invoice.id);
          const c = consumptionPeriod(invoice);
          const b = month(invoice.billing_period || invoice.period_start);
          if (uploadedInvoiceDocs.some((doc) => doc.consumption === c && doc.billing === b)) continue;
          docs.push({
            id: invoice.id,
            name: `Factura ${invoice.invoice_number || b}`,
            path: typeof storedPath === "string" && storedPath.startsWith(`${organizationId}/`) ? storedPath : undefined,
            consumption: c,
            billing: b,
            kind: "consumption",
          });
        }
      } else {
        failures.push("No se pudieron consultar los adjuntos de facturas");
      }

      const scheduleResult = results[3];
      let scheduleRows: Schedule[] = [];
      if (scheduleResult.status === "fulfilled" && !scheduleResult.value.error) {
        scheduleRows = (scheduleResult.value.data || []) as Schedule[];
        setSchedules(scheduleRows);
        const relevantPeriods = new Set(ownHistory.map(consumptionPeriod));
        for (const schedule of scheduleRows) {
          const c = month(schedule.consumption_month);
          const b = month(schedule.billing_month);
          if (!relevantPeriods.has(c)) continue;
          if (uploadedTariffDocs.some((doc) => doc.consumption === c && doc.billing === b)) continue;
          const storedPath = schedule.source_document_path;
          docs.push({
            id: schedule.id,
            name: `Cuadro tarifario · Resolución ${schedule.resolution_number}`,
            path: typeof storedPath === "string" && storedPath.startsWith(`${organizationId}/`) ? storedPath : undefined,
            consumption: c,
            billing: b,
            kind: "tariff",
          });
        }
      } else {
        failures.push("No se pudieron consultar los cuadros tarifarios");
      }

      for (const control of controls.filter((row) => row.meter_id === meterId)) {
        const value = (control.change_type === "tariff" ? control.details?.agreement : control.details?.attachment) as
          | { path?: string; name?: string }
          | undefined;
        if (value?.path?.startsWith(`${organizationId}/`)) {
          docs.push({
            id: control.id,
            name: value.name || "Comprobante de mejora",
            path: value.path,
            consumption: month(control.effective_period),
            billing: "",
            kind: control.change_type === "tariff" ? "tariff" : "consumption",
            note: "Comprobante de mejora",
          });
        }
      }

      setDocuments(docs.sort((a, b) => b.consumption.localeCompare(a.consumption) || a.name.localeCompare(b.name)));
      setError(failures.join(". "));
      setLoading(false);
    }

    load().catch((e) => {
      if (!cancelled) {
        setError(e instanceof Error ? e.message : "No se pudieron cargar los archivos");
        setLoading(false);
      }
    });
    return () => {
      cancelled = true;
    };
  }, [organizationId, meterId, historyKey, controlKey, revision]);

  const invoiceDoc = documents.find(
    (doc) => doc.kind === "consumption" && doc.consumption === consumption && doc.billing === selectedBilling,
  );
  const tariffSchedule = schedules.find(
    (row) => month(row.consumption_month) === consumption && month(row.billing_month) === selectedBilling,
  );
  const tariffDoc = documents.find(
    (doc) => doc.kind === "tariff" && doc.consumption === consumption && doc.billing === selectedBilling,
  );

  function goTo(invoice: Invoice | null) {
    if (!invoice || !onPeriod) return;
    onPeriod(month(invoice.billing_period || invoice.period_start));
  }

  async function open(doc: Document, download: boolean) {
    if (!doc.path) return;
    setError("");
    const { data, error } = await supabase.storage
      .from(bucket)
      .createSignedUrl(doc.path, 120, download ? { download: doc.name } : undefined);
    if (error || !data?.signedUrl) {
      setError("No se pudo abrir el archivo. Puede faltar el PDF o no tener acceso.");
      return;
    }
    const link = document.createElement("a");
    link.href = data.signedUrl;
    link.target = "_blank";
    link.rel = "noopener noreferrer";
    link.click();
  }

  async function upload(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!file || !uploadTarget || busy) return;
    if (file.type && file.type !== "application/pdf") {
      setError("En este apartado se permiten únicamente archivos PDF.");
      return;
    }
    if (file.size > 50 * 1024 * 1024) {
      setError("El PDF debe pesar hasta 50 MB.");
      return;
    }

    setBusy(true);
    setError("");
    try {
      const hash = Array.from(
        new Uint8Array(await crypto.subtle.digest("SHA-256", await file.arrayBuffer())),
      )
        .map((value) => value.toString(16).padStart(2, "0"))
        .join("");
      const safeName = file.name
        .replace(/[^a-zA-Z0-9.áéíóúñÁÉÍÓÚÑ _()-]/g, "_")
        .replaceAll("__", "_");
      const folder = uploadTarget === "tariff" ? tariffPrefix : prefix;
      const path = `${folder}/${consumption}__${selectedBilling}__${hash.slice(0, 20)}__${safeName}`;
      const { error: storageError } = await supabase.storage
        .from(bucket)
        .upload(path, file, { contentType: "application/pdf", upsert: false });
      if (storageError) throw storageError;

      if (uploadTarget === "consumption") {
        const { error: updateError } = await supabase
          .from("invoices")
          .update({ document_path: path })
          .eq("id", selected.id);
        if (updateError) throw updateError;
      } else if (tariffSchedule?.id) {
        const { error: updateError } = await supabase
          .from("tariff_schedules")
          .update({ source_document_path: path })
          .eq("id", tariffSchedule.id);
        if (updateError) throw updateError;
      }

      setFile(null);
      setUploadTarget(null);
      setRevision((value) => value + 1);
    } catch (e) {
      setError(e instanceof Error ? e.message : "No se pudo adjuntar el PDF");
    } finally {
      setBusy(false);
    }
  }

  function FileCard({
    title,
    subtitle,
    doc,
    target,
    shared = false,
  }: {
    title: string;
    subtitle: string;
    doc?: Document;
    target: UploadTarget;
    shared?: boolean;
  }) {
    const available = Boolean(doc?.path);
    const active = uploadTarget === target;
    return (
      <article
        style={{
          border: active ? "2px solid #0b8f68" : "1px solid #dce5e0",
          borderRadius: 14,
          padding: 18,
          background: active ? "#f4fbf7" : "#fff",
          minHeight: 190,
          display: "flex",
          flexDirection: "column",
          gap: 12,
          cursor: available ? "default" : "pointer",
        }}
        onClick={() => {
          if (!available) setUploadTarget(target);
        }}
      >
        <div style={{ display: "flex", justifyContent: "space-between", gap: 12, alignItems: "flex-start" }}>
          <div>
            <span style={{ fontSize: 11, fontWeight: 800, letterSpacing: ".06em", color: "#6a7771" }}>
              {target === "consumption" ? "FACTURA" : "CUADRO TARIFARIO"}
            </span>
            <h4 style={{ margin: "5px 0 0", fontSize: 18 }}>{title}</h4>
          </div>
          <span
            style={{
              borderRadius: 999,
              padding: "5px 9px",
              fontSize: 11,
              fontWeight: 800,
              background: available ? "#e9f7f1" : "#f1f3f2",
              color: available ? "#08795a" : "#69766f",
            }}
          >
            {available ? "Disponible" : "No disponible"}
          </span>
        </div>

        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10 }}>
          <div style={{ padding: 10, borderRadius: 10, background: "#f7f9f8" }}>
            <small style={{ display: "block", color: "#738079" }}>Período de consumo</small>
            <b>{consumption}</b>
          </div>
          <div style={{ padding: 10, borderRadius: 10, background: "#f7f9f8" }}>
            <small style={{ display: "block", color: "#738079" }}>Período de facturación</small>
            <b>{selectedBilling}</b>
          </div>
        </div>

        <p style={{ margin: 0, color: "#66736d", fontSize: 13 }}>{subtitle}</p>
        {shared && (
          <small style={{ color: "#0b8f68", fontWeight: 700 }}>
            Se comparte con todas las facturas de la organización para este período.
          </small>
        )}

        <div style={{ marginTop: "auto", display: "flex", gap: 8, flexWrap: "wrap" }}>
          {available && doc ? (
            <>
              <button type="button" onClick={(event) => { event.stopPropagation(); open(doc, false); }}>
                Abrir PDF
              </button>
              <button type="button" onClick={(event) => { event.stopPropagation(); open(doc, true); }}>
                Descargar
              </button>
            </>
          ) : (
            <button
              type="button"
              onClick={(event) => {
                event.stopPropagation();
                setUploadTarget(target);
              }}
              style={{ fontWeight: 800 }}
            >
              Adjuntar PDF
            </button>
          )}
        </div>
      </article>
    );
  }

  return (
    <section className="invoice-analysis-panel meter-documents" style={{ padding: 22 }}>
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "48px 1fr 48px",
          alignItems: "center",
          gap: 14,
          marginBottom: 20,
        }}
      >
        <button type="button" disabled={!older} onClick={() => goTo(older)} aria-label="Período anterior">
          ←
        </button>
        <div style={{ textAlign: "center" }}>
          <h3 style={{ margin: 0 }}>Archivos del medidor</h3>
          <div style={{ marginTop: 5, color: "#66736d", fontSize: 13 }}>
            Consumo <b>{prettyMonth(consumption)}</b> · Facturación <b>{prettyMonth(selectedBilling)}</b>
          </div>
        </div>
        <button type="button" disabled={!newer} onClick={() => goTo(newer)} aria-label="Período siguiente">
          →
        </button>
      </div>

      {error && <p role="alert" style={{ color: "#9b2c2c" }}>{error}</p>}

      {loading ? (
        <p>Cargando archivos…</p>
      ) : (
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(320px, 1fr))", gap: 16 }}>
          <FileCard
            title={`Factura ${selected.invoice_number || selectedBilling}`}
            subtitle={invoiceDoc?.name || "PDF de la factura correspondiente al período seleccionado."}
            doc={invoiceDoc}
            target="consumption"
          />
          <FileCard
            title={
              tariffSchedule?.resolution_number
                ? `Resolución ${tariffSchedule.resolution_number}`
                : "Cuadro tarifario"
            }
            subtitle={tariffDoc?.name || "Cuadro tarifario aplicable al consumo del período seleccionado."}
            doc={tariffDoc}
            target="tariff"
            shared
          />
        </div>
      )}

      {uploadTarget && (
        <form
          onSubmit={upload}
          style={{
            marginTop: 18,
            padding: 18,
            border: "1px solid #cfe0d7",
            borderRadius: 14,
            background: "#f8fbf9",
            display: "grid",
            gap: 12,
          }}
        >
          <div style={{ display: "flex", justifyContent: "space-between", gap: 12, alignItems: "center" }}>
            <div>
              <b>{uploadTarget === "consumption" ? "Adjuntar PDF de factura" : "Adjuntar cuadro tarifario compartido"}</b>
              <small style={{ display: "block", marginTop: 4, color: "#66736d" }}>
                Consumo {consumption} · Facturación {selectedBilling}
              </small>
            </div>
            <button type="button" onClick={() => { setUploadTarget(null); setFile(null); }}>
              Cancelar
            </button>
          </div>
          <input
            type="file"
            required
            accept="application/pdf,.pdf"
            onChange={(event) => setFile(event.target.files?.[0] || null)}
          />
          <button type="submit" disabled={busy || !file} style={{ fontWeight: 800 }}>
            {busy ? "Guardando…" : "Guardar PDF"}
          </button>
        </form>
      )}
    </section>
  );
}
