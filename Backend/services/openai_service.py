import os
import time
from openai import AsyncOpenAI
from models.memory import SessionMemory, AnalyzeResponse

# ── OpenAIService ────────────────────────────────────────────────────────────

class OpenAIService:

    SYSTEM_PROMPT = """You are ScreenSiri — a screen-aware AI assistant running on the user's iPhone.

You can see exactly what is on the user's screen right now via the image provided.

Your role:
- Give short, clear, actionable guidance (2-3 sentences MAX for voice output)
- Reference specific elements you can see (buttons, text, menus)
- Remember what the user is trying to accomplish from the session context
- Speak naturally, as if you're right next to the user
- Be direct and specific — the user is in the middle of doing something

Output JSON in this exact format:
{
  "guidance": "<your spoken response — 2-3 sentences max>",
  "screen_summary": "<1 sentence: what app + screen is visible>",
  "current_step": "<what step the user is on, if determinable>",
  "next_expected_action": "<what the user should do next, if clear>"
}
"""

    def __init__(self):
        api_key = os.getenv("OPENAI_API_KEY")
        if not api_key:
            raise RuntimeError("OPENAI_API_KEY environment variable not set.")
        self.client = AsyncOpenAI(api_key=api_key)

    async def analyze(
        self,
        data_url: str,
        user_query: str,
        memory: SessionMemory,
        model: str = "gpt-4o"
    ) -> AnalyzeResponse:

        start = time.time()

        # Build context string from memory
        memory_context = self._build_memory_context(memory)

        # Build messages
        messages = [
            {
                "role":    "system",
                "content": self.SYSTEM_PROMPT + (f"\n\n{memory_context}" if memory_context else "")
            }
        ]

        # Add conversation history (last 6 turns)
        for turn in memory.conversation_history[-6:]:
            messages.append({"role": turn.role, "content": turn.content})

        # Current user message with image
        messages.append({
            "role": "user",
            "content": [
                {
                    "type":      "image_url",
                    "image_url": {"url": data_url, "detail": "high"}
                },
                {
                    "type": "text",
                    "text": user_query
                }
            ]
        })

        # Call GPT-4o
        response = await self.client.chat.completions.create(
            model=model,
            messages=messages,
            max_tokens=400,
            temperature=0.7,
            response_format={"type": "json_object"}
        )

        latency_ms = int((time.time() - start) * 1000)
        raw_content = response.choices[0].message.content or "{}"

        # Parse JSON response
        import json
        try:
            parsed = json.loads(raw_content)
        except json.JSONDecodeError:
            # Fallback: treat raw content as guidance
            parsed = {"guidance": raw_content}

        return AnalyzeResponse(
            guidance              = parsed.get("guidance", raw_content),
            screen_summary        = parsed.get("screen_summary"),
            current_step          = parsed.get("current_step"),
            next_expected_action  = parsed.get("next_expected_action"),
            model_used            = model,
            latency_ms            = latency_ms
        )

    # ── Helpers ───────────────────────────────────────────────────────────────

    def _build_memory_context(self, memory: SessionMemory) -> str:
        parts = []
        if memory.task:
            parts.append(f"User's task: {memory.task}")
        if memory.current_step:
            parts.append(f"Current step: {memory.current_step}")
        if memory.last_screen_summary:
            parts.append(f"Previous screen was: {memory.last_screen_summary}")
        if memory.last_action:
            parts.append(f"Last action: {memory.last_action}")
        if memory.next_expected_action:
            parts.append(f"Expected next: {memory.next_expected_action}")

        if not parts:
            return ""

        return "Session context:\n" + "\n".join(f"- {p}" for p in parts)
