import os

# Configuration
#DEFAULT_TEXT_MODEL ='Qwen/Qwen2.5-Coder-32B-Instruct'

# smaller model
# 10s per request + glitches 
DEFAULT_TEXT_MODEL = 'HuggingFaceH4/zephyr-7b-beta'

# qwen2-vl-7b-instruct on a dedicated TGI
# 12s per request + glitches 
#DEFAULT_TEXT_MODEL = 'https://nd6os5jddi09tkwc.us-east-1.aws.endpoints.huggingface.cloud'

# zephyr-7b-beta on a dedicated TGI
# 30s per request
#DEFAULT_TEXT_MODEL = 'https://gfu53amfunrrbihl.us-east-1.aws.endpoints.huggingface.cloud'

#DEFAULT_IMAGE_MODEL = 'black-forest-labs/FLUX.1-schnell'
DEFAULT_IMAGE_MODEL = 'https://cud1ku2k9e6gxo6d.us-east-1.aws.endpoints.huggingface.cloud'

TEXT_MODEL = os.environ.get('HF_TEXT_MODEL', DEFAULT_TEXT_MODEL)

IMAGE_MODEL = os.environ.get('HF_IMAGE_MODEL', DEFAULT_IMAGE_MODEL)

# make sure this matches the number of servers you have!
# 2 spaces are enough for 1 user, provided low settings
NUM_SPACES = int(os.environ.get('NUM_SPACES', '4'))

# the prefix to use for the spaces
# this will be something like YOUR_USERNAME/YOUR_SPACE
#
# the base space you can use is a fork of:
# https://huggingface.co/spaces/jbilcke-hf/ai-tube-model-ltxv-1/tree/main?duplicate=true
BASE_SPACE_NAME = os.environ.get('BASE_SPACE_NAME')

HF_TOKEN = os.environ.get('HF_TOKEN')

# use the same secret token as you used to secure your BASE_SPACE_NAME spaces
SECRET_TOKEN = os.environ.get('SECRET_TOKEN')
