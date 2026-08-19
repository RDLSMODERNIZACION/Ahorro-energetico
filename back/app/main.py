from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from .config import get_settings
from .routers import analysis,catalog,imports,invoices,tariffs

app=FastAPI(title="Gestión Energética Municipal API",version="1.0.0",description="Facturas EPEN, cuadros tarifarios y oportunidades de ahorro")
app.add_middleware(CORSMiddleware,allow_origins=get_settings().origins,allow_credentials=True,allow_methods=["*"],allow_headers=["*"])
app.include_router(catalog.router,prefix="/api")
app.include_router(imports.router,prefix="/api")
app.include_router(tariffs.router,prefix="/api")
app.include_router(invoices.router,prefix="/api")
app.include_router(analysis.router,prefix="/api")

@app.get("/health",tags=["Sistema"])
def health():return {"status":"ok","service":"energia-municipal-api"}
