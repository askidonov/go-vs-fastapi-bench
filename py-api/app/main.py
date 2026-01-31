from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.responses import JSONResponse
from app.api import router
from app.db import get_pool, close_pool


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage application lifespan."""
    # Startup: initialize database pool
    await get_pool()
    yield
    # Shutdown: close database pool
    await close_pool()


app = FastAPI(
    title="Python Bench API",
    lifespan=lifespan,
    docs_url=None,  # Disable docs for performance
    redoc_url=None,  # Disable redoc for performance
)

# Include router
app.include_router(router)


# Custom exception handler for consistent error responses
@app.exception_handler(Exception)
async def generic_exception_handler(request, exc):
    return JSONResponse(
        status_code=500,
        content={"error": "internal_error"},
    )
