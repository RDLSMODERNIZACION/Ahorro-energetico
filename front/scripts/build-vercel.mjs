import { rmSync } from "node:fs";
import { execFileSync } from "node:child_process";

const patches = [
  "patch-t2-excess-bars.mjs",
  "patch-proposal-compare-current.mjs",
  "patch-t2-optimal-proposal.mjs",
  "patch-t2-optimal-v4.mjs",
  "patch-t2-proposal-savings.mjs",
  "patch-t2-exc-cost-card.mjs",
  "patch-t1-no-contracted-surplus.mjs",
  "patch-performance-cache.mjs",
  "patch-dashboard-performance-v2.mjs",
  "patch-remove-eager-secondary.mjs",
  "patch-invoice-summary-lazy-detail.mjs",
  "patch-dashboard-bootstrap-v1.mjs",
  "patch-restore-change-controls-load.mjs",
  "patch-lazy-tariff-data.mjs",
  "patch-lazy-epen-tab-v2.mjs",
  "patch-defer-summary.mjs",
  "patch-lazy-heavy-panels.mjs",
  "patch-documents-launcher-safe.mjs",
  "patch-meter-documents-close.mjs",
  "patch-improvement-button-period.mjs",
  "patch-improvement-audit-table.mjs",
  "patch-improvement-audit-tab.mjs",
  "patch-edit-power-like-register.mjs",
  "patch-power-year-register.mjs",
  "patch-power-year-edit-audit.mjs",
  "patch-power-table-layout-v2.mjs",
  "patch-hide-power-summary.mjs",
  "patch-tax-db-only-v2.mjs",
  "patch-month-peer-selection-v2.mjs",
  "patch-same-origin-api-v2.mjs",
];

for (const patch of patches) {
  execFileSync(process.execPath, ["scripts/" + patch], { stdio: "inherit" });
}

rmSync(".next", { recursive: true, force: true });
execFileSync(process.platform === "win32" ? "npx.cmd" : "npx", ["next", "build"], {
  stdio: "inherit",
});
