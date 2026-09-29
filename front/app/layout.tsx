import { MeterObservationsProvider } from "./meter-observations";
import { BASE_PATH } from "./lib/paths";
import type { Metadata } from "next";
import "./globals.css";
import "./table-single-invoices.css";
import "./table-scroll-unified.css";
import "./table-scroll-fix.css";
import "./dirac-theme.css";
export const metadata: Metadata = { title: "DIRAC | Ahorro Energético", icons: { icon: `${BASE_PATH}/logodirac.jpeg`, apple: `${BASE_PATH}/logodirac.jpeg` }, description: "Análisis y proyección de ahorro energético municipal", other: { "codex-preview": "development" } };
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="es"><body><MeterObservationsProvider>{children}</MeterObservationsProvider></body></html>}


