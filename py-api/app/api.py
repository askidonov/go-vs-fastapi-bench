from fastapi import APIRouter, HTTPException, Query
from uuid import UUID
from app.db import get_pool
from app.schemas import User, UserListResponse, HealthResponse, ErrorResponse

router = APIRouter()


@router.get("/healthz", response_model=HealthResponse)
async def health():
    """Health check endpoint."""
    return {"status": "ok"}


@router.get("/users/{user_id}", response_model=User)
async def get_user(user_id: UUID):
    """Get user by ID."""
    pool = await get_pool()
    
    query = """
        SELECT id, email, full_name, age, country_code, is_active, created_at
        FROM users
        WHERE id = $1
    """
    
    row = await pool.fetchrow(query, user_id)
    
    if row is None:
        raise HTTPException(status_code=404, detail={"error": "not_found"})
    
    return User(
        id=row["id"],
        email=row["email"],
        full_name=row["full_name"],
        age=row["age"],
        country_code=row["country_code"],
        is_active=row["is_active"],
        created_at=row["created_at"],
    )


@router.get("/users", response_model=UserListResponse)
async def list_users(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
):
    """List users with pagination."""
    pool = await get_pool()
    
    # Get users
    query = """
        SELECT id, email, full_name, age, country_code, is_active, created_at
        FROM users
        ORDER BY created_at DESC
        LIMIT $1 OFFSET $2
    """
    
    rows = await pool.fetch(query, limit, offset)
    
    users = [
        User(
            id=row["id"],
            email=row["email"],
            full_name=row["full_name"],
            age=row["age"],
            country_code=row["country_code"],
            is_active=row["is_active"],
            created_at=row["created_at"],
        )
        for row in rows
    ]
    
    # Get total count
    count_query = "SELECT COUNT(*) FROM users"
    total = await pool.fetchval(count_query)
    
    return UserListResponse(
        items=users,
        limit=limit,
        offset=offset,
        total=total,
    )
