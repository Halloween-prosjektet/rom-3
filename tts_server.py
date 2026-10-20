"""Grim's voice server, so Godot only plays finished WAVs.

Voices come from Gemini TTS via OpenRouter (very human, follows style instructions). Without a key or
network it falls back to Piper (offline) with sox effects.

Run: .venv/bin/python tts_server.py <voice.onnx> <port>
POST /synthesize {"text": str, "mood": "calm"|"angry"|"dark"|"inner", "length_scale": float,
                  "pitch": float, "shadow_db": float | null}
  mood       delivery for Gemini: Grim calm/angry, his *dark* parts, the player's inner voice, her scream or crying
  pitch      Piper only: pitch factor for Grim (1.0 = unchanged); missing = plain voice, no effects
  shadow_db  Piper only: volume of the demonic octave-down layer; null = no layer
Finished Gemini lines are kept in voice_cache/ next to this file (shipped with the game), so a line
that was said before, or prerendered with tools/prerender.gd, is instant and costs nothing.
"""

import hashlib
import io
import json
import math
import os
import shutil
import ssl
import subprocess
import sys
import tempfile
import urllib.request
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from piper import PiperVoice, SynthesisConfig

voice = PiperVoice.load(sys.argv[1])
port = int(sys.argv[2])
RUBBERBAND = shutil.which("rubberband")  # optional (apt install rubberband-cli); sox pitch without it
CACHE = Path(__file__).parent / "voice_cache"
CACHE.mkdir(exist_ok=True)


def env(key: str, default: str) -> str:
    """Environment variable, else the game's .env file (same rule as the game)."""
    if os.environ.get(key):
        return os.environ[key]
    dotenv = Path(__file__).parent / ".env"
    for line in dotenv.read_text().splitlines() if dotenv.exists() else []:
        if "=" in line and not line.startswith("#") and line.split("=", 1)[0].strip() == key:
            return line.split("=", 1)[1].strip()
    return default


# python.org's Python on macOS ships without CA certificates; macOS has its own bundle here.
SSL = ssl.create_default_context(cafile="/etc/ssl/cert.pem" if Path("/etc/ssl/cert.pem").exists() else None)
# Own key for the voice, so the game's judge can use another provider (TTS_* falls back to LLM_*).
API_KEY = env("TTS_API_KEY", "") or env("LLM_API_KEY", "")
BASE_URL = env("TTS_BASE_URL", "") or env("LLM_BASE_URL", "https://openrouter.ai/api/v1")
TTS_MODEL = env("TTS_MODEL", "google/gemini-3.8-flash-tts")
TTS_VOICE = env("TTS_VOICE", "Algenib")  # gravelly and deep; also good: Charon, Fenrir
TEMPO = float(env("TTS_TEMPO", "1.15"))  # Gemini talks slowly; this speeds every line up, pitch unchanged
INNER_VOICE = env("TTS_INNER_VOICE", "Leda")  # the player: a girl of about 10 (youngest-sounding voice)
GRIM = ("Les på norsk bokmål med naturlig norsk uttale. Du er Gresskar-Grim, et hundre år gammelt levende "
        "gresskar med menneskestemme: dyp, litt hes og nær mikrofonen. Lekent ondskapsfull og selvsikker, "
        "aldri tegnefilmaktig. Normalt tempo.")
MOODS = {
    "calm": GRIM,
    "angry": GRIM + " Nå er du sint og utålmodig: hardt, kort og truende.",
    "dark": GRIM + " Si dette lavt, sakte og truende, nesten hviskende.",
    "inner": "Les på norsk bokmål med naturlig østnorsk uttale. En jente på rundt 10 år, alene i et stummende "
             "mørkt rom, kjempe redd: skjelvende stemme, småklynker og hvisker, men prøver å "
             "være tøff med små vitser. Lys barnestemme.",
    "cry": "Les på norsk bokmål med naturlig østnorsk uttale. En jente på rundt 10 år som gråter og sutrer i "
           "et stummende mørkt rom: hulker, snufser og klynker, sutrete og gråtkvalt, med pauser for å trekke "
           "pusten mellom hulkene. Ikke lest rolig.",
    "scream": "Skrik av full hals i ren panikk, som en jente på rundt 10 år som faller fritt gjennom luften. "
              "Lange, høye, desperate skrik, ikke lest rolig. Norsk.",
}


def gemini(text: str, mood: str) -> bytes:
    """Speech from Gemini via OpenRouter as a WAV (raises on any failure)."""
    body = {"model": TTS_MODEL, "input": text, "voice": INNER_VOICE if mood in ("inner", "scream", "cry") else TTS_VOICE,
            "response_format": "pcm", "instructions": MOODS.get(mood, GRIM)}
    req = urllib.request.Request(BASE_URL + "/audio/speech", json.dumps(body).encode(),
                                 {"Content-Type": "application/json", "Authorization": "Bearer " + API_KEY})
    with urllib.request.urlopen(req, timeout=20, context=SSL) as res:
        pcm = res.read()
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wav:  # 24 kHz 16-bit mono PCM
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(24000)
        wav.writeframes(pcm)
    return loud(buf.getvalue())


def loud(wav: bytes) -> bytes:
    """A bit faster (same pitch), even and loud: gentle compression, then peaks normalized to -1 dB."""
    return subprocess.run(["sox", "-t", "wav", "-", "-t", "wav", "-", "tempo", "-s", str(TEMPO), "compand", "0.02,0.3", "-60,-60,-30,-15,0,-5", "-3",
                           "gain", "-n", "-1"], input=wav, capture_output=True, check=True).stdout


def synthesize(text: str, length_scale: float) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wav:
        voice.synthesize_wav(text, wav, syn_config=SynthesisConfig(length_scale=length_scale))
    return buf.getvalue()


def add_effects(wav: bytes, pitch: float, shadow_db: float | None) -> bytes:
    cents = 1200 * math.log2(pitch)
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "in.wav"
        src.write_bytes(wav)
        pitch_fx = f"pitch {cents:.0f} "
        if RUBBERBAND and pitch >= 0.7:
            # Formant-preserving shift: a deeper voice that still sounds like a person, not a slowed tape.
            # Lower (the *demonic* parts) stays on sox, which drags the formants down too: a monster.
            deep = Path(tmp) / "deep.wav"
            subprocess.run([RUBBERBAND, "-q", "--fast", "--formant", f"--pitch={cents / 100:.2f}", str(src), str(deep)],
                           capture_output=True, check=True)
            src, pitch_fx = deep, ""
        # A person talking from inside a pumpkin: natural and warm, with a faint hollow ring from a 5 ms
        # echo (like a shell around the voice). Light touch everywhere else so it stays human.
        voice = (f"{pitch_fx}highpass 60 equalizer 120 1q +3 equalizer 2500 1q +2 "
                 "echo 0.9 0.8 5 0.25 compand 0.01,0.2 -60,-60,-30,-20,0,-6 -1")
        if shadow_db is None:
            cmd = f"sox {src} -b 16 -t wav - {voice} gain -n -1"
            return subprocess.run(cmd.split(), capture_output=True, check=True).stdout
        clear = f"|sox {src} -p {voice}"
        # Angry: a darker octave-down layer underneath, kept soft so it never masks words.
        shadow = f"|sox {Path(tmp) / 'in.wav'} -p pitch -1000 lowpass 1400 overdrive 4 reverb 25 gain {shadow_db:.1f}"
        return subprocess.run(
            ["sox", "-m", clear, shadow, "-b", "16", "-t", "wav", "-", "gain", "-n", "-1"],
            capture_output=True, check=True,
        ).stdout


def save(path: Path, data: bytes) -> None:
    """Write via a temp file + rename, flushed to disk, so a power cut never leaves a half-written file."""
    tmp = path.with_suffix(".tmp")
    with open(tmp, "wb") as f:
        f.write(data)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


class Handler(BaseHTTPRequestHandler):
    def do_POST(self) -> None:
        try:
            data = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            # Same text, mood and voice = same audio, so Gemini lines are kept on disk: repeats are instant.
            mood = data.get("mood", "calm")
            voice_name = INNER_VOICE if mood in ("inner", "scream", "cry") else TTS_VOICE
            key = json.dumps([data["text"], mood, TTS_MODEL, voice_name, MOODS.get(mood, GRIM)])
            cached = CACHE / (hashlib.sha1(key.encode()).hexdigest() + ".wav")
            wav = b""
            source = "gemini"
            if cached.exists():
                wav = cached.read_bytes()
                if wav[:4] != b"RIFF":  # corrupted (e.g. zeroed by a power cut): make it again
                    wav = b""
            elif API_KEY:
                try:
                    wav = gemini(data["text"], mood)
                    save(cached, wav)
                except Exception as e:
                    print("Gemini TTS feilet, bruker Piper:", e, flush=True)
            if not wav:  # offline fallback, not cached so Gemini gets another try next time
                source = "piper"
                wav = synthesize(data["text"], float(data.get("length_scale", 1.0)))
                if data.get("pitch") is not None:
                    shadow = data.get("shadow_db")
                    wav = add_effects(wav, float(data["pitch"]), None if shadow is None else float(shadow))
        except Exception as e:  # report instead of dropping the connection
            self.send_error(500, str(e))
            return
        self.send_response(200)
        self.send_header("Content-Type", "audio/wav")
        self.send_header("X-Voice", source)
        self.send_header("Content-Length", str(len(wav)))
        self.end_headers()
        self.wfile.write(wav)

    def log_message(self, *args) -> None:
        pass


ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
