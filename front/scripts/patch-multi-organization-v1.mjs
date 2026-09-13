import { readFileSync, writeFileSync } from "node:fs";

const pagePath = new URL("../app/page.tsx", import.meta.url);
const cssPath = new URL("../app/globals.css", import.meta.url);
let s = readFileSync(pagePath, "utf8");
if (s.includes("MULTI_ORGANIZATION_V1")) process.exit(0);

s = s.replace(
  '  const [organization, setOrganization] = useState<Organization | null>(null),\n    [meters, setMeters] = useState<Meter[]>([]),',
  '  const [organization, setOrganization] = useState<Organization | null>(null),\n    // MULTI_ORGANIZATION_V1\n    [organizations, setOrganizations] = useState<Organization[]>([]),\n    [meters, setMeters] = useState<Meter[]>([]),',
);

const oldOrgLoad = `        if (!target) {\n          const orgs = await api<Organization[]>("/api/organizations", s);\n          if (!orgs.length)\n            throw new Error(\n              "Tu usuario todavía no está asociado a la Municipalidad",\n            );\n          setOrganization(orgs[0]);\n          target = orgs[0].organization_id;\n        }`;
const newOrgLoad = `        if (!target) {\n          const orgs = await api<Organization[]>("/api/organizations", s);\n          if (!orgs.length)\n            throw new Error("Tu usuario todavía no está asociado a una organización");\n          setOrganizations(orgs);\n          const remembered = typeof window !== "undefined" ? window.localStorage.getItem("energy.organization_id") : null;\n          const selected = orgs.find((item) => item.organization_id === remembered) || orgs[0];\n          setOrganization(selected);\n          target = selected.organization_id;\n          if (typeof window !== "undefined") window.localStorage.setItem("energy.organization_id", target);\n        }`;
if (!s.includes(oldOrgLoad)) throw new Error("organization load block not found");
s = s.replace(oldOrgLoad, newOrgLoad);

const analyzeNeedle = '  async function analyze() {';
if (!s.includes(analyzeNeedle)) throw new Error("analyze insertion point not found");
const switchFn = `  async function switchOrganization(organizationId: string) {\n    if (!session || organizationId === organization?.organization_id) return;\n    const next = organizations.find((item) => item.organization_id === organizationId);\n    if (!next) return;\n    setOrganization(next);\n    if (typeof window !== "undefined") window.localStorage.setItem("energy.organization_id", organizationId);\n    setMeters([]);\n    setInvoices([]);\n    setMissing([]);\n    setOpportunities([]);\n    setAssessments([]);\n    setTariffSavings([]);\n    setSelectedMeterId(null);\n    await load(session, organizationId);\n  }\n\n`;
s = s.replace(analyzeNeedle, switchFn + analyzeNeedle);

const userBoxNeedle = `          <b>{session.user.email}</b>\n          <small>{organization?.organizations.name}</small>\n          <button onClick={() => supabase.auth.signOut()}>Cerrar sesión</button>`;
const userBoxReplacement = `          <b>{session.user.email}</b>\n          {organizations.length > 1 ? (\n            <label className="organization-switcher">\n              <span>Empresa / organización</span>\n              <select\n                value={organization?.organization_id || ""}\n                onChange={(event) => switchOrganization(event.target.value)}\n              >\n                {organizations.map((item) => (\n                  <option key={item.organization_id} value={item.organization_id}>\n                    {item.organizations.name}\n                  </option>\n                ))}\n              </select>\n            </label>\n          ) : (\n            <small>{organization?.organizations.name}</small>\n          )}\n          {organization && (\n            <span className="organization-role">\n              {organization.role === "admin" ? "Administrador" : organization.role === "analyst" ? "Analista" : "Solo lectura"}\n            </span>\n          )}\n          <button onClick={() => supabase.auth.signOut()}>Cerrar sesión</button>`;
if (!s.includes(userBoxNeedle)) throw new Error("user box block not found");
s = s.replace(userBoxNeedle, userBoxReplacement);

writeFileSync(pagePath, s, "utf8");

let css = readFileSync(cssPath, "utf8");
if (!css.includes("MULTI_ORGANIZATION_V1")) {
  css += `\n/* MULTI_ORGANIZATION_V1 */\n.organization-switcher { display:block; margin-top:8px; }\n.organization-switcher span { display:block; font-size:7px; color:#7f978c; margin-bottom:4px; text-transform:uppercase; letter-spacing:.06em; }\n.organization-switcher select { width:100%; border:1px solid #355347; background:#1b3028; color:#e7f4ed; border-radius:7px; padding:7px 8px; font-size:9px; }\n.organization-role { display:inline-flex; margin-top:7px; padding:4px 6px; border-radius:999px; background:#254136; color:#9fddc1; font-size:7px; font-weight:700; }\n`;
  writeFileSync(cssPath, css, "utf8");
}

console.log("Added multi-organization selector and persisted organization context.");
