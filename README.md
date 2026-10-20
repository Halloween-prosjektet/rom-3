# Rom 3 – Gresskar-Grim

Talestyrt Halloween-spill i Godot 4 som kjører på en Raspberry Pi.
Spilleren faller ned i mørket og møter Gresskar-Grim, et gretten gresskar som vokter veien til printeren.
For å slippe forbi må spilleren klare en quiz, sant-eller-usant og gåter, og alt besvares muntlig.

## Slik virker det

- **Tale til tekst:** spilleren holder inne en knapp og snakker. [whisper.cpp](https://github.com/ggerganov/whisper.cpp) kjører lokalt som server med en norsk NB-Whisper-modell.
- **Vurdering:** svaret sendes til en LLM (OpenAI-kompatibelt API, standard `openai/gpt-oss-20b` på Groq). LLM-en svarer i rollen som Grim, og svaret starter med `[RIKTIG]`, `[FEIL]` eller `[ANNET]`.
- **Stemme:** `tts_server.py` lager Grims stemme med Gemini TTS via OpenRouter. Uten nett brukes Piper (offline) med sox-effekter. Ferdige replikker lagres i `voice_cache/`.
- **Kontrollrom:** spillet er rom 3 og bruker [control-room-klienten](https://github.com/Halloween-prosjektet/control-room) (git submodule i `addons/control_room_client/`). Spillet sender `start_game()` når spilleren starter, og `finish_game()` når spilleren vinner. Se seksjonen «Kontrollrom» nederst i `main.gd`. Pi-en må være på WiFi-et **BakkaIM** for å nå serveren.

## Filer

| Fil | Hva |
| --- | --- |
| `main.gd` | Hele spillet: flyt, quiz, gåter, sinne-måler, animasjon og lyd |
| `tts_server.py` | Stemmeserver (Gemini TTS, med Piper som reserve) |
| `keys.py` | Leser tastetrykk rett fra `/dev/input` på Pi-en (snakkeknappen) |
| `start.sh` | Starter spillet i fullskjerm på Pi-en |
| `tools/prerender.gd` | Lager alle faste replikker på forhånd i `voice_cache/` |
| `tests/` | Tester |
| `art/`, `sfx/`, `fonts/` | Grafikk (Aseprite), lyd og font |

## Oppsett

Hent prosjektet med tillegget:

```sh
git clone --recurse-submodules https://github.com/Halloween-prosjektet/rom-3.git
```

Har du allerede klonet uten tillegget, kjør `git submodule update --init`.
Oppdater tillegget med `git submodule update --remote addons/control_room_client`.

### 1. Filer som ikke ligger i repoet

Store filer og hemmeligheter ligger ikke på GitHub (se `.gitignore`):

- `models/nb-whisper-base-q5_0.bin`: NB-Whisper base i ggml-format (fra NbAiLab på Hugging Face).
- `voices/no_NO-talesyntese-medium.onnx`: Piper-stemmen (fra `rhasspy/piper-voices` på Hugging Face). `.onnx.json`-filen ligger i repoet.
- `voice_cache/`: ferdige replikker (valgfritt). Kopier mappen fra en maskin som har den, eller lag den på nytt med `tools/prerender.gd`.
- `.env`: innstillinger og API-nøkkel (se under).

### 2. Programmer

- Godot 4
- whisper.cpp (`whisper-server`)
- Python med Piper i `.venv/`: `python3 -m venv .venv && .venv/bin/pip install piper-tts`
- `sox` (og gjerne `rubberband-cli`)

### 3. `.env`

Lag `.env` i prosjektmappen. Miljøvariabler overstyrer verdiene i filen.

```sh
LLM_API_KEY=...                            # påkrevd
LLM_BASE_URL=https://api.groq.com/openai/v1
LLM_MODEL=openai/gpt-oss-20b
WHISPER_SERVER=whisper-server              # sti til whisper-server
WHISPER_MODEL=/full/sti/til/models/nb-whisper-base-q5_0.bin
CONTROL_ROOM_URL=ws://172.31.0.200:7321    # valgfri, dette er standard
```

Valgfrie innstillinger:

- `AUDIO_DELAY`: forsinkelse i sekunder for Bluetooth- eller nettverkshøyttalere.
- `MIC_START_DB`: hvor høyt man må snakke for å starte. Standard er `-40`.
- `VOICE_PITCH` og `VOICE_LENGTH`: stemmen til Piper.
- `TTS_MODEL`, `TTS_VOICE`, `TTS_TEMPO` og `TTS_INNER_VOICE`: stemmene til Gemini.
- `DEBUG=1`: viser debug-tekst. F1 slår den av og på.

## Kjøre

**Mac:** åpne prosjektet i Godot og trykk Play.

**Raspberry Pi:** kjør `./start.sh`. Skriptet setter stiene for Pi-en, importerer nye filer og starter Godot i fullskjerm.
Spillet starter automatisk ved innlogging fra `~/.config/labwc/autostart`.

## Spille

1. Snakk, eller trykk på knappen, for å starte.
2. Hold inne knappen (eller mellomrom) mens du svarer, og slipp når du er ferdig.
3. Svar riktig på alle utfordringene for å komme forbi Grim til printeren.
