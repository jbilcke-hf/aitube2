
(note: this is not a documentation - there is currently no documentation for AiTube since the project is in an early experimental state).

### Seting up the Python virtual environment

```bash
python3 -m venv .python_venv
source .python_venv/bin/activate
python3 -m pip install --no-cache-dir --upgrade -r requirements.txt 
```

### Running the API server

```bash
# load the environment
# (if you haven't done it already for this shell session)
source .python_venv/bin/activate

NUM_SPACES="2" BASE_SPACE_NAME="YOUR_OWN_ACCOUNT/ai-tube-model-ltxv" HF_TOKEN="YOUR OWN TOKEN" SECRET_TOKEN="YOUR OWN SECRET" python3 api.py
```

### Run the client (web)

```bash
flutter run -d chrome
```

