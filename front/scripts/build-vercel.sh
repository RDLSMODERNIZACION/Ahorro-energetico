#!/usr/bin/env bash
set -e
node scripts/patch-t2-excess-bars.mjs
node scripts/patch-t1-no-contracted-surplus.mjs
node scripts/patch-performance-cache.mjs
rm -rf .next
npx next build
