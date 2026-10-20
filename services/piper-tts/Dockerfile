FROM python:3.12-slim

RUN pip install --no-cache-dir piper-tts==1.3.0 soxr==0.5.0.post1 numpy

# The voice is baked into the image: it is small (~60 MB) and the server then
# starts without network access. Change it via PIPER_VOICE in scripts/piper-tts.env.
ARG PIPER_VOICE=pl_PL-mc_speech-medium
ARG PIPER_VOICE_URL=https://huggingface.co/rhasspy/piper-voices/resolve/main/pl/pl_PL/mc_speech/medium
ADD ${PIPER_VOICE_URL}/${PIPER_VOICE}.onnx /voices/voice.onnx
ADD ${PIPER_VOICE_URL}/${PIPER_VOICE}.onnx.json /voices/voice.onnx.json

COPY server.py /app/server.py

ENV PIPER_VOICE_PATH=/voices/voice.onnx \
    PIPER_VOICE_NAME=${PIPER_VOICE} \
    PORT=8000 \
    PYTHONUNBUFFERED=1

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"

CMD ["python", "/app/server.py"]
