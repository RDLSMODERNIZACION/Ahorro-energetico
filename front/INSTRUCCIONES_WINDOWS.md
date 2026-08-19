# Ahorro Energético Municipal

## Requisitos

- Node.js 22 o superior.
- PowerShell.

## Ejecutar el frontend

1. Descomprimir el ZIP.
2. Abrir PowerShell dentro de la carpeta.
3. Ejecutar:

```powershell
npm install
npm run dev
```

4. Abrir la dirección que muestre la consola, normalmente `http://localhost:3000`.

## Compilar para producción

```powershell
npm run build
```

## Archivos principales

- `app/page.tsx`: interfaz, carga ZIP/CSV, análisis, proyección y mapa.
- `app/globals.css`: diseño completo y versión responsive.
- `app/layout.tsx`: configuración general de la aplicación.
- `package.json`: dependencias y comandos.

## Formato del CSV

La aplicación intenta reconocer automáticamente columnas equivalentes a:

- medidor o suministro;
- ubicación, sitio o dependencia;
- período, fecha o mes;
- kWh o consumo;
- demanda o potencia máxima;
- potencia contratada;
- importe, monto o total;
- energía reactiva, penalización o recargo.

El ZIP puede contener uno o varios archivos CSV.
