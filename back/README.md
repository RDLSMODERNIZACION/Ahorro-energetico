# Backend - Gestión Energética Municipal

API para almacenar y analizar facturas EPEN, cuadros tarifarios mensuales, medidores y oportunidades de ahorro. Está configurado para el proyecto Supabase `AhorroEnergeticoEpen`.

## Instalación en Windows

1. Ejecutar `INSTALAR_BACKEND.ps1` con PowerShell.
2. Abrir `.env` y reemplazar `PEGAR_AQUI_LA_SECRET_KEY_DE_SUPABASE`.
3. La clave se obtiene en Supabase: **Project Settings > API Keys > Secret keys**.
4. Ejecutar `INICIAR_BACKEND.ps1`.
5. Abrir `http://localhost:8000/docs`.

La Secret Key debe permanecer solamente en este backend. Nunca debe copiarse al frontend ni subirse a GitHub.

## Primer usuario

Crear el usuario desde **Supabase > Authentication > Users**. Después agregarlo a la Municipalidad desde el SQL Editor:

```sql
insert into public.organization_members (organization_id, user_id, role)
select o.id, u.id, 'admin'
from public.organizations o
cross join auth.users u
where o.name = 'Municipalidad de Rincón de los Sauces'
  and u.email = 'CORREO_DEL_ADMINISTRADOR';
```

## Endpoints principales

- `GET /health`: estado de la API.
- `GET /api/organizations`: organizaciones del usuario.
- `GET/POST /api/sites`: establecimientos.
- `GET/POST /api/meters`: medidores.
- `PUT /api/meters/{id}/location`: posición del medidor.
- `POST /api/imports/invoices`: carga ZIP/CSV.
- `POST /api/imports/document`: PDF o documento original.
- `GET /api/organizations/{id}/invoices`: facturas.
- `GET /api/invoices/{id}`: factura completa.
- `GET/POST /api/tariffs/schedules`: cuadros mensuales.
- `GET/POST /api/tariffs/schedules/{id}/rates`: precios tarifarios.
- `POST /api/organizations/{id}/analysis/run`: análisis de ahorro.
- `GET /api/organizations/{id}/opportunities`: oportunidades.
- `GET /api/organizations/{id}/dashboard`: resumen.

## Autenticación

Los endpoints protegidos esperan el token de Supabase:

```text
Authorization: Bearer TOKEN_DEL_USUARIO
```

El backend valida el token y la pertenencia del usuario a la organización antes de leer o modificar datos.

## Formato CSV reconocido

Reconoce nombres equivalentes a:

```text
medidor;ubicacion;periodo;kwh;demanda;potencia contratada;importe total;energia reactiva;tarifa;nivel tension
```

El importador acepta CSV individual o ZIP con múltiples CSV, evita duplicar archivos por SHA-256 y registra las filas rechazadas.

## Desarrollo

```powershell
.\.venv\Scripts\Activate.ps1
pytest
uvicorn app.main:app --reload
```
