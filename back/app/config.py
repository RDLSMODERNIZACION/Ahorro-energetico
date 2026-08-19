from functools import lru_cache
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    supabase_url: str
    supabase_secret_key: str
    frontend_origins: str = "http://localhost:3000,http://localhost:5173"
    max_upload_mb: int = 50
    model_config = SettingsConfigDict(env_file=".env", case_sensitive=False, extra="ignore")

    @property
    def origins(self) -> list[str]:
        return [x.strip() for x in self.frontend_origins.split(",") if x.strip()]

@lru_cache
def get_settings() -> Settings:
    return Settings()
