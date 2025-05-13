# views.py

import google.generativeai as genai
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.parsers import MultiPartParser, JSONParser, FormParser
from .models import ChatHistory
from .serializers import ChatHistorySerializer
from PIL import Image
import io
import json
import os
import base64
import openai
from django.conf import settings
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Configure API keys
gemini_api_key = settings.GEMINI_API_KEY
openrouter_api_key = settings.OPENROUTER_API_KEY

# Configure OpenRouter client
openai.api_key = openrouter_api_key
openai.base_url = "https://openrouter.ai/api/v1"

# Define default HTTP headers as a separate variable
# These will be passed directly in the HTTP request, not in the API call parameters
DEFAULT_HTTP_HEADERS = {
    "HTTP-Referer": "https://eyeconic-chat.example",  # Replace with your site url
    "X-Title": "Eyeconic Chat App",  # App name
}


class ChatBotView(APIView):
    parser_classes = [MultiPartParser, JSONParser, FormParser]

    def post(self, request):
        # Handle both web and mobile requests
        if request.content_type and 'application/json' in request.content_type:
            # Web request with JSON
            try:
                data = json.loads(request.body)
                prompt = data.get('prompt', '')
                image_file = None  # Web image handling would be different
            except json.JSONDecodeError:
                prompt = request.data.get('prompt', '')
                image_file = None
        else:
            # Mobile request with multipart form data
            prompt = request.data.get('prompt', '')
            image_file = request.FILES.get('image')

        if not prompt:
            return Response({"error": "Prompt is required"}, status=400)

        try:
            if image_file:
                # Process image for OpenRouter (convert to base64)
                image_bytes = image_file.read()
                image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
                buffered = io.BytesIO()
                image.save(buffered, format="JPEG")
                img_base64 = base64.b64encode(
                    buffered.getvalue()).decode("utf-8")

                # Use Qwen 2.5 VL model for image processing
                # Set up a session with custom headers
                session = openai.Client(
                    api_key=openrouter_api_key,
                    base_url="https://openrouter.ai/api/v1",
                    default_headers=DEFAULT_HTTP_HEADERS
                )

                response = session.chat.completions.create(
                    # Free version of Qwen with vision capabilities
                    model="qwen/qwen2.5-vl-3b-instruct:free",
                    messages=[
                        {"role": "system", "content": "You are Eyeconic, an AI assistant and advisor. Always introduce yourself as 'I am Eyeconic, your AI assistant and advisor' when asked about your identity. You can analyze images and respond to questions about them."},
                        {"role": "user", "content": [
                            {"type": "text", "text": prompt},
                            {"type": "image_url", "image_url": {
                                "url": f"data:image/jpeg;base64,{img_base64}",
                                "detail": "high"
                            }}
                        ]}]
                )
                result_text = response.choices[0].message.content
            else:
                # Text-only request - use the free Qwen text model
                # Set up a session with custom headers
                session = openai.Client(
                    api_key=openrouter_api_key,
                    base_url="https://openrouter.ai/api/v1",
                    default_headers=DEFAULT_HTTP_HEADERS
                )

                response = session.chat.completions.create(
                    # Free version of Qwen for text responses
                    model="qwen/qwen2.5-vl-3b-instruct:free",
                    messages=[
                        {"role": "system", "content": "You are Eyeconic, an AI assistant and advisor. Always introduce yourself as 'I am Eyeconic, your AI assistant and advisor' when asked about your identity. You can analyze images and respond to questions about them."},
                        {"role": "user", "content": prompt}
                    ]
                )
                # Save to chat history
                result_text = response.choices[0].message.content
            ChatHistory.objects.create(
                prompt=prompt,
                image=image_file if image_file else None,
                response=result_text,
                source="desktop"
            )

            return Response({"response": result_text})
        except Exception as e:
            # Log the detailed error for debugging
            import logging
            logger = logging.getLogger(__name__)
            logger.error(f"Error in ChatBotView: {str(e)}")

            # Return a helpful error response
            return Response(
                {"error": f"Server error: {str(e)}"},
                status=500
            )


class ChatHistoryView(APIView):
    def get(self, request):
        try:
            chats = ChatHistory.objects.all().order_by('-timestamp')
            serializer = ChatHistorySerializer(chats, many=True)
            return Response(serializer.data)
        except Exception as e:
            # Log the detailed error for debugging
            import logging
            logger = logging.getLogger(__name__)
            logger.error(f"Error in ChatHistoryView: {str(e)}")

            # Return a helpful error response
            return Response(
                {"error": f"Server error: {str(e)}"},
                status=500
            )
