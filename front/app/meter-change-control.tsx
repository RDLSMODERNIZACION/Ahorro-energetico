"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";
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
type TariffCategory = { code: string; name?: string | null };

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
function attachmentOf(row: MeterChangeControl) {
  const value =
    row.change_type === "tariff"
      ? row.details?.agreement
      : row.details?.attachment;
  if (!value || typeof value !== "object") return null;
  const document = value as Record<string, unknown>;
  return typeof document.path === "string"
    ? {
        path: document.path,
        name: String(document.name || "Adjunto"),
        type: String(document.document_type || "Adjunto"),
      }
    : null;
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
  const [workspace, setWorkspace] = useState<"register" | "history">("history"),
    [editingId, setEditingId] = useState<string | null>(null),
    [editPeriod, setEditPeriod] = useState(""),
    [editPrevious, setEditPrevious] = useState(""),
    [editNew, setEditNew] = useState(""),
    [editNotes, setEditNotes] = useState(""),
    [editStatus, setEditStatus] =
      useState<MeterChangeControl["status"]>("applied");
  const [type, setType] =
    useState<MeterChangeControl["change_type"]>("contracted_power");
  const [effectivePeriod, setEffectivePeriod] = useState(selectedPeriod),
    [previousValue, setPreviousValue] = useState(""),
    [newValue, setNewValue] = useState(""),
    [notes, setNotes] = useState(""),
    [capacitorCount, setCapacitorCount] = useState(""),
    [installedKvar, setInstalledKvar] = useState(""),
    [actualPowers, setActualPowers] = useState<Record<number, string>>({}),
    [powerAttachment, setPowerAttachment] = useState<File | null>(null),
    [tariffAgreement, setTariffAgreement] = useState<File | null>(null),
    [tariffCategories, setTariffCategories] = useState<TariffCategory[]>([]),
    [supplyStatus, setSupplyStatus] = useState<"active" | "removed">("active");
  useEffect(() => {
    if (!open || type !== "tariff" || tariffCategories.length) return;
    supabase
      .from("tariff_categories")
      .select("code,name")
      .order("code")
      .then(({ data, error: categoryError }) => {
        if (categoryError) setError(categoryError.message);
        else setTariffCategories((data || []) as TariffCategory[]);
      });
  }, [open, type, tariffCategories.length]);
  const valid = controls
    .filter((row) => row.status !== "cancelled")
    .sort((a, b) => a.effective_period.localeCompare(b.effective_period));
  const applied = valid.filter(
    (row) => String(row.effective_period).slice(0, 7) <= selectedPeriod,
  );
  const phase = applied.length ? "after" : valid.length ? "before" : "none";
  const deactivationControl = [...valid]
    .reverse()
    .find((row) => row.change_type === "supply_deactivation");
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
  function beginEdit(row: MeterChangeControl) {
    setEditingId(row.id);
    setEditPeriod(String(row.effective_period).slice(0, 7));
    setEditPrevious(row.previous_value || "");
    setEditNew(row.new_value || "");
    setEditNotes(row.notes || "");
    setEditStatus(row.status);
    setError("");
  }
  async function updateControl(event: FormEvent) {
    event.preventDefault();
    if (!editingId) return;
    setSaving(true);
    setError("");
    const { error: updateError } = await supabase
      .from("meter_change_controls")
      .update({
        effective_period: `${editPeriod}-01`,
        previous_value: editPrevious || null,
        new_value: editNew || null,
        notes: editNotes || null,
        status: editStatus,
        updated_at: new Date().toISOString(),
      })
      .eq("id", editingId)
      .eq("organization_id", organizationId);
    if (updateError) setError(updateError.message);
    else {
      setEditingId(null);
      await onSaved();
    }
    setSaving(false);
  }
  async function undoControl(row: MeterChangeControl) {
    if (!window.confirm(`¿Deshacer ${labels[row.change_type]}?`)) return;
    setSaving(true);
    setError("");
    const { error: updateError } = await supabase
      .from("meter_change_controls")
      .update({ status: "cancelled", updated_at: new Date().toISOString() })
      .eq("id", row.id)
      .eq("organization_id", organizationId);
    if (updateError) setError(updateError.message);
    else await onSaved();
    setSaving(false);
  }
  async function viewAttachment(row: MeterChangeControl) {
    const document = attachmentOf(row);
    if (!document) return;
    setError("");
    const { data, error: signedError } = await supabase.storage
      .from("energy-documents")
      .createSignedUrl(document.path, 60);
    if (signedError) setError(signedError.message);
    else window.open(data.signedUrl, "_blank", "noopener,noreferrer");
  }
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
    if (type === "tariff" && !tariffAgreement) {
      setError("Adjuntá el convenio del cambio tarifario.");
      setSaving(false);
      return;
    }
    if (type === "supply_deactivation" && supplyStatus !== "removed") {
      setError("Cambiá el estado de Activo a Dado de baja para confirmar.");
      setSaving(false);
      return;
    }
    const baselineInvoices = [...history]
      .filter((invoice) => periodOf(invoice) <= effectivePeriod)
      .sort((a, b) => periodOf(b).localeCompare(periodOf(a)))
      .slice(0, 3);
    const baselineMonthlyCost = baselineInvoices.length
      ? baselineInvoices.reduce(
          (sum, invoice) => sum + Number(invoice.total_amount || 0),
          0,
        ) / baselineInvoices.length
      : 0;
    const evidenceFile =
      type === "contracted_power"
        ? powerAttachment
        : type === "tariff"
          ? tariffAgreement
          : null;
    if (evidenceFile && evidenceFile.size > 10 * 1024 * 1024) {
      setError("El adjunto no puede superar los 10 MB.");
      setSaving(false);
      return;
    }
    let attachment: Record<string, unknown> | null = null;
    let attachmentPath = "";
    if (evidenceFile) {
      const safeName = evidenceFile.name.replace(/[^a-zA-Z0-9._-]/g, "_");
      attachmentPath = `${organizationId}/${meterId}/improvements/${Date.now()}-${crypto.randomUUID()}-${safeName}`;
      const { error: uploadError } = await supabase.storage
        .from("energy-documents")
        .upload(attachmentPath, evidenceFile, {
          contentType: evidenceFile.type || undefined,
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
        document_type: type === "tariff" ? "Convenio" : "Comprobante",
        name: evidenceFile.name,
        mime_type: evidenceFile.type,
        size: evidenceFile.size,
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
                agreement: attachment,
              }
            : {
                deactivated: true,
                previous_status: "active",
                new_status: supplyStatus,
                baseline_monthly_cost: baselineMonthlyCost,
                annual_saving: baselineMonthlyCost * 12,
              };
    const resolvedPrevious =
      type === "tariff"
        ? previousValue || currentTariff
        : type === "supply_deactivation"
          ? "Activo"
          : type === "contracted_power"
            ? `${number.format(powerProposals.find((row) => row.monthNumber === Number(effectivePeriod.slice(5, 7)))?.latestKw || 0)} kW`
            : previousValue;
    const resolvedNew =
      type === "tariff"
        ? newValue || recommendedTariff
        : type === "power_factor"
          ? `${capacitorCount || 0} capacitores · ${installedKvar || 0} kVAr`
          : type === "supply_deactivation"
            ? "Dado de baja"
            : type === "contracted_power"
              ? `${number.format(Number(actualPowers[Number(effectivePeriod.slice(5, 7))] || powerProposals.find((row) => row.monthNumber === Number(effectivePeriod.slice(5, 7)))?.proposalKw || 0))} kW`
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
      setWorkspace("history");
      setPreviousValue("");
      setNewValue("");
      setNotes("");
      setPowerAttachment(null);
      setTariffAgreement(null);
      setSupplyStatus("active");
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
          <button
            onClick={() => {
              setWorkspace("history");
              setOpen(true);
            }}
          >
            Abrir control de mejoras →
          </button>
        </div>
      </div>
      {open && (
        <div className="improvement-backdrop">
          <div className="improvement-page">
            <div className="improvement-head">
              <div>
                <span>CONTROL DE IMPLEMENTACIÓN</span>
                <h2>Gestión de mejoras</h2>
                <p>
                  Registro, historial, correcciones y seguimiento del
                  suministro.
                </p>
              </div>
              <button type="button" onClick={() => setOpen(false)}>
                ← Volver al análisis
              </button>
            </div>
            <div className="improvement-workspace-tabs">
              <button
                className={workspace === "register" ? "active" : ""}
                onClick={() => setWorkspace("register")}
              >
                ＋ Registrar mejora
              </button>
              <button
                className={workspace === "history" ? "active" : ""}
                onClick={() => setWorkspace("history")}
              >
                Historial y seguimiento ({controls.length})
              </button>
            </div>
            {workspace === "register" && (
              <>
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
                        Adjuntá la nota, factura, resolución o planilla
                        confirmada por EPEN. PDF, imagen o Excel; máximo 10 MB.
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
                      <label className="unit-field">
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
                        Tarifa vigente
                        <input
                          required
                          value={previousValue || currentTariff || ""}
                          readOnly
                          aria-readonly="true"
                        />
                        <small>Se toma de la última factura disponible.</small>
                      </label>
                      <label>
                        Tarifa a la que se solicita pasar
                        <select
                          required
                          value={newValue || recommendedTariff || ""}
                          onChange={(e) => setNewValue(e.target.value)}
                        >
                          <option value="">Seleccionar tarifa</option>
                          {tariffCategories
                            .filter(
                              (category) => category.code !== currentTariff,
                            )
                            .map((category) => (
                              <option key={category.code} value={category.code}>
                                {category.code}
                                {category.name ? ` · ${category.name}` : ""}
                              </option>
                            ))}
                        </select>
                      </label>
                    </div>
                  )}
                  {type === "tariff" && (
                    <label className="improvement-attachment">
                      Convenio
                      <input
                        type="file"
                        required
                        accept=".pdf,.doc,.docx,image/*"
                        onChange={(event) =>
                          setTariffAgreement(event.target.files?.[0] || null)
                        }
                      />
                      <small>
                        Adjuntá el convenio que autoriza el nuevo
                        encuadramiento. PDF, Word o imagen; máximo 10 MB.
                      </small>
                    </label>
                  )}
                  {type === "supply_deactivation" && (
                    <div className="improvement-status-change">
                      <div>
                        <span>Estado actual</span>
                        <b>Activo</b>
                        <small>
                          El suministro continúa visible en la aplicación.
                        </small>
                      </div>
                      <span className="improvement-status-arrow">→</span>
                      <label>
                        Nuevo estado
                        <select
                          value={supplyStatus}
                          onChange={(event) =>
                            setSupplyStatus(
                              event.target.value as "active" | "removed",
                            )
                          }
                        >
                          <option value="active">Activo</option>
                          <option value="removed">Dado de baja</option>
                        </select>
                      </label>
                      <p>
                        La baja no elimina el suministro ni su historial.
                        Quedará identificado para comparar el gasto anterior con
                        el ahorro generado desde el período efectivo.
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
              </>
            )}
            {workspace === "history" && (
              <div className="improvement-history-page">
                <div className="improvement-history-kpis">
                  <article>
                    <span>TOTAL REGISTRADAS</span>
                    <b>{controls.length}</b>
                  </article>
                  <article>
                    <span>APLICADAS</span>
                    <b>
                      {
                        controls.filter((row) => row.status === "applied")
                          .length
                      }
                    </b>
                  </article>
                  <article>
                    <span>VERIFICADAS</span>
                    <b>
                      {
                        controls.filter((row) => row.status === "verified")
                          .length
                      }
                    </b>
                  </article>
                  <article>
                    <span>DESHECHAS</span>
                    <b>
                      {
                        controls.filter((row) => row.status === "cancelled")
                          .length
                      }
                    </b>
                  </article>
                </div>
                {!controls.length && (
                  <div className="improvement-history-empty">
                    <b>Sin mejoras registradas</b>
                    <span>
                      Usá “Registrar mejora” para iniciar el seguimiento.
                    </span>
                  </div>
                )}
                <div className="improvement-history-list">
                  {[...controls]
                    .sort((a, b) =>
                      b.effective_period.localeCompare(a.effective_period),
                    )
                    .map((row) => (
                      <article
                        key={row.id}
                        className={
                          row.status === "cancelled" ? "cancelled" : ""
                        }
                      >
                        <div className="improvement-history-card-head">
                          <div>
                            <span>
                              {String(row.effective_period).slice(0, 7)}
                            </span>
                            <h3>{labels[row.change_type]}</h3>
                            <p>
                              {row.previous_value || "S/D"} →{" "}
                              {row.new_value || "S/D"}
                            </p>
                          </div>
                          <span className={`improvement-status ${row.status}`}>
                            {statusLabels[row.status]}
                          </span>
                        </div>
                        {row.notes && (
                          <p className="improvement-history-notes">
                            {row.notes}
                          </p>
                        )}
                        {editingId === row.id ? (
                          <form
                            className="improvement-edit-form"
                            onSubmit={updateControl}
                          >
                            <label>
                              Período
                              <input
                                type="month"
                                required
                                value={editPeriod}
                                onChange={(event) =>
                                  setEditPeriod(event.target.value)
                                }
                              />
                            </label>
                            <label>
                              Valor anterior
                              <input
                                value={editPrevious}
                                onChange={(event) =>
                                  setEditPrevious(event.target.value)
                                }
                              />
                            </label>
                            <label>
                              Valor aplicado
                              <input
                                value={editNew}
                                onChange={(event) =>
                                  setEditNew(event.target.value)
                                }
                              />
                            </label>
                            <label>
                              Estado
                              <select
                                value={editStatus}
                                onChange={(event) =>
                                  setEditStatus(
                                    event.target
                                      .value as MeterChangeControl["status"],
                                  )
                                }
                              >
                                <option value="planned">Planificado</option>
                                <option value="applied">Aplicado</option>
                                <option value="verified">Verificado</option>
                                <option value="cancelled">Cancelado</option>
                              </select>
                            </label>
                            <label className="wide">
                              Observaciones
                              <input
                                value={editNotes}
                                onChange={(event) =>
                                  setEditNotes(event.target.value)
                                }
                              />
                            </label>
                            <div className="improvement-edit-actions">
                              <button
                                type="button"
                                onClick={() => setEditingId(null)}
                              >
                                Cancelar
                              </button>
                              <button disabled={saving}>
                                Guardar modificación
                              </button>
                            </div>
                          </form>
                        ) : (
                          <div className="improvement-history-actions">
                            {attachmentOf(row) && (
                              <button onClick={() => viewAttachment(row)}>
                                Ver {attachmentOf(row)?.type.toLowerCase()}
                              </button>
                            )}
                            <button onClick={() => beginEdit(row)}>
                              Modificar
                            </button>
                            {row.status !== "cancelled" && (
                              <button
                                className="danger-action"
                                onClick={() => undoControl(row)}
                              >
                                Deshacer cambio
                              </button>
                            )}
                          </div>
                        )}
                      </article>
                    ))}
                </div>
                {error && <small className="danger">{error}</small>}
                {!!valid.length && (
                  <div className="improvement-tracking-block">
                    <h3>Seguimiento antes y después</h3>
                    {deactivationControl && (
                      <div className="change-deactivation-saving">
                        <div>
                          <span>SUMINISTRO</span>
                          <b>Activo → Dado de baja</b>
                          <small>
                            Visible para control · desde{" "}
                            {deactivationControl.effective_period.slice(0, 7)}
                          </small>
                        </div>
                        <div>
                          <span>AHORRO POR BAJA</span>
                          <b>
                            {money.format(
                              Number(
                                deactivationControl.details
                                  ?.baseline_monthly_cost || 0,
                              ),
                            )}{" "}
                            /mes
                          </b>
                          <small>
                            {money.format(
                              Number(
                                deactivationControl.details?.annual_saving || 0,
                              ),
                            )}{" "}
                            anual estimado
                          </small>
                        </div>
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
                  </div>
                )}
              </div>
            )}
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
      {deactivationControl && (
        <div className="change-deactivation-saving">
          <div>
            <span>SUMINISTRO</span>
            <b>Activo → Dado de baja</b>
            <small>
              Visible para control · desde{" "}
              {deactivationControl.effective_period.slice(0, 7)}
            </small>
          </div>
          <div>
            <span>AHORRO POR BAJA</span>
            <b>
              {money.format(
                Number(deactivationControl.details?.baseline_monthly_cost || 0),
              )}{" "}
              /mes
            </b>
            <small>
              {money.format(
                Number(deactivationControl.details?.annual_saving || 0),
              )}{" "}
              anual estimado
            </small>
          </div>
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
