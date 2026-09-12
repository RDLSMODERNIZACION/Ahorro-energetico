import { rmSync } from "node:fs";
import { execFileSync } from "node:child_process";

const patches = [
  "patch-t2-excess-bars.mjs",
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
  "patch-lazy-tariff-data.mjs",
  "patch-lazy-epen-tab-v2.mjs",
  "patch-defer-summary.mjs",
  "patch-lazy-heavy-panels.mjs",
  "patch-improvement-button-period.mjs",
  "patch-hide-power-summary.mjs",
  "patch-same-origin-api-v2.mjs",
];

for (const patch of patches) {
  execFileSync(process.execPath, ["scripts/" + patch], { stdio: "inherit" });
}

rmSync(".next", { recursive: true, force: true });
execFileSync(process.platform === "win32" ? "npx.cmd" : "npx", ["next", "build"], {
  stdio: "inherit",
});
