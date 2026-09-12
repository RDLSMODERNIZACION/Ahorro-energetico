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
];

for (const patch of patches) {
  execFileSync(process.execPath, ["scripts/" + patch], { stdio: "inherit" });
}

rmSync(".next", { recursive: true, force: true });
execFileSync(process.platform === "win32" ? "npx.cmd" : "npx", ["next", "build"], {
  stdio: "inherit",
});
