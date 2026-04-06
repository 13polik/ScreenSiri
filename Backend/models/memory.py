from pydantic import BaseModel, Field
from typing import Optional, List, Any, Dict
from datetime import datetime


# ── Conversation Turn ────────────────────────────────────────────────────────

class ConversationTurn(BaseModel):
    role: str                          # "user" | "assistant" | "system"
    content: str


# ── Session Memory ───────────────────────────────────────────────────────────

class SessionMemory(BaseModel):
    session_id: Optional[str]             = None
    task: Optional[str]                   = None
    current_step: Optional[str]           = None
    last_screen_summary: Optional[str]    = None
    last_action: Optional[str]            = None
    next_expected_action: Optional[str]   = None
    conversation_history: List[ConversationTurn] = Field(default_factory=list)


# ── Analyze Request (iOS → Backend) ─────────────────────────────────────────

class AnalyzeRequest(BaseModel):
    image: str                             # base64-encoded JPEG
    user_query: str
    memory: SessionMemory                  = Field(default_factory=SessionMemory)
    model: str                             = "gpt-4o"

    class Config:
        json_schema_extra = {
            "example": {
                "image": "<base64 string>",
                "user_query": "What should I tap next?",
                "memory": {
                    "task": "Book a flight",
                    "current_step": "Selecting departure date",
                    "conversation_history": []
                },
                "model": "gpt-4o"
            }
        }


# ── Analyze Response (Backend → iOS) ────────────────────────────────────────

class AnalyzeResponse(BaseModel):
    guidance: str                             # The spoken/displayed response
    screen_summary: Optional[str]             = None
    current_step: Optional[str]               = None
    next_expected_action: Optional[str]       = None
    confidence: Optional[float]               = None
    model_used: str                           = "gpt-4o"
    latency_ms: Optional[int]                 = None
