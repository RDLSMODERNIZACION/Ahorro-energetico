"use client";

import { useEffect, useState } from "react";
import type { Session } from "@supabase/supabase-js";
import { supabase } from "./lib/supabase";
import { API_BASE } from "./lib/paths";
import { calculateCanonicalSavings } from "./invoice-analysis-panel";
import type { MeterChangeControl } from "./meter-change-control";
import { billingMonth, primaryInvoices, confirmedSavings, savingKinds } from "./lib/summary-savings";
import styles from "./dashboard-summary.module.css";

type CanonicalInput = Parameters<typeof calculateCanonicalSavings>[0];
type Invoice = CanonicalInput["invoice"] & { document_type?: string; issue_date?: string };
type Meter = { id: string; status?: string; meter_number?: string; service_name?: string };
type Advanced = { billing_period: string; meters: ({ meter_id: string } & NonNullable<CanonicalInput["advancedTariffPoint"]>)[] };
type Snapshot = {
  period: string; invoices: Invoice[]; meters: Meter[]; controls: MeterChangeControl[];
  assessments: NonNullable<CanonicalInput["assessment"]>[];
  tariffs: CanonicalInput["tariffSavings"]; advanced: Advanced;
};
const money = new Intl.NumberFormat("es-AR", { style: "currency", currency: "ARS", maximumFractionDigits: 0 });
const labels: Record<string, string> = { contracted_power: "Potencia contratada", power_factor: "Factor de potencia", tariff: "Cambio tarifario", supply_deactivation: "Baja del suministro" };
const invoiceSelect = "id,meter_id,invoice_number,billing_period,period_start,period_end,issue_date,total_amount,current_tariff_code,voltage_level,contracted_kw_peak,contracted_kw_off_peak,document_type:raw_data->>document_type,meters(*,sites(name,address)),invoice_measurements(*),invoice_lines(concept_code,quantity,unit_price,net_amount)";

export type SummarySelection = { label: string; period: string; meterIds: string[]; invoices: Invoice[] };
type SummaryProps = { organizationId: string; session: Session; onOpenInvoices: (selection: SummarySelection) => void };
export function DashboardSummary({ organizationId, session, onOpenInvoices }: SummaryProps) {
  return <Summary key={`${session.user.id}:${organizationId}`} organizationId={organizationId} onOpenInvoices={onOpenInvoices} />;
}
function Summary({ organizationId, onOpenInvoices }: Omit<SummaryProps, "session">) {
  const [snapshot, setSnapshot] = useState<Snapshot | null>(null);
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState("");
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    let cancelled = false;
    const controller = new AbortController();
    async function load() {
      setBusy(true); setError("");
      try {
        const { data: { session } } = await supabase.auth.getSession();
        if (!session) throw new Error("Iniciá sesión para cargar el resumen.");
        async function get<T>(path: string): Promise<T> {
          const response = await fetch(`${API_BASE}/api/organizations/${organizationId}/${path}`, {
            headers: { Authorization: `Bearer ${session!.access_token}` }, cache: "no-store", signal: controller.signal,
          });
          if (!response.ok) throw new Error("No se pudieron completar los datos del resumen. Reintentá la carga.");
          return response.json();
        }
        async function allInvoices() {
          const rows: Invoice[] = [];
          for (let start = 0; ; start += 1000) {
            if (cancelled) throw new Error("Cancelado");
            const { data, error } = await supabase.from("invoices").select(invoiceSelect).eq("organization_id", organizationId)
              .order("id").range(start, start + 999).abortSignal(controller.signal);
            if (error) throw new Error("No se pudo cargar el historial completo de facturas.");
            rows.push(...(data || []) as unknown as Invoice[]);
            if ((data || []).length < 1000) return rows;
          }
        }
        const [invoices, meters, assessments, tariffResult, controlsResult] = await Promise.all([
          allInvoices(), get<Meter[]>("meters"), get<Snapshot["assessments"]>("tariff-assessments?v=14"),
          get<{ candidates: Snapshot["tariffs"] }>("tariff-savings?v=1"),
          supabase.from("meter_change_controls").select("*").eq("organization_id", organizationId).abortSignal(controller.signal),
        ]);
        if (controlsResult.error) throw new Error("No se pudieron cargar las mejoras aplicadas.");
        const period = [...new Set(invoices.map(billingMonth))].filter(Boolean).sort().at(-1) || "";
        const advanced = period ? await get<Advanced>(`tariff-saving-summary?period=${period}`) : { billing_period: "", meters: [] };
        if (period && advanced.billing_period !== period) throw new Error("La tarifa recibida no corresponde al período del resumen.");
        if (!cancelled) setSnapshot({ period, invoices: primaryInvoices(invoices), meters,
          assessments, tariffs: tariffResult.candidates || [], advanced, controls: controlsResult.data as MeterChangeControl[] });
      } catch (cause) {
        if (!cancelled) setError(cause instanceof Error ? cause.message : "No se pudo cargar el resumen.");
      } finally { if (!cancelled) setBusy(false); }
    }
    if (organizationId) void load(); else setBusy(false);
    return () => { cancelled = true; controller.abort(); };
  }, [organizationId, revision]);

  const action = <button type="button" className={styles.refresh} disabled={busy} onClick={() => setRevision(value => value + 1)}>{busy ? "Cargando…" : "Actualizar resumen"}</button>;
  if (busy) return <section className={styles.notice} role="status">Calculando el resumen completo: historial de facturas, tarifas y mejoras aplicadas…</section>;
  if (error) return <section className={styles.notice} role="alert"><p>{error}</p>{action}</section>;
  if (!snapshot?.period) return <section className={styles.notice}>Todavía no hay facturas para este resumen. {action}</section>;
  const { period, invoices, meters, controls, assessments, tariffs, advanced } = snapshot;
  const periodLabel = new Date(`${period}-01T12:00:00`).toLocaleDateString("es-AR", { month: "long", year: "numeric" });
  const active = meters.filter(meter => meter.status !== "removed");
  const activeIds = new Set(active.map(meter => meter.id));
  const current = invoices.filter(invoice => billingMonth(invoice) === period && activeIds.has(invoice.meter_id));
  const proposed: Record<string, { monthly: number; annual: number }> = Object.fromEntries(savingKinds.map(kind => [kind, { monthly: 0, annual: 0 }]));
  const proposedIds: Record<string, string[]> = Object.fromEntries(savingKinds.map(kind => [kind, []]));
  const opportunities = new Set<string>();
  const histories = new Map<string, Invoice[]>();
  for (const invoice of invoices) {
    if (billingMonth(invoice) <= period) histories.set(invoice.meter_id, [...(histories.get(invoice.meter_id) || []), invoice]);
  }
  for (const invoice of current) {
    const assessment = assessments.find(row => row.meter_id === invoice.meter_id);
    const saving = calculateCanonicalSavings({ invoice, history: histories.get(invoice.meter_id) || [invoice],
      assessment, tariffSavings: tariffs, advancedTariffPoint: advanced.meters.find(row => row.meter_id === invoice.meter_id) });
    if (saving.totalMonthly > 0) opportunities.add(invoice.meter_id);
    // Deactivation is an alternative to operating improvements, not an extra saving.
    if (saving.deactivationMonthly > saving.operationalMonthly) {
      proposedIds.supply_deactivation.push(invoice.meter_id);
      proposed.supply_deactivation.monthly += saving.deactivationMonthly;
      proposed.supply_deactivation.annual += saving.deactivationAnnual;
    } else {
      for (const [kind, monthly, annual] of [
        ["contracted_power", saving.powerMonthly, saving.powerAnnual],
        ["power_factor", saving.reactiveMonthly, saving.reactiveAnnual],
        ["tariff", saving.tariffMonthly, saving.tariffAnnual],
      ] as [string, number, number][]) { if (monthly > 0) proposedIds[kind].push(invoice.meter_id); proposed[kind].monthly += monthly; proposed[kind].annual += annual; }
    }
  }
  const confirmed = confirmedSavings(controls, period);
  const proposedMonthly = Object.values(proposed).reduce((sum, row) => sum + row.monthly, 0);
  const proposedAnnual = Object.values(proposed).reduce((sum, row) => sum + row.annual, 0);
  const received = new Set(current.map(row => row.meter_id)).size;
  const open = (label: string, meterIds: string[]) => onOpenInvoices({ label, period, meterIds: [...new Set(meterIds)], invoices });
  const amountLink = (value: number, label: string, ids: string[]) => <button type="button" className={styles.amountLink} aria-label={`Ver facturas: ${label}`} onClick={() => open(label, ids)}>{money.format(value)}</button>;
  return <section className={styles.summary} aria-label="Resumen de ahorro">
    <div className={styles.heading}><div><h2>Resumen de {periodLabel}</h2><p>Período de facturación · historial completo · un cálculo por suministro</p></div>{action}</div>
    <div className={`${styles.kpis} ${styles.counts}`}>
      <button type="button" className={styles.card} onClick={() => open("Facturas recibidas", current.map(row => row.meter_id))}><span>Facturas recibidas</span><strong>{received} / {active.length}</strong><small>{active.length - received} faltantes de {periodLabel}</small></button>
      <button type="button" className={styles.card} onClick={() => open("Suministros con oportunidad", [...opportunities])}><span>Suministros con oportunidad</span><strong>{opportunities.size}</strong><small>Ver facturas con ahorro propuesto →</small></button>
    </div>
    <div className={`${styles.kpis} ${styles.savings}`}>
      <button type="button" className={`${styles.card} ${styles.proposed}`} onClick={() => open("Ahorro propuesto", [...opportunities])}><span>Ahorro propuesto</span><strong>{money.format(proposedMonthly)}</strong><small>Mensual · {money.format(proposedAnnual)} de proyección anual<br />Ver facturas →</small></button>
      <button type="button" className={`${styles.card} ${styles.confirmed}`} onClick={() => open("Ahorro de mejoras aplicadas", Object.values(confirmed.meterIds).flat())}><span>Ahorro de mejoras aplicadas</span><strong>{money.format(confirmed.monthly)}</strong><small>Estimación mensual registrada · {confirmed.count} mejoras vigentes<br />Ver facturas →</small></button>
      <article className={`${styles.card} ${styles.unverified}`} aria-label="Ahorro comprobado en factura: sin verificar"><span>Ahorro comprobado en factura</span><strong>Sin verificar</strong><small>Pendiente de cotejar las facturas posteriores con las condiciones anteriores. No hay un importe comprobado calculado en este resumen.</small></article>
    </div>
    <div className={styles.breakdown}><h3>Seguimiento del ahorro por tipo de mejora</h3>
      <div className={styles.tableWrap}><table><thead><tr><th>Tipo de mejora</th><th>Propuesto mensual</th><th>Proyección anual propuesta</th><th>Aplicado mensual estimado</th><th>Comprobado en factura</th></tr></thead>
      <tbody>{savingKinds.map(kind => <tr key={kind}><th>{labels[kind]}</th><td>{amountLink(proposed[kind].monthly, `Ahorro propuesto · ${labels[kind]}`, proposedIds[kind])}</td><td>{money.format(proposed[kind].annual)}</td><td>{amountLink(confirmed.totals[kind], `Ahorro de mejoras aplicadas · ${labels[kind]}`, confirmed.meterIds[kind])}</td><td>Sin verificar</td></tr>)}</tbody>
      <tfoot><tr><th>Total</th><td>{money.format(proposedMonthly)}</td><td>{money.format(proposedAnnual)}</td><td>{money.format(confirmed.monthly)}</td><td>Sin verificar</td></tr></tfoot></table></div>
      <p>Tocá un importe mensual para ver sus facturas en la pestaña Facturas.</p>
      <p>Mejoras aplicadas: ahorro estimado registrado en medidas con estado Aplicada o Verificada. Excluye planificadas, canceladas y futuras; toma la última vigente de cada tipo por medidor. No se suma al propuesto.</p>
      <p>Comprobado en factura: requiere cotejar el cambio facturado por EPEN y calcular su efecto respecto de las condiciones anteriores. Marcar una mejora como Verificada no acredita por sí solo un importe ahorrado. “Sin verificar” no significa ahorro cero.</p>
      {confirmed.unvalued > 0 && <p role="status">{confirmed.unvalued} mejoras aplicadas todavía no tienen un importe registrado y no se incluyen en el monto.</p>}
      <p>La potencia propuesta usa la curva histórica de 12 meses; factor de potencia y tarifa se anualizan desde el mes. Valores con el tratamiento de IVA del análisis individual.</p>
    </div>
  </section>;
}
