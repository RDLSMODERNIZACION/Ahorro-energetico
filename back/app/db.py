from functools import lru_cache
from supabase import Client, create_client
from .config import get_settings

@lru_cache
def admin_db() -> Client:
    cfg = get_settings()
    return create_client(cfg.supabase_url, cfg.supabase_secret_key)
