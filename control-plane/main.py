# control-plane/main.py
"""
Zero Trust Control Plane - Main Application
FastAPI application entry point
"""

import uvicorn
import logging
from datetime import datetime
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError

from api.v1 import agent, admin, endpoints
from database.session import init_db, db_manager
from config import settings
from schemas.base import HealthResponse, ErrorResponse

# Configure logging
logging.basicConfig(
    level=getattr(logging, settings.LOG_LEVEL),
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)

# Track startup time
startup_time = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Application lifespan events
    - Startup: Initialize database
    - Shutdown: Cleanup resources
    """
    global startup_time

    # Startup
    logger.info(f"Starting {settings.APP_NAME} v{settings.APP_VERSION}")
    logger.info(f"Environment: {settings.ENV}")

    init_db()
    startup_time = datetime.utcnow()

    logger.info("Application started successfully")

    yield

    # Shutdown
    logger.info("Shutting down application")


# Initialize FastAPI App
app = FastAPI(
    title=settings.APP_NAME,
    description="""
    Zero Trust Control Plane API

    This API manages the Zero Trust network infrastructure including:
    - Node registration and lifecycle management
    - WireGuard overlay network configuration
    - Policy-based access control
    - Real-time configuration distribution

    ## Architecture

    - **Agent API**: Endpoints for Agent nodes to register, sync config, and heartbeat
    - **Admin API**: Endpoints for administrators to manage nodes and policies

    ## Authentication

    - Agent endpoints: Authenticated by WireGuard public key
    - Admin endpoints: Require X-Admin-Token header
    """,
    version=settings.APP_VERSION,
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json",
    lifespan=lifespan
)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=settings.CORS_ALLOW_CREDENTIALS,
    allow_methods=["*"],
    allow_headers=["*"],
)


# === Exception Handlers ===

@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    """Handle Pydantic validation errors"""
    errors = []
    for error in exc.errors():
        errors.append({
            "field": ".".join(str(loc) for loc in error["loc"]),
            "message": error["msg"],
            "type": error["type"]
        })

    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content={
            "success": False,
            "error": "Validation error",
            "error_code": "VALIDATION_ERROR",
            "details": {"errors": errors},
            "timestamp": datetime.utcnow().isoformat()
        }
    )


@app.exception_handler(Exception)
async def general_exception_handler(request: Request, exc: Exception):
    """Handle unexpected exceptions"""
    logger.exception(f"Unexpected error: {exc}")

    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={
            "success": False,
            "error": "Internal server error",
            "error_code": "INTERNAL_ERROR",
            "details": {"message": str(exc)} if settings.DEBUG else None,
            "timestamp": datetime.utcnow().isoformat()
        }
    )


# === Include Routers ===

# Legacy endpoints (deprecated, for backward compatibility)
app.include_router(
    endpoints.router,
    prefix="/api/v1",
    tags=["Legacy"]
)

# Agent API
app.include_router(
    agent.router,
    prefix="/api/v1/agent",
    tags=["Agent"]
)

# Admin API
app.include_router(
    admin.router,
    prefix="/api/v1/admin",
    tags=["Admin"]
)


# === Root Endpoints ===

@app.get(
    "/",
    summary="Root endpoint",
    description="Welcome message and API info"
)
async def read_root():
    """Root endpoint with API information"""
    return {
        "message": f"Welcome to {settings.APP_NAME}",
        "version": settings.APP_VERSION,
        "docs": "/docs",
        "redoc": "/redoc",
        "health": "/health"
    }


@app.get(
    "/health",
    response_model=HealthResponse,
    summary="Health check",
    description="Check application and database health"
)
async def health_check():
    """Health check endpoint for monitoring"""
    global startup_time

    # Check database connection
    db_status = "connected" if db_manager.check_connection() else "disconnected"

    # Calculate uptime
    uptime = None
    if startup_time:
        uptime = (datetime.utcnow() - startup_time).total_seconds()

    return HealthResponse(
        status="healthy" if db_status == "connected" else "unhealthy",
        service="control-plane",
        version=settings.APP_VERSION,
        uptime_seconds=uptime,
        database=db_status
    )


@app.get(
    "/api/v1",
    summary="API v1 info",
    description="API version information"
)
async def api_v1_info():
    """API v1 information"""
    return {
        "version": "v1",
        "status": "stable",
        "endpoints": {
            "agent": "/api/v1/agent",
            "admin": "/api/v1/admin",
            "legacy": "/api/v1 (deprecated)"
        }
    }


# === Run Application ===

if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host=settings.API_HOST,
        port=settings.API_PORT,
        reload=settings.is_development,
        log_level=settings.LOG_LEVEL.lower()
    )