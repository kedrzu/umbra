"""Piper TTS behind an OpenAI-compatible `/v1/audio/speech` endpoint.

Paseo's local TTS only ships an English voice, but its `openai` speech provider
accepts a custom base URL. This server fills that slot with a Piper voice, so
Paseo talks to it exactly as it would to OpenAI.

Paseo hard-codes the OpenAI names (model `tts-1`/`tts-1-hd`, voices `alloy`,
`echo`, ...), so the requested model and voice are accepted and ignored: every
request is spoken with the one configured Piper voice.

`response_format: "pcm"` follows the OpenAI contract - raw 24 kHz, 16-bit,
mono, little-endian - because Paseo plays a bare `pcm` stream at 24 kHz. Piper
voices run at 22.05 kHz (medium) or 16 kHz (low), so audio is resampled.
"""

import ctypes
import gc
import io
import json
import logging
import os
import re
import threading
import time
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import numpy as np
import soxr
from piper import PiperVoice, SynthesisConfig

VOICE_PATH = os.environ.get("PIPER_VOICE_PATH", "/voices/voice.onnx")
VOICE_NAME = os.environ.get("PIPER_VOICE_NAME", "piper")
PORT = int(os.environ.get("PORT", "8000"))
# Piper's length_scale: >1 is slower, <1 is faster. OpenAI's `speed` divides it.
LENGTH_SCALE = float(os.environ.get("PIPER_LENGTH_SCALE", "1.0"))
# The voice is unloaded after this many idle seconds (0 = keep it loaded),
# mirroring Paseo's own local speech worker. Reloading takes well under a second.
IDLE_UNLOAD_SECONDS = int(os.environ.get("PIPER_IDLE_UNLOAD_SECONDS", "300"))
# OpenAI's pcm format is fixed at 24 kHz; wav keeps the same rate for simplicity.
OUTPUT_RATE = 24000
MAX_INPUT_CHARS = 4096

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("piper-tts")

with open(VOICE_PATH + ".json") as f:
    VOICE_RATE = json.load(f)["audio"]["sample_rate"]


def release_freed_memory():
    """glibc keeps freed heap pages; hand them back so the container shrinks."""
    try:
        ctypes.CDLL("libc.so.6").malloc_trim(0)
    except OSError:
        pass


class VoiceHolder:
    """Loads the voice on first use and drops it after IDLE_UNLOAD_SECONDS."""

    def __init__(self):
        self.lock = threading.Lock()
        self.voice = None
        self.in_use = 0
        self.last_used = time.monotonic()
        if IDLE_UNLOAD_SECONDS > 0:
            threading.Thread(target=self.reap, daemon=True).start()

    def acquire(self):
        with self.lock:
            if self.voice is None:
                started = time.monotonic()
                self.voice = PiperVoice.load(VOICE_PATH)
                log.info("Loaded %s in %.2fs", VOICE_NAME, time.monotonic() - started)
            self.in_use += 1
            return self.voice

    def release(self):
        with self.lock:
            self.in_use -= 1
            self.last_used = time.monotonic()

    def reap(self):
        while True:
            time.sleep(15)
            with self.lock:
                idle = time.monotonic() - self.last_used
                if self.voice is not None and self.in_use == 0 and idle >= IDLE_UNLOAD_SECONDS:
                    self.voice = None
                    gc.collect()
                    release_freed_memory()
                    log.info("Unloaded %s after %ds idle", VOICE_NAME, int(idle))


voices = VoiceHolder()

# Markdown that Piper would otherwise read out loud ("gwiazdka", "krzyżyk").
MARKDOWN_NOISE = [
    (re.compile(r"```.*?```", re.S), " "),
    (re.compile(r"`([^`]*)`"), r"\1"),
    (re.compile(r"!\[([^\]]*)\]\([^)]*\)"), r"\1"),
    (re.compile(r"\[([^\]]*)\]\([^)]*\)"), r"\1"),
    (re.compile(r"^\s{0,3}#{1,6}\s*", re.M), ""),
    (re.compile(r"^\s*[-*+]\s+", re.M), ""),
    (re.compile(r"(\*\*|__|\*|_|~~)"), ""),
    (re.compile(r"\|"), " "),
]


def clean(text):
    for pattern, replacement in MARKDOWN_NOISE:
        text = pattern.sub(replacement, text)
    return re.sub(r"[ \t]+", " ", text).strip()


def synthesize(text, speed):
    """Yield 24 kHz int16 PCM chunks, one per sentence, as Piper produces them."""
    config = SynthesisConfig(length_scale=LENGTH_SCALE / speed)
    resampler = None
    if VOICE_RATE != OUTPUT_RATE:
        resampler = soxr.ResampleStream(VOICE_RATE, OUTPUT_RATE, 1, dtype="int16")
    voice = voices.acquire()
    try:
        for chunk in voice.synthesize(text, syn_config=config):
            samples = np.frombuffer(chunk.audio_int16_bytes, dtype=np.int16)
            if resampler is not None:
                samples = resampler.resample_chunk(samples)
            if samples.size:
                yield samples.tobytes()
    finally:
        voices.release()
    if resampler is not None:
        tail = resampler.resample_chunk(np.zeros(0, dtype=np.int16), last=True)
        if tail.size:
            yield tail.tobytes()


def to_wav(pcm):
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(OUTPUT_RATE)
        out.writeframes(pcm)
    return buffer.getvalue()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        log.info("%s %s", self.address_string(), fmt % args)

    def send_json(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_error_json(self, status, message):
        self.send_json(status, {"error": {"message": message, "type": "invalid_request_error"}})

    def do_GET(self):
        if self.path == "/health":
            self.send_json(200, {
                "status": "ok",
                "voice": VOICE_NAME,
                "sampleRate": VOICE_RATE,
                "loaded": voices.voice is not None,
            })
        elif self.path == "/v1/models":
            models = [{"id": m, "object": "model", "owned_by": "piper"} for m in ("tts-1", "tts-1-hd")]
            self.send_json(200, {"object": "list", "data": models})
        else:
            self.send_error_json(404, "Not found")

    def do_POST(self):
        if self.path != "/v1/audio/speech":
            self.send_error_json(404, "Not found")
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            request = json.loads(self.rfile.read(length) or b"{}")
        except (ValueError, json.JSONDecodeError):
            self.send_error_json(400, "Body must be JSON")
            return

        text = clean(str(request.get("input", "")))[:MAX_INPUT_CHARS]
        if not text:
            self.send_error_json(400, "`input` is empty")
            return
        response_format = request.get("response_format", "mp3")
        if response_format not in ("pcm", "wav"):
            self.send_error_json(400, f"Unsupported response_format {response_format!r}; use pcm or wav")
            return
        try:
            speed = min(max(float(request.get("speed", 1.0)), 0.25), 4.0)
        except (TypeError, ValueError):
            self.send_error_json(400, "`speed` must be a number")
            return

        log.info("speak %d chars, format=%s, speed=%.2f", len(text), response_format, speed)

        if response_format == "wav":
            body = to_wav(b"".join(synthesize(text, speed)))
            self.send_response(200)
            self.send_header("Content-Type", "audio/wav")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        # Stream pcm sentence by sentence, so a long message starts playing
        # after the first sentence instead of after the whole text.
        self.send_response(200)
        self.send_header("Content-Type", "audio/pcm")
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()
        try:
            for pcm in synthesize(text, speed):
                self.wfile.write(f"{len(pcm):X}\r\n".encode() + pcm + b"\r\n")
                self.wfile.flush()
            self.wfile.write(b"0\r\n\r\n")
        except (BrokenPipeError, ConnectionResetError):
            log.info("client went away mid-stream")


if __name__ == "__main__":
    log.info("Serving %s (%d Hz) on :%d, idle unload after %ds", VOICE_NAME, VOICE_RATE, PORT, IDLE_UNLOAD_SECONDS)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
