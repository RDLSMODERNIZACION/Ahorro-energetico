"use client";

import { FormEvent, useEffect, useState } from "react";
import type { Session } from "@supabase/supabase-js";
import { supabase } from "../lib/supabase";

type Organization = {
  id: string;
  name: string;
  tax_id?: string | null;
  member_count?: number;
};
type Member = {
  id: string;
  user_id: string;
  role: "admin" | "analyst" | "viewer";
  email?: string;
  created_at?: string;
};

async function request<T>(path: string, session: Session, init?: RequestInit): Promise<T> {
  const response = await fetch(`/api/backend/api${path}`, {
    ...init,
    cache: "no-store",
    headers: {
      Authorization: `Bearer ${session.access_token}`,
      "Content-Type": "application/json",
      ...(init?.headers || {}),
    },
  });
  if (!response.ok) throw new Error((await response.text()) || `Error ${response.status}`);
  if (response.status === 204) return undefined as T;
  return response.json();
}

export default function AdminPage() {
  const [session, setSession] = useState<Session | null>(null);
  const [authorized, setAuthorized] = useState<boolean | null>(null);
  const [organizations, setOrganizations] = useState<Organization[]>([]);
  const [selectedId, setSelectedId] = useState("");
  const [members, setMembers] = useState<Member[]>([]);
  const [name, setName] = useState("");
  const [taxId, setTaxId] = useState("");
  const [memberEmail, setMemberEmail] = useState("");
  const [memberRole, setMemberRole] = useState<Member["role"]>("viewer");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");

  async function loadOrganizations(active: Session) {
    const rows = await request<Organization[]>("/admin/organizations", active);
    setOrganizations(rows);
    if (!selectedId && rows.length) setSelectedId(rows[0].id);
  }

  async function loadMembers(active: Session, organizationId: string) {
    if (!organizationId) return setMembers([]);
    const rows = await request<Member[]>(`/admin/organizations/${organizationId}/members`, active);
    setMembers(rows);
  }

  useEffect(() => {
    supabase.auth.getSession().then(async ({ data }) => {
      const active = data.session;
      if (!active) {
        window.location.href = "/";
        return;
      }
      setSession(active);
      try {
        const me = await request<{ is_superadmin: boolean }>("/admin/me", active);
        setAuthorized(me.is_superadmin);
        if (me.is_superadmin) await loadOrganizations(active);
      } catch (error) {
        setAuthorized(false);
        setMessage(error instanceof Error ? error.message : "No se pudo validar el acceso");
      }
    });
  }, []);

  useEffect(() => {
    if (session && selectedId) loadMembers(session, selectedId).catch((e) => setMessage(e.message));
  }, [session, selectedId]);

  async function createOrganization(event: FormEvent) {
    event.preventDefault();
    if (!session || !name.trim()) return;
    setBusy(true); setMessage("");
    try {
      const created = await request<Organization>("/admin/organizations", session, {
        method: "POST",
        body: JSON.stringify({ name: name.trim(), tax_id: taxId.trim() || null }),
      });
      setName(""); setTaxId("");
      await loadOrganizations(session);
      setSelectedId(created.id);
      setMessage("Empresa creada y vinculada a tu usuario como administrador.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "No se pudo crear la empresa");
    } finally { setBusy(false); }
  }

  async function addMember(event: FormEvent) {
    event.preventDefault();
    if (!session || !selectedId || !memberEmail.trim()) return;
    setBusy(true); setMessage("");
    try {
      await request(`/admin/organizations/${selectedId}/members`, session, {
        method: "POST",
        body: JSON.stringify({ email: memberEmail.trim(), role: memberRole }),
      });
      setMemberEmail("");
      await loadMembers(session, selectedId);
      await loadOrganizations(session);
      setMessage("Usuario agregado a la empresa.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "No se pudo agregar el usuario");
    } finally { setBusy(false); }
  }

  async function changeRole(member: Member, role: Member["role"]) {
    if (!session || !selectedId) return;
    setBusy(true); setMessage("");
    try {
      await request(`/admin/organizations/${selectedId}/members/${member.id}`, session, {
        method: "PATCH",
        body: JSON.stringify({ role }),
      });
      await loadMembers(session, selectedId);
      setMessage("Permiso actualizado.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "No se pudo actualizar el permiso");
    } finally { setBusy(false); }
  }

  if (authorized === null) return <main style={{padding:40}}>Cargando administración…</main>;
  if (!authorized) return (
    <main style={{padding:40,fontFamily:"Inter,system-ui"}}>
      <a href="/">← Volver</a><h1>Administración global</h1>
      <p>No tenés permiso de superadministrador para administrar empresas.</p>
      {message && <p>{message}</p>}
    </main>
  );

  const selected = organizations.find((org) => org.id === selectedId);
  return (
    <main style={{minHeight:"100vh",background:"#f4f7f5",padding:"28px 34px",fontFamily:"Inter,system-ui",color:"#17211d"}}>
      <div style={{display:"flex",justifyContent:"space-between",alignItems:"center",marginBottom:24}}>
        <div><small style={{color:"#718078",fontWeight:800}}>DIRAC · ADMINISTRACIÓN GLOBAL</small><h1 style={{margin:"6px 0"}}>Empresas, usuarios y permisos</h1><p style={{margin:0,color:"#718078"}}>Separación de clientes por organización. Cada empresa conserva sus propios medidores, facturas, mejoras y documentos.</p></div>
        <a href="/" style={{color:"#168758",fontWeight:800}}>← Volver a energía</a>
      </div>

      {message && <div style={{background:"#fff",border:"1px solid #dce5df",borderRadius:10,padding:12,marginBottom:16}}>{message}</div>}

      <section style={{display:"grid",gridTemplateColumns:"360px 1fr",gap:18}}>
        <div style={{display:"grid",gap:18,alignContent:"start"}}>
          <div style={{background:"white",border:"1px solid #e5ebe7",borderRadius:12,padding:18}}>
            <h2 style={{fontSize:16,marginTop:0}}>Nueva empresa</h2>
            <form onSubmit={createOrganization} style={{display:"grid",gap:12}}>
              <label>Nombre<input value={name} onChange={(e)=>setName(e.target.value)} required style={inputStyle}/></label>
              <label>CUIT / Identificación<input value={taxId} onChange={(e)=>setTaxId(e.target.value)} style={inputStyle}/></label>
              <button disabled={busy} style={primaryButton}>Crear empresa</button>
            </form>
          </div>

          <div style={{background:"white",border:"1px solid #e5ebe7",borderRadius:12,padding:18}}>
            <h2 style={{fontSize:16,marginTop:0}}>Empresas</h2>
            <div style={{display:"grid",gap:8}}>{organizations.map((org)=><button key={org.id} onClick={()=>setSelectedId(org.id)} style={{textAlign:"left",padding:12,borderRadius:9,border:selectedId===org.id?"1px solid #1b925e":"1px solid #e5ebe7",background:selectedId===org.id?"#edf8f2":"white",cursor:"pointer"}}><b>{org.name}</b><small style={{display:"block",marginTop:4,color:"#718078"}}>{org.member_count || 0} usuario(s){org.tax_id?` · ${org.tax_id}`:""}</small></button>)}</div>
          </div>
        </div>

        <div style={{background:"white",border:"1px solid #e5ebe7",borderRadius:12,padding:20}}>
          <div style={{display:"flex",justifyContent:"space-between",alignItems:"start",gap:20}}>
            <div><small style={{color:"#718078",fontWeight:800}}>EMPRESA SELECCIONADA</small><h2 style={{margin:"5px 0 0"}}>{selected?.name || "Seleccioná una empresa"}</h2></div>
          </div>

          {selected && <>
            <form onSubmit={addMember} style={{display:"grid",gridTemplateColumns:"1fr 180px auto",gap:10,margin:"22px 0"}}>
              <input type="email" placeholder="usuario@empresa.com" value={memberEmail} onChange={(e)=>setMemberEmail(e.target.value)} required style={inputStyle}/>
              <select value={memberRole} onChange={(e)=>setMemberRole(e.target.value as Member["role"])} style={inputStyle}><option value="admin">Administrador</option><option value="analyst">Analista</option><option value="viewer">Solo lectura</option></select>
              <button disabled={busy} style={primaryButton}>Agregar usuario</button>
            </form>
            <p style={{fontSize:12,color:"#718078"}}>En esta primera etapa, el correo debe corresponder a un usuario que ya exista en la plataforma.</p>

            <div style={{borderTop:"1px solid #e5ebe7",marginTop:18}}>
              {members.map((member)=><div key={member.id} style={{display:"grid",gridTemplateColumns:"1fr 220px",gap:12,alignItems:"center",padding:"14px 4px",borderBottom:"1px solid #edf0ee"}}><div><b>{member.email || member.user_id}</b><small style={{display:"block",color:"#89958f",marginTop:3}}>ID {member.user_id}</small></div><select value={member.role} disabled={busy} onChange={(e)=>changeRole(member,e.target.value as Member["role"])} style={inputStyle}><option value="admin">Administrador</option><option value="analyst">Analista</option><option value="viewer">Solo lectura</option></select></div>)}
              {!members.length && <p style={{padding:20,color:"#89958f"}}>Esta empresa todavía no tiene usuarios.</p>}
            </div>
          </>}
        </div>
      </section>
    </main>
  );
}

const inputStyle = {width:"100%",height:40,border:"1px solid #dce5df",borderRadius:8,padding:"0 10px",marginTop:5,background:"white"};
const primaryButton = {border:0,borderRadius:8,background:"#1b925e",color:"white",padding:"0 16px",minHeight:40,fontWeight:800,cursor:"pointer"};
