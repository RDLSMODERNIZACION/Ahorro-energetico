"use client";

import { useMemo, useState, useEffect } from "react";
import { MeterLocationEditor } from "./meter-location-editor";
import {
  MeterChangeControlPanel,
  type MeterChangeControl,
} from "./meter-change-control";
import { supabase } from "./lib/supabase";
import type { EpenOptimizationMeter } from "./epen-optimization-panel";
import styles from "./power-curve.module.css";

type Measurement = {
  active_energy_kwh?: number;
  reactive_energy_kvarh?: number;
  demand_kw?: number;
  registered_demand_peak_kw?: number;
  registered_demand_off_peak_kw?: number;
  power_factor?: number;
  resolved_power_factor?: number;
  power_factor_source?: string;
  power_factor_penalized?: boolean;
  tangent_phi?: number;
  reactive_surcharge_percent?: number;
  meter_number?: string;
  measurement_type?: string;
};
type Line = {
  concept_code?: string;
  description?: string;
  quantity?: number;
  unit_price?: number;
  net_amount?: number;
};
type Meter = {
  id: string;
  tracking_code?: string;
  meter_number?: string;
  supply_number?: string;
  contract_number?: string;
  service_code?: string;
  service_name?: string;
  cadastral_number?: string;
  voltage_level?: string;
  contracted_kw_peak?: number;
  contracted_kw_off_peak?: number;
  sites?: { name?: string; address?: string };
};
type Invoice = {
  id: string;
  meter_id: string;
  invoice_number?: string;
  billing_period?: string;
  period_start: string;
  period_end: string;
  issue_date?: string;
  due_date?: string;
  total_amount: number;
  amount_due?: number;
  current_tariff_code?: string;
  tariff_name?: string;
  voltage_level?: string;
  contracted_kw_peak?: number;
  contracted_kw_off_peak?: number;
  vat_amount?: number;
  previous_debt_amount?: number;
  meters?: Meter;
  invoice_measurements?: Measurement[];
  invoice_lines?: Line[];
};
type TariffSaving = {
  meter_id: string;
  billing_period: string;
  current_tariff?: string;
  recommended_tariff?: string;
  current_cost_with_vat?: number;
  recommended_cost_with_vat?: number;
  monthly_saving_with_vat: number;
  annual_saving_with_vat?: number;
};
type TariffAssessment = {
  meter_id: string;
  billing_period?: string;
  current_tariff?: string;
  recommended_tariff: string;
  status: string;
  maximum_demand_kw: number;
  tariff_monthly_saving: number;
  tariff_annual_saving: number;
  tariff_simulation_available: boolean;
  tariff_current_simulated?: number;
  tariff_recommended_simulated?: number;
};
type AdvancedTariffHistoryPoint = {
  billing_period: string;
  current_tariff: string;
  recommended_tariff: string;
  current_cost: number;
  recommended_cost: number;
  monthly_saving: number;
  annualized_saving: number;
  capacity_kw: number;
  available?: boolean;
  reason?: string | null;
  resolution_number?: string | null;
  billing_month?: string | null;
  consumption_month?: string | null;
  current_cost_source?: string;
  current_components?: Array<{
    code: string;
    description?: string;
    quantity?: number | null;
    unit_price?: number | null;
    net_amount: number;
  }>;
  proposed_components?: Array<{
    code: string;
    description?: string;
    quantity?: number | null;
    unit_price?: number | null;
    net_amount: number;
  }>;
  available?: boolean;
  reason?: string | null;
};
type AdvancedTariffHistoryResponse = {
  meter_id: string;
  mode: "t4" | "mt" | "downshift" | "none";
  current_tariff?: string;
  recommended_tariff?: string;
  taxes_included?: boolean;
  status?: string;
  requires_epen_feasibility?: boolean;
  requires_epen_contract?: boolean;
  points: AdvancedTariffHistoryPoint[];
};
type Metric = "kwh" | "amount" | "demand" | "pf" | "tariff";

const nf = new Intl.NumberFormat("es-AR", { maximumFractionDigits: 0 });
const dec = new Intl.NumberFormat("es-AR", { maximumFractionDigits: 3 });
const API = "https://ahorro-energetico.onrender.com";
const money = new Intl.NumberFormat("es-AR", {
  style: "currency",
  currency: "ARS",
  maximumFractionDigits: 0,
});

function periodOf(i: Invoice) {
  return String(i.billing_period || i.period_start).slice(0, 7);
}
function contractedBands(i: Invoice) {
  const lines = i.invoice_lines || [];
  const dep = Math.max(
    0,
    ...lines
      .filter((x) => x.concept_code === "DEP" || x.concept_code === "DEM")
      .map((x) => Number(x.quantity || 0)),
  );
  const dfp = Math.max(
    0,
    ...lines
      .filter((x) => x.concept_code === "DFP")
      .map((x) => Number(x.quantity || 0)),
  );
  const peak = Number(
    i.contracted_kw_peak || i.meters?.contracted_kw_peak || dep || 0,
  );
  const offPeak = Number(
    i.contracted_kw_off_peak || i.meters?.contracted_kw_off_peak || dfp || 0,
  );
  return { peak, offPeak };
}
function labelPeriod(period: string) {
  const [y, m] = period.split("-").map(Number);
  return new Date(y, m - 1, 1)
    .toLocaleString("es-AR", { month: "short", year: "2-digit" })
    .replace(".", "");
}
function values(i: Invoice) {
  const ms = i.invoice_measurements || [];
  const kwh = ms.reduce((s, m) => s + Number(m.active_energy_kwh || 0), 0);
  const kvarh = ms.reduce(
    (s, m) => s + Number(m.reactive_energy_kvarh || 0),
    0,
  );
  const demand = Math.max(
    0,
    ...ms.map((m) => Number(m.demand_kw || m.registered_demand_peak_kw || 0)),
  );
  const contracted = contractedBands(i).peak;
  const pfs = ms
    .map((m) => Number(m.resolved_power_factor || m.power_factor || 0))
    .filter((v) => v > 0);
  const pf = pfs.length
    ? Math.min(...pfs)
    : Number(i.resolved_power_factor || 0);
  const surcharge = Math.max(
    0,
    ...ms.map((m) => Number(m.reactive_surcharge_percent || 0)),
  );
  const cosCharge = (i.invoice_lines || [])
    .filter((x) => String(x.concept_code || "").toUpperCase() === "COS")
    .reduce((s, x) => s + Math.max(0, Number(x.net_amount || 0)), 0);
  const penalized =
    Boolean(i.power_factor_penalized) ||
    ms.some((m) => m.power_factor_penalized) ||
    surcharge > 0 ||
    cosCharge > 0;
  const pfUnknownPenalized = penalized && !(pf > 0);
  return {
    kwh,
    kvarh,
    demand,
    contracted,
    pf,
    surcharge,
    penalized,
    pfUnknownPenalized,
    cosCharge,
  };
}
function metricValue(i: Invoice, m: Metric) {
  const v = values(i);
  if (m === "amount") return Number(i.total_amount || 0);
  if (m === "demand") return v.demand;
  if (m === "pf") return v.pf;
  return v.kwh;
}
function fmt(metric: Metric, value: number) {
  if (metric === "amount") return money.format(value);
  if (metric === "demand") return `${nf.format(value)} kW`;
  if (metric === "pf") return value ? value.toFixed(3) : "S/D";
  return `${nf.format(value)} kWh`;
}

const powerMonthNames = [
  "Enero",
  "Febrero",
  "Marzo",
  "Abril",
  "Mayo",
  "Junio",
  "Julio",
  "Agosto",
  "Septiembre",
  "Octubre",
  "Noviembre",
  "Diciembre",
];
function minimumContractedKw(tariff?: string) {
  const code = String(tariff || "")
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "");
  if (code.startsWith("T3")) return 50;
  if (code.startsWith("T2")) return 10;
  return 0;
}
function powerRate(i: Invoice) {
  return Math.max(
    0,
    ...(i.invoice_lines || [])
      .filter((x) =>
        ["DEM", "DEP"].includes(String(x.concept_code || "").toUpperCase()),
      )
      .map((x) => Number(x.unit_price || 0)),
  );
}
function latestContractedForMonth(history: Invoice[], monthNumber: number) {
  const invoice = [...history]
    .filter(
      (row) =>
        Number(periodOf(row).slice(5, 7)) === monthNumber &&
        contractedBands(row).peak > 0,
    )
    .sort((a, b) => periodOf(b).localeCompare(periodOf(a)))[0];
  return invoice
    ? {
        latestKw: contractedBands(invoice).peak,
        latestPeriod: periodOf(invoice),
      }
    : { latestKw: 0, latestPeriod: "" };
}
const epenPowerQuarters = [
  { label: "Noviembre–Enero", months: [11, 12, 1] },
  { label: "Febrero–Abril", months: [2, 3, 4] },
  { label: "Mayo–Julio", months: [5, 6, 7] },
  { label: "Agosto–Octubre", months: [8, 9, 10] },
];
function buildPowerCurve(history: Invoice[]) {
  const valid = history
    .filter((i) => values(i).demand > 0)
    .sort((a, b) => periodOf(a).localeCompare(periodOf(b)));
  const latestContract = [...valid]
    .reverse()
    .find((i) => contractedBands(i).peak > 0);
  const latestRateInvoice = [...valid].reverse().find((i) => powerRate(i) > 0);
  const currentKw = Number(
    latestContract ? contractedBands(latestContract).peak : 0,
  );
  const tariffCode = String(
    latestContract?.current_tariff_code ||
      latestContract?.meters?.current_tariff_code ||
      "",
  ).toUpperCase();
  const minimumKw = minimumContractedKw(tariffCode);
  const rate = Number(latestRateInvoice ? powerRate(latestRateInvoice) : 0);
  const monthlyRows = powerMonthNames.map((month, idx) => {
    const monthNumber = idx + 1;
    const matches = valid.filter(
      (i) => Number(periodOf(i).slice(5, 7)) === monthNumber,
    );
    const observations = matches.map((i) => ({
      period: periodOf(i),
      demand: values(i).demand,
    }));
    const monthlyProposalKw = observations.length
      ? Math.max(minimumKw, ...observations.map((x) => x.demand))
      : 0;
    return { month, monthNumber, observations, monthlyProposalKw };
  });
  const quarterlyDecision = new Map<
    number,
    {
      proposalKw: number;
      quarterlyProposalKw: number;
      quarter: string;
      method: "trimestral" | "mensual";
      reason: string;
      spreadKw: number;
      extraCost: number;
    }
  >();
  for (const quarter of epenPowerQuarters) {
    const quarterRows = quarter.months.map((month) =>
      monthlyRows.find((row) => row.monthNumber === month)!,
    );
    const complete = quarterRows.every((row) => row.monthlyProposalKw > 0);
    const proposals = quarterRows
      .map((row) => row.monthlyProposalKw)
      .filter((value) => value > 0);
    const quarterlyProposalKw = proposals.length ? Math.max(...proposals) : 0;
    const spreadKw = proposals.length
      ? quarterlyProposalKw - Math.min(...proposals)
      : 0;
    const monthlySaving = quarterRows.reduce(
      (sum, row) =>
        sum + Math.max(0, currentKw - row.monthlyProposalKw) * rate * 1.3,
      0,
    );
    const extraCost = quarterRows.reduce(
      (sum, row) =>
        sum +
        Math.max(0, quarterlyProposalKw - row.monthlyProposalKw) * rate * 1.3,
      0,
    );
    const economicLimit = monthlySaving * 0.1;
    const useQuarter = complete && spreadKw <= 10 && extraCost <= economicLimit;
    const reason = !complete
      ? "Mes a mes: faltan datos en el trimestre"
      : spreadKw > 10
        ? `Mes a mes: diferencia trimestral de ${nf.format(spreadKw)} kW (>10 kW)`
        : extraCost > economicLimit
          ? `Mes a mes: el costo extra supera el 10% del ahorro mensual`
          : "Trimestral EPEN: diferencia ≤10 kW y costo extra ≤10% del ahorro";
    for (const row of quarterRows) {
      quarterlyDecision.set(row.monthNumber, {
        proposalKw: useQuarter ? quarterlyProposalKw : row.monthlyProposalKw,
        quarterlyProposalKw,
        quarter: quarter.label,
        method: useQuarter ? "trimestral" : "mensual",
        reason,
        spreadKw,
        extraCost,
      });
    }
  }
  const rows = monthlyRows.map((row) => {
    const decision = quarterlyDecision.get(row.monthNumber)!;
    const proposalKw = decision.proposalKw;
    const reducibleKw =
      proposalKw > 0 ? Math.max(0, currentKw - proposalKw) : 0;
    const savingNet = reducibleKw * rate;
    const saving = savingNet * 1.3;
    return { ...row, ...decision, proposalKw, reducibleKw, savingNet, saving };
  });
  return {
    currentKw,
    tariffCode,
    minimumKw,
    rate,
    rows,
    annualSaving: rows.reduce((sum, row) => sum + row.saving, 0),
    annualSavingNet: rows.reduce((sum, row) => sum + row.savingNet, 0),
    hasData:
      currentKw > 0 && rate > 0 && rows.some((row) => row.proposalKw > 0),
  };
}
function xmlCell(value: string | number, type: "String" | "Number" = "String") {
  const escaped = String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
  return `<Cell><Data ss:Type="${type}">${escaped}</Data></Cell>`;
}

function TariffSavingTrend({
  rows,
  selectedPeriod,
  onPeriod,
}: {
  rows: {
    billing_period: string;
    monthly_saving: number;
    current_tariff?: string;
    recommended_tariff?: string;
    available?: boolean;
  }[];
  selectedPeriod: string;
  onPeriod: (p: string) => void;
}) {
  const data = useMemo(() => {
    const map = new Map<
      string,
      {
        billing_period: string;
        monthly_saving: number;
        current_tariff?: string;
        recommended_tariff?: string;
        available?: boolean;
      }
    >();
    for (const row of rows) {
      const p = String(row.billing_period || "").slice(0, 7);
      if (p) map.set(p, row);
    }
    return [...map.entries()]
      .sort((a, b) => a[0].localeCompare(b[0]))
      .slice(-24)
      .map(([period, row]) => ({
        period,
        row,
        value: Math.max(0, Number(row.monthly_saving || 0)),
        available: row.available !== false,
      }));
  }, [rows]);

  if (!data.length) {
    return (
      <div className="invoice-tariff-no-data">
        <b>Sin histórico tarifario</b>
        <span>No hay períodos disponibles para este medidor.</span>
      </div>
    );
  }

  const width = 1280,
    height = 330,
    left = 82,
    right = 28,
    top = 25,
    bottom = 52;
  const plotW = width - left - right,
    plotH = height - top - bottom;
  const max =
    Math.max(1, ...data.filter((d) => d.available).map((d) => d.value)) * 1.08;
  const slot = plotW / Math.max(1, data.length),
    bw = Math.max(12, slot * 0.58);

  const axis = (value: number) => {
    if (value >= 1000000)
      return `$ ${(value / 1000000).toLocaleString("es-AR", { maximumFractionDigits: 1 })} M`;
    if (value >= 1000)
      return `$ ${(value / 1000).toLocaleString("es-AR", { maximumFractionDigits: 0 })} mil`;
    return money.format(value);
  };

  return (
    <div className="invoice-analysis-chart-wrap">
      <svg
        viewBox={`0 0 ${width} ${height}`}
        className="invoice-analysis-chart"
      >
        {[0, 0.25, 0.5, 0.75, 1].map((step) => {
          const y = top + plotH * (1 - step);
          return (
            <g key={step}>
              <line x1={left} x2={width - right} y1={y} y2={y} />
              <text x={left - 10} y={y + 4} textAnchor="end">
                {axis(max * step)}
              </text>
            </g>
          );
        })}

        {data.map((d, index) => {
          const x = left + index * slot + (slot - bw) / 2;
          const y = top + plotH - (d.value / max) * plotH;
          const missing = !d.available;
          const barY = missing
            ? top + plotH - 10
            : d.value > 0
              ? y
              : top + plotH - 3;
          const barH = missing ? 10 : Math.max(3, top + plotH - y);

          return (
            <g
              className={`invoice-analysis-bar tariff-saving-bar${missing ? " missing" : ""}${selectedPeriod === d.period ? " selected" : ""}`}
              key={d.period}
              onClick={() => onPeriod(d.period)}
            >
              <rect x={x} y={barY} width={bw} height={barH} rx="5">
                <title>
                  {missing
                    ? `${labelPeriod(d.period)} · Falta cuadro tarifario ${d.row.recommended_tariff || "propuesto"}`
                    : `${labelPeriod(d.period)} · ${d.row.current_tariff || "Actual"} → ${d.row.recommended_tariff || "Propuesta"} · ${money.format(d.value)}`}
                </title>
              </rect>
              {(index % 3 === 0 || index === data.length - 1) && (
                <text x={x + bw / 2} y={height - 22} textAnchor="middle">
                  {labelPeriod(d.period)}
                </text>
              )}
            </g>
          );
        })}
      </svg>

      <div className="invoice-tariff-legend">
        <span>
          <i className="saving" />
          Ahorro valorizado
        </span>
        {data.some((d) => !d.available) && (
          <span>
            <i className="missing" />
            Falta cuadro tarifario para ese mes
          </span>
        )}
      </div>
    </div>
  );
}
function InvoiceTrend({
  rows,
  metric,
  selectedPeriod,
  onPeriod,
  powerLine = "current",
  proposals = [],
}: {
  rows: Invoice[];
  metric: Metric;
  selectedPeriod: string;
  onPeriod: (p: string) => void;
  powerLine?: "current" | "proposal";
  proposals?: Array<{ monthNumber: number; proposalKw: number }>;
}) {
  const data = useMemo(() => {
    const map = new Map<string, Invoice>();
    for (const row of rows) {
      const p = periodOf(row);
      const current = map.get(p);
      if (
        !current ||
        String(row.issue_date || row.id) >
          String(current.issue_date || current.id)
      )
        map.set(p, row);
    }
    return [...map.entries()]
      .sort((a, b) => a[0].localeCompare(b[0]))
      .slice(-24)
      .map(([period, invoice]) => ({
        period,
        invoice,
        value: metricValue(invoice, metric),
        contracted: values(invoice).contracted,
        proposed:
          proposals.find(
            (row) => row.monthNumber === Number(period.slice(5, 7)),
          )?.proposalKw || 0,
        pfUnknownPenalized: values(invoice).pfUnknownPenalized,
        penalized: values(invoice).penalized,
      }));
  }, [rows, metric, proposals]);

  const width = 1280,
    height = 330,
    left = 70,
    right = 28,
    top = 25,
    bottom = 52;
  const plotW = width - left - right,
    plotH = height - top - bottom;
  const max =
    Math.max(
      1,
      ...data.map((d) => d.value),
      ...(metric === "demand"
        ? data.map((d) =>
            powerLine === "proposal" ? d.proposed : d.contracted,
          )
        : []),
    ) * 1.08;
  const slot = plotW / Math.max(1, data.length),
    bw = Math.max(12, slot * 0.58);

  return (
    <div className="invoice-analysis-chart-wrap">
      <svg
        viewBox={`0 0 ${width} ${height}`}
        className="invoice-analysis-chart"
      >
        {[0, 0.25, 0.5, 0.75, 1].map((step) => {
          const y = top + plotH * (1 - step);
          return (
            <g key={step}>
              <line x1={left} x2={width - right} y1={y} y2={y} />
              <text x={left - 10} y={y + 4} textAnchor="end">
                {metric === "pf"
                  ? (max * step).toFixed(2)
                  : nf.format(max * step)}
              </text>
            </g>
          );
        })}

        {data.map((d, index) => {
          const x = left + index * slot + (slot - bw) / 2;
          const graphValue =
            metric === "pf" && d.pfUnknownPenalized ? 0.95 : d.value;
          const y = top + plotH - (graphValue / max) * plotH;
          return (
            <g
              className={`invoice-analysis-bar${metric === "pf" && ((d.value > 0 && d.value < 0.95) || d.pfUnknownPenalized) ? " bad-pf" : ""}${metric === "pf" && d.value >= 0.95 && !d.pfUnknownPenalized ? " good-pf" : ""}${metric === "pf" && d.pfUnknownPenalized ? " pf-unknown-penalty" : ""}${selectedPeriod === d.period ? " selected" : ""}`}
              key={d.period}
              onClick={() => onPeriod(d.period)}
            >
              <rect
                x={x}
                y={y}
                width={bw}
                height={Math.max(2, top + plotH - y)}
                rx="5"
              >
                <title>
                  {metric === "pf" && d.pfUnknownPenalized
                    ? `${labelPeriod(d.period)} · Penalización de factor de potencia · cos φ no informado`
                    : `${labelPeriod(d.period)} · ${fmt(metric, d.value)}`}
                </title>
              </rect>
              {(index % 3 === 0 || index === data.length - 1) && (
                <text x={x + bw / 2} y={height - 22} textAnchor="middle">
                  {labelPeriod(d.period)}
                </text>
              )}
            </g>
          );
        })}

        {metric === "pf" && (
          <g className="invoice-pf-limit">
            <line
              x1={left}
              x2={width - right}
              y1={top + plotH - (0.95 / max) * plotH}
              y2={top + plotH - (0.95 / max) * plotH}
            />
            <text
              x={width - right - 4}
              y={top + plotH - (0.95 / max) * plotH - 7}
              textAnchor="end"
            >
              Límite cos φ 0,95
            </text>
          </g>
        )}

        {metric === "demand" &&
          powerLine === "current" &&
          data.map((d, index) =>
            d.contracted > 0 ? (
              <line
                key={`c-${d.period}`}
                className="invoice-contract-line"
                x1={left + index * slot}
                x2={left + (index + 1) * slot}
                y1={top + plotH - (d.contracted / max) * plotH}
                y2={top + plotH - (d.contracted / max) * plotH}
              />
            ) : null,
          )}

        {metric === "demand" &&
          powerLine === "proposal" &&
          data.map((d, index) =>
            d.proposed > 0 ? (
              <g key={`p-${d.period}`}>
                <line
                  className="invoice-proposal-line"
                  x1={left + index * slot}
                  x2={left + (index + 1) * slot}
                  y1={top + plotH - (d.proposed / max) * plotH}
                  y2={top + plotH - (d.proposed / max) * plotH}
                >
                  <title>{`${labelPeriod(d.period)} · Propuesta ${nf.format(d.proposed)} kW`}</title>
                </line>
                {selectedPeriod === d.period && (
                  <>
                    <circle
                      className="invoice-proposal-marker"
                      cx={left + (index + 0.5) * slot}
                      cy={top + plotH - (d.proposed / max) * plotH}
                      r="5"
                    />
                    <text
                      className="invoice-proposal-label"
                      x={left + (index + 0.5) * slot}
                      y={top + plotH - (d.proposed / max) * plotH - 12}
                      textAnchor="middle"
                    >{`Propuesta ${nf.format(d.proposed)} kW`}</text>
                  </>
                )}
              </g>
            ) : null,
          )}
      </svg>

      {metric === "demand" && (
        <div className="invoice-power-legend">
          {powerLine === "current" ? (
            <span>
              <i className="current" />
              Contratada actual
            </span>
          ) : (
            <span>
              <i className="proposal" />
              Contratada propuesta · mes seleccionado marcado
            </span>
          )}
        </div>
      )}

      {metric === "pf" && (
        <div className="invoice-pf-legend">
          <span>
            <i className="good" />
            Correcto: cos φ ≥ 0,95
          </span>
          <span>
            <i className="bad" />
            Revisar: cos φ &lt; 0,95
          </span>
        </div>
      )}
    </div>
  );
}
export function InvoiceAnalysisPanel({
  invoice,
  history,
  tariffSavings,
  assessment,
  optimization,
  organizationId,
  changeControls = [],
  onChangeControls,
  onClose,
  backLabel = "← Volver a facturas",
  analysisLabel = "ANÁLISIS INDIVIDUAL DE FACTURA",
  allowNameEdit = true,
  simpleTariffHistory,
  hideLocationEditor = false,
}: {
  invoice: Invoice;
  history: Invoice[];
  tariffSavings: TariffSaving[];
  assessment?: TariffAssessment;
  optimization?: EpenOptimizationMeter;
  organizationId?: string;
  changeControls?: MeterChangeControl[];
  onChangeControls?: () => Promise<void> | void;
  onClose: () => void;
  backLabel?: string;
  analysisLabel?: string;
  allowNameEdit?: boolean;
  simpleTariffHistory?: Array<{
    billing_period: string;
    tariff_code?: string | null;
    invoice_number?: string | null;
    total_amount?: number | null;
  }>;
  hideLocationEditor?: boolean;
}) {
  const [metric, setMetric] = useState<Metric>("demand");
  const [controlPageOpen, setControlPageOpen] = useState(false);
  const [powerLine, setPowerLine] = useState<"current" | "proposal">("current");
  const [advancedTariffHistory, setAdvancedTariffHistory] =
    useState<AdvancedTariffHistoryResponse | null>(null);
  const [advancedTariffReady, setAdvancedTariffReady] = useState(false);
  const [editingName, setEditingName] = useState(false);
  const [nameDraft, setNameDraft] = useState(
    invoice.meters?.service_name || invoice.meters?.sites?.name || "",
  );
  const [displayName, setDisplayName] = useState(
    invoice.meters?.service_name ||
      invoice.meters?.sites?.name ||
      "Servicio sin nombre",
  );
  const [nameBusy, setNameBusy] = useState(false);
  const [nameError, setNameError] = useState("");
  const [selectedPeriod, setSelectedPeriod] = useState(periodOf(invoice));
  const selected =
    history.find((i) => periodOf(i) === selectedPeriod) || invoice;
  const v = values(selected);
  const contractedBand = contractedBands(selected);
  const isT3 = String(selected.current_tariff_code || "")
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "")
    .startsWith("T3");
  const currentVoltage = String(
    selected.voltage_level || selected.meters?.voltage_level || "",
  ).toUpperCase();
  const powerLines = (selected.invoice_lines || []).filter(
    (x) => x.concept_code === "DEM" || x.concept_code === "DEP",
  );
  const selectedRate = Math.max(
    0,
    ...powerLines.map((x) => Number(x.unit_price || 0)),
  );
  const excess = Math.max(0, v.contracted - v.demand);
  const powerCurve = useMemo(() => buildPowerCurve(history), [history]);
  const selectedMonthNumber = Number(periodOf(selected).slice(5, 7));
  const selectedPowerProposal = powerCurve.rows.find(
    (row) => row.monthNumber === selectedMonthNumber,
  );
  const currentPower = powerCurve.currentKw || v.contracted;
  const proposedPower = Number(selectedPowerProposal?.proposalKw || 0);
  const rate = powerCurve.rate || selectedRate;
  const powerSaving = Number(selectedPowerProposal?.saving || 0);
  const annualPowerSaving = powerCurve.annualSaving;
  const reactiveSaving =
    (selected.invoice_lines || [])
      .filter((x) => x.concept_code === "COS")
      .reduce((s, x) => s + Math.max(0, Number(x.net_amount || 0)), 0) * 1.3;
  const selectedAssessment =
    assessment &&
    (!assessment.billing_period ||
      String(assessment.billing_period).slice(0, 7) === periodOf(selected))
      ? assessment
      : undefined;
  const advancedTariffDefinitive =
    advancedTariffReady && advancedTariffHistory !== null;
  const assessmentTariffCandidate =
    !advancedTariffDefinitive &&
    Boolean(
      selectedAssessment?.current_tariff &&
      selectedAssessment.current_tariff !==
        selectedAssessment.recommended_tariff,
    );
  const legacyTariffSaving = Math.max(
    Number(
      tariffSavings.find(
        (x) =>
          x.meter_id === selected.meter_id &&
          String(x.billing_period).slice(0, 7) === periodOf(selected),
      )?.monthly_saving_with_vat || 0,
    ),
    Number(selectedAssessment?.tariff_monthly_saving || 0),
  );
  const advancedTariffPoint = advancedTariffHistory?.points.find(
    (x) => String(x.billing_period).slice(0, 7) === periodOf(selected),
  );
  const advancedTariffSaving =
    advancedTariffPoint?.available === false
      ? 0
      : Number(advancedTariffPoint?.monthly_saving || 0);
  const tariffSaving = advancedTariffDefinitive
    ? advancedTariffSaving
    : legacyTariffSaving;
  const tariffSavingSource =
    advancedTariffSaving > 0
      ? "T4"
      : !advancedTariffDefinitive && legacyTariffSaving > 0
        ? "legacy"
        : assessmentTariffCandidate
          ? "candidate"
          : "none";
  const tariffCandidateLabel = assessmentTariffCandidate
    ? `${selectedAssessment?.current_tariff} → ${selectedAssessment?.recommended_tariff}`
    : "";
  const totalSaving = powerSaving + reactiveSaving + tariffSaving;
  const annualTotalSaving =
    annualPowerSaving + reactiveSaving * 12 + tariffSaving * 12;
  const m = selected.meters || invoice.meters;
  const sorted = [...history].sort((a, b) =>
    periodOf(a).localeCompare(periodOf(b)),
  );
  useEffect(() => {
    let cancelled = false;
    async function loadTariffHistory() {
      setAdvancedTariffHistory(null);
      setAdvancedTariffReady(false);
      try {
        const { data } = await supabase.auth.getSession();
        if (!data.session || !selected.meter_id) {
          if (!cancelled) setAdvancedTariffReady(true);
          return;
        }
        const response = await fetch(
          `${API}/api/meters/${selected.meter_id}/tariff-saving-history`,
          {
            cache: "no-store",
            headers: { Authorization: `Bearer ${data.session.access_token}` },
          },
        );
        if (!response.ok) throw new Error(await response.text());
        const json = (await response.json()) as AdvancedTariffHistoryResponse;
        if (!cancelled) setAdvancedTariffHistory(json);
      } catch {
        if (!cancelled) setAdvancedTariffHistory(null);
      } finally {
        if (!cancelled) setAdvancedTariffReady(true);
      }
    }
    loadTariffHistory();
    return () => {
      cancelled = true;
    };
  }, [selected.meter_id]);
  function downloadPowerCurveExcel() {
    if (!powerCurve.hasData) return;
    const header = [
      "Mes",
      "Histórico comparado",
      "Trimestre EPEN",
      "Método aplicado",
      "Criterio",
      "Tarifa",
      "Mínimo EPEN (kW)",
      "Potencia actual (kW)",
      "Propuesta mensual (kW)",
      "Máximo trimestral (kW)",
      "Propuesta aplicada (kW)",
      "Diferencia trimestre (kW)",
      "Costo extra trimestral ($)",
      "Reducción (kW)",
      "Tarifa potencia ($/kW)",
      "Ahorro neto ($)",
      "Ahorro +30% ($)",
    ];
    const rows = powerCurve.rows.map((row) => {
      const historical =
        row.observations
          .map((x) => `${x.period.slice(0, 4)}: ${nf.format(x.demand)} kW`)
          .join(" | ") || "Sin datos";
      return [
        row.month,
        historical,
        row.quarter,
        row.method,
        row.reason,
        powerCurve.tariffCode || "S/D",
        powerCurve.minimumKw,
        powerCurve.currentKw,
        row.monthlyProposalKw,
        row.quarterlyProposalKw,
        row.proposalKw || 0,
        row.spreadKw,
        row.extraCost,
        row.reducibleKw,
        powerCurve.rate,
        row.savingNet,
        row.saving,
      ];
    });
    const sheetRows = [
      `<Row>${header.map((v) => xmlCell(v)).join("")}</Row>`,
      ...rows.map(
        (row) =>
          `<Row>${row.map((v, index) => xmlCell(v, index >= 6 ? "Number" : "String")).join("")}</Row>`,
      ),
      `<Row>${xmlCell("TOTAL ANUAL")}${Array.from({ length: 14 }, () => xmlCell("")).join("")}${xmlCell(powerCurve.annualSavingNet, "Number")}${xmlCell(powerCurve.annualSaving, "Number")}</Row>`,
    ].join("");
    const xml = `<?xml version="1.0"?><?mso-application progid="Excel.Sheet"?><Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:x="urn:schemas-microsoft-com:office:excel" xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet"><Worksheet ss:Name="Curva potencia"><Table>${sheetRows}</Table></Worksheet></Workbook>`;
    const blob = new Blob(["\ufeff", xml], {
      type: "application/vnd.ms-excel;charset=utf-8",
    });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    const code = (m?.tracking_code || m?.meter_number || "suministro").replace(
      /[^A-Za-z0-9_-]+/g,
      "_",
    );
    link.href = url;
    link.download = `Propuesta_Potencia_${code}.xls`;
    document.body.appendChild(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(url);
  }
  async function saveMeterName() {
    const clean = nameDraft.trim();
    if (clean.length < 2) {
      setNameError("Ingresá un nombre válido.");
      return;
    }
    setNameBusy(true);
    setNameError("");
    try {
      const { data } = await supabase.auth.getSession();
      if (!data.session) throw new Error("Sesión vencida");
      const response = await fetch(
        `${API}/api/meters/${selected.meter_id}/name`,
        {
          method: "PUT",
          headers: {
            Authorization: `Bearer ${data.session.access_token}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ service_name: clean }),
        },
      );
      const body = await response.text();
      if (!response.ok) {
        let message = body;
        try {
          message = JSON.parse(body).detail || body;
        } catch {}
        throw new Error(message);
      }
      setDisplayName(clean);
      if (m) m.service_name = clean;
      setEditingName(false);
    } catch (error) {
      setNameError(
        error instanceof Error ? error.message : "No se pudo guardar el nombre",
      );
    } finally {
      setNameBusy(false);
    }
  }
  const controlPowerProposals = powerCurve.rows.map((row) => ({
    ...latestContractedForMonth(history, row.monthNumber),
    month: row.month,
    monthNumber: row.monthNumber,
    proposalKw: row.proposalKw,
    method: row.method,
    quarter: row.quarter,
  }));
  if (controlPageOpen && organizationId) {
    return (
      <div className="invoice-analysis-backdrop">
        <div className="invoice-analysis-page improvement-route-page">
          <MeterChangeControlPanel
            organizationId={organizationId}
            meterId={selected.meter_id}
            selectedPeriod={periodOf(selected)}
            history={history}
            controls={changeControls.filter(
              (row) => row.meter_id === selected.meter_id,
            )}
            powerProposals={controlPowerProposals}
            currentTariff={selected.current_tariff_code}
            recommendedTariff={
              advancedTariffHistory?.recommended_tariff ||
              selectedAssessment?.recommended_tariff
            }
            meterName={displayName}
            meterReference={`${m?.tracking_code || "Sin ID"} · Medidor ${m?.meter_number || "S/D"} · Suministro ${m?.supply_number || "S/D"}`}
            displayMode="page"
            onClosePage={() => setControlPageOpen(false)}
            onSaved={() => onChangeControls?.()}
          />
        </div>
      </div>
    );
  }
  return (
    <div className="invoice-analysis-backdrop">
      <div className="invoice-analysis-page">
        <div className="invoice-analysis-top">
          <div>
            <button className="invoice-analysis-back" onClick={onClose}>
              {backLabel}
            </button>
            <small>{analysisLabel}</small>
            <div className="invoice-name-row">
              {editingName ? (
                <div className="invoice-name-editor">
                  <input
                    value={nameDraft}
                    onChange={(e) => setNameDraft(e.target.value)}
                    autoFocus
                  />
                  <button
                    className="save"
                    onClick={saveMeterName}
                    disabled={nameBusy}
                  >
                    {nameBusy ? "Guardando…" : "Guardar"}
                  </button>
                  <button
                    className="cancel"
                    onClick={() => {
                      setEditingName(false);
                      setNameError("");
                      setNameDraft(displayName);
                    }}
                  >
                    Cancelar
                  </button>
                </div>
              ) : (
                <>
                  <h2>{displayName}</h2>
                  {allowNameEdit && (
                    <button
                      className="invoice-edit-name"
                      onClick={() => {
                        setNameDraft(displayName);
                        setEditingName(true);
                      }}
                    >
                      ✎ Editar nombre
                    </button>
                  )}
                </>
              )}
            </div>
            {nameError && <div className="invoice-name-error">{nameError}</div>}
            <p>
              {m?.tracking_code} · Medidor {m?.meter_number || "S/D"} ·
              Suministro {m?.supply_number || "S/D"}
            </p>
          </div>
          <div className="invoice-analysis-period">
            <span>Factura seleccionada</span>
            <b>{periodOf(selected)}</b>
            <small>{selected.invoice_number || "S/D"}</small>
          </div>
        </div>

        {organizationId && (
          <MeterChangeControlPanel
            organizationId={organizationId}
            meterId={selected.meter_id}
            selectedPeriod={periodOf(selected)}
            history={history}
            controls={changeControls.filter(
              (row) => row.meter_id === selected.meter_id,
            )}
            powerProposals={controlPowerProposals}
            currentTariff={selected.current_tariff_code}
            recommendedTariff={
              advancedTariffHistory?.recommended_tariff ||
              selectedAssessment?.recommended_tariff
            }
            meterName={displayName}
            meterReference={`${m?.tracking_code || "Sin ID"} · Medidor ${m?.meter_number || "S/D"}`}
            onOpenPage={() => setControlPageOpen(true)}
            onSaved={() => onChangeControls?.()}
          />
        )}

        {powerCurve.hasData && (
          <div className={styles.powerCurveSummary}>
            <div className={styles.powerMetric}>
              <span>Potencia actual</span>
              <b>{nf.format(currentPower)} kW</b>
              <small>última contratación vigente</small>
            </div>
            <div className={styles.powerMetric}>
              <span>
                Propuesta · {powerMonthNames[selectedMonthNumber - 1]}
              </span>
              <b>
                {proposedPower > 0 ? `${nf.format(proposedPower)} kW` : "S/D"}
              </b>
              <small>
                {selectedPowerProposal?.method === "trimestral"
                  ? `trimestre EPEN ${selectedPowerProposal.quarter}`
                  : selectedPowerProposal?.reason ||
                    "máximo del mismo mes entre años"}
              </small>
            </div>
            <div className={`${styles.powerMetric} ${styles.savingMetric}`}>
              <span>Ahorro</span>
              <b>{money.format(powerSaving)}</b>
              <small>{money.format(annualPowerSaving)} anual según curva</small>
            </div>
            <button
              type="button"
              className={styles.excelButton}
              onClick={downloadPowerCurveExcel}
            >
              <span>↓</span> Descargar Excel
            </button>
          </div>
        )}

        <div className="invoice-analysis-kpis">
          <article>
            <span>Consumo</span>
            <b>{nf.format(v.kwh)} kWh</b>
            <small>energía activa del período</small>
          </article>
          <article>
            <span>Demanda máxima</span>
            <b>{nf.format(v.demand)} kW</b>
            <small>registrada en factura</small>
          </article>
          {isT3 ? (
            <>
              <article className={contractedBand.peak > 0 ? "warn" : ""}>
                <span>Potencia contratada punta</span>
                <b>
                  {contractedBand.peak > 0
                    ? `${nf.format(contractedBand.peak)} kW`
                    : "S/D"}
                </b>
                <small>capacidad convenida en horas punta</small>
              </article>
              <article className={contractedBand.offPeak > 0 ? "warn" : ""}>
                <span>Potencia contratada fuera punta</span>
                <b>
                  {contractedBand.offPeak > 0
                    ? `${nf.format(contractedBand.offPeak)} kW`
                    : "S/D"}
                </b>
                <small>capacidad convenida en resto + valle</small>
              </article>
            </>
          ) : (
            <article className={excess > 0 ? "warn" : ""}>
              <span>Potencia contratada</span>
              <b>{nf.format(v.contracted)} kW</b>
              <small>
                {excess > 0
                  ? `${nf.format(excess)} kW por encima de la demanda`
                  : "sin sobrante detectado"}
              </small>
            </article>
          )}
          <article className={v.pf > 0 && v.pf < 0.95 ? "warn" : ""}>
            <span>Factor de potencia</span>
            <b>{v.pf ? v.pf.toFixed(3) : "S/D"}</b>
            <small>
              {v.surcharge > 0
                ? `recargo ${v.surcharge}%`
                : v.penalized
                  ? "penalización de factor de potencia facturada"
                  : "sin recargo detectado"}
            </small>
          </article>
          <article>
            <span>Importe factura</span>
            <b>{money.format(Number(selected.total_amount || 0))}</b>
            <small>importe total</small>
          </article>
          <article className="saving">
            <span>Ahorro potencial</span>
            <b>{money.format(totalSaving)}</b>
            <small>{money.format(annualTotalSaving)} anual según curva</small>
          </article>
        </div>

        <section className="invoice-analysis-panel">
          <div className="invoice-analysis-chart-head">
            <div>
              <h3>Evolución histórica del medidor</h3>
              <p>Hasta 24 meses. Tocá una barra para abrir esa factura.</p>
            </div>
            <div className="invoice-analysis-controls">
              <div className="invoice-analysis-metrics">
                <button
                  className={metric === "demand" ? "active" : ""}
                  onClick={() => setMetric("demand")}
                >
                  Demanda
                </button>
                <button
                  className={metric === "kwh" ? "active" : ""}
                  onClick={() => setMetric("kwh")}
                >
                  Consumo
                </button>
                <button
                  className={metric === "pf" ? "active" : ""}
                  onClick={() => setMetric("pf")}
                >
                  Factor de potencia
                </button>
                <button
                  className={metric === "tariff" ? "active" : ""}
                  onClick={() => setMetric("tariff")}
                >
                  Tarifaria
                </button>
                <button
                  className={metric === "amount" ? "active" : ""}
                  onClick={() => setMetric("amount")}
                >
                  Importe
                </button>
              </div>
              {metric === "demand" && (
                <div
                  className="invoice-power-mode"
                  role="group"
                  aria-label="Línea de potencia contratada"
                >
                  <button
                    className={powerLine === "current" ? "active" : ""}
                    onClick={() => setPowerLine("current")}
                  >
                    Actual
                  </button>
                  <button
                    className={
                      powerLine === "proposal" ? "active proposal" : ""
                    }
                    onClick={() => setPowerLine("proposal")}
                  >
                    Propuesta
                  </button>
                </div>
              )}
            </div>
          </div>

          {metric === "tariff" && simpleTariffHistory?.length ? (
            <div className="invoice-tariff-detail-view">
              <div className="invoice-tariff-period-detail">
                <div className="invoice-tariff-period-head">
                  <div>
                    <span>HISTÓRICO TARIFARIO</span>
                    <h4>
                      {periodOf(selected)} ·{" "}
                      {selected.current_tariff_code || "S/D"}
                    </h4>
                    <p>
                      Tarifa informada en las facturas disponibles del
                      suministro.
                    </p>
                  </div>
                  <div className="saving">
                    <span>TARIFA ACTUAL</span>
                    <b>{selected.current_tariff_code || "S/D"}</b>
                    <small>período seleccionado</small>
                  </div>
                </div>
                <div className="invoice-analysis-table-wrap">
                  <table className="invoice-analysis-table">
                    <thead>
                      <tr>
                        <th>Período</th>
                        <th>Tarifa</th>
                        <th>Factura</th>
                        <th>Importe</th>
                      </tr>
                    </thead>
                    <tbody>
                      {[...simpleTariffHistory]
                        .sort((a, b) =>
                          b.billing_period.localeCompare(a.billing_period),
                        )
                        .map((row, index) => (
                          <tr key={`${row.billing_period}-${index}`}>
                            <td>
                              <b>{row.billing_period}</b>
                            </td>
                            <td>
                              <b>{row.tariff_code || "S/D"}</b>
                            </td>
                            <td>{row.invoice_number || "S/D"}</td>
                            <td>
                              <b>
                                {row.total_amount == null
                                  ? "—"
                                  : money.format(Number(row.total_amount || 0))}
                              </b>
                            </td>
                          </tr>
                        ))}
                    </tbody>
                  </table>
                </div>
              </div>
            </div>
          ) : metric === "tariff" ? (
            (() => {
              const legacyRows = tariffSavings
                .filter((x) => x.meter_id === selected.meter_id)
                .map((x) => ({
                  billing_period: String(x.billing_period).slice(0, 7),
                  monthly_saving: Number(x.monthly_saving_with_vat || 0),
                  current_tariff: x.current_tariff,
                  recommended_tariff: x.recommended_tariff,
                  available: true,
                }));

              const advancedRows = (advancedTariffHistory?.points || []).map(
                (x) => ({
                  billing_period: String(x.billing_period).slice(0, 7),
                  monthly_saving: Number(x.monthly_saving || 0),
                  current_tariff: x.current_tariff,
                  recommended_tariff: x.recommended_tariff,
                  available: x.available !== false,
                }),
              );

              const assessmentRows = selectedAssessment
                ? [
                    {
                      billing_period: String(
                        selectedAssessment.billing_period || periodOf(selected),
                      ).slice(0, 7),
                      monthly_saving: Number(
                        selectedAssessment.tariff_monthly_saving || 0,
                      ),
                      current_tariff:
                        selectedAssessment.current_tariff ||
                        selected.current_tariff_code,
                      recommended_tariff: selectedAssessment.recommended_tariff,
                      available:
                        selectedAssessment.tariff_simulation_available ||
                        !assessmentTariffCandidate,
                    },
                  ]
                : [];
              const invoiceTariffRows = history.map((x) => ({
                billing_period: periodOf(x),
                monthly_saving: 0,
                current_tariff: x.current_tariff_code || "S/D",
                recommended_tariff: x.current_tariff_code || "S/D",
                available: true,
              }));
              const chartRows = advancedTariffDefinitive
                ? advancedRows.length
                  ? advancedRows
                  : invoiceTariffRows
                : legacyRows.length
                  ? legacyRows
                  : assessmentRows.length
                    ? assessmentRows
                    : invoiceTariffRows;
              const detail = advancedTariffHistory?.points.find(
                (x) =>
                  String(x.billing_period).slice(0, 7) === periodOf(selected),
              );
              const legacyDetail = !advancedTariffDefinitive
                ? tariffSavings.find(
                    (x) =>
                      x.meter_id === selected.meter_id &&
                      String(x.billing_period).slice(0, 7) ===
                        periodOf(selected),
                  )
                : undefined;
              const fallbackAssessment = !advancedTariffDefinitive
                ? selectedAssessment
                : undefined;
              const tariffCurrent =
                detail?.current_tariff ||
                legacyDetail?.current_tariff ||
                fallbackAssessment?.current_tariff ||
                selected.current_tariff_code ||
                "S/D";
              const tariffRecommended =
                detail?.recommended_tariff ||
                legacyDetail?.recommended_tariff ||
                fallbackAssessment?.recommended_tariff ||
                tariffCurrent;
              const periodTariffSaving = detail
                ? Number(detail.monthly_saving || 0)
                : Math.max(
                    Number(legacyDetail?.monthly_saving_with_vat || 0),
                    Number(fallbackAssessment?.tariff_monthly_saving || 0),
                  );
              const periodTariffAnnual = detail
                ? Number(detail.annualized_saving || 0)
                : periodTariffSaving * 12;
              const tariffChange = tariffCurrent !== tariffRecommended;
              const tariffAvailable = detail
                ? detail.available !== false
                : fallbackAssessment
                  ? fallbackAssessment.tariff_simulation_available ||
                    !tariffChange
                  : true;

              return (
                <div className="invoice-tariff-detail-view">
                  <TariffSavingTrend
                    rows={chartRows}
                    selectedPeriod={periodOf(selected)}
                    onPeriod={setSelectedPeriod}
                  />

                  <div className="invoice-tariff-period-detail">
                    <div className="invoice-tariff-period-head">
                      <div>
                        <span>DETALLE DEL PERÍODO</span>
                        <h4>
                          {periodOf(selected)} · {tariffCurrent}
                          {tariffChange
                            ? ` → ${tariffRecommended}`
                            : " · encuadramiento sin cambio"}
                        </h4>
                        <p>
                          {!tariffAvailable
                            ? `Se detectó el posible cambio a ${tariffRecommended}, pero falta el cuadro oficial para valorizarlo.`
                            : tariffChange
                              ? "Comparación entre la tarifa actual y la categoría propuesta por la regla de demanda máxima promedio de 15 minutos."
                              : "La tarifa informada no presenta un cambio de categoría según los datos disponibles."}
                        </p>
                      </div>
                      <div className={!tariffAvailable ? "missing" : "saving"}>
                        <span>AHORRO TARIFARIO</span>
                        <b>
                          {!tariffAvailable
                            ? "POSIBLE AHORRO"
                            : money.format(periodTariffSaving)}
                        </b>
                        <small>
                          {!tariffAvailable
                            ? "Falta cuadro tarifario"
                            : `${money.format(periodTariffAnnual)} anualizado`}
                        </small>
                      </div>
                    </div>

                    {!detail && tariffChange && (
                      <div className="invoice-tariff-missing-detail">
                        <b>
                          Regla detectada: demanda máxima{" "}
                          {nf.format(
                            Number(
                              selectedAssessment?.maximum_demand_kw || v.demand,
                            ),
                          )}{" "}
                          kW
                        </b>
                        <span>
                          {tariffCurrent} → {tariffRecommended}. Al estar por
                          debajo de 10 kW promedio en 15 minutos, se muestra
                          como posible ahorro tarifario sujeto a validación de
                          EPEN.
                        </span>
                      </div>
                    )}

                    {detail?.available !== false && detail && (
                      <>
                        <div className="invoice-tariff-summary-grid">
                          <article>
                            <span>
                              {advancedTariffHistory?.mode === "downshift"
                                ? "TARIFA BASE COMPARABLE"
                                : "TARIFA ACTUAL REAL"}
                            </span>
                            <b>
                              {money.format(Number(detail.current_cost || 0))}
                            </b>
                            <small>
                              {advancedTariffHistory?.mode === "downshift"
                                ? "T2 simulada al mínimo reglamentario de 10 kW"
                                : "Subtotal real tomado de invoice_lines"}
                            </small>
                          </article>
                          <article>
                            <span>TARIFA PROPUESTA SIMULADA</span>
                            <b>
                              {money.format(
                                Number(detail.recommended_cost || 0),
                              )}
                            </b>
                            <small>
                              {detail.recommended_tariff} ·{" "}
                              {nf.format(Number(detail.capacity_kw || 0))} kW
                            </small>
                          </article>
                          <article>
                            <span>CUADRO OFICIAL APLICADO</span>
                            <b>{detail.resolution_number || "S/D"}</b>
                            <small>
                              Facturación{" "}
                              {String(
                                detail.billing_month || periodOf(selected),
                              ).slice(0, 7)}{" "}
                              · Consumo{" "}
                              {String(detail.consumption_month || "S/D").slice(
                                0,
                                7,
                              )}
                            </small>
                          </article>
                        </div>

                        <div className="invoice-tariff-comparison-grid">
                          <div>
                            <h5>
                              {detail.current_tariff}
                              {advancedTariffHistory?.mode === "downshift"
                                ? " simulada"
                                : " real facturada"}
                            </h5>
                            <table>
                              <thead>
                                <tr>
                                  <th>Concepto</th>
                                  <th>Cantidad</th>
                                  <th>Precio</th>
                                  <th>Importe</th>
                                </tr>
                              </thead>
                              <tbody>
                                {(detail.current_components || []).map(
                                  (row, index) => (
                                    <tr key={`${row.code}-${index}`}>
                                      <td>
                                        <b>{row.code}</b>
                                        <small>{row.description || ""}</small>
                                      </td>
                                      <td>
                                        {row.quantity == null
                                          ? "—"
                                          : dec.format(Number(row.quantity))}
                                      </td>
                                      <td>
                                        {row.unit_price == null
                                          ? "—"
                                          : money.format(
                                              Number(row.unit_price),
                                            )}
                                      </td>
                                      <td>
                                        <b>
                                          {money.format(
                                            Number(row.net_amount || 0),
                                          )}
                                        </b>
                                      </td>
                                    </tr>
                                  ),
                                )}
                              </tbody>
                            </table>
                          </div>

                          <div>
                            <h5>{detail.recommended_tariff} simulada</h5>
                            <table>
                              <thead>
                                <tr>
                                  <th>Concepto</th>
                                  <th>Cantidad</th>
                                  <th>Precio oficial</th>
                                  <th>Importe</th>
                                </tr>
                              </thead>
                              <tbody>
                                {(detail.proposed_components || []).map(
                                  (row, index) => (
                                    <tr key={`${row.code}-${index}`}>
                                      <td>
                                        <b>{row.code}</b>
                                        <small>{row.description || ""}</small>
                                      </td>
                                      <td>
                                        {row.quantity == null
                                          ? "—"
                                          : dec.format(Number(row.quantity))}
                                      </td>
                                      <td>
                                        {row.unit_price == null
                                          ? "—"
                                          : money.format(
                                              Number(row.unit_price),
                                            )}
                                      </td>
                                      <td>
                                        <b>
                                          {money.format(
                                            Number(row.net_amount || 0),
                                          )}
                                        </b>
                                      </td>
                                    </tr>
                                  ),
                                )}
                              </tbody>
                            </table>
                          </div>
                        </div>

                        <div className="invoice-tariff-formula">
                          <span>FÓRMULA DEL AHORRO</span>
                          <b>
                            {money.format(Number(detail.current_cost || 0))} −{" "}
                            {money.format(Number(detail.recommended_cost || 0))}{" "}
                            = {money.format(Number(detail.monthly_saving || 0))}
                          </b>
                          <small>
                            {advancedTariffHistory?.mode === "downshift"
                              ? "T2 a 10 kW − T1 propuesta; no duplica el ahorro por potencia"
                              : "Actual real facturada − tarifa propuesta simulada"}{" "}
                            · antes de impuestos
                            {advancedTariffHistory?.mode === "mt"
                              ? " · BT→MT sujeto a factibilidad EPEN"
                              : ""}
                          </small>
                        </div>
                      </>
                    )}

                    {detail?.available === false && (
                      <div className="invoice-tariff-missing-detail">
                        <b>
                          Falta el cuadro oficial {detail.recommended_tariff}{" "}
                          para {periodOf(selected)}
                        </b>
                        <span>
                          La factura actual sí está cargada. No se extrapola el
                          precio de otro mes: el ahorro queda sin valorizar
                          hasta incorporar el cuadro tarifario oficial
                          correspondiente.
                        </span>
                      </div>
                    )}
                  </div>
                </div>
              );
            })()
          ) : (
            <InvoiceTrend
              rows={sorted}
              metric={metric}
              selectedPeriod={periodOf(selected)}
              onPeriod={setSelectedPeriod}
              powerLine={powerLine}
              proposals={powerCurve.rows}
            />
          )}
        </section>
        <div className="invoice-analysis-grid">
          <section className="invoice-analysis-panel">
            <h3>Detalle completo de la factura</h3>
            <div className="invoice-analysis-details">
              <div>
                <span>Período</span>
                <b>{periodOf(selected)}</b>
              </div>
              <div>
                <span>Número de factura</span>
                <b>{selected.invoice_number || "S/D"}</b>
              </div>
              <div>
                <span>Emisión</span>
                <b>{selected.issue_date || "S/D"}</b>
              </div>
              <div>
                <span>Vencimiento</span>
                <b>{selected.due_date || "S/D"}</b>
              </div>
              <div>
                <span>Tarifa</span>
                <b>
                  {selected.current_tariff_code || "S/D"} ·{" "}
                  {selected.voltage_level || m?.voltage_level || "S/D"}
                </b>
              </div>
              <div>
                <span>Importe</span>
                <b>{money.format(Number(selected.total_amount || 0))}</b>
              </div>
              <div>
                <span>IVA</span>
                <b>{money.format(Number(selected.vat_amount || 0))}</b>
              </div>
              <div>
                <span>Deuda anterior</span>
                <b>
                  {money.format(Number(selected.previous_debt_amount || 0))}
                </b>
              </div>
              <div>
                <span>Reactiva</span>
                <b>{nf.format(v.kvarh)} kvarh</b>
              </div>
              <div>
                <span>Dirección</span>
                <b>{m?.sites?.address || "S/D"}</b>
              </div>
            </div>
          </section>

          <section className="invoice-analysis-panel">
            <h3>Oportunidades de ahorro de esta factura</h3>
            <div className="invoice-analysis-saving-list">
              <div>
                <span>Potencia contratada</span>
                <b>{money.format(powerSaving)}</b>
                <small>
                  {proposedPower > 0 && currentPower > proposedPower
                    ? `${nf.format(currentPower - proposedPower)} kW reducibles · curva mensual histórica + 30%`
                    : "Sin ahorro detectado para este mes"}
                </small>
              </div>
              <div>
                <span>Factor de potencia</span>
                <b>{money.format(reactiveSaving)}</b>
                <small>
                  {reactiveSaving > 0
                    ? "Penalización reactiva evitable + IVA 30%"
                    : "Sin penalización valorizada"}
                </small>
              </div>
              <div>
                <span>Encuadramiento tarifario</span>
                <b>
                  {tariffSaving > 0
                    ? money.format(tariffSaving)
                    : assessmentTariffCandidate
                      ? "POSIBLE AHORRO"
                      : "$ 0"}
                </b>
                <small>
                  {tariffSavingSource === "T4"
                    ? `${advancedTariffPoint?.current_tariff || "Actual"} → ${advancedTariffPoint?.recommended_tariff || "T4"} · simulación antes de impuestos`
                    : tariffSavingSource === "legacy"
                      ? `${tariffCandidateLabel || "Cambio tarifario"} · ahorro mensual simulado con IVA`
                      : tariffSavingSource === "candidate"
                        ? `${tariffCandidateLabel} por demanda máxima menor a 10 kW · falta valorizar con el cuadro oficial`
                        : advancedTariffPoint?.available === false
                          ? "Falta cuadro tarifario oficial para este período"
                          : "Sin ahorro tarifario valorizado"}
                </small>
              </div>
              <div className="total">
                <span>Total mensual</span>
                <b>{money.format(totalSaving)}</b>
                <small>
                  {money.format(annualTotalSaving)} / año según curva
                </small>
              </div>
            </div>
          </section>
        </div>
        <section className="invoice-analysis-panel">
          <h3>Conceptos facturados</h3>
          <div className="invoice-analysis-table-wrap">
            <table className="invoice-analysis-table">
              <thead>
                <tr>
                  <th>Código</th>
                  <th>Descripción</th>
                  <th>Cantidad</th>
                  <th>Precio unitario</th>
                  <th>Importe neto</th>
                </tr>
              </thead>
              <tbody>
                {(selected.invoice_lines || []).map((line, index) => (
                  <tr key={`${line.concept_code || "x"}-${index}`}>
                    <td>{line.concept_code || "—"}</td>
                    <td>{line.description || "Sin descripción"}</td>
                    <td>{dec.format(Number(line.quantity || 0))}</td>
                    <td>{money.format(Number(line.unit_price || 0))}</td>
                    <td>
                      <b>{money.format(Number(line.net_amount || 0))}</b>
                    </td>
                  </tr>
                ))}
                {!(selected.invoice_lines || []).length && (
                  <tr>
                    <td colSpan={5}>
                      No hay conceptos discriminados en esta factura.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </section>

        <section className="invoice-analysis-panel">
          <h3>Mediciones registradas</h3>
          <div className="invoice-analysis-table-wrap">
            <table className="invoice-analysis-table">
              <thead>
                <tr>
                  <th>Tipo</th>
                  <th>Medidor</th>
                  <th>kWh</th>
                  <th>kvarh</th>
                  <th>Demanda kW</th>
                  <th>FP</th>
                  <th>Recargo</th>
                </tr>
              </thead>
              <tbody>
                {(selected.invoice_measurements || []).map((row, index) => (
                  <tr key={index}>
                    <td>{row.measurement_type || "—"}</td>
                    <td>{row.meter_number || m?.meter_number || "—"}</td>
                    <td>{nf.format(Number(row.active_energy_kwh || 0))}</td>
                    <td>{nf.format(Number(row.reactive_energy_kvarh || 0))}</td>
                    <td>
                      {nf.format(
                        Number(
                          row.demand_kw || row.registered_demand_peak_kw || 0,
                        ),
                      )}
                    </td>
                    <td>
                      {row.power_factor
                        ? Number(row.power_factor).toFixed(3)
                        : "—"}
                    </td>
                    <td>{Number(row.reactive_surcharge_percent || 0)}%</td>
                  </tr>
                ))}
                {!(selected.invoice_measurements || []).length && (
                  <tr>
                    <td colSpan={7}>
                      No hay mediciones discriminadas en esta factura.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </section>
        {!hideLocationEditor && (
          <MeterLocationEditor
            meterId={selected.meter_id}
            label={`${m?.service_name || m?.sites?.name || "Servicio"} · Medidor ${m?.meter_number || "S/D"}`}
          />
        )}
      </div>
    </div>
  );
}
