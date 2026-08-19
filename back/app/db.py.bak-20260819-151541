from threading import local
from supabase import Client, create_client
from .config import get_settings

_clients = local()

def admin_db() -> Client:
    # Los endpoints síncronos de FastAPI se ejecutan en un pool de hilos.
    # Un único cliente global de Supabase/httpx no debe compartirse entre
    # consultas concurrentes porque puede corromper el stream HTTP/2.
    client = getattr(_clients, "admin", None)
    if client is None:
        cfg = get_settings()
        client = create_client(cfg.supabase_url, cfg.supabase_secret_key)
        _clients.admin = client
    return client
