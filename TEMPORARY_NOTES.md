
(note: this is not a documentation - there is currently no documentation for AiTube since the project is in an early experimental state).

### Seting up the Python virtual environment

```bash
python3 -m venv .python_venv
source .python_venv/bin/activate
python3 -m pip install --no-cache-dir --upgrade -r requirements.txt 
```

### Deployment to production

AiTube1 required some complex setup and databases (redis, index files etc) to handle the user database, indexing, mp4 hosting, content flagging, background job execution etc.

In AiTube2 all of those steps are made irrelevant, resulting in a much simpler deployment (you still need dedicated servers and high-end GPUs, but one day the hardware side of things will become faster and cheaper).

```bash
# load the environment
# (if you haven't done it already for this shell session)
source .python_venv/bin/activate

HF_TOKEN="<USE YOUR OWN TOKEN>" \
    SECRET_TOKEN="<USE YOUR OWN TOKEN>" \
    VIDEO_ROUND_ROBIN_SERVER_1="https:/<USE YOUR OWN SERVER>.endpoints.huggingface.cloud" \
    VIDEO_ROUND_ROBIN_SERVER_2="https://<USE YOUR OWN SERVER>.endpoints.huggingface.cloud" \
    VIDEO_ROUND_ROBIN_SERVER_3="https://<USE YOUR OWN SERVER>.endpoints.huggingface.cloud" \
    VIDEO_ROUND_ROBIN_SERVER_4="https://<USE YOUR OWN SERVER>.endpoints.huggingface.cloud" \
    IMAGE_MODEL="https://<USE YOUR OWN SERVER>.endpoints.huggingface.cloud" \
    python3 api.py
```

### Run the client (web)

```bash

flutter run --dart-define=CONFIG_PATH=assets/config/demo.yaml -d chrome
```

