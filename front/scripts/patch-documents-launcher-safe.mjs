import { readFileSync, writeFileSync } from "node:fs";

const path = new URL("../app/invoice-analysis-panel.tsx", import.meta.url);
let source = readFileSync(path, "utf8");
const marker = "DOCUMENTS_LAUNCHER_SAFE_V1";
if (source.includes(marker)) process.exit(0);

source = source.replace(
  '<span style={{display:"block",fontSize:11,fontWeight:800,letterSpacing:".08em",color:"#0b8f68",marginBottom:3}}>DOCUMENTACIÓN</span>',
  ''
);
source = source.replace(
  '<small style={{display:"block",marginTop:4,color:"#68766f"}}>Facturas, cuadros tarifarios y documentos asociados al suministro.</small>',
  ''
);
source = source.replace(
  '<section className="invoice-analysis-panel" style={{overflow:"hidden"}}>',
  '<section className="invoice-analysis-panel" style={{overflow:"hidden",padding:"18px 22px"}}>'
);
source = source.replace('width:42,height:42', 'width:48,height:48');
source = source.replace('gap:14,minWidth:0', 'gap:18,minWidth:0');
source = source.replace(
  '<h3 style={{margin:0,fontSize:18}}>Archivos del medidor</h3>',
  '<h3 style={{margin:0,fontSize:18}}>Archivos del medidor</h3>{/* DOCUMENTS_LAUNCHER_SAFE_V1 */}'
);

writeFileSync(path, source, "utf8");
console.log("Applied safe simplified meter documents card.");