import os

RODUCT_NAME = os.environ.get('PRODUCT_NAME', 'AiTube')


TEXT_MODEL = os.environ.get('HF_TEXT_MODEL',
    #'HuggingFaceH4/zephyr-7b-beta'
    'HuggingFaceTB/SmolLM2-1.7B-Instruct'
)

IMAGE_MODEL = os.environ.get('HF_IMAGE_MODEL', '')


VIDEO_ROUND_ROBIN_ENDPOINT_URLS = [
    os.environ.get('VIDEO_ROUND_ROBIN_SERVER_1', ''),
    os.environ.get('VIDEO_ROUND_ROBIN_SERVER_2', ''),
    os.environ.get('VIDEO_ROUND_ROBIN_SERVER_3', ''),
    os.environ.get('VIDEO_ROUND_ROBIN_SERVER_4', ''),
]

HF_TOKEN = os.environ.get('HF_TOKEN')

# use the same secret token as you used to secure your BASE_SPACE_NAME spaces
SECRET_TOKEN = os.environ.get('SECRET_TOKEN')
