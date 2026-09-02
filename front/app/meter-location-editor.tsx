"use client";

import { useEffect, useRef, useState } from "react";
import { supabase } from "./lib/supabase";

const API="https://ahorro-energetico.onrender.com";

declare global{
  interface Window{L?:any}
}

type LocationRow={
  id?:string;
  meter_id?:string;
  latitude:number|string;
  longitude:number|string;
  valid_from?:string;
  valid_to?:string|null;
  source?:string|null;
};

const DEFAULT_LAT=-37.3895;
const DEFAULT_LNG=-68.9250;

async function token(){
  const {data}=await supabase.auth.getSession();
  if(!data.session)throw new Error("SesiÃ³n vencida");
  return data.session.access_token;
}

function loadLeaflet():Promise<any>{
  if(typeof window==="undefined")return Promise.reject(new Error("Mapa no disponible"));
  if(window.L)return Promise.resolve(window.L);

  return new Promise((resolve,reject)=>{
    const cssId="leaflet-css-aem";
    if(!document.getElementById(cssId)){
      const link=document.createElement("link");
      link.id=cssId;
      link.rel="stylesheet";
      link.href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css";
      document.head.appendChild(link);
    }

    const existing=document.getElementById("leaflet-js-aem") as HTMLScriptElement|null;
    if(existing){
      existing.addEventListener("load",()=>resolve(window.L),{once:true});
      existing.addEventListener("error",()=>reject(new Error("No se pudo cargar el mapa")),{once:true});
      return;
    }

    const script=document.createElement("script");
    script.id="leaflet-js-aem";
    script.src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js";
    script.async=true;
    script.onload=()=>resolve(window.L);
    script.onerror=()=>reject(new Error("No se pudo cargar Leaflet"));
    document.body.appendChild(script);
  });
}

export function MeterLocationEditor({meterId,label}:{meterId:string;label?:string}){
  const[lat,setLat]=useState("");
  const[lng,setLng]=useState("");
  const[original,setOriginal]=useState<LocationRow|null>(null);
  const[busy,setBusy]=useState(false);
  const[message,setMessage]=useState("");
  const[mapReady,setMapReady]=useState(false);
  const mapNode=useRef<HTMLDivElement|null>(null);
  const mapRef=useRef<any>(null);
  const markerRef=useRef<any>(null);

  useEffect(()=>{
    let cancelled=false;
    (async()=>{
      try{
        const access=await token();
        const response=await fetch(`${API}/api/meters/${meterId}/location`,{
          headers:{Authorization:`Bearer ${access}`}
        });
        if(response.status===404)return;
        if(!response.ok)throw new Error(await response.text());
        const row=await response.json();
        if(cancelled||!row)return;
        setOriginal(row);
        setLat(String(row.latitude??""));
        setLng(String(row.longitude??""));
      }catch(error){
        if(!cancelled)setMessage(error instanceof Error?error.message:"No se pudo consultar la ubicaciÃ³n");
      }
    })();
    return()=>{cancelled=true};
  },[meterId]);

  useEffect(()=>{
    let cancelled=false;
    let clickHandler:any;
    loadLeaflet().then(L=>{
      if(cancelled||!mapNode.current||mapRef.current)return;
      const initialLat=Number(lat)||DEFAULT_LAT;
      const initialLng=Number(lng)||DEFAULT_LNG;
      const map=L.map(mapNode.current,{zoomControl:true}).setView([initialLat,initialLng],Number(lat)&&Number(lng)?17:13);
      L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",{
        maxZoom:20,
        attribution:'&copy; OpenStreetMap'
      }).addTo(map);
      mapRef.current=map;

      function setPoint(a:number,b:number){
        setLat(a.toFixed(6));
        setLng(b.toFixed(6));
        if(markerRef.current)markerRef.current.setLatLng([a,b]);
        else markerRef.current=L.marker([a,b],{draggable:true}).addTo(map);
        markerRef.current.off("dragend");
        markerRef.current.on("dragend",(e:any)=>{
          const p=e.target.getLatLng();
          setLat(p.lat.toFixed(6));
          setLng(p.lng.toFixed(6));
        });
      }

      if(Number(lat)&&Number(lng))setPoint(Number(lat),Number(lng));
      clickHandler=(e:any)=>setPoint(e.latlng.lat,e.latlng.lng);
      map.on("click",clickHandler);
      setMapReady(true);
      setTimeout(()=>map.invalidateSize(),100);
    }).catch(error=>setMessage(error instanceof Error?error.message:"No se pudo cargar el mapa"));

    return()=>{
      cancelled=true;
      if(mapRef.current){
        if(clickHandler)mapRef.current.off("click",clickHandler);
        mapRef.current.remove();
        mapRef.current=null;
        markerRef.current=null;
      }
    };
    // Se crea una vez por medidor; lat/lng iniciales se toman al montar.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  },[meterId]);

  useEffect(()=>{
    const L=window.L;
    const map=mapRef.current;
    const a=Number(lat),b=Number(lng);
    if(!L||!map||!Number.isFinite(a)||!Number.isFinite(b)||!lat||!lng)return;
    if(markerRef.current)markerRef.current.setLatLng([a,b]);
    else{
      markerRef.current=L.marker([a,b],{draggable:true}).addTo(map);
      markerRef.current.on("dragend",(e:any)=>{
        const p=e.target.getLatLng();
        setLat(p.lat.toFixed(6));
        setLng(p.lng.toFixed(6));
      });
    }
  },[lat,lng]);

  function useMyLocation(){
    setMessage("");
    if(!navigator.geolocation){setMessage("El navegador no permite obtener ubicaciÃ³n.");return}
    navigator.geolocation.getCurrentPosition(
      position=>{
        const a=position.coords.latitude,b=position.coords.longitude;
        setLat(a.toFixed(6));setLng(b.toFixed(6));
        if(mapRef.current)mapRef.current.setView([a,b],18);
      },
      ()=>setMessage("No se pudo obtener tu ubicaciÃ³n actual."),
      {enableHighAccuracy:true,timeout:10000}
    );
  }

  async function save(){
    const a=Number(lat),b=Number(lng);
    if(!Number.isFinite(a)||a < -90||a > 90){setMessage("Latitud invÃ¡lida.");return}
    if(!Number.isFinite(b)||b < -180||b > 180){setMessage("Longitud invÃ¡lida.");return}
    setBusy(true);setMessage("");
    try{
      const access=await token();
      const response=await fetch(`${API}/api/meters/${meterId}/location`,{
        method:"PUT",
        headers:{Authorization:`Bearer ${access}`,"Content-Type":"application/json"},
        body:JSON.stringify({latitude:a,longitude:b})
      });
      const body=await response.text();
      if(!response.ok)throw new Error(body||`Error ${response.status}`);
      const row=JSON.parse(body);
      setOriginal(row);
      setMessage("UbicaciÃ³n guardada correctamente.");
      if(mapRef.current)mapRef.current.setView([a,b],18);
    }catch(error){
      setMessage(error instanceof Error?error.message:"No se pudo guardar la ubicaciÃ³n");
    }finally{setBusy(false)}
  }

  const hasCurrent=Boolean(original);
  return <section className="invoice-analysis-panel meter-location-editor">
    <div className="meter-location-head">
      <div>
        <h3>UbicaciÃ³n del medidor</h3>
        <p>{label||"Medidor"} Â· cargÃ¡ coordenadas o tocÃ¡ directamente el mapa.</p>
      </div>
      <span className={hasCurrent?"location-status saved":"location-status pending"}>
        {hasCurrent?"UBICACIÃ“N GUARDADA":"SIN UBICACIÃ“N"}
      </span>
    </div>

    <div className="meter-location-layout">
      <div className="meter-location-form">
        <label>Latitud
          <input value={lat} onChange={e=>setLat(e.target.value.replace(",","."))} placeholder="-37.389500"/>
        </label>
        <label>Longitud
          <input value={lng} onChange={e=>setLng(e.target.value.replace(",","."))} placeholder="-68.925000"/>
        </label>

        <div className="meter-location-actions">
          <button type="button" className="secondary" onClick={useMyLocation}>âŒ– Usar mi ubicaciÃ³n</button>
          <button type="button" className="primary" disabled={busy} onClick={save}>{busy?"Guardandoâ€¦":"Guardar ubicaciÃ³n"}</button>
        </div>

        <div className="meter-location-help">
          <b>TambiÃ©n podÃ©s ubicarlo visualmente</b>
          <span>TocÃ¡ cualquier punto del mapa. DespuÃ©s podÃ©s arrastrar el marcador para ajustarlo con precisiÃ³n.</span>
        </div>

        {original&&<div className="meter-location-current">
          <span>Ãšltima ubicaciÃ³n registrada</span>
          <b>{Number(original.latitude).toFixed(6)}, {Number(original.longitude).toFixed(6)}</b>
          <small>{original.valid_from?`Desde ${new Date(original.valid_from).toLocaleString("es-AR")}`:"UbicaciÃ³n vigente"}</small>
        </div>}

        {message&&<div className={message.includes("correctamente")?"meter-location-message ok":"meter-location-message"}>{message}</div>}
      </div>

      <div className="meter-location-map-wrap">
        <div ref={mapNode} className="meter-location-map"/>
        {!mapReady&&<div className="meter-location-loading">Cargando mapaâ€¦</div>}
        <div className="meter-location-map-note">Mapa OpenStreetMap Â· clic para posicionar Â· marcador arrastrable</div>
      </div>
    </div>
  </section>
}

