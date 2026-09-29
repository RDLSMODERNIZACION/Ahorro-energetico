"use client";

import { createContext, useContext, useEffect, useRef, useState, type ReactNode } from "react";
import { supabase } from "./lib/supabase";
import styles from "./meter-observations.module.css";

type Observation = { meter_id: string; observation: string; updated_at: string };
type State = {
  rows: Record<string, Observation>; loading: boolean; error: string;
  save: (meterId: string, text: string) => Promise<void>;
};
const Context = createContext<State | null>(null);

export function MeterObservationsProvider({ children }: { children: ReactNode }) {
  const [rows, setRows] = useState<Record<string, Observation>>({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const generation = useRef(0);
  useEffect(() => {
    let disposed = false;
    async function load() {
      const request = ++generation.current;
      setLoading(true); setError("");
      try {
        const { data: { session } } = await supabase.auth.getSession();
        const next: Record<string, Observation> = {};
        if (session) {
          for (let start = 0; ; start += 1000) {
            const { data, error } = await supabase.from("meter_observations")
              .select("meter_id,observation,updated_at").order("meter_id").range(start, start + 999);
            if (error) throw error;
            for (const row of data || []) next[row.meter_id] = row;
            if ((data || []).length < 1000) break;
          }
        }
        if (!disposed && request === generation.current) setRows(next);
      } catch { if (!disposed && request === generation.current) setError("No se pudieron cargar las observaciones. Actualizá la página para reintentar."); }
      finally { if (!disposed && request === generation.current) setLoading(false); }
    }
    void load();
    const { data: { subscription } } = supabase.auth.onAuthStateChange((event) => {
      if (event === "SIGNED_OUT") { ++generation.current; setRows({}); setLoading(false); }
      if (event === "SIGNED_IN") setTimeout(() => { if (!disposed) void load(); }, 0);
    });
    return () => { disposed = true; ++generation.current; subscription.unsubscribe(); };
  }, []);
  async function save(meterId: string, text: string) {
    const observation = text.trim();
    if (observation.length > 2000) throw new Error("La observación admite hasta 2000 caracteres.");
    const request = generation.current;
    if (observation) {
      const { data, error } = await supabase.from("meter_observations").upsert({
        meter_id: meterId, observation, updated_at: new Date().toISOString(),
      }, { onConflict: "meter_id" }).select("meter_id,observation,updated_at").single();
      if (error) throw new Error("No se pudo guardar la observación. Revisá tu conexión y tus permisos.");
      if (request === generation.current) setRows(current => ({ ...current, [meterId]: data }));
    } else {
      const { error } = await supabase.from("meter_observations").delete().eq("meter_id", meterId).select("meter_id");
      if (error) throw new Error("No se pudo quitar la observación.");
      if (request === generation.current) setRows(current => { const next = { ...current }; delete next[meterId]; return next; });
    }
  }
  return <Context.Provider value={{ rows, loading, error, save }}>{children}</Context.Provider>;
}

export function ObservationBadge({ meterId }: { meterId: string }) {
  const context = useContext(Context);
  const note = context?.rows[meterId]?.observation;
  return note ? <span className={styles.badge} title={note}><strong>Observado</strong><span>{note}</span></span> : null;
}

export function MeterObservationEditor({ meterId }: { meterId: string }) {
  return <Editor key={meterId} meterId={meterId} />;
}
function Editor({ meterId }: { meterId: string }) {
  const context = useContext(Context)!;
  const saved = context.rows[meterId]?.observation || "";
  const [draft, setDraft] = useState(saved);
  const [editable, setEditable] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [failed, setFailed] = useState(false);
  useEffect(() => { setDraft(saved); }, [saved]);
  useEffect(() => {
    let cancelled = false;
    async function check() {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) return;
      const { data: meter } = await supabase.from("meters").select("organization_id").eq("id", meterId).single();
      if (!meter) return;
      const { data: member } = await supabase.from("organization_members").select("role")
        .eq("organization_id", meter.organization_id).eq("user_id", session.user.id).single();
      if (!cancelled) setEditable(["admin", "analyst"].includes(member?.role || ""));
    }
    void check();
    return () => { cancelled = true; };
  }, [meterId]);
  async function submit(text: string) {
    setBusy(true); setMessage(""); setFailed(false);
    try { await context.save(meterId, text); setDraft(text.trim()); setMessage(text.trim() ? "Observación guardada." : "Observación quitada."); }
    catch (error) { setFailed(true); setMessage(error instanceof Error ? error.message : "No se pudo guardar."); }
    finally { setBusy(false); }
  }
  return <section className={styles.editor} aria-label="Observaciones del medidor">
    <div className={styles.heading}><h3>Observaciones</h3><ObservationBadge meterId={meterId} /></div>
    <p>Nota general del medidor, visible en todos los períodos. Por ejemplo: Sin factura de septiembre.</p>
    {context.loading ? <p>Cargando observaciones…</p> : context.error ? <p role="alert">{context.error}</p> : editable ? <>
      <label htmlFor={`observation-${meterId}`}>Observación</label>
      <textarea id={`observation-${meterId}`} value={draft} maxLength={2000} rows={3} disabled={busy}
        placeholder="Ej.: Sin factura de septiembre" onChange={event => { setDraft(event.target.value); setMessage(""); }} />
      <div className={styles.actions}>
        <button type="button" disabled={busy || draft.trim() === saved} onClick={() => void submit(draft)}>{busy ? "Guardando…" : "Guardar observación"}</button>
        {saved && <button type="button" className={styles.remove} disabled={busy} onClick={() => void submit("")}>Quitar observación</button>}
        <small>{draft.length}/2000</small>
      </div>
    </> : <p>{saved || "Sin observaciones."}</p>}
    {message && <p role={failed ? "alert" : "status"}>{message}</p>}
  </section>;
}
