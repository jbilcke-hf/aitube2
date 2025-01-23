import asyncio
import json
import logging
from aiohttp import web, WSMsgType
from typing import Dict, Any
from api_core import VideoGenerationAPI

from api_config import *

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

async def process_generic_request(data: dict, ws: web.WebSocketResponse, api) -> None:
    """Handle general requests that don't fit into specialized queues"""
    try:
        request_id = data.get('requestId')
        action = data.get('action')
        
        def error_response(message: str):
            return {
                'action': action,
                'requestId': request_id,
                'success': False,
                'error': message
            }

        if action == 'heartbeat':
            await ws.send_json({
                'action': 'heartbeat',
                'requestId': request_id,
                'success': True
            })
        
        elif action == 'generate_caption':
            title = data.get('params', {}).get('title')
            description = data.get('params', {}).get('description')
            
            if not title or not description:
                await ws.send_json(error_response('Missing title or description'))
                return
                
            caption = await api.generate_caption(title, description)
            await ws.send_json({
                'action': action,
                'requestId': request_id,
                'success': True,
                'caption': caption
            })
            
        elif action == 'generate_thumbnail':
            title = data.get('params', {}).get('title')
            description = data.get('params', {}).get('description')
            
            if not title or not description:
                await ws.send_json(error_response('Missing title or description'))
                return
                
            thumbnail = await api.generate_thumbnail(title, description)
            await ws.send_json({
                'action': action,
                'requestId': request_id,
                'success': True,
                'thumbnailUrl': thumbnail
            })
            
        else:
            await ws.send_json(error_response(f'Unknown action: {action}'))
            
    except Exception as e:
        logger.error(f"Error processing generic request: {str(e)}")
        try:
            await ws.send_json({
                'action': data.get('action'),
                'requestId': data.get('requestId'),
                'success': False,
                'error': f'Internal server error: {str(e)}'
            })
        except Exception as send_error:
            logger.error(f"Error sending error response: {send_error}")

async def process_search_queue(queue: asyncio.Queue, ws: web.WebSocketResponse, api):
    """Medium priority queue for search operations"""
    while True:
        try:
            data = await queue.get()
            request_id = data.get('requestId')
            query = data.get('query', '').strip()
            search_count = data.get('searchCount', 0)
            attempt_count = data.get('attemptCount', 0)

            logger.info(f"Processing search request: query='{query}', search_count={search_count}, attempt={attempt_count}")

            if not query:
                logger.warning(f"Empty query received in request: {data}")
                result = {
                    'action': 'search',
                    'requestId': request_id,
                    'success': False,
                    'error': 'No search query provided'
                }
            else:
                try:
                    search_result = await api.search_video(
                        query,
                        search_count=search_count,
                        attempt_count=attempt_count
                    )
                    
                    if search_result:
                        logger.info(f"Search successful for query '{query}' (#{search_count})")
                        result = {
                            'action': 'search',
                            'requestId': request_id,
                            'success': True,
                            'result': search_result
                        }
                    else:
                        logger.warning(f"No results found for query '{query}' (#{search_count})")
                        result = {
                            'action': 'search',
                            'requestId': request_id,
                            'success': False,
                            'error': 'No results found'
                        }
                except Exception as e:
                    logger.error(f"Search error for query '{query}' (#{search_count}, attempt {attempt_count}): {str(e)}")
                    result = {
                        'action': 'search',
                        'requestId': request_id,
                        'success': False,
                        'error': f'Search error: {str(e)}'
                    }

            await ws.send_json(result)
            
        except Exception as e:
            logger.error(f"Error in search queue processor: {str(e)}")
            try:
                error_response = {
                    'action': 'search',
                    'requestId': data.get('requestId') if 'data' in locals() else None,
                    'success': False,
                    'error': f'Internal server error: {str(e)}'
                }
                await ws.send_json(error_response)
            except Exception as send_error:
                logger.error(f"Error sending error response: {send_error}")
        finally:
            if 'queue' in locals():
                queue.task_done()

async def process_chat_queue(queue: asyncio.Queue, ws: web.WebSocketResponse):
    """High priority queue for chat operations"""
    while True:
        data = await queue.get()
        try:
            api = ws.app['api']
            if data['action'] == 'join_chat':
                result = await api.handle_join_chat(data, ws)
            elif data['action'] == 'chat_message':
                result = await api.handle_chat_message(data, ws)
            elif data['action'] == 'leave_chat':
                result = await api.handle_leave_chat(data, ws)
            await ws.send_json(result)
        except Exception as e:
            logger.error(f"Error processing chat request: {e}")
            try:
                await ws.send_json({
                    'action': data['action'],
                    'requestId': data.get('requestId'),
                    'success': False,
                    'error': f'Chat error: {str(e)}'
                })
            except Exception as send_error:
                logger.error(f"Error sending error response: {send_error}")
        finally:
            queue.task_done()

async def process_video_queue(queue: asyncio.Queue, ws: web.WebSocketResponse):
    """Process multiple video generation requests in parallel"""
    active_tasks = set()
    MAX_CONCURRENT = len(VIDEO_ROUND_ROBIN_ENDPOINT_URLS)  # Match client's max concurrent generations

    async def process_single_request(data):
        try:
            api = ws.app['api']
            title = data.get('title', '')
            description = data.get('description', '')
            video_prompt_prefix = data.get('video_prompt_prefix', '')
            options = data.get('options', {})

            video_data = await api.generate_video(title, description, video_prompt_prefix, options)
            
            result = {
                'action': 'generate_video',
                'requestId': data.get('requestId'),
                'success': True,
                'video': video_data,
            }
            
            await ws.send_json(result)
            
        except Exception as e:
            logger.error(f"Error processing video request: {e}")
            try:
                await ws.send_json({
                    'action': 'generate_video',
                    'requestId': data.get('requestId'),
                    'success': False,
                    'error': f'Video generation error: {str(e)}'
                })
            except Exception as send_error:
                logger.error(f"Error sending error response: {send_error}")
        finally:
            active_tasks.discard(asyncio.current_task())

    while True:
        # Clean up completed tasks
        active_tasks = {task for task in active_tasks if not task.done()}
        
        # Start new tasks if we have capacity
        while len(active_tasks) < MAX_CONCURRENT:
            try:
                # Use try_get to avoid blocking if queue is empty
                data = await asyncio.wait_for(queue.get(), timeout=0.1)
                
                # Create and start new task
                task = asyncio.create_task(process_single_request(data))
                active_tasks.add(task)
                
            except asyncio.TimeoutError:
                # No items in queue, break inner loop
                break
            except Exception as e:
                logger.error(f"Error creating video generation task: {e}")
                break

        # Wait a short time before checking queue again
        await asyncio.sleep(0.1)

        # Handle any completed tasks' errors
        for task in list(active_tasks):
            if task.done():
                try:
                    await task
                except Exception as e:
                    logger.error(f"Task failed with error: {e}")
                active_tasks.discard(task)

async def websocket_handler(request: web.Request) -> web.WebSocketResponse:
    ws = web.WebSocketResponse(
        max_msg_size=1024*1024*10,  # 10MB max message size
        timeout=30.0  # we want to keep things tight and short
    )
    
    ws.app = request.app
    await ws.prepare(request)
    api = request.app['api']

    # Create separate queues for different request types
    chat_queue = asyncio.Queue()
    video_queue = asyncio.Queue()
    search_queue = asyncio.Queue()
    
    # Start background tasks for handling different request types
    background_tasks = [
        asyncio.create_task(process_chat_queue(chat_queue, ws)),
        asyncio.create_task(process_video_queue(video_queue, ws)),
        asyncio.create_task(process_search_queue(search_queue, ws, api))
    ]

    try:
        async for msg in ws:
            if msg.type == WSMsgType.TEXT:
                try:
                    data = json.loads(msg.data)
                    action = data.get('action')
                    
                    # Route requests to appropriate queues
                    if action in ['join_chat', 'leave_chat', 'chat_message']:
                        await chat_queue.put(data)
                    elif action in ['generate_video']:
                        await video_queue.put(data)
                    elif action == 'search':
                        await search_queue.put(data)
                    else:
                        await process_generic_request(data, ws, api)
                        
                except Exception as e:
                    logger.error(f"Error processing WebSocket message: {str(e)}")
                    await ws.send_json({
                        'action': data.get('action') if 'data' in locals() else 'unknown',
                        'success': False,
                        'error': f'Error processing message: {str(e)}'
                    })
                    
            elif msg.type in (WSMsgType.ERROR, WSMsgType.CLOSE):
                break
                
    finally:
        # Cleanup
        for task in background_tasks:
            task.cancel()
        try:
            await asyncio.gather(*background_tasks, return_exceptions=True)
        except asyncio.CancelledError:
            pass
    
    return ws

async def init_app() -> web.Application:
    app = web.Application(
        client_max_size=1024**2*10  # 10MB max size
    )
    
    # Create API instance
    api = VideoGenerationAPI()
    app['api'] = api
    
    # Add cleanup logic
    async def cleanup_api(app):
        # Add any necessary cleanup for the API
        pass
    
    app.on_shutdown.append(cleanup_api)
    
    # Add routes
    app.router.add_get('/ws', websocket_handler)
    
    return app

if __name__ == '__main__':
    app = asyncio.run(init_app())
    web.run_app(app, host='0.0.0.0', port=8080)