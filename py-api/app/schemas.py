from datetime import datetime
from uuid import UUID
from pydantic import BaseModel, Field


class User(BaseModel):
    id: UUID
    email: str
    full_name: str
    age: int
    country_code: str
    is_active: bool
    created_at: datetime

    class Config:
        from_attributes = True


class UserListResponse(BaseModel):
    items: list[User]
    limit: int
    offset: int
    total: int


class HealthResponse(BaseModel):
    status: str


class ErrorResponse(BaseModel):
    error: str
