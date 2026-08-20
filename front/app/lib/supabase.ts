import { createClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL || "https://ywfgjwghaqrmsefzvqgs.supabase.co";
const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || "sb_publishable_VIoLn6S43Rzh6q6gXvAKow_4M2FDxar";

if (!url || !key) throw new Error("Faltan las variables públicas de Supabase");
export const supabase = createClient(url, key, { auth: { persistSession: true, autoRefreshToken: true } });
