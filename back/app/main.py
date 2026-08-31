from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from .config import get_settings
from .routers import analysis,catalog,imports,invoices,tariffs,ai,intelligence,epen_optimization,tariff_history,public_lighting,public_lighting_fast

api=FastAPI(title="Gestión Energética Municipal API",version="1.0.0",description="Facturas EPEN, cuadros tarifarios y oportunidades de ahorro")
api.include_router(catalog.router,prefix="/api")
api.include_router(imports.router,prefix="/api")
api.include_router(tariffs.router,prefix="/api")
api.include_router(invoices.router,prefix="/api")
api.include_router(analysis.router,prefix="/api")
api.include_router(epen_optimization.router,prefix="/api")
api.include_router(tariff_history.router,prefix="/api")
api.include_router(public_lighting.router,prefix="/api")
api.include_router(public_lighting_fast.router,prefix="/api")
api.include_router(ai.router,prefix="/api")
api.include_router(intelligence.router,prefix="/api")

@api.get("/health",tags=["Sistema"])
def health():return {"status":"ok","service":"energia-municipal-api"}

# Debe envolver toda la aplicación para que incluso los errores no controlados
# incluyan los encabezados CORS y el navegador pueda mostrar la respuesta real.
app=CORSMiddleware(
    app=api,
    allow_origins=get_settings().origins,
    allow_origin_regex=r"https?://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)







