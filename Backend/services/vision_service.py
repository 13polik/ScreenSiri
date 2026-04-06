import base64
from io import BytesIO
from PIL import Image
import os

# ── VisionService ────────────────────────────────────────────────────────────
# Optional preprocessing layer before sending to GPT-4o.
# Current implementation:
#   - Validates and optimizes images (resize, re-compress)
#   - Future: Gemini Flash for cheap fast pre-analysis
#             to extract structured context before GPT reasoning

class VisionService:

    MAX_DIMENSION = 1536      # GPT-4o handles up to 2048, we stay safe
    JPEG_QUALITY  = 75

    def preprocess_image(self, base64_image: str) -> tuple[str, dict]:
        """
        Decodes, resizes if needed, and re-encodes the image.
        Returns (optimized_base64, metadata_dict).
        """
        try:
            # Decode
            img_data = base64.b64decode(base64_image)
            img = Image.open(BytesIO(img_data)).convert("RGB")
            original_size = img.size

            # Resize if too large
            img = self._resize_if_needed(img)
            final_size = img.size

            # Re-encode
            buffer = BytesIO()
            img.save(buffer, format="JPEG", quality=self.JPEG_QUALITY, optimize=True)
            optimized_b64 = base64.b64encode(buffer.getvalue()).decode("utf-8")

            metadata = {
                "original_size": original_size,
                "final_size":    final_size,
                "size_bytes":    len(buffer.getvalue()),
            }

            return optimized_b64, metadata

        except Exception as e:
            # If preprocessing fails, return original unchanged
            return base64_image, {"error": str(e)}

    def _resize_if_needed(self, img: Image.Image) -> Image.Image:
        w, h = img.size
        if w <= self.MAX_DIMENSION and h <= self.MAX_DIMENSION:
            return img
        ratio = min(self.MAX_DIMENSION / w, self.MAX_DIMENSION / h)
        new_size = (int(w * ratio), int(h * ratio))
        return img.resize(new_size, Image.LANCZOS)

    def build_data_url(self, base64_image: str) -> str:
        return f"data:image/jpeg;base64,{base64_image}"


# ── Gemini Pre-Processor (Future / Advanced Pipeline) ───────────────────────
# Uncomment and configure to enable the dual-AI pipeline:
#   Gemini Flash → fast context extraction
#   GPT-4o       → reasoning + guidance

# import google.generativeai as genai
#
# class GeminiPreProcessor:
#     def __init__(self):
#         genai.configure(api_key=os.getenv("GEMINI_API_KEY"))
#         self.model = genai.GenerativeModel("gemini-1.5-flash")
#
#     async def extract_context(self, base64_image: str) -> str:
#         """Quick pass to extract UI elements and app context."""
#         prompt = """
#         Look at this iPhone screenshot and extract:
#         1. App name (if visible)
#         2. Main UI elements visible
#         3. Current screen/page type
#         4. Key text content
#         Respond in 2-3 sentences. Be specific and concise.
#         """
#         img_data = base64.b64decode(base64_image)
#         response = self.model.generate_content([
#             {"mime_type": "image/jpeg", "data": img_data},
#             prompt
#         ])
#         return response.text
