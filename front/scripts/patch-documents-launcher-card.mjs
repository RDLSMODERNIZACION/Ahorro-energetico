import { readFileSync, writeFileSync } from "node:fs";

const path = new URL("../app/invoice-analysis-panel.tsx", import.meta.url);
let source = readFileSync(path, "utf8");
const marker = "// DOCUMENTS_LAUNCHER_CARD_V1";
if (source.includes(marker)) process.exit(0);

const oldBlock = `          <section className="invoice-analysis-panel">\n            <div style={{display:"flex",justifyContent:"space-between",alignItems:"center",gap:12,flexWrap:"wrap"}}>\n              <div><h3>Archivos del medidor</h3><small>Se cargan solo cuando los necesitás.</small></div>\n              <button type="button" onClick={() => setDocumentsOpen(true)}>Ver archivos</button>\n            </div>\n          </section>`;

const newBlock = `          <section className="invoice-analysis-panel" style={{overflow:"hidden"}}>\n            {/* DOCUMENTS_LAUNCHER_CARD_V1 */}\n            <div style={{display:"flex",justifyContent:"space-between",alignItems:"center",gap:18,flexWrap:"wrap"}}>\n              <div style={{display:"flex",alignItems:"center",gap:14,minWidth:0}}>\n                <div style={{width:42,height:42,borderRadius:12,background:"#eaf6f1",display:"grid",placeItems:"center",fontSize:14,fontWeight:900,color:"#0b8f68",flex:"0 0 auto"}}>PDF</div>\n                <div style={{minWidth:0}}>\n                  <span style={{display:"block",fontSize:11,fontWeight:800,letterSpacing:".08em",color:"#0b8f68",marginBottom:3}}>DOCUMENTACIÓN</span>\n                  <h3 style={{margin:0,fontSize:18}}>Archivos del medidor</h3>\n                  <small style={{display:"block",marginTop:4,color:"#68766f"}}>Facturas, cuadros tarifarios y documentos asociados al suministro.</small>\n                </div>\n              </div>\n              <button type="button" onClick={() => setDocumentsOpen(true)} style={{padding:"10px 16px",borderRadius:10,border:"1px solid #0b8f68",background:"#0b8f68",color:"#fff",fontWeight:800,cursor:"pointer",whiteSpace:"nowrap"}}>Ver archivos →</button>\n            </div>\n          </section>`;

if (!source.includes(oldBlock)) throw new Error("documents launcher block not found");
source = source.replace(oldBlock, newBlock);
writeFileSync(path, source, "utf8");
console.log("Improved meter documents launcher card.");
