// Next injects this prefix at build time; other runtimes can retain the root path.
export const BASE_PATH = process.env.NEXT_PUBLIC_BASE_PATH || "";
export const APP_HOME = BASE_PATH || "/";
export const API_BASE = `${BASE_PATH}/api/backend`;
