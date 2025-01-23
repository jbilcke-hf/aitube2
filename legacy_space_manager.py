
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
