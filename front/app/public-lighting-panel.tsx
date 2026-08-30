"use client";

import { useEffect, useMemo, useState } from "react";
import type { Session } from "@supabase/supabase-js";

const API = "https://ahorro-energetico.onrender.com";
const money = new Intl.NumberFormat("es-AR", { style: "currency", currency: "ARS", maximumFractionDigits: 0 });
const number = new Intl.NumberFormat("es-AR", { maximumFractionDigits: 0 });

type PLHistory = {
  billing_period: string;
  active_energy_kwh?: number | null;
  total_amount?: number | null;
  tariff_code?: string | null;
  invoice_number?: string | null;
};

type PLRow = {
  public_lighting_meter_id: string;
  supply_number?: string;
  supply_contract?: string;
  meter_number?: string;
  address?: string;
  billing_period: string;
  invoice_id?: string | null;
  invoice_number?: string | null;
  active_energy_kwh?: number | null;
  average_12m_kwh?: number | null;
  previous_kwh?: number | null;
  change_percent?: number | null;
  total_amount?: number | null;
  tariff_code?: string | null;
  validation_status?: string | null;
  analysis_status: "normal" | "warning" | "critical" | "missing";
  analysis_reasons: string[];
  constant_consumption: boolean;
  history: PLHistory[];
};

type PLResponse = {
  billing_period: string;
  periods: string[];
  summary: {
    expected: number;
    received: number;
    missing: number;
    total_kwh: number;
    total_amount: number;
    anomalies: number;
    warnings: number;
    critical: number;
  };
  rows: PLRow[];
};

async function getAnalysis(session: Session, organizationId: string, period?: string): Promise<PLResponse> {
  const qs = period ? `?billing_period=${period}` : "";
  const response = await fetch(`${API}/api/organizations/${organizationId}/public-lighting/analysis${qs}`, {
    cache: "no-store",
    headers: { Authorization: `Bearer ${session.access_token}` },
  });
  if (!response.ok) throw new Error(await response.text() || `Error ${response.status}`);
  return response.json();
}

function statusLabel(row: PLRow) {
  if (row.analysis_status === "critical") return "Revisar urgente";
  if (row.analysis_status === "warning") return "Revisar";
  if (row.analysis_status === "missing") return "Sin factura";
  return "Normal";
}

export function PublicLightingPanel({ session, organizationId }: { session: Session; organizationId: string }) {
  const [data, setData] = useState<PLResponse | null>(null);
  const [period, setPeriod] = useState("");
  const [search, setSearch] = useState("");
  const [status, setStatus] = useState("all");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [selected, setSelected] = useState<PLRow | null>(null);

  useEffect(() => {
    if (!organizationId) return;
    setLoading(true);
    setError("");
    getAnalysis(session, organizationId, period || undefined)
      .then(result => {
        setData(result);
        if (!period) setPeriod(result.billing_period);
      })
      .catch(e => setError(e instanceof Error ? e.message : "No se pudo cargar Alumbrado Público"))
      .finally(() => setLoading(false));
  }, [session, organizationId, period]);

  const rows = useMemo(() => {
    if (!data) return [];
    const q = search.trim().toLowerCase();
    return data.rows.filter(row => {
      if (status !== "all" && row.analysis_status !== status) return false;
      if (!q) return true;
      return [row.meter_number, row.supply_number, row.supply_contract, row.address, row.invoice_number]
        .some(value => String(value || "").toLowerCase().includes(q));
    });
  }, [data, search, status]);

  if (error) return <section className="panel pl-error">{error}</section>;
  if (!data) return <section className="panel pl-loading">{loading ? "Analizando Alumbrado Público…" : "Sin datos"}</section>;

  return <div className="pl-module">
    <section className="pl-kpis">
      <article><span>PERÍODO CONTROLADO</span><strong>{data.billing_period}</strong><small>Alumbrado Público</small></article>
      <article><span>FACTURAS ESPERADAS</span><strong>{data.summary.expected}</strong><small>suministros del padrón AP</small></article>
      <article className="green"><span>FACTURAS RECIBIDAS</span><strong>{data.summary.received}</strong><small>{data.summary.missing} faltantes</small></article>
      <article className={data.summary.anomalies ? "alert" : ""}><span>REQUIEREN REVISIÓN</span><strong>{data.summary.anomalies}</strong><small>{data.summary.critical} críticas · {data.summary.warnings} alertas</small></article>
    </section>

    <section className="panel pl-summary-strip">
      <div><span>Consumo del mes</span><b>{number.format(data.summary.total_kwh)} kWh</b></div>
      <div><span>Importe facturado</span><b>{money.format(data.summary.total_amount)}</b></div>
      <div><span>Promedio por factura</span><b>{data.summary.received ? number.format(data.summary.total_kwh / data.summary.received) : 0} kWh</b></div>
      <div><span>Cobertura</span><b>{data.summary.expected ? Math.round(data.summary.received / data.summary.expected * 100) : 0}%</b></div>
    </section>

    <section className="panel">
      <div className="panel-title pl-title">
        <div><h2>Análisis mensual de Alumbrado Público</h2><p>Consumo · costo · variación · anomalías · tarifa</p></div>
      </div>
      <div className="pl-filters">
        <label>Período<select value={period} onChange={e => setPeriod(e.target.value)}>{data.periods.map(p => <option key={p} value={p}>{p}</option>)}</select></label>
        <label>Estado<select value={status} onChange={e => setStatus(e.target.value)}><option value="all">Todos</option><option value="critical">Críticos</option><option value="warning">Revisar</option><option value="missing">Sin factura</option><option value="normal">Normales</option></select></label>
        <label className="pl-search">Buscar<input value={search} onChange={e => setSearch(e.target.value)} placeholder="Medidor, suministro o dirección" /></label>
        <button onClick={() => { setSearch(""); setStatus("all"); }}>Limpiar</button>
      </div>

      <div className="pl-table-scroll">
        <div className="pl-table">
          <div className="pl-row pl-head">
            <span>MEDIDOR / SUMINISTRO</span><span>UBICACIÓN</span><span>CONSUMO</span><span>PROM. 12M</span><span>VARIACIÓN</span><span>IMPORTE</span><span>TARIFA</span><span>ANÁLISIS</span>
          </div>
          {rows.map(row => <button className={`pl-row pl-data ${row.analysis_status}`} key={row.public_lighting_meter_id} onClick={() => setSelected(row)}>
            <span><b>Medidor {row.meter_number || "S/D"}</b><small>Suministro {row.supply_number || "S/D"}</small></span>
            <span><b>{row.address || "Sin dirección"}</b><small>{row.invoice_number ? `Factura ${row.invoice_number}` : "Sin factura del período"}</small></span>
            <span><b>{row.active_energy_kwh == null ? "—" : `${number.format(row.active_energy_kwh)} kWh`}</b><small>{row.previous_kwh == null ? "Sin mes anterior" : `Anterior ${number.format(row.previous_kwh)} kWh`}</small></span>
            <span><b>{row.average_12m_kwh == null ? "—" : `${number.format(row.average_12m_kwh)} kWh`}</b><small>histórico previo</small></span>
            <span><b className={(row.change_percent || 0) > 50 || (row.change_percent || 0) < -50 ? "pl-danger" : ""}>{row.change_percent == null ? "—" : `${row.change_percent > 0 ? "+" : ""}${row.change_percent}%`}</b><small>vs. mes anterior</small></span>
            <span><b>{row.total_amount == null ? "—" : money.format(row.total_amount)}</b><small>facturado</small></span>
            <span><b className={`pl-tariff ${row.tariff_code !== "T1AP" ? "review" : ""}`}>{row.tariff_code || "S/D"}</b><small>EPEN</small></span>
            <span><em className={`pl-status ${row.analysis_status}`}>{statusLabel(row)}</em><small>{row.analysis_reasons[0] || "Sin observaciones"}</small></span>
          </button>)}
          {!rows.length && <div className="pl-empty">No hay registros para esos filtros.</div>}
        </div>
      </div>
    </section>

    {selected && <div className="pl-backdrop" onClick={() => setSelected(null)}>
      <aside className="pl-detail" onClick={e => e.stopPropagation()}>
        <div className="pl-detail-head"><div><small>ALUMBRADO PÚBLICO</small><h2>{selected.address || "Sin dirección"}</h2><p>Medidor {selected.meter_number || "S/D"} · Suministro {selected.supply_number || "S/D"}</p></div><button onClick={() => setSelected(null)}>×</button></div>
        <div className="pl-detail-kpis"><article><span>Consumo</span><b>{selected.active_energy_kwh == null ? "—" : `${number.format(selected.active_energy_kwh)} kWh`}</b></article><article><span>Promedio 12m</span><b>{selected.average_12m_kwh == null ? "—" : `${number.format(selected.average_12m_kwh)} kWh`}</b></article><article><span>Importe</span><b>{selected.total_amount == null ? "—" : money.format(selected.total_amount)}</b></article><article className={selected.analysis_status !== "normal" ? "alert" : ""}><span>Estado</span><b>{statusLabel(selected)}</b></article></div>
        <section className="pl-detail-section"><h3>Diagnóstico</h3>{selected.analysis_reasons.length ? <ul>{selected.analysis_reasons.map((r, i) => <li key={i}>{r}</li>)}</ul> : <p>Sin observaciones para el período.</p>}</section>
        <section className="pl-detail-section"><h3>Histórico</h3><div className="pl-history">{[...selected.history].reverse().map(h => <div key={`${h.billing_period}-${h.invoice_number}`}><b>{h.billing_period}</b><span>{h.active_energy_kwh == null ? "—" : `${number.format(h.active_energy_kwh)} kWh`}</span><span>{h.total_amount == null ? "—" : money.format(h.total_amount)}</span><em>{h.tariff_code || "S/D"}</em></div>)}</div></section>
      </aside>
    </div>}
  </div>;
}
