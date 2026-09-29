"use client";
import { useEffect, useRef, useState } from "react";

type Detail = { file: string; invoice_number?: string; period?: string; status: string; message?: string };
type Report = { imported: number; duplicates?: number; rejected?: number; total?: number; processed?: number; details?: Detail[]; error?: string };
type Response = { background?: boolean; batch_id?: string; status?: string; result?: Report; imported?: number; rejected?: number; duplicate?: boolean; errors?: { error: string; row?: number }[] };

export function InvoiceImporter({ orgId, userId, token, apiBase, disabled }: { orgId: string; userId: string; token: string; apiBase: string; disabled?: boolean }) {
  const input = useRef<HTMLInputElement>(null);
  const tokenRef = useRef(token);
  tokenRef.current = token;
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [job, setJob] = useState<string | null>(null);
  const [report, setReport] = useState<Report | null>(null);
  const [error, setError] = useState("");
  const key = `energy.import.${userId}.${orgId}`;

  useEffect(() => {
    setReport(null); setError(""); setBusy(false);
    const saved = localStorage.getItem(key);
    setJob(saved);
    if (saved) { setBusy(true); setOpen(true); }
  }, [key]);

  useEffect(() => {
    if (!job) return;
    let cancelled = false;
    let timer: ReturnType<typeof setTimeout>;
    const started = Date.now();
    async function poll() {
      try {
        const response = await fetch(`${apiBase}/api/imports/invoices/${job}`, { cache: "no-store", headers: { Authorization: `Bearer ${tokenRef.current}` } });
        if (!response.ok) throw new Error("No se pudo consultar el progreso. Volvé a abrir la página para retomarlo.");
        const data: Response = await response.json();
        if (cancelled) return;
        if (data.result) setReport(data.result);
        if (["completed", "partial", "failed"].includes(data.status || "")) {
          localStorage.removeItem(key); setJob(null); setBusy(false); return;
        }
        if (Date.now() - started > 15 * 60 * 1000) throw new Error("La carga tarda más de lo esperado. Podés volver a subir el archivo: las facturas guardadas no se duplicarán.");
        timer = setTimeout(poll, 2000);
      } catch (e) {
        if (!cancelled) { setError(e instanceof Error ? e.message : "No se pudo consultar la carga"); setBusy(false); }
      }
    }
    void poll();
    return () => { cancelled = true; clearTimeout(timer); };
  }, [job, key, apiBase]);

  async function upload(file?: File) {
    if (!file) return;
    setOpen(true); setError(""); setReport(null); setJob(null);
    // Stay below the hosting proxy's 4.5 MB request limit, including multipart overhead.
    if (file.size > 4 * 1024 * 1024) { setError("Máximo 4 MB por carga. Dividí el ZIP/RAR en lotes más pequeños."); return; }
    setBusy(true);
    try {
      const form = new FormData(); form.append("organization_id", orgId); form.append("file", file);
      const response = await fetch(`${apiBase}/api/imports/invoices`, { method: "POST", headers: { Authorization: `Bearer ${tokenRef.current}` }, body: form });
      const data = await response.json();
      if (!response.ok) throw new Error(typeof data.detail === "string" ? data.detail : "No se pudo importar el archivo");
      if (data.background && data.batch_id) { localStorage.setItem(key, data.batch_id); setJob(data.batch_id); }
      else {
        setReport({ imported: data.imported || 0, duplicates: data.duplicate ? 1 : 0, rejected: data.rejected || 0, details: (data.errors || []).map((e: {row?: number; error: string}) => ({ file: `Fila ${e.row || ""}`, status: "rejected", message: e.error })) });
        setBusy(false);
      }
    } catch (e) { setError(e instanceof Error ? e.message : "No se pudo importar"); setBusy(false); }
    finally { if (input.current) input.current.value = ""; }
  }

  const labels: Record<string, string> = { imported: "Incorporada", duplicate: "Ya existente", conflict: "Revisar diferencia", rejected: "No incorporada" };
  return <>
    <button onClick={() => { if (busy) setOpen(true); else input.current?.click(); }} disabled={disabled}> {busy ? "Ver progreso de carga" : "＋ Cargar facturas"}</button>
    <input ref={input} type="file" accept=".pdf,.zip,.rar,.csv" hidden onChange={e => void upload(e.target.files?.[0])} />
    {open && <div className="invoice-import-overlay"><section className="invoice-import-dialog" role="dialog" aria-modal="true" aria-labelledby="import-heading">
      <header><h2 id="import-heading">Carga de facturas</h2><button aria-label="Cerrar resumen" onClick={() => setOpen(false)}>Cerrar</button></header>
      <p>PDF originales de EPEN, ZIP/RAR con PDF o CSV. Máximo 4 MB por carga. Los PDF escaneados y los suministros sin registrar se informan para revisión.</p>
      {busy && <p role="status">Procesando {report?.processed || 0}{report?.total ? ` de ${report.total}` : ""} documentos… Podés cerrar este resumen; la carga continúa.</p>}
      {(error || report?.error) && <p role="alert">{error || report?.error}</p>}
      {report && <><div className="invoice-import-totals"><strong>{report.imported} incorporadas</strong><span>{report.duplicates || 0} ya existentes</span><span>{report.rejected || 0} para revisar</span></div>
        <div className="invoice-import-table"><table><thead><tr><th>Archivo / factura</th><th>Período</th><th>Resultado</th></tr></thead><tbody>{report.details?.map((d, i) => <tr key={i}><td>{d.file}<small>{d.invoice_number}</small></td><td>{d.period?.slice(0, 7) || "—"}</td><td>{labels[d.status] || d.status}<small>{d.message}</small></td></tr>)}</tbody></table></div></>}
      {!busy && <footer><button onClick={() => input.current?.click()}>Cargar otro archivo</button><button onClick={() => window.location.reload()}>Actualizar panel</button></footer>}
    </section></div>}
  </>;
}
