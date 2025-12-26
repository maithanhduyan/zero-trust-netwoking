# control-plane/config.py
"""
Application Configuration
Uses pydantic-settings for environment variable management
"""

import os
from typing import List, Optional
from pydantic_settings import BaseSettings, SettingsConfigDict
from functools import lru_cache


class Settings(BaseSettings):
    """
    Application settings loaded from environment variables
    Create a .env file for local development
    """

    # === Application ===
    APP_NAME: str = "Zero Trust Control Plane"
    APP_VERSION: str = "1.0.0"
    ENV: str = "development"  # development, staging, production
    DEBUG: bool = False
    LOG_LEVEL: str = "INFO"

    # === API ===
    API_HOST: str = "0.0.0.0"
    API_PORT: int = 8000
    API_PREFIX: str = "/api/v1"

    # CORS
    CORS_ORIGINS: List[str] = ["*"]
    CORS_ALLOW_CREDENTIALS: bool = True

    # === Database ===
    DATABASE_URL: str = "sqlite:///./zerotrust.db"
    DB_POOL_SIZE: int = 5
    DB_MAX_OVERFLOW: int = 10

    # === Security ===
    SECRET_KEY: str = "change-me-in-production-use-secrets-manager"
    ADMIN_SECRET: str = "change-me-admin-secret"

    # JWT Settings (for future use)
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRE_MINUTES: int = 60

    # === WireGuard Network ===
    OVERLAY_NETWORK: str = "10.0.0.0/24"
    OVERLAY_GATEWAY: str = "10.0.0.1"

    # Hub Configuration
    HUB_PUBLIC_KEY: str = "REPLACE_WITH_HUB_PUBLIC_KEY"
    HUB_ENDPOINT: str = "hub.example.com:51820"
    HUB_LISTEN_PORT: int = 51820

    # DNS
    DNS_SERVERS: List[str] = ["10.0.0.1", "1.1.1.1"]

    # === Node Registration ===
    REQUIRE_REGISTRATION_TOKEN: bool = False
    REGISTRATION_TOKEN: Optional[str] = None
    AUTO_APPROVE_ROLES: List[str] = ["ops", "hub"]
    AUTO_APPROVE_ALL: bool = True  # Set False in production

    # === Agent Sync ===
    HEARTBEAT_INTERVAL: int = 30  # seconds
    CONFIG_SYNC_INTERVAL: int = 60  # seconds
    NODE_TIMEOUT_MINUTES: int = 5  # Mark node as offline after this

    # === Logging & Audit ===
    ENABLE_AUDIT_LOG: bool = True
    AUDIT_LOG_RETENTION_DAYS: int = 90

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore",
    )

    @property
    def is_production(self) -> bool:
        """Check if running in production"""
        return self.ENV.lower() == "production"

    @property
    def is_development(self) -> bool:
        """Check if running in development"""
        return self.ENV.lower() == "development"


@lru_cache()
def get_settings() -> Settings:
    """
    Cached settings instance
    Use this to get settings throughout the application
    """
    return Settings()


# Singleton instance for backward compatibility
settings = get_settings()