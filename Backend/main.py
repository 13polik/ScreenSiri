"""
ScreenSiri Backend
──────────────────
FastAPI service that orchestrates AI analysis of iPhone screenshots.

Routes:
  POST /analyze        — Main endpoint (image + query + memory → guidance)
  GET  /health         — Health check
  GET  /               — Info

Run locally:
  uvicorn main:app --reload --port 8000

Deploy:
  Railway / Render / Fly.io / AWS Lambda (via Mangum)
"""

import os
import logging
from dotenv import load_dotenv
load_dotenv()
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from routes.analyze import router as analyze_router

# ── Logging ───────────────────────────────────────────────────────────────────

logging.basicConfig(
    level   = logging.INFO,
    format  = "%(asctime)s | %(levelname)s | %(name)s | %(message)s",
    datefmt = "%Y-%m-%d %H:%M:%S"
)
logger = logging.getLogger("screensiri")


# ── Lifespan ──────────────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("ScreenSiri backend starting…")

    # Validate required env vars
    if not os.getenv("OPENAI_API_KEY"):
        logger.warning("⚠️  OPENAI_API_KEY not set — /analyze calls will fail")

    yield

    logger.info("ScreenSiri backend shutting down.")


# ── App ───────────────────────────────────────────────────────────────────────

app = FastAPI(
    title       = "ScreenSiri Backend",
    description = "AI-powered screen assistant backend for the ScreenSiri iOS app.",
    version     = "1.0.0",
    lifespan    = lifespan,
    docs_url    = "/docs",
    redoc_url   = "/redoc",
)


# ── CORS ──────────────────────────────────────────────────────────────────────
# Restrict to your app's bundle ID in production

app.add_middleware(
    CORSMiddleware,
    allow_origins     = ["*"],      # Tighten in production
    allow_credentials = True,
    allow_methods     = ["*"],
    allow_headers     = ["*"],
)


# ── Routes ────────────────────────────────────────────────────────────────────

app.include_router(analyze_router)


@app.get("/", tags=["info"])
async def root():
    return {
        "name":    "ScreenSiri Backend",
        "version": "1.0.0",
        "status":  "running",
        "docs":    "/docs"
    }


@app.get("/health", tags=["info"])
async def health():
    return {"status": "ok"}


# ── Error Handlers ────────────────────────────────────────────────────────────

@app.exception_handler(Exception)
async def global_exception_handler(request, exc):
    logger.error(f"Unhandled exception: {exc}", exc_info=True)
    return JSONResponse(
        status_code = 500,
        content     = {"detail": "Internal server error. Please try again."}
    )
