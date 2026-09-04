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
  details?: Record<string, unknown>;
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
  contracted_power: "Potencia mejorada",
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
  powerProposals,
  currentTariff,
  recommendedTariff,
  onSaved,
}: {
  organizationId: string;
  meterId: string;
  selectedPeriod: string;
  history: Invoice[];
  controls: MeterChangeControl[];
  powerProposals: Array<{
    month: string;
    monthNumber: number;
    proposalKw: number;
    method: string;
    quarter: string;
    latestKw: number;
    latestPeriod: string;
  }>;
  currentTariff?: string;
  recommendedTariff?: string;
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
    [notes, setNotes] = useState(""),
    [capacitorCount, setCapacitorCount] = useState(""),
    [installedKvar, setInstalledKvar] = useState(""),
    [actualPowers, setActualPowers] = useState<Record<number, string>>({}),
    [powerAttachment, setPowerAttachment] = useState<File | null>(null);
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
    if (type === "contracted_power" && !powerAttachment) {
      setError("Adjuntá el comprobante con la potencia corregida.");
      setSaving(false);
      return;
    }
    if (powerAttachment && powerAttachment.size > 10 * 1024 * 1024) {
      setError("El adjunto no puede superar los 10 MB.");
      setSaving(false);
      return;
    }
    let attachment: Record<string, unknown> | null = null;
    let attachmentPath = "";
    if (type === "contracted_power" && powerAttachment) {
      const safeName = powerAttachment.name.replace(/[^a-zA-Z0-9._-]/g, "_");
      attachmentPath = `${organizationId}/${meterId}/improvements/${Date.now()}-${crypto.randomUUID()}-${safeName}`;
      const { error: uploadError } = await supabase.storage
        .from("energy-documents")
        .upload(attachmentPath, powerAttachment, {
          contentType: powerAttachment.type || undefined,
          upsert: false,
        });
      if (uploadError) {
        setError(`No se pudo subir el adjunto: ${uploadError.message}`);
        setSaving(false);
        return;
      }
      attachment = {
        bucket: "energy-documents",
        path: attachmentPath,
        name: powerAttachment.name,
        mime_type: powerAttachment.type,
        size: powerAttachment.size,
      };
    }
    const details =
      type === "contracted_power"
        ? {
            months: powerProposals.map((row) => ({
              ...row,
              effective_kw: Number(
                actualPowers[row.monthNumber] || row.proposalKw,
              ),
            })),
            attachment,
          }
        : type === "power_factor"
          ? {
              capacitor_count: Number(capacitorCount || 0),
              installed_kvar: Number(installedKvar || 0),
            }
          : type === "tariff"
            ? {
                previous_tariff: previousValue || currentTariff || null,
                new_tariff: newValue || recommendedTariff || null,
              }
            : { deactivated: true };
    const resolvedPrevious =
      type === "tariff" ? previousValue || currentTariff : previousValue;
    const resolvedNew =
      type === "tariff"
        ? newValue || recommendedTariff
        : type === "power_factor"
          ? `${capacitorCount || 0} capacitores · ${installedKvar || 0} kVAr`
          : newValue;
    const { error: insertError } = await supabase
      .from("meter_change_controls")
      .insert({
        organization_id: organizationId,
        meter_id: meterId,
        change_type: type,
        effective_period: `${effectivePeriod}-01`,
        status: "applied",
        previous_value: resolvedPrevious || null,
        new_value: resolvedNew || null,
        details,
        notes: notes || null,
        created_by: data.session.user.id,
      });
    if (insertError) {
      if (attachmentPath)
        await supabase.storage
          .from("energy-documents")
          .remove([attachmentPath]);
      setError(insertError.message);
    } else {
      setOpen(false);
      setPreviousValue("");
      setNewValue("");
      setNotes("");
      setPowerAttachment(null);
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
          <button onClick={() => setOpen(true)}>＋ Registrar mejora</button>
        </div>
      </div>
      {open && (
        <div className="improvement-backdrop">
          <div className="improvement-page">
            <div className="improvement-head">
              <div>
                <span>CONTROL DE IMPLEMENTACIÓN</span>
                <h2>Registrar mejora</h2>
                <p>
                  Indicá exactamente qué se aplicó y desde qué factura debe
                  controlarse.
                </p>
              </div>
              <button type="button" onClick={() => setOpen(false)}>
                ← Volver al análisis
              </button>
            </div>
            <div className="improvement-tabs">
              {Object.entries(labels).map(([value, label]) => (
                <button
                  key={value}
                  className={type === value ? "active" : ""}
                  onClick={() =>
                    setType(value as MeterChangeControl["change_type"])
                  }
                >
                  {label}
                </button>
              ))}
            </div>
            <form className="improvement-form" onSubmit={save}>
              <label>
                Período efectivo
                <input
                  type="month"
                  required
                  value={effectivePeriod}
                  onChange={(e) => setEffectivePeriod(e.target.value)}
                />
              </label>
              {type === "contracted_power" && (
                <div className="improvement-power-table">
                  <div className="improvement-power-head">
                    <span>Mes</span>
                    <span>Última potencia disponible</span>
                    <span>Propuesta calculada</span>
                    <span>Potencia efectivamente contratada</span>
                  </div>
                  {powerProposals.map((row) => (
                    <div key={row.monthNumber}>
                      <b>{row.month}</b>
                      <span>
                        {row.latestKw > 0
                          ? `${number.format(row.latestKw)} kW`
                          : "S/D"}
                        <small>
                          {row.latestPeriod || "Sin factura disponible"}
                        </small>
                      </span>
                      <span>
                        {number.format(row.proposalKw)} kW
                        <small>
                          {row.method === "trimestral"
                            ? `Trimestre ${row.quarter}`
                            : "Propuesta mensual"}
                        </small>
                      </span>
                      <label>
                        <input
                          type="number"
                          min="0"
                          step="0.1"
                          value={
                            actualPowers[row.monthNumber] ??
                            String(row.proposalKw)
                          }
                          onChange={(e) =>
                            setActualPowers((values) => ({
                              ...values,
                              [row.monthNumber]: e.target.value,
                            }))
                          }
                        />{" "}
                        kW
                      </label>
                    </div>
                  ))}
                </div>
              )}
              {type === "contracted_power" && (
                <label className="improvement-attachment">
                  Comprobante de potencia corregida
                  <input
                    type="file"
                    required
                    accept=".pdf,.xlsx,.xls,image/*"
                    onChange={(event) =>
                      setPowerAttachment(event.target.files?.[0] || null)
                    }
                  />
                  <small>
                    Adjuntá la nota, factura, resolución o planilla confirmada
                    por EPEN. PDF, imagen o Excel; máximo 10 MB.
                  </small>
                </label>
              )}
              {type === "power_factor" && (
                <div className="improvement-specific">
                  <label>
                    Cantidad de capacitores
                    <input
                      type="number"
                      min="0"
                      required
                      value={capacitorCount}
                      onChange={(e) => setCapacitorCount(e.target.value)}
                    />
                  </label>
                  <label>
                    Compensación total instalada
                    <input
                      type="number"
                      min="0"
                      step="0.1"
                      required
                      value={installedKvar}
                      onChange={(e) => setInstalledKvar(e.target.value)}
                    />
                    <small>kVAr</small>
                  </label>
                </div>
              )}
              {type === "tariff" && (
                <div className="improvement-specific">
                  <label>
                    Tarifa anterior
                    <input
                      required
                      value={previousValue || currentTariff || ""}
                      onChange={(e) => setPreviousValue(e.target.value)}
                    />
                  </label>
                  <label>
                    Tarifa a la que se solicita pasar
                    <input
                      required
                      value={newValue || recommendedTariff || ""}
                      onChange={(e) => setNewValue(e.target.value)}
                    />
                  </label>
                </div>
              )}
              {type === "supply_deactivation" && (
                <div className="improvement-warning">
                  <b>Baja del suministro</b>
                  <p>
                    Desde el período efectivo dejará de esperarse una nueva
                    factura. La baja quedará pendiente de verificación hasta
                    confirmar que EPEN dejó de facturar.
                  </p>
                </div>
              )}
              <label className="notes">
                Observaciones
                <input
                  value={notes}
                  onChange={(e) => setNotes(e.target.value)}
                  placeholder="Trabajo realizado, expediente, orden o referencia EPEN"
                />
              </label>
              <div className="improvement-footer">
                <button
                  type="button"
                  className="secondary"
                  onClick={() => setOpen(false)}
                >
                  Cancelar
                </button>
                <button disabled={saving}>
                  {saving ? "Guardando…" : "Guardar mejora aplicada"}
                </button>
              </div>
              {error && <small className="danger">{error}</small>}
            </form>
          </div>
        </div>
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
