# HalloweenSpill – plan

2D-spill i Godot 4.3 på Raspberry Pi. Gresskar-Grim stiller gåter med tale (TTS).
Spilleren svarer muntlig. Lokal whisper.cpp gjør tale om til tekst. En LLM via API-nøkkel
(standard: `openai/gpt-oss-20b` på Groq) vurderer svaret og lager neste gåte.

## Flyt

1. Gresskaret leser en gåte høyt (Godot TTS).
2. Spilleren holder inne mellomrom, snakker og slipper.
3. Godot lagrer `user://svar.wav` og kjører `whisper-cli` i en egen tråd.
4. Teksten sendes til LLM-en. Svaret starter med `[RIKTIG]` hvis spilleren svarte riktig.
5. Poeng oppdateres, og gresskaret leser svaret høyt.

## Fase 1 – Prototype på Mac (pågår)

- [x] Opprette Godot-prosjekt (`project.godot`, GL Compatibility, mikrofon og TTS på)
- [x] Hovedscene med tegnet gresskar som snakker (`main.gd`)
- [x] Mikrofonopptak med `AudioEffectRecord` (hold mellomrom)
- [x] Kall til `whisper-cli` i egen tråd
- [x] LLM-kall (OpenAI-kompatibelt API) med systemprompt på norsk
- [x] Poengtelling via `[RIKTIG]`-markør
- [ ] Installere whisper.cpp lokalt: `brew install whisper-cpp`
- [ ] Laste ned modell til `models/ggml-base.bin`
- [ ] Skaffe API-nøkkel (Groq eller annen leverandør) og sette `LLM_API_KEY`
- [ ] Kjøre spillet og teste en hel runde
- [ ] Sjekke at det finnes en norsk TTS-stemme på maskinen

## Fase 2 – Raspberry Pi

- [ ] Velge Pi-modell (anbefalt: Pi 5 med 8 GB, Pi 4 blir treg med whisper)
- [ ] Installere Raspberry Pi OS 64-bit
- [ ] Bygge whisper.cpp fra kilde på Pi-en (`cmake -B build && cmake --build build -j`)
- [ ] Teste modellstørrelser: `tiny`, `base`, `small` – mål tid per svar
- [ ] Installere `speech-dispatcher` og `espeak-ng` for norsk TTS
- [ ] Koble til USB-mikrofon og høyttaler, teste med `arecord`/`aplay`
- [ ] Eksportere spillet fra Godot for Linux ARM64
- [ ] Lage startskript som setter miljøvariabler og starter spillet
- [ ] Autostart ved oppstart (fullskjerm, kiosk-modus)

Miljøvariabler i startskriptet:

```sh
export LLM_API_KEY="..."
export LLM_BASE_URL="https://api.groq.com/openai/v1"
export LLM_MODEL="openai/gpt-oss-20b"
export WHISPER_BIN="$HOME/whisper.cpp/build/bin/whisper-cli"
export WHISPER_MODEL="$HOME/whisper.cpp/models/ggml-base.bin"
./HalloweenSpill.arm64
```

## Fase 3 – Spillopplevelse

- [ ] Bedre gresskar-grafikk (sprites i stedet for tegnede former)
- [ ] Halloween-bakgrunn og stemningsmusikk
- [ ] Lydeffekt ved riktig og feil svar
- [ ] Tydelig visning av «lytter» og «tenker»
- [ ] Slutt på runden etter for eksempel 5 gåter, vis poengsum
- [ ] Startskjerm: «Trykk for å starte»

## Fase 4 – Robusthet

- [x] Håndtere at nettet er nede (Grim sier en feilreplikk og gjentar gåten)
- [x] Tidsavbrudd på LLM-kall (`http.timeout`)
- [x] Stoppe opptak automatisk etter maks 10 sekunder
- [ ] Teste at whisper forstår barn og ulike dialekter
- [ ] Sjekke kostnad per runde hos API-leverandøren

## Åpne spørsmål

- Skal gåtene lages av LLM-en, eller skal vi ha en fast liste med gåter og svar?
  En fast liste gir mer kontroll og gjør det enklere å vurdere svar.
- Holde inne knapp, eller automatisk stemmedeteksjon? Knapp er enklest og sikrest.
- Hvilken leverandør for LLM? Groq er rask og billig for `gpt-oss-20b`.
