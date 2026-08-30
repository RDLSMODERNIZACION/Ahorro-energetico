ALUMBRADO PUBLICO V1

Objetivo
- Agrega una tercera pestaña dentro de Facturas: "Alumbrado público".
- Mantiene separado el padrón/facturas AP de las dependencias municipales.
- Backend analiza el período seleccionado y devuelve:
  * esperadas / recibidas / faltantes
  * consumo total
  * importe total
  * promedio histórico 12 meses
  * variación contra mes anterior
  * anomalías de consumo
  * tarifa distinta de T1AP
  * consumo casi constante
  * historial de hasta 24 meses
- Front muestra KPIs, filtros, tabla y panel lateral por suministro.

Instalación
1. Descomprimir este ZIP dentro o fuera del repositorio.
2. Abrir PowerShell en la raíz de Ahorro-energetico.
3. Ejecutar:
   Set-ExecutionPolicy -Scope Process Bypass
   .\<carpeta-del-parche>\APLICAR_ALUMBRADO_PUBLICO_V1.ps1

Si el script está en la raíz del repo:
   .\APLICAR_ALUMBRADO_PUBLICO_V1.ps1

Después desplegar backend en Render y front en Vercel.

Nota de seguridad
Las tablas public_lighting_* actualmente tienen RLS deshabilitado. Este parche no cambia RLS para no bloquear la app sin definir antes las políticas.
