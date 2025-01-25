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

from api_config import *

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

    response_text = response_text.split("```")[0]

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
class Endpoint:
    id: int
    url: str
    busy: bool = False
    last_used: float = 0

class EndpointManager:
    def __init__(self):
        self.endpoints: List[Endpoint] = []
        self.lock = Lock()
        self.endpoint_queue: Queue[Endpoint] = Queue()
        self.initialize_endpoints()

    def initialize_endpoints(self):
        """Initialize the list of endpoints"""
        for i, url in enumerate(VIDEO_ROUND_ROBIN_ENDPOINT_URLS):
            endpoint = Endpoint(id=i + 1, url=url)
            self.endpoints.append(endpoint)
            self.endpoint_queue.put_nowait(endpoint)

    @asynccontextmanager
    async def get_endpoint(self, max_wait_time: int = 10):
        """Get the next available endpoint using a context manager"""
        start_time = time.time()
        endpoint = None
        
        try:
            while True:
                if time.time() - start_time > max_wait_time:
                    raise TimeoutError(f"Could not acquire an endpoint within {max_wait_time} seconds")

                try:
                    endpoint = self.endpoint_queue.get_nowait()
                    async with self.lock:
                        if not endpoint.busy:
                            endpoint.busy = True
                            endpoint.last_used = time.time()
                            break
                        else:
                            await self.endpoint_queue.put(endpoint)
                except asyncio.QueueEmpty:
                    await asyncio.sleep(0.5)
                    continue

            yield endpoint

        finally:
            if endpoint:
                async with self.lock:
                    endpoint.busy = False
                    endpoint.last_used = time.time()
                    await self.endpoint_queue.put(endpoint)

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
        self.endpoint_manager = EndpointManager()
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
        prompt = f"""# Instruction
Your response MUST be a YAML object containing a title, description, and tags, consistent with what we can find on a video sharing platform.
Format your YAML response with only those fields: "title" (single string of a short sentence), "description" (single string of a few sentences to describe the visuals), and "tags" (array of strings). Do not add any other field.
The description is a prompt for a generative AI, so please describe the visual elements of the scene in details, including: camera angle and focus, people's appearance, their age, actions, precise look, clothing, the location characteristics, lighting, action, objects, weather.
Make the result unique and different from previous search results. ONLY RETURN YAML AND WITH ENGLISH CONTENT, NOT CHINESE - DO NOT ADD ANY OTHER COMMENT!

# Context
This is attempt {attempt_count} at generating search result number {search_count}.

# Input
Describe the video for this theme: "{query}".
Don't forget to repeat singular elements about the characters, location.. in your description.

# Output

```yaml
title: \""""

        try:
            #print(f"search_video(): calling self.inference_client.text_generation({prompt}, model={TEXT_MODEL}, max_new_tokens=300, temperature=0.65)")
            response = await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: self.inference_client.text_generation(
                    prompt,
                    model=TEXT_MODEL,
                    max_new_tokens=300,
                    temperature=0.6
                )
            )

            #print("response: ", response)

            response_text = re.sub(r'^\s*\.\s*\n', '', f"title: \"{response.strip()}")
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
            #print(f"calling self.generate_thumbnail({title}, {description})")
            try:
                #thumbnail = await self.generate_thumbnail(title, description)
                raise ValueError("thumbnail generation is too buggy and slow right now")
            except Exception as e:
                logger.error(f"Thumbnail generation failed: {str(e)}")
                thumbnail = ""

            print("got response thumbnail")
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
        
        json_payload = {
            "inputs": {
                "prompt": prompt,
            },
            "parameters": {

                # ------------------- settings for LTX-Video -----------------------
                
                # this param doesn't exist
                #"enhance_prompt_toggle": options.get('enhance_prompt', False),

                #"negative_prompt": "saturated, highlight, overexposed, highlighted, overlit, shaking, too bright, worst quality, inconsistent motion, blurry, jittery, distorted, cropped, watermarked, watermark, logo, subtitle, subtitles, lowres",
                "negative_prompt": options.get('negative_prompt', 'low quality, worst quality, deformed, distorted, disfigured, blurry, text, watermark'),

                # note about resolution:
                # we cannot use 720 since it cannot be divided by 32
                #
                # for a cinematic look:
                "width": options.get('width', 640),
                "height": options.get('height', 416),

                # this is a hack to fool LTX-Video into believing our input image is an actual video frame with poor encoding quality
                #"input_image_quality": 70,

                # for a vertical video look:
                #"width": 480,
                #"height": 768,

                # LTX-Video requires a frame number divisible by 8, plus one frame
                # note: glitches might appear if you use more than 168 frames
                "num_frames": options.get('num_frames', 153),

                # using 30 steps seems to be enough for most cases, otherwise use 50 for best quality
                # I think using a large number of steps (> 30) might create some overexposure and saturation
                "num_inference_steps": options.get('num_inference_steps', 12),

                # values between 3.0 and 4.0 are nice
                "guidance_scale": options.get('guidance_scale', 3.3),

                "seed": options.get('seed', 42),
            
                # ----------------------------------------------------------------

                # ------------------- settings for Varnish -----------------------
                # This will double the number of frames.
                # You can activate this if you want:
                # - a slow motion effect (in that case use double_num_frames=True and fps=24, 25 or 30)
                # - a HD soap / video game effect (in that case use double_num_frames=True and fps=60)
                "double_num_frames": False, # <- False as we want real-time generation

                # controls the number of frames per second
                # use this in combination with the num_frames and double_num_frames settings to control the duration and "feel" of your video
                # typical values are: 24, 25, 30, 60
                "fps": options.get('frame_rate', 25),

                # upscale the video using Real-ESRGAN.
                # This upscaling algorithm is relatively fast,
                # but might create an uncanny "3D render" or "drawing" effect.
                "super_resolution": False, # <- False as we want real-time generation

                # for cosmetic purposes and get a "cinematic" feel, you can optionally add some film grain.
                # it is not recommended to add film grain if your theme doesn't match (film grain is great for black & white, retro looks)
                # and if you do, adding more than 12% will start to negatively impact file size (video codecs aren't great are compressing film grain)
                # 0% = no grain
                # 10% = a bit of grain
                "grain_amount": 0, # value between 0-100


                # The range of the CRF scale is 0–51, where:
                # 0 is lossless (for 8 bit only, for 10 bit use -qp 0)
                # 23 is the default
                # 51 is worst quality possible
                # A lower value generally leads to higher quality, and a subjectively sane range is 17–28.
                # Consider 17 or 18 to be visually lossless or nearly so;
                # it should look the same or nearly the same as the input but it isn't technically lossless.
                # The range is exponential, so increasing the CRF value +6 results in roughly half the bitrate / file size, while -6 leads to roughly twice the bitrate.
                #"quality": 18,

            }
        }

        async with self.endpoint_manager.get_endpoint() as endpoint:
            #logger.info(f"Using endpoint {endpoint.id} for video generation with prompt: {prompt}")
            
            async with ClientSession() as session:
                async with session.post(
                    endpoint.url,
                    headers={
                        "Accept": "application/json",
                        "Authorization": f"Bearer {HF_TOKEN}",
                        "Content-Type": "application/json"
                    },
                    json=json_payload
                ) as response:
                    if response.status != 200:
                        error_text = await response.text()
                        raise Exception(f"Video generation failed: HTTP {response.status} - {error_text}")
                    
                    result = await response.json()
                    
                    if "error" in result:
                        raise Exception(f"Video generation failed: {result['error']}")
                    
                    video_data_uri = result.get("video")
                    if not video_data_uri:
                        raise Exception("No video data in response")
                    
                    return video_data_uri


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