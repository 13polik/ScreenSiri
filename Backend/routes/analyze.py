from fastapi import APIRouter, HTTPException, Depends
from models.memory import AnalyzeRequest, AnalyzeResponse
from services.openai_service import OpenAIService
from services.vision_service import VisionService
import logging

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/analyze", tags=["analyze"])

# ── Dependency injection ──────────────────────────────────────────────────────

def get_openai_service() -> OpenAIService:
    return OpenAIService()

def get_vision_service() -> VisionService:
    return VisionService()


# ── POST /analyze ─────────────────────────────────────────────────────────────

@router.post("", response_model=AnalyzeResponse)
async def analyze_screen(
    request: AnalyzeRequest,
    openai: OpenAIService   = Depends(get_openai_service),
    vision: VisionService   = Depends(get_vision_service),
) -> AnalyzeResponse:
    """
    Main endpoint: accepts a base64 screenshot + session memory,
    runs it through GPT-4o Vision, returns AI guidance.

    Body:
        image       : base64 JPEG
        user_query  : what the user asked
        memory      : session context (conversation history, task, etc.)
        model       : GPT model to use (default: gpt-4o)
    """

    if not request.image:
        raise HTTPException(status_code=400, detail="image field is required")

    if not request.user_query:
        raise HTTPException(status_code=400, detail="user_query field is required")

    # Step 1: Preprocess / optimize image
    logger.info(f"Received analyze request | query='{request.user_query[:60]}' | model={request.model}")

    optimized_b64, img_meta = vision.preprocess_image(request.image)
    logger.debug(f"Image preprocessed: {img_meta}")

    # Step 2: Build data URL for OpenAI
    data_url = vision.build_data_url(optimized_b64)

    # Step 3: Call GPT-4o
    try:
        response = await openai.analyze(
            data_url   = data_url,
            user_query = request.user_query,
            memory     = request.memory,
            model      = request.model
        )
    except Exception as e:
        logger.error(f"OpenAI error: {e}", exc_info=True)
        raise HTTPException(status_code=502, detail=f"AI service error: {str(e)}")

    logger.info(f"Response generated | latency={response.latency_ms}ms | guidance='{response.guidance[:80]}'")

    return response


# ── GET /analyze/health ───────────────────────────────────────────────────────

@router.get("/health")
async def health_check():
    """Simple health check for the analyze route."""
    return {"status": "ok", "route": "/analyze"}
