# control-plane/schemas/base.py
"""
Base schemas for API responses
"""

from pydantic import BaseModel, Field
from typing import TypeVar, Generic, Optional, List, Any
from datetime import datetime

T = TypeVar("T")


class BaseResponse(BaseModel, Generic[T]):
    """
    Standard API response wrapper
    All API responses should follow this format
    """
    success: bool = True
    message: str = "Operation successful"
    data: Optional[T] = None
    timestamp: datetime = Field(default_factory=datetime.utcnow)

    class Config:
        from_attributes = True


class ErrorResponse(BaseModel):
    """
    Standard error response
    Used for 4xx and 5xx responses
    """
    success: bool = False
    error: str
    error_code: str
    details: Optional[dict] = None
    timestamp: datetime = Field(default_factory=datetime.utcnow)

    class Config:
        json_schema_extra = {
            "example": {
                "success": False,
                "error": "Node not found",
                "error_code": "NODE_NOT_FOUND",
                "details": {"node_id": 123},
                "timestamp": "2025-12-26T10:00:00Z"
            }
        }


class PaginatedResponse(BaseModel, Generic[T]):
    """
    Paginated response for list endpoints
    """
    success: bool = True
    data: List[T]
    total: int
    page: int
    page_size: int
    total_pages: int
    has_next: bool
    has_prev: bool
    timestamp: datetime = Field(default_factory=datetime.utcnow)

    class Config:
        from_attributes = True


class HealthResponse(BaseModel):
    """Health check response"""
    status: str = "healthy"
    service: str = "control-plane"
    version: str = "1.0.0"
    uptime_seconds: Optional[float] = None
    database: str = "connected"
    timestamp: datetime = Field(default_factory=datetime.utcnow)
