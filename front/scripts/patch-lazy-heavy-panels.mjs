import { readFileSync, writeFileSync } from "node:fs";

const path = new URL("../app/invoice-analysis-panel.tsx", import.meta.url);
let source = readFileSync(path, "utf8");
const marker = "// LAZY_HEAVY_PANELS_V1";
if (source.includes(marker)) process.exit(0);

const stateNeedle = '  const [powerLine, setPowerLine] = useState<"current" | "proposal">("current");';
if (!source.includes(stateNeedle)) throw new Error("state block not found");
source = source.replace(
  stateNeedle,
  stateNeedle + '\n  // LAZY_HEAVY_PANELS_V1\n  const [documentsOpen, setDocumentsOpen] = useState(false);\n  const [locationOpen, setLocationOpen] = useState(false);',
);

const effectNeedle = '    async function loadTariffHistory() {\n      setAdvancedTariffReady(false);';
if (!source.includes(effectNeedle)) throw new Error("tariff effect not found");
source = source.replace(
  effectNeedle,
  '    async function loadTariffHistory() {\n      if (metric !== "tariff" && !controlPageOpen) {\n        if (!cancelled) setAdvancedTariffReady(false);\n        return;\n      }\n      setAdvancedTariffReady(false);',
);
source = source.replace(
  '  }, [selected.meter_id]);',
  '  }, [selected.meter_id, metric, controlPageOpen]);',
);

const docsNeedle = `        {organizationId && <MeterDocuments
          organizationId={organizationId}
          meterId={selected.meter_id}
          selected={selected}
          history={history}
          controls={changeControls}
        />}`;
if (!source.includes(docsNeedle)) throw new Error("documents block not found");
source = source.replace(docsNeedle, `        {organizationId && (documentsOpen ? (
          <MeterDocuments
            organizationId={organizationId}
            meterId={selected.meter_id}
            selected={selected}
            history={history}
            controls={changeControls}
          />
        ) : (
          <section className="invoice-analysis-panel">
            <div style={{display:"flex",justifyContent:"space-between",alignItems:"center",gap:12,flexWrap:"wrap"}}>
              <div><h3>Archivos del medidor</h3><small>Se cargan solo cuando los necesitás.</small></div>
              <button type="button" onClick={() => setDocumentsOpen(true)}>Ver archivos</button>
            </div>
          </section>
        ))}`);

const locationNeedle = `        {!hideLocationEditor && (
          <MeterLocationEditor
            meterId={selected.meter_id}
            label={\`${m?.service_name || m?.sites?.name || "Servicio"} · Medidor ${m?.meter_number || "S/D"}\`}
          />
        )}`;
if (!source.includes(locationNeedle)) throw new Error("location block not found");
source = source.replace(locationNeedle, `        {!hideLocationEditor && (locationOpen ? (
          <MeterLocationEditor
            meterId={selected.meter_id}
            label={\`${m?.service_name || m?.sites?.name || "Servicio"} · Medidor ${m?.meter_number || "S/D"}\`}
          />
        ) : (
          <section className="invoice-analysis-panel">
            <div style={{display:"flex",justifyContent:"space-between",alignItems:"center",gap:12,flexWrap:"wrap"}}>
              <div><h3>Ubicación del medidor</h3><small>Mapa y coordenadas se cargan bajo demanda.</small></div>
              <button type="button" onClick={() => setLocationOpen(true)}>Abrir ubicación</button>
            </div>
          </section>
        ))}`);

writeFileSync(path, source, "utf8");
console.log("Applied lazy loading for tariff details, documents and location.");
