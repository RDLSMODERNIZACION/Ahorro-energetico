"use client";

import { FormEvent, useMemo, useState } from "react";
import { supabase } from "./lib/supabase";

export type MeterChangeControl = {
  id: string;
  organization_id: string;
  meter_id: string;
  change_type:
    "contracted_power" | "power_factor" | "tariff" | "supply_deactivation";
  effective_period: string;
  status: "planned" | "applied" | "verified" | "cancelled";
  previous_value?: string | null;
  new_value?: string | null;
  notes?: string | null;
  created_at?: string;
};
type Invoice = {
  billing_period?: string;
  period_start: string;
  total_amount: number;
  invoice_measurements?: Array<{
    active_energy_kwh?: number;
    demand_kw?: number;
    registered_demand_peak_kw?: number;
    power_factor?: number;
    resolved_power_factor?: number;
  }>;
  invoice_lines?: Array<{ concept_code?: string; net_amount?: number }>;
};

const labels = {
  contracted_power: "Potencia contratada",
  power_factor: "Factor de potencia",
  tariff: "Tarifa",
  supply_deactivation: "Baja del suministro",
};
const statusLabels = {
  planned: "Planificado",
  applied: "Aplicado",
  verified: "Verificado",
  cancelled: "Cancelado",
};
const money = new Intl.NumberFormat("es-AR", {
  style: "currency",
  currency: "ARS",
  maximumFractionDigits: 0,
});
const number = new Intl.NumberFormat("es-AR", { maximumFractionDigits: 1 });
const periodOf = (invoice: Invoice) =>
  String(invoice.billing_period || invoice.period_start).slice(0, 7);
function invoiceMetrics(invoice: Invoice) {
  const measurements = invoice.invoice_measurements || [];
  const kwh = measurements.reduce(
    (sum, row) => sum + Number(row.active_energy_kwh || 0),
    0,
  );
  const demand = Math.max(
    0,
    ...measurements.map((row) =>
      Number(row.demand_kw || row.registered_demand_peak_kw || 0),
    ),
  );
  const factors = measurements
    .map((row) => Number(row.resolved_power_factor || row.power_factor || 0))
    .filter((value) => value > 0);
  const pf = factors.length ? Math.min(...factors) : 0;
  const reactive = (invoice.invoice_lines || [])
    .filter((row) => String(row.concept_code || "").toUpperCase() === "COS")
    .reduce((sum, row) => sum + Number(row.net_amount || 0), 0);
  return {
    kwh,
    demand,
    pf,
    reactive,
    total: Number(invoice.total_amount || 0),
  };
}
function average(rows: Invoice[]) {
  if (!rows.length) return null;
  const values = rows.map(invoiceMetrics);
  return values.reduce(
    (sum, row) => ({
      kwh: sum.kwh + row.kwh,
      demand: sum.demand + row.demand,
      pf: sum.pf + row.pf,
      reactive: sum.reactive + row.reactive,
      total: sum.total + row.total,
    }),
    { kwh: 0, demand: 0, pf: 0, reactive: 0, total: 0 },
  );
}

export function MeterChangeControlPanel({
  organizationId,
  meterId,
  selectedPeriod,
  history,
  controls,
  onSaved,
}: {
  organizationId: string;
  meterId: string;
  selectedPeriod: string;
  history: Invoice[];
  controls: MeterChangeControl[];
  onSaved: () => Promise<void> | void;
}) {
  const [open, setOpen] = useState(false),
    [saving, setSaving] = useState(false),
    [error, setError] = useState("");
  const [type, setType] =
    useState<MeterChangeControl["change_type"]>("contracted_power");
  const [effectivePeriod, setEffectivePeriod] = useState(selectedPeriod),
    [previousValue, setPreviousValue] = useState(""),
    [newValue, setNewValue] = useState(""),
    [notes, setNotes] = useState("");
  const valid = controls
    .filter((row) => row.status !== "cancelled")
    .sort((a, b) => a.effective_period.localeCompare(b.effective_period));
  const applied = valid.filter(
    (row) => String(row.effective_period).slice(0, 7) <= selectedPeriod,
  );
  const phase = applied.length ? "after" : valid.length ? "before" : "none";
  const comparison = useMemo(() => {
    const change = [...valid]
      .reverse()
      .find((row) => row.status === "applied" || row.status === "verified");
    if (!change) return null;
    const effective = String(change.effective_period).slice(0, 7);
    const sorted = [...history].sort((a, b) =>
      periodOf(a).localeCompare(periodOf(b)),
    );
    const before = sorted.filter((row) => periodOf(row) < effective).slice(-3);
    const after = sorted
      .filter((row) => periodOf(row) >= effective)
      .slice(0, 3);
    const beforeSum = average(before),
      afterSum = average(after);
    const normalize = (sum: ReturnType<typeof average>, count: number) =>
      sum
        ? {
            kwh: sum.kwh / count,
            demand: sum.demand / count,
            pf: sum.pf / count,
            reactive: sum.reactive / count,
            total: sum.total / count,
          }
        : null;
    return {
      change,
      effective,
      before: normalize(beforeSum, before.length),
      after: normalize(afterSum, after.length),
      beforeCount: before.length,
      afterCount: after.length,
    };
  }, [history, valid]);
  async function save(event: FormEvent) {
    event.preventDefault();
    setSaving(true);
    setError("");
    const { data } = await supabase.auth.getSession();
    if (!data.session) {
      setError("La sesión venció.");
      setSaving(false);
      return;
    }
    const { error: insertError } = await supabase
      .from("meter_change_controls")
      .insert({
        organization_id: organizationId,
        meter_id: meterId,
        change_type: type,
        effective_period: `${effectivePeriod}-01`,
        status: "applied",
        previous_value: previousValue || null,
        new_value: newValue || null,
        notes: notes || null,
        created_by: data.session.user.id,
      });
    if (insertError) setError(insertError.message);
    else {
      setOpen(false);
      setPreviousValue("");
      setNewValue("");
      setNotes("");
      await onSaved();
    }
    setSaving(false);
  }
  return (
    <section className="invoice-analysis-panel change-control-panel">
      <div className="change-control-head">
        <div>
          <span>CONTROL DE CAMBIOS</span>
          <h3>Seguimiento antes y después</h3>
          <p>
            Las facturas se clasifican desde el período efectivo de cada
            intervención.
          </p>
        </div>
        <div className="change-control-actions">
          <span className={`change-phase ${phase}`}>
            {phase === "after"
              ? "DESPUÉS DEL CAMBIO"
              : phase === "before"
                ? "ANTES DEL CAMBIO"
                : "SIN CAMBIOS REGISTRADOS"}
          </span>
          <button onClick={() => setOpen((value) => !value)}>
            ＋ Registrar cambio
          </button>
        </div>
      </div>
      {open && (
        <form className="change-control-form" onSubmit={save}>
          <label>
            Tipo
            <select
              value={type}
              onChange={(e) =>
                setType(e.target.value as MeterChangeControl["change_type"])
              }
            >
              {Object.entries(labels).map(([value, label]) => (
                <option key={value} value={value}>
                  {label}
                </option>
              ))}
            </select>
          </label>
          <label>
            Período efectivo
            <input
              type="month"
              required
              value={effectivePeriod}
              onChange={(e) => setEffectivePeriod(e.target.value)}
            />
          </label>
          <label>
            Valor anterior
            <input
              value={previousValue}
              onChange={(e) => setPreviousValue(e.target.value)}
              placeholder="Ej.: 79 kW o T2"
            />
          </label>
          <label>
            Valor nuevo
            <input
              value={newValue}
              onChange={(e) => setNewValue(e.target.value)}
              placeholder="Ej.: 60 kW o T1G2"
            />
          </label>
          <label className="notes">
            Observaciones
            <input
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              placeholder="Trabajo realizado, expediente o referencia EPEN"
            />
          </label>
          <button disabled={saving}>
            {saving ? "Guardando…" : "Guardar intervención"}
          </button>
          {error && <small className="danger">{error}</small>}
        </form>
      )}
      {!!valid.length && (
        <div className="change-control-timeline">
          {valid.map((row) => (
            <article key={row.id}>
              <span>{String(row.effective_period).slice(0, 7)}</span>
              <b>{labels[row.change_type]}</b>
              <small>
                {row.previous_value || "S/D"} →{" "}
                {row.new_value || statusLabels[row.status]}
              </small>
              {row.notes && <p>{row.notes}</p>}
            </article>
          ))}
        </div>
      )}
      {comparison && (
        <div className="change-comparison">
          <div>
            <span>LÍNEA BASE</span>
            <b>
              {comparison.beforeCount} factura
              {comparison.beforeCount === 1 ? "" : "s"} anteriores
            </b>
          </div>
          <Comparison
            label="Importe promedio"
            before={comparison.before?.total}
            after={comparison.after?.total}
            format={money.format}
          />
          <Comparison
            label="Consumo promedio"
            before={comparison.before?.kwh}
            after={comparison.after?.kwh}
            format={(value) => `${number.format(value)} kWh`}
          />
          <Comparison
            label="Demanda promedio"
            before={comparison.before?.demand}
            after={comparison.after?.demand}
            format={(value) => `${number.format(value)} kW`}
          />
          <Comparison
            label="Recargo FP promedio"
            before={comparison.before?.reactive}
            after={comparison.after?.reactive}
            format={money.format}
          />
        </div>
      )}
    </section>
  );
}
function Comparison({
  label,
  before,
  after,
  format,
}: {
  label: string;
  before?: number;
  after?: number;
  format: (value: number) => string;
}) {
  return (
    <div>
      <span>{label}</span>
      <b>
        {before == null ? "S/D" : format(before)} →{" "}
        {after == null ? "Esperando facturas" : format(after)}
      </b>
    </div>
  );
}
