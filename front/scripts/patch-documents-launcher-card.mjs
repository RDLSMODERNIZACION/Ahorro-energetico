import { readFileSync, writeFileSync } from "node:fs";

const path = new URL("../app/invoice-analysis-panel.tsx", import.meta.url);
let source = readFileSync(path, "utf8");
const marker = "// DOCUMENTS_LAUNCHER_CARD_V2";
if (source.includes(marker)) process.exit(0);

const blockPattern = /          <section className="invoice-analysis-panel"(?: style=\{\{overflow:"hidden"\}\})?>\n[\s\S]*?Archivos del medidor[\s\S]*?Ver archivos →[\s\S]*?          <\/section>/;

if (!blockPattern.test(source)) {
  throw new Error("documents launcher block not found");
}

const newBlock = `          <section className="invoice-analysis-panel" style={{overflow:"hidden",padding:"18px 22px"}}>
            {/* DOCUMENTS_LAUNCHER_CARD_V2 */}
            <div style={{display:"flex",justifyContent:"space-between",alignItems:"center",gap:20,flexWrap:"wrap"}}>
              <div style={{display:"flex",alignItems:"center",gap:18,minWidth:0}}>
                <div style={{width:48,height:48,borderRadius:12,background:"#eaf6f1",display:"grid",placeItems:"center",fontSize:15,fontWeight:900,color:"#0b8f68",flex:"0 0 auto"}}>PDF</div>
                <h3 style={{margin:0,fontSize:18}}>Archivos del medidor</h3>
              </div>
              <button type="button" onClick={() => setDocumentsOpen(true)} style={{padding:"10px 16px",borderRadius:10,border:"1px solid #0b8f68",background:"#0b8f68",color:"#fff",fontWeight:800,cursor:"pointer",whiteSpace:"nowrap"}}>Ver archivos →</button>
            </div>
          </section>`;

source = source.replace(blockPattern, newBlock);
writeFileSync(path, source, "utf8");
console.log("Simplified meter documents launcher card.");
