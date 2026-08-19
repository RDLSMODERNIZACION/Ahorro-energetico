import { createClient } from "@supabase/supabase-js";

const url = import.meta.env.VITE_SUPABASE_URL as string;
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string;

if (!url || !key) throw new Error("Faltan las variables públicas de Supabase");
export const supabase = createClient(url, key, { auth: { persistSession: true, autoRefreshToken: true } });
