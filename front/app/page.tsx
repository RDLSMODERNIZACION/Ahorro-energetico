"use client";
import { ChangeEvent, DragEvent, useMemo, useRef, useState } from "react";
import JSZip from "jszip";
type Row = {
  meter: string;
  site: string;
  period: string;
  kwh: number;
  kw: number;
  contracted: number;
  amount: number;
  reactive: number;
};
type Marker = { meter: string; site: string; x: number; y: number };
const money = new Intl.NumberFormat("es-AR", {
  style: "currency",
  currency: "ARS",
  maximumFractionDigits: 0,
});
const num = new Intl.NumberFormat("es-AR", { maximumFractionDigits: 0 });
const demo: Row[] = [
  {
    meter: "71470/01",
    site: "Planta Oeste 1",
    period: "2026-03",
    kwh: 91200,
    kw: 312,
    contracted: 480,
    amount: 19344000,
    reactive: 18,
  },
  {
    meter: "71470/01",
    site: "Planta Oeste 1",
    period: "2026-04",
    kwh: 97800,
    kw: 328,
    contracted: 480,
    amount: 20733600,
    reactive: 20,
  },
  {
    meter: "133349/01",
    site: "Planta Oeste 2",
    period: "2026-03",
    kwh: 62400,
    kw: 221,
    contracted: 300,
    amount: 13228800,
    reactive: 9,
  },
  {
    meter: "133349/01",
    site: "Planta Oeste 2",
    period: "2026-04",
    kwh: 65900,
    kw: 235,
    contracted: 300,
    amount: 13970800,
    reactive: 11,
  },
  {
    meter: "107619/02",
    site: "Planta Este 1",
    period: "2026-03",
    kwh: 54200,
    kw: 146,
    contracted: 181,
    amount: 11490400,
    reactive: 26,
  },
  {
    meter: "107619/02",
    site: "Planta Este 1",
    period: "2026-04",
    kwh: 58800,
    kw: 158,
    contracted: 181,
    amount: 12465600,
    reactive: 29,
  },
  {
    meter: "136379/01",
    site: "Palacio Municipal",
    period: "2026-03",
    kwh: 18400,
    kw: 88,
    contracted: 160,
    amount: 3900800,
    reactive: 5,
  },
  {
    meter: "136379/01",
    site: "Palacio Municipal",
    period: "2026-04",
    kwh: 16900,
    kw: 82,
    contracted: 160,
    amount: 3582800,
    reactive: 4,
  },
  {
    meter: "136380/01",
    site: "Cargadero",
    period: "2026-03",
    kwh: 23100,
    kw: 118,
    contracted: 130,
    amount: 4897200,
    reactive: 14,
  },
  {
    meter: "136380/01",
    site: "Cargadero",
    period: "2026-04",
    kwh: 24700,
    kw: 126,
    contracted: 130,
    amount: 5236400,
    reactive: 17,
  },
];
const markerDemo: Marker[] = [
  { meter: "71470/01", site: "Planta Oeste 1", x: 19, y: 31 },
  { meter: "133349/01", site: "Planta Oeste 2", x: 28, y: 65 },
  { meter: "107619/02", site: "Planta Este 1", x: 75, y: 34 },
  { meter: "136379/01", site: "Palacio Municipal", x: 50, y: 53 },
  { meter: "136380/01", site: "Cargadero", x: 64, y: 72 },
];
function parseCSV(text: string) {
  const ls = text
    .replace(/^\uFEFF/, "")
    .split(/\r?\n/)
    .filter(Boolean);
  if (ls.length < 2) return [];
  const d =
    (ls[0].match(/;/g)?.length || 0) > (ls[0].match(/,/g)?.length || 0)
      ? ";"
      : ",";
  const h = ls[0].split(d).map((x) =>
    x
      .trim()
      .toLowerCase()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, ""),
  );
  const ix = (...n: string[]) =>
    h.findIndex((x) => n.some((y) => x.includes(y)));
  const n = (v: string) =>
    Number(
      (v || "0")
        .replace(/\s/g, "")
        .replace(/\.(?=\d{3}(?:\D|$))/g, "")
        .replace(",", "."),
    ) || 0;
  return ls
    .slice(1)
    .map((l) => {
      const c = l.split(d).map((x) => x.trim().replace(/^"|"$/g, ""));
      return {
        meter: c[ix("medidor", "suministro", "nis")] || "Sin identificar",
        site:
          c[ix("ubicacion", "sitio", "dependencia", "lugar")] ||
          "Sin ubicación",
        period: c[ix("periodo", "fecha", "mes")] || "S/P",
        kwh: n(c[ix("kwh", "energia activa", "consumo")]),
        kw: n(c[ix("demanda", "potencia maxima", "kw")]),
        contracted: n(c[ix("contratada", "potencia contratada")]),
        amount: n(c[ix("importe", "total", "monto")]),
        reactive: n(c[ix("reactiva", "penalizacion", "recargo")]),
      };
    })
    .filter((x) => x.kwh || x.amount || x.kw);
}
export default function Home() {
  const [rows, setRows] = useState(demo),
    [tab, setTab] = useState<"analysis" | "projection" | "map">("analysis"),
    [fileName, setFileName] = useState("Demo municipal · 10 facturas"),
    [drag, setDrag] = useState(false),
    [toast, setToast] = useState("");
  const [markers, setMarkers] = useState(markerDemo),
    [selected, setSelected] = useState("71470/01");
  const [actions, setActions] = useState([
    {
      id: "power",
      name: "Ajustar potencia contratada",
      on: true,
      pct: 8,
      cost: 0,
    },
    {
      id: "reactive",
      name: "Corregir energía reactiva",
      on: true,
      pct: 5,
      cost: 8200000,
    },
    {
      id: "schedule",
      name: "Optimizar horarios de bombeo",
      on: true,
      pct: 7,
      cost: 2800000,
    },
    {
      id: "led",
      name: "Eficiencia operativa y LED",
      on: false,
      pct: 11,
      cost: 28000000,
    },
  ]);
  const input = useRef<HTMLInputElement>(null);
  const sites = useMemo(() => {
    const m = new Map<string, Row[]>();
    rows.forEach((r) => m.set(r.meter, [...(m.get(r.meter) || []), r]));
    return [...m]
      .map(([meter, a]) => {
        const amount = a.reduce((s, r) => s + r.amount, 0),
          kwh = a.reduce((s, r) => s + r.kwh, 0),
          maxKw = Math.max(...a.map((r) => r.kw)),
          contracted = Math.max(...a.map((r) => r.contracted)),
          reactive = a.reduce((s, r) => s + r.reactive, 0) / a.length,
          gap = contracted ? Math.max(0, (contracted - maxKw) / contracted) : 0,
          opp = Math.min(24, Math.round(gap * 18 + (reactive > 15 ? 6 : 1)));
        return {
          meter,
          site: a[0].site,
          amount,
          kwh,
          maxKw,
          contracted,
          reactive,
          opp,
          saving: (amount * opp) / 100,
        };
      })
      .sort((a, b) => b.saving - a.saving);
  }, [rows]);
  const total = rows.reduce((s, r) => s + r.amount, 0),
    months = Math.max(1, new Set(rows.map((r) => r.period)).size),
    annual = (total / months) * 12,
    pct = actions.filter((a) => a.on).reduce((s, a) => s + a.pct, 0),
    saving = (annual * pct) / 100,
    investment = actions.filter((a) => a.on).reduce((s, a) => s + a.cost, 0);
  async function load(file?: File) {
    if (!file) return;
    try {
      let data: Row[] = [];
      if (file.name.toLowerCase().endsWith(".zip")) {
        const z = await JSZip.loadAsync(file);
        for (const f of Object.values(z.files).filter(
          (x) => !x.dir && x.name.toLowerCase().endsWith(".csv"),
        ))
          data.push(...parseCSV(await f.async("text")));
      } else data = parseCSV(await file.text());
      if (!data.length) throw Error("No se encontraron filas válidas");
      setRows(data);
      setFileName(`${file.name} · ${data.length} facturas`);
      const unique = [...new Map(data.map((r) => [r.meter, r.site])).entries()];
      setMarkers(
        unique.map(([meter, site], i) => ({
          meter,
          site,
          x: 15 + ((i * 17) % 72),
          y: 18 + ((i * 23) % 65),
        })),
      );
      setSelected(unique[0]?.[0] || "");
      setToast("Archivo analizado correctamente");
    } catch (e) {
      setToast(e instanceof Error ? e.message : "No se pudo leer el archivo");
    }
    setTimeout(() => setToast(""), 3000);
  }
  function drop(e: DragEvent) {
    e.preventDefault();
    setDrag(false);
    load(e.dataTransfer.files[0]);
  }
  function move(e: React.PointerEvent<HTMLDivElement>, meter: string) {
    const b = e.currentTarget.parentElement!.getBoundingClientRect();
    const mm = (v: PointerEvent) =>
      setMarkers((x) =>
        x.map((m) =>
          m.meter === meter
            ? {
                ...m,
                x: Math.max(
                  3,
                  Math.min(97, ((v.clientX - b.left) / b.width) * 100),
                ),
                y: Math.max(
                  4,
                  Math.min(96, ((v.clientY - b.top) / b.height) * 100),
                ),
              }
            : m,
        ),
      );
    const up = () => {
      window.removeEventListener("pointermove", mm);
      window.removeEventListener("pointerup", up);
      setToast("Posición guardada en este dispositivo");
      setTimeout(() => setToast(""), 1800);
    };
    window.addEventListener("pointermove", mm);
    window.addEventListener("pointerup", up);
  }
  return (
    <main className="shell">
      <aside className="side">
        <div className="brand">
            <span>M</span>
          <div>
              <b>GESTIÓN</b>
              <small>ENERGÉTICA MUNICIPAL</small>
          </div>
        </div>
        <nav>
          <button
            className={tab === "analysis" ? "active" : ""}
            onClick={() => setTab("analysis")}
          >
            ⌁ <span>Análisis</span>
          </button>
          <button
            className={tab === "projection" ? "active" : ""}
            onClick={() => setTab("projection")}
          >
            ↗ <span>Proyección</span>
          </button>
          <button
            className={tab === "map" ? "active" : ""}
            onClick={() => setTab("map")}
          >
            ⌖ <span>Mapa de medidores</span>
          </button>
        </nav>
        <div className="privacy">
          ● Datos procesados localmente
          <small>Las facturas no salen del equipo</small>
        </div>
      </aside>
      <section className="work">
        <header>
          <div>
            <p>MUNICIPALIDAD DE RINCÓN DE LOS SAUCES</p>
            <h1>
              {tab === "analysis"
                ? "Inteligencia energética"
                : tab === "projection"
                  ? "Proyección de ahorro"
                  : "Mapa de suministros"}
            </h1>
          </div>
          <div className="head-actions">
            <span>{fileName}</span>
            <button onClick={() => input.current?.click()}>
              ＋ Cargar ZIP / CSV
            </button>
            <input
              ref={input}
              hidden
              type="file"
              accept=".zip,.csv"
              onChange={(e: ChangeEvent<HTMLInputElement>) =>
                load(e.target.files?.[0])
              }
            />
          </div>
        </header>
        {tab === "analysis" && (
          <>
            <div
              className={`drop ${drag ? "drag" : ""}`}
              onClick={() => input.current?.click()}
              onDragOver={(e) => {
                e.preventDefault();
                setDrag(true);
              }}
              onDragLeave={() => setDrag(false)}
              onDrop={drop}
            >
              <i>⇧</i>
              <div>
                <b>Arrastrá aquí el ZIP de facturación</b>
                <span>Detectamos automáticamente los CSV y sus columnas</span>
              </div>
              <em>medidor · período · kWh · demanda · contratada · importe</em>
            </div>
            <div className="kpis">
              <article>
                <span>Gasto analizado</span>
                <strong>{money.format(total)}</strong>
                <small>
                  {months} períodos · {rows.length} facturas
                </small>
              </article>
              <article>
                <span>Consumo total</span>
                <strong>
                  {num.format(rows.reduce((s, r) => s + r.kwh, 0))} <i>kWh</i>
                </strong>
                <small>{sites.length} suministros activos</small>
              </article>
              <article className="green">
                <span>Ahorro potencial detectado</span>
                <strong>
                  {money.format(sites.reduce((s, r) => s + r.saving, 0))}
                </strong>
                <small>sobre el período analizado</small>
              </article>
              <article>
                <span>Oportunidades</span>
                <strong>{sites.filter((s) => s.opp > 6).length}</strong>
                <small>
                  {sites.filter((s) => s.opp > 12).length} de prioridad alta
                </small>
              </article>
            </div>
            <div className="analysis-grid">
              <section className="panel">
                <Title
                  title="Ranking de oportunidades"
                  sub="Ordenado por impacto económico estimado"
                  action={() => setTab("projection")}
                />
                <div className="table">
                  <table>
                    <thead>
                      <tr>
                        <th>Suministro</th>
                        <th>Consumo</th>
                        <th>Demanda / Contratada</th>
                        <th>Diagnóstico</th>
                        <th>Ahorro estimado</th>
                      </tr>
                    </thead>
                    <tbody>
                      {sites.map((s, i) => (
                        <tr key={s.meter}>
                          <td>
                            <div className="supply">
                              <i>{i + 1}</i>
                              <div>
                                <b>{s.site}</b>
                                <small>{s.meter}</small>
                              </div>
                            </div>
                          </td>
                          <td>
                            <b>{num.format(s.kwh)} kWh</b>
                            <small>{money.format(s.amount)}</small>
                          </td>
                          <td>
                            <b>
                              {s.maxKw} / {s.contracted} kW
                            </b>
                            <div className="bar">
                              <i
                                style={{
                                  width: `${Math.min(100, (s.maxKw / s.contracted) * 100 || 0)}%`,
                                }}
                              />
                            </div>
                          </td>
                          <td>
                            <span
                              className={`tag ${s.opp > 12 ? "high" : s.opp > 6 ? "mid" : "low"}`}
                            >
                              {s.opp > 12
                                ? "Alta"
                                : s.opp > 6
                                  ? "Media"
                                  : "Baja"}
                            </span>
                            <small>
                              {s.reactive > 15
                                ? "Reactiva elevada"
                                : "Revisar potencia"}
                            </small>
                          </td>
                          <td>
                            <strong className="save">
                              {money.format(s.saving)}
                            </strong>
                            <small>{s.opp}% estimado</small>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </section>
              <aside className="panel findings">
                <Title title="Hallazgos clave" sub="Acciones recomendadas" />
                {sites.slice(0, 3).map((s, i) => (
                  <div className="finding" key={s.meter}>
                    <i>{i === 0 ? "⚡" : i === 1 ? "◔" : "↘"}</i>
                    <div>
                      <b>
                        {i === 0
                          ? "Potencia sobredimensionada"
                          : i === 1
                            ? "Energía reactiva"
                            : "Consumo fuera de patrón"}
                      </b>
                      <p>
                        {s.site} presenta una oportunidad estimada del {s.opp}%.
                      </p>
                      <button onClick={() => setTab("projection")}>
                        Evaluar impacto
                      </button>
                    </div>
                  </div>
                ))}
              </aside>
            </div>
          </>
        )}
        {tab === "projection" && (
          <div className="projection">
            <section className="panel scenario">
              <Title
                title="Escenario de medidas"
                sub="Activá acciones y ajustá el porcentaje esperado"
              />
              {actions.map((a) => (
                <div className="action" key={a.id}>
                  <label>
                    <input
                      type="checkbox"
                      checked={a.on}
                      onChange={() =>
                        setActions((x) =>
                          x.map((v) =>
                            v.id === a.id ? { ...v, on: !v.on } : v,
                          ),
                        )
                      }
                    />
                    <i />
                  </label>
                  <div>
                    <b>{a.name}</b>
                    <small>
                      Inversión:{" "}
                      {a.cost ? money.format(a.cost) : "Sin inversión"}
                    </small>
                  </div>
                  <input
                    type="range"
                    min="0"
                    max="25"
                    value={a.pct}
                    onChange={(e) =>
                      setActions((x) =>
                        x.map((v) =>
                          v.id === a.id ? { ...v, pct: +e.target.value } : v,
                        ),
                      )
                    }
                  />
                  <strong>{a.pct}%</strong>
                </div>
              ))}
            </section>
            <aside className="result">
              <p>RESULTADO ANUAL PROYECTADO</p>
              <strong>{money.format(saving)}</strong>
              <span>ahorro anual</span>
              <div className="gauge">
                <i style={{ width: `${Math.min(100, pct * 2.5)}%` }} />
              </div>
              <div className="result-grid">
                <span>
                  Ahorro a 5 años<b>{money.format(saving * 5 - investment)}</b>
                </span>
                <span>
                  Inversión inicial<b>{money.format(investment)}</b>
                </span>
              </div>
              <div className="payback">
                <span>Retorno estimado</span>
                <b>
                  {investment ? ((investment / saving) * 12).toFixed(1) : 0}{" "}
                  meses
                </b>
              </div>
              <button onClick={() => window.print()}>
                Generar informe ejecutivo
              </button>
            </aside>
            <section className="panel chartbox">
              <Title
                title="Gasto actual vs. optimizado"
                sub="Proyección acumulada a cinco años"
              />
              <div className="chart">
                {[1, 2, 3, 4, 5].map((y) => (
                  <div key={y}>
                    <section>
                      <i style={{ height: `${y * 18}%` }} />
                      <b style={{ height: `${y * 18 * (1 - pct / 100)}%` }} />
                    </section>
                    <span>Año {y}</span>
                  </div>
                ))}
              </div>
              <div className="legend">
                <span>■ Gasto actual</span>
                <span>■ Con medidas</span>
              </div>
            </section>
          </div>
        )}
        {tab === "map" && (
          <div className="map-layout">
            <section className="panel map-panel">
              <div className="map-head">
                <div>
                  <h2>Ubicación de medidores</h2>
                  <p>Arrastrá cada punto hasta su posición real</p>
                </div>
                <span>↔ Modo edición activo</span>
              </div>
              <div className="map">
                <div className="river" />
                <i className="route r1">RUTA PROVINCIAL 6</i>
                <i className="route r2">AV. 20 DE DICIEMBRE</i>
                <b className="zone west">OESTE</b>
                <b className="zone center">CENTRO</b>
                <b className="zone east">ESTE</b>
                {markers.map((m) => (
                  <div
                    key={m.meter}
                    className={`marker ${selected === m.meter ? "selected" : ""}`}
                    style={{ left: `${m.x}%`, top: `${m.y}%` }}
                    onPointerDown={(e) => move(e, m.meter)}
                    onClick={() => setSelected(m.meter)}
                  >
                    <i>⚡</i>
                    <label>
                      {m.site}
                      <small>{m.meter}</small>
                    </label>
                  </div>
                ))}
              </div>
            </section>
            <aside className="panel meter-list">
              <Title
                title="Suministros"
                sub={`${markers.length} posicionados`}
              />
              {markers.map((m) => {
                const s = sites.find((x) => x.meter === m.meter);
                return (
                  <button
                    className={selected === m.meter ? "active" : ""}
                    key={m.meter}
                    onClick={() => setSelected(m.meter)}
                  >
                    <i>●</i>
                    <div>
                      <b>{m.site}</b>
                      <small>{m.meter}</small>
                    </div>
                    <em>{s ? `${s.opp}% potencial` : "Sin datos"}</em>
                  </button>
                );
              })}
              <p>
                Las posiciones quedan guardadas localmente en esta versión.
                Luego se pueden sincronizar con Supabase.
              </p>
            </aside>
          </div>
        )}
      </section>
      {toast && <div className="toast">✓ {toast}</div>}
    </main>
  );
}
function Title({
  title,
  sub,
  action,
}: {
  title: string;
  sub: string;
  action?: () => void;
}) {
  return (
    <div className="panel-title">
      <div>
        <h2>{title}</h2>
        <p>{sub}</p>
      </div>
      {action && <button onClick={action}>Simular medidas →</button>}
    </div>
  );
}
