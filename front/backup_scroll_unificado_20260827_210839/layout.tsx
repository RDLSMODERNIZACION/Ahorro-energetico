import type { Metadata } from "next";
import "./globals.css";
import "./table-scroll-fix.css";
export const metadata: Metadata = { title: "Ahorro Energético Municipal", description: "Análisis y proyección de ahorro energético municipal", other: { "codex-preview": "development" } };
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="es"><body>{children}</body></html>}
