"use client";

import { useEffect, useMemo, useState } from "react";
import type { Session } from "@supabase/supabase-js";
import "./public-lighting-panel.css";

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

type DetailTab = "summary" | "consumption" | "amount" | "tariff";

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

function pct(value?: number | null) {
  if (value == null || !Number.isFinite(value)) return "—";
  return `${value > 0 ? "+" : ""}${value.toFixed(1)}%`;
}

function PublicLightingDetail({ row, onClose }: { row: PLRow; onClose: () => void }) {
  const [tab, setTab] = useState<DetailTab>("summary");
  const newest = [...row.history].sort((a, b) => b.billing_period.localeCompare(a.billing_period))[0];
  const [selectedPeriod, setSelectedPeriod] = useState(row.billing_period || newest?.billing_period || "");

  useEffect(() => {
    setTab("summary");
    setSelectedPeriod(row.billing_period || newest?.billing_period || "");
  }, [row.public_lighting_meter_id, row.billing_period]);

  const history = useMemo(
    () => [...row.history].sort((a, b) => a.billing_period.localeCompare(b.billing_period)),
    [row.history],
  );
  const selectedHistory = history.find(h => h.billing_period === selectedPeriod) || newest || history[history.length - 1];
  const maxKwh = Math.max(1, ...history.map(h => Number(h.active_energy_kwh || 0)));
  const maxAmount = Math.max(1, ...history.map(h => Number(h.total_amount || 0)));

  return <div className="pl-backdrop" onClick={onClose}>
    <aside className="pl-detail pl-detail-v2" onClick={e => e.stopPropagation()}>
      <div className="pl-detail-head">
        <div>
          <small>ANÁLISIS INDIVIDUAL · ALUMBRADO PÚBLICO</small>
          <h2>{row.address || "Sin dirección"}</h2>
          <p>Medidor {row.meter_number || "S/D"} · Suministro {row.supply_number || "S/D"}</p>
        </div>
        <button onClick={onClose}>×</button>
      </div>

      <div className="pl-detail-tabs">
        <button className={tab === "summary" ? "active" : ""} onClick={() => setTab("summary")}>Resumen</button>
        <button className={tab === "consumption" ? "active" : ""} onClick={() => setTab("consumption")}>Consumo</button>
        <button className={tab === "amount" ? "active" : ""} onClick={() => setTab("amount")}>Importe</button>
        <button className={tab === "tariff" ? "active" : ""} onClick={() => setTab("tariff")}>Tarifa</button>
      </div>

      <div className="pl-detail-kpis">
        <article><span>Período</span><b>{selectedHistory?.billing_period || row.billing_period}</b></article>
        <article><span>Consumo</span><b>{selectedHistory?.active_energy_kwh == null ? "—" : `${number.format(selectedHistory.active_energy_kwh)} kWh`}</b></article>
        <article><span>Importe</span><b>{selectedHistory?.total_amount == null ? "—" : money.format(selectedHistory.total_amount)}</b></article>
        <article className={row.analysis_status !== "normal" ? "alert" : ""}><span>Estado</span><b>{statusLabel(row)}</b></article>
      </div>

      {tab === "summary" && <>
        <section className="pl-detail-section pl-detail-diagnosis">
          <h3>Diagnóstico del período controlado</h3>
          <div className="pl-detail-summary-grid">
            <div><span>Promedio histórico 12m</span><b>{row.average_12m_kwh == null ? "—" : `${number.format(row.average_12m_kwh)} kWh`}</b></div>
            <div><span>Mes anterior</span><b>{row.previous_kwh == null ? "—" : `${number.format(row.previous_kwh)} kWh`}</b></div>
            <div><span>Variación mensual</span><b className={Math.abs(row.change_percent || 0) >= 50 ? "danger" : ""}>{pct(row.change_percent)}</b></div>
            <div><span>Tarifa</span><b>{row.tariff_code || "S/D"}</b></div>
          </div>
          {row.analysis_reasons.length ? <ul>{row.analysis_reasons.map((r, i) => <li key={i}>{r}</li>)}</ul> : <p>Sin observaciones para el período.</p>}
        </section>

        <section className="pl-detail-section">
          <h3>Facturación disponible</h3>
          <div className="pl-history pl-history-clickable">
            {[...history].reverse().map(h => <button key={`${h.billing_period}-${h.invoice_number}`} className={selectedPeriod === h.billing_period ? "active" : ""} onClick={() => setSelectedPeriod(h.billing_period)}>
              <b>{h.billing_period}</b>
              <span>{h.active_energy_kwh == null ? "—" : `${number.format(h.active_energy_kwh)} kWh`}</span>
              <span>{h.total_amount == null ? "—" : money.format(h.total_amount)}</span>
              <em>{h.tariff_code || "S/D"}</em>
            </button>)}
          </div>
        </section>
      </>}

      {tab === "consumption" && <section className="pl-detail-section">
        <div className="pl-chart-head"><div><h3>Consumo histórico</h3><p>Últimos {history.length} períodos disponibles</p></div><b>{selectedHistory?.active_energy_kwh == null ? "—" : `${number.format(selectedHistory.active_energy_kwh)} kWh`}</b></div>
        <div className="pl-bars">
          {history.map(h => <button key={h.billing_period} className={selectedPeriod === h.billing_period ? "active" : ""} onClick={() => setSelectedPeriod(h.billing_period)} title={`${h.billing_period}: ${number.format(h.active_energy_kwh || 0)} kWh`}>
            <i style={{ height: `${Math.max(3, Number(h.active_energy_kwh || 0) / maxKwh * 100)}%` }} />
            <span>{h.billing_period.slice(5)}</span>
          </button>)}
        </div>
        <div className="pl-selected-record"><span>Período seleccionado</span><b>{selectedHistory?.billing_period}</b><strong>{selectedHistory?.active_energy_kwh == null ? "—" : `${number.format(selectedHistory.active_energy_kwh)} kWh`}</strong><small>Promedio previo 12m: {row.average_12m_kwh == null ? "—" : `${number.format(row.average_12m_kwh)} kWh`}</small></div>
      </section>}

      {tab === "amount" && <section className="pl-detail-section">
        <div className="pl-chart-head"><div><h3>Importe facturado</h3><p>Evolución mensual del costo</p></div><b>{selectedHistory?.total_amount == null ? "—" : money.format(selectedHistory.total_amount)}</b></div>
        <div className="pl-bars amount">
          {history.map(h => <button key={h.billing_period} className={selectedPeriod === h.billing_period ? "active" : ""} onClick={() => setSelectedPeriod(h.billing_period)} title={`${h.billing_period}: ${money.format(h.total_amount || 0)}`}>
            <i style={{ height: `${Math.max(3, Number(h.total_amount || 0) / maxAmount * 100)}%` }} />
            <span>{h.billing_period.slice(5)}</span>
          </button>)}
        </div>
        <div className="pl-selected-record"><span>Factura</span><b>{selectedHistory?.invoice_number || "S/D"}</b><strong>{selectedHistory?.total_amount == null ? "—" : money.format(selectedHistory.total_amount)}</strong><small>{selectedHistory?.active_energy_kwh == null ? "Sin consumo informado" : `${number.format(selectedHistory.active_energy_kwh)} kWh facturados`}</small></div>
      </section>}

      {tab === "tariff" && <section className="pl-detail-section">
        <h3>Histórico tarifario</h3>
        <div className="pl-tariff-history">
          {[...history].reverse().map(h => <button key={h.billing_period} className={selectedPeriod === h.billing_period ? "active" : ""} onClick={() => setSelectedPeriod(h.billing_period)}>
            <span>{h.billing_period}</span><b className={`pl-tariff ${h.tariff_code !== "T1AP" ? "review" : ""}`}>{h.tariff_code || "S/D"}</b><small>{h.invoice_number || "Sin número de factura"}</small>
          </button>)}
        </div>
        {history.some(h => h.tariff_code && h.tariff_code !== "T1AP") && <div className="pl-note-warning">Hay períodos con tarifa distinta de T1AP. Se muestran como observación administrativa; no se asume automáticamente que cambiar de tarifa genere ahorro.</div>}
      </section>}
    </aside>
  </div>;
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
    let cancelled = false;
    setLoading(true);
    setError("");
    setPeriod("");
    setSelected(null);

    getAnalysis(session, organizationId)
      .then(result => {
        if (cancelled) return;
        const latest = result.periods[0] || result.billing_period;
        setPeriod(latest);
        if (result.billing_period === latest) {
          setData(result);
          return;
        }
        return getAnalysis(session, organizationId, latest).then(latestResult => {
          if (!cancelled) setData(latestResult);
        });
      })
      .catch(e => !cancelled && setError(e instanceof Error ? e.message : "No se pudo cargar Alumbrado Público"))
      .finally(() => !cancelled && setLoading(false));

    return () => { cancelled = true; };
  }, [session, organizationId]);

  const changePeriod = async (nextPeriod: string) => {
    setPeriod(nextPeriod);
    setLoading(true);
    setError("");
    try {
      const result = await getAnalysis(session, organizationId, nextPeriod);
      setData(result);
      setSelected(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : "No se pudo cargar el período");
    } finally {
      setLoading(false);
    }
  };

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

  const latestAvailable = data.periods[0] || data.billing_period;

  return <div className="pl-module">
    <section className="pl-kpis">
      <article><span>PERÍODO CONTROLADO</span><strong>{data.billing_period}</strong><small>{data.billing_period === latestAvailable ? "Último mes disponible" : `Histórico · último disponible ${latestAvailable}`}</small></article>
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
        <div><h2>Análisis mensual de Alumbrado Público</h2><p>Consumo · costo · variación · anomalías · tarifa · tocar una fila para abrir análisis individual</p></div>
        {loading && <span className="pl-refreshing">Actualizando…</span>}
      </div>
      <div className="pl-filters">
        <label>Período<select value={period} onChange={e => changePeriod(e.target.value)}>{data.periods.map(p => <option key={p} value={p}>{p}{p === latestAvailable ? " · último" : ""}</option>)}</select></label>
        <label>Estado<select value={status} onChange={e => setStatus(e.target.value)}><option value="all">Todos</option><option value="critical">Críticos</option><option value="warning">Revisar</option><option value="missing">Sin factura</option><option value="normal">Normales</option></select></label>
        <label className="pl-search">Buscar<input value={search} onChange={e => setSearch(e.target.value)} placeholder="Medidor, suministro o dirección" /></label>
        <button onClick={() => { setSearch(""); setStatus("all"); }}>Limpiar</button>
      </div>

      <div className="pl-table-scroll">
        <div className="pl-table">
          <div className="pl-row pl-head">
            <span>MEDIDOR / SUMINISTRO</span><span>UBICACIÓN</span><span>CONSUMO</span><span>PROM. 12M</span><span>VARIACIÓN</span><span>IMPORTE</span><span>TARIFA</span><span>ANÁLISIS</span>
          </div>
          {rows.map(row => <button className={`pl-row pl-data ${row.analysis_status}`} key={row.public_lighting_meter_id} onClick={() => setSelected(row)} title="Abrir análisis individual">
            <span><b>Medidor {row.meter_number || "S/D"}</b><small>Suministro {row.supply_number || "S/D"}</small></span>
            <span><b>{row.address || "Sin dirección"}</b><small>{row.invoice_number ? `Factura ${row.invoice_number}` : "Sin factura del período"}</small></span>
            <span><b>{row.active_energy_kwh == null ? "—" : `${number.format(row.active_energy_kwh)} kWh`}</b><small>{row.previous_kwh == null ? "Sin mes anterior" : `Anterior ${number.format(row.previous_kwh)} kWh`}</small></span>
            <span><b>{row.average_12m_kwh == null ? "—" : `${number.format(row.average_12m_kwh)} kWh`}</b><small>histórico previo</small></span>
            <span><b className={Math.abs(row.change_percent || 0) >= 50 ? "pl-danger" : ""}>{pct(row.change_percent)}</b><small>vs. mes anterior</small></span>
            <span><b>{row.total_amount == null ? "—" : money.format(row.total_amount)}</b><small>facturado</small></span>
            <span><b className={`pl-tariff ${row.tariff_code !== "T1AP" ? "review" : ""}`}>{row.tariff_code || "S/D"}</b><small>EPEN</small></span>
            <span><em className={`pl-status ${row.analysis_status}`}>{statusLabel(row)}</em><small>{row.analysis_reasons[0] || "Sin observaciones"}</small></span>
          </button>)}
          {!rows.length && <div className="pl-empty">No hay registros para esos filtros.</div>}
        </div>
      </div>
    </section>

    {selected && <PublicLightingDetail row={selected} onClose={() => setSelected(null)} />}
  </div>;
}
