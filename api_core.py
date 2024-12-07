import logging
import os
import io
import re
import base64
import uuid
from typing import Dict, Any, Optional, List
from dataclasses import dataclass
from asyncio import Lock, Queue
import asyncio
import time
import datetime
from contextlib import asynccontextmanager
from collections import defaultdict
from aiohttp import web, ClientSession
from huggingface_hub import InferenceClient
from gradio_client import Client
import random
import yaml

from api_config import DEFAULT_TEXT_MODEL, DEFAULT_IMAGE_MODEL, TEXT_MODEL, IMAGE_MODEL, NUM_SPACES, BASE_SPACE_NAME, HF_TOKEN, SECRET_TOKEN

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def generate_seed():
    """Generate a random positive 32-bit integer seed."""
    return random.randint(0, 2**32 - 1)

def sanitize_yaml_response(response_text: str) -> str:
    """
    Sanitize and format AI response into valid YAML.
    Returns properly formatted YAML string.
    """
    # Remove any markdown code block indicators and YAML document markers
    clean_text = re.sub(r'```yaml|```|---|\.\.\.$', '', response_text.strip())
    
    # Split into lines and process each line
    lines = clean_text.split('\n')
    sanitized_lines = []
    current_field = None
    
    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue
            
        # Handle field starts
        if stripped.startswith('title:') or stripped.startswith('description:'):
            # Ensure proper YAML format with space after colon and proper quoting
            field_name = stripped.split(':', 1)[0]
            field_value = stripped.split(':', 1)[1].strip().strip('"\'')
            
            # Quote the value if it contains special characters
            if any(c in field_value for c in ':[]{},&*#?|-<>=!%@`'):
                field_value = f'"{field_value}"'
                
            sanitized_lines.append(f"{field_name}: {field_value}")
            current_field = field_name
            
        elif stripped.startswith('tags:'):
            sanitized_lines.append('tags:')
            current_field = 'tags'
            
        elif stripped.startswith('-') and current_field == 'tags':
            # Process tag values
            tag = stripped[1:].strip().strip('"\'')
            if tag:
                # Clean and format tag
                tag = re.sub(r'[^\x00-\x7F]+', '', tag)  # Remove non-ASCII
                tag = re.sub(r'[^a-zA-Z0-9\s-]', '', tag)  # Keep only alphanumeric and hyphen
                tag = tag.strip().lower().replace(' ', '-')
                if tag:
                    sanitized_lines.append(f"  - {tag}")
                    
        elif current_field in ['title', 'description']:
            # Handle multi-line title/description continuation
            value = stripped.strip('"\'')
            if value:
                # Append to previous line
                prev = sanitized_lines[-1]
                sanitized_lines[-1] = f"{prev} {value}"
    
    # Ensure the YAML has all required fields
    required_fields = {'title', 'description', 'tags'}
    found_fields = {line.split(':')[0].strip() for line in sanitized_lines if ':' in line}
    
    for field in required_fields - found_fields:
        if field == 'tags':
            sanitized_lines.extend(['tags:', '  - default'])
        else:
            sanitized_lines.append(f'{field}: "No {field} provided"')
    
    return '\n'.join(sanitized_lines)

@dataclass
class Space:
    id: int
    url: str
    client: Client
    busy: bool = False
    last_used: float = 0

class SpaceManager:
    def __init__(self):
        self.spaces: List[Space] = []
        self.lock = Lock()
        self.space_queue: Queue[Space] = Queue()
        self.initialize_spaces()

    def initialize_spaces(self):
        """Initialize the list of spaces"""
        for i in range(NUM_SPACES):
            space_id = i + 1
            space_url = f"https://jbilcke-hf-ai-tube-model-ltxv-{space_id}.hf.space"
            client = Client(f"{BASE_SPACE_NAME}-{space_id}")
            space = Space(id=space_id, url=space_url, client=client)
            self.spaces.append(space)
            self.space_queue.put_nowait(space)

    @asynccontextmanager
    async def get_space(self, max_wait_time: int = 45):
        """Get the next available space using a context manager"""
        start_time = time.time()
        space = None
        
        try:
            while True:
                if time.time() - start_time > max_wait_time:
                    raise TimeoutError(f"Could not acquire a space within {max_wait_time} seconds")

                try:
                    space = self.space_queue.get_nowait()
                    async with self.lock:
                        if not space.busy:
                            space.busy = True
                            space.last_used = time.time()
                            break
                        else:
                            await self.space_queue.put(space)
                except asyncio.QueueEmpty:
                    await asyncio.sleep(0.5)
                    continue

            yield space

        finally:
            if space:
                async with self.lock:
                    space.busy = False
                    space.last_used = time.time()
                    await self.space_queue.put(space)

class ChatRoom:
    def __init__(self):
        self.messages = []
        self.connected_clients = set()
        self.max_history = 100

    def add_message(self, message):
        self.messages.append(message)
        if len(self.messages) > self.max_history:
            self.messages.pop(0)

    def get_recent_messages(self, limit=50):
        return self.messages[-limit:]

class VideoGenerationAPI:
    def __init__(self):
        self.inference_client = InferenceClient(token=HF_TOKEN)
        self.space_manager = SpaceManager()
        self.active_requests: Dict[str, asyncio.Future] = {}
        self.chat_rooms = defaultdict(ChatRoom)
        self.video_events: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
        self.event_history_limit = 50


    def _add_event(self, video_id: str, event: Dict[str, Any]):
        """Add an event to the video's history and maintain the size limit"""
        events = self.video_events[video_id]
        events.append(event)
        if len(events) > self.event_history_limit:
            events.pop(0)

    async def download_video(self, url: str) -> bytes:
        """Download video file from URL and return bytes"""
        async with ClientSession() as session:
            async with session.get(url) as response:
                if response.status != 200:
                    raise Exception(f"Failed to download video: HTTP {response.status}")
                return await response.read()

    async def search_video(self, query: str, search_count: int = 0, attempt_count: int = 0) -> Optional[dict]:
        """Generate a single search result using HF text generation"""
        prompt = f"""[Search Query #{search_count}, Attempt #{attempt_count}] Generate a video search result object for the query: "{query}"
    The YAML response object include a title, description, and tags, consistent with what we can find on a video sharing platform.
    Format the result as a YAML object with only those fields: "title" (single string of a short sentence), "description" (single string of a few sentences to describe the visuals), and "tags" (array of strings). Do not add any other field.
    The description is a prompt for a generative AI, so please describe the visual elements of the scene in details, including: camera angle and focus, people's appearance, age, look, costumes, clothes, the location visual characteristics and geometry, lighting, action, objects, weather, textures, lighting.
    Make the result unique and different from previous search results. ONLY RETURN YAML AND WITH ENGLISH CONTENT, NOT CHINESE - DO NOT ADD ANY OTHER COMMENT!"""

        try:
            response = await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: self.inference_client.text_generation(
                    prompt,
                    model=TEXT_MODEL,
                    max_new_tokens=300,
                    temperature=0.65
                )
            )

            response_text = re.sub(r'^\s*\.\s*\n', '', response.strip())
            sanitized_yaml = sanitize_yaml_response(response_text)
            
            try:
                result = yaml.safe_load(sanitized_yaml)
            except yaml.YAMLError as e:
                logger.error(f"YAML parsing failed: {str(e)}")
                result = None
            
            if not result or not isinstance(result, dict):
                logger.error(f"Invalid result format: {result}")
                return None

            # Extract fields with defaults
            title = str(result.get('title', '')).strip() or 'Untitled Video'
            description = str(result.get('description', '')).strip() or 'No description available'
            tags = result.get('tags', [])
            
            # Ensure tags is a list of strings
            if not isinstance(tags, list):
                tags = []
            tags = [str(t).strip() for t in tags if t and isinstance(t, (str, int, float))]

            # Generate thumbnail
            try:
                thumbnail = await self.generate_thumbnail(title, description)
            except Exception as e:
                logger.error(f"Thumbnail generation failed: {str(e)}")
                thumbnail = ""

            # Return valid result with all required fields
            return {
                'id': str(uuid.uuid4()),
                'title': title,
                'description': description,
                'thumbnailUrl': thumbnail,
                'videoUrl': '',
                'isLatent': True,
                'useFixedSeed': "webcam" in description.lower(),
                'seed': generate_seed(),
                'views': 0,
                'tags': tags
            }

        except Exception as e:
            logger.error(f"Search video generation failed: {str(e)}")
            return None

    async def generate_thumbnail(self, title: str, description: str) -> str:
        """Generate thumbnail using HF image generation"""
        try:
            image_prompt = f"Thumbnail for video titled '{title}': {description}"
            
            image = await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: self.inference_client.text_to_image(
                    prompt=image_prompt,
                    model=IMAGE_MODEL,
                    width=1024,
                    height=512
                )
            )

            buffered = io.BytesIO()
            image.save(buffered, format="JPEG")
            img_str = base64.b64encode(buffered.getvalue()).decode()
            return f"data:image/jpeg;base64,{img_str}"
        except Exception as e:
            logger.error(f"Error generating thumbnail: {str(e)}")
            return ""

    async def generate_caption(self, title: str, description: str) -> str:
        """Generate detailed caption using HF text generation"""
        try:
            prompt = f"""Generate a detailed story for a video named: "{title}"
Visual description of the video: {description}.
Instructions: Write the story summary, including the plot, action, what should happen.
Make it around 200-300 words long.
A video can be anything from a tutorial, webcam, trailer, movie, live stream etc."""

            response = await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: self.inference_client.text_generation(
                    prompt,
                    model=TEXT_MODEL,
                    max_new_tokens=180,
                    temperature=0.7
                )
            )
     
            if "Caption: " in response:
                response = response.replace("Caption: ", "")
            
            chunks = f" {response} ".split(". ")
            if len(chunks) > 1:
                text = ". ".join(chunks[:-1])
            else:
                text = response

            return text.strip()
        except Exception as e:
            logger.error(f"Error generating caption: {str(e)}")
            return ""


    async def _generate_clip_prompt(self, video_id: str, title: str, description: str) -> str:
        """Generate a new prompt for the next clip based on event history"""
        events = self.video_events.get(video_id, [])
        events_json = "\n".join(json.dumps(event) for event in events)
        
        prompt = f"""# Context and task
Please write the caption for a new clip.

# Instructions
1. Consider the video context and recent events
2. Create a natural progression from previous clips
3. Take into account user suggestions (chat messages) into the scene
4. Don't generate hateful, political, violent or sexual content
5. Keep visual consistency with previous clips (in most cases you should repeat the same exact description of the location, characters etc but only change a few elements. If this is a webcam scenario, don't touch the camera orientation or focus)
6. Return ONLY the caption text, no additional formatting or explanation
7. Write in English, about 200 words.
8. Your caption must describe visual elements of the scene in details, including: camera angle and focus, people's appearance, age, look, costumes, clothes, the location visual characteristics and geometry, lighting, action, objects, weather, textures, lighting.

# Examples
Here is a demo scenario, with fake data:
{{"time": "2024-11-29T13:36:15Z", "event": "new_stream_clip", "caption": "webcam view of a beautiful park, squirrels are playing in the lush grass, blablabla etc... (rest omitted for brevity)"}}
{{"time": "2024-11-29T13:36:20Z", "event": "new_chat_message", "username": "MonkeyLover89", "data": "hi"}}
{{"time": "2024-11-29T13:36:25Z", "event": "new_chat_message", "username": "MonkeyLover89", "data": "more squirrels plz"}}
{{"time": "2024-11-29T13:36:26Z", "event": "new_stream_clip", "caption": "webcam view of a beautiful park, a lot of squirrels are playing in the lush grass, blablabla etc... (rest omitted for brevity)"}}

# Real scenario and data

We are inside a video titled "{title}"
The video is described by: "{description}".
Here is a summary of the {len(events)} most recent events:
{events_json}

# Your response
Your caption:"""

        try:
            response = await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: self.inference_client.text_generation(
                    prompt,
                    model=TEXT_MODEL,
                    max_new_tokens=200,
                    temperature=0.7
                )
            )
            
            # Clean up the response
            caption = response.strip()
            if caption.lower().startswith("caption:"):
                caption = caption[8:].strip()
                
            return caption
            
        except Exception as e:
            logger.error(f"Error generating clip prompt: {str(e)}")
            # Fallback to original description if prompt generation fails
            return description

    async def generate_video(self, title: str, description: str, video_prompt_prefix: str, options: dict) -> str:
        """Generate video using available space from pool"""
        video_id = options.get('video_id', str(uuid.uuid4()))
        
        # Generate a new prompt based on event history
        #clip_caption = await self._generate_clip_prompt(video_id, title, description)
        clip_caption = f"{video_prompt_prefix} - {title.strip()} - {description.strip()}"

        # Add the new clip to event history
        self._add_event(video_id, {
            "time": datetime.datetime.utcnow().isoformat() + "Z",
            "event": "new_stream_clip",
            "caption": clip_caption
        })

        # Use the generated caption as the prompt
        prompt = f"{clip_caption}, high quality, cinematic, 4K, intricate details"
        
        params = {
            "secret_token": SECRET_TOKEN,
            "prompt": prompt,
            "enhance_prompt_toggle": options.get('enhance_prompt', False),
            "negative_prompt": options.get('negative_prompt', 'low quality, worst quality, deformed, distorted, disfigured, blurry, text, watermark'),
            "frame_rate": options.get('frame_rate', 25),
            "seed": options.get('seed', 42),
            "num_inference_steps": options.get('num_inference_steps', 12),
            "guidance_scale": options.get('guidance_scale', 3.3),
            "height": options.get('height', 416),
            "width": options.get('width', 640),
            "num_frames": options.get('num_frames', 153),
        }

        async with self.space_manager.get_space() as space:
            logger.info(f"Using space {space.id} for video generation with prompt: {prompt}")
            result = await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: space.client.predict(
                    **params,
                    api_name="/generate_video_from_text"
                )
            )
            return result

    async def handle_chat_message(self, data: dict, ws: web.WebSocketResponse) -> dict:
        """Process and broadcast a chat message"""
        video_id = data.get('videoId')
        request_id = data.get('requestId')
        
        if not video_id:
            return {
                'action': 'chat_message',
                'requestId': request_id,
                'success': False,
                'error': 'No video ID provided'
            }

        # Add chat message to event history
        self._add_event(video_id, {
            "time": datetime.datetime.utcnow().isoformat() + "Z",
            "event": "new_chat_message",
            "username": data.get('username', 'Anonymous'),
            "data": data.get('content', '')
        })

        room = self.chat_rooms[video_id]
        message_data = {k: v for k, v in data.items() if k != '_ws'}
        room.add_message(message_data)
        
        for client in room.connected_clients:
            if client != ws:
                try:
                    await client.send_json({
                        'action': 'chat_message',
                        'broadcast': True,
                        **message_data
                    })
                except Exception as e:
                    logger.error(f"Failed to broadcast to client: {e}")
                    room.connected_clients.remove(client)
        
        return {
            'action': 'chat_message',
            'requestId': request_id,
            'success': True,
            'message': message_data
        }

    async def handle_join_chat(self, data: dict, ws: web.WebSocketResponse) -> dict:
        """Handle a request to join a chat room"""
        video_id = data.get('videoId')
        request_id = data.get('requestId')
        
        if not video_id:
            return {
                'action': 'join_chat',
                'requestId': request_id,
                'success': False,
                'error': 'No video ID provided'
            }

        room = self.chat_rooms[video_id]
        room.connected_clients.add(ws)
        recent_messages = room.get_recent_messages()
        
        return {
            'action': 'join_chat',
            'requestId': request_id,
            'success': True,
            'messages': recent_messages
        }

    async def handle_leave_chat(self, data: dict, ws: web.WebSocketResponse) -> dict:
        """Handle a request to leave a chat room"""
        video_id = data.get('videoId')
        request_id = data.get('requestId')
        
        if not video_id:
            return {
                'action': 'leave_chat',
                'requestId': request_id,
                'success': False,
                'error': 'No video ID provided'
            }

        room = self.chat_rooms[video_id]
        if ws in room.connected_clients:
            room.connected_clients.remove(ws)
        
        return {
            'action': 'leave_chat',
            'requestId': request_id,
            'success': True
        }