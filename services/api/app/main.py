"""FastAPI application setup and health endpoint."""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routers.briefs import router as briefs_router
from app.settings import settings

app = FastAPI(
    title="ThreadBrief API",
    version="0.1.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(briefs_router, prefix="/v1", tags=["briefs"])


@app.get("/health")
def health():
    """Return a simple health payload for uptime checks."""
    return {"status": "ok", "env": settings.app_env}
