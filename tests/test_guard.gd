# Run: godot --headless --path . --script res://tests/test_guard.gd
# Checks the local answer guard (repeat = never correct, keyword = correct) and Whisper-server transcription.
extends SceneTree


func _initialize() -> void:
	var game = load("res://main.gd").new()
	root.add_child(game)  # starts the servers like the real game
	game.riddle = ["Hva blir våtere jo mer det tørker?", "et håndkle", ["håndkle", "håndkleet", "handkle"]]
	assert(game._is_repeat("Hva blir våtere jo mer det tørker?"))
	assert(game._is_repeat("hva blir våtere jo mer det tørker"))
	assert(not game._has_keyword("Hva blir våtere jo mer det tørker?"))
	assert(not game._is_repeat("Det er et håndkle"))
	assert(game._has_keyword("Det er et håndkle!"))
	assert(not game._has_keyword("Er det en svamp?"))
	game.riddle = ["Hvor mange hjerter har en blekksprut?", "tre", ["tre", "3"]]
	assert(game._has_keyword("Den har 3 hjerter"))
	assert(not game._has_keyword("Hvor mange hjerter har en blekksprut"))
	assert(game._asks_again("Hva var gåten igjen?"))
	assert(game._asks_again("Kan du gjenta?"))
	assert(game._asks_skip("Neste spørsmål."))
	assert(game._asks_skip("Jeg gir opp!"))
	assert(not game._asks_skip("Passer det?"))  # skip words count only as whole words
	assert(not game._asks_again("Galdhøpiggen"))
	game.riddle = ["Jo mer du tar bort, jo større blir det. Hva er det?", "et hull", ["hull", "hullet"]]
	assert(game._has_keyword("Et rull."))
	assert(game._has_keyword("Ett hull!"))
	assert(not game._has_keyword("En stein"))
	game.riddle = ["Hvor mange hjerter har en blekksprut?", "tre", ["tre", "3"]]
	assert(not game._has_keyword("tro"))  # short keywords stay exact
	game.quiz = ["Hvem malte det berømte maleriet Skrik?", ["Pablo Picasso", "Edvard Munch", "Vincent van Gogh", "Salvador Dalí"], 1]
	assert(game._quiz_pick("Jeg tror det er B") == 1)
	assert(game._quiz_pick("Se.") == 2)
	assert(game._quiz_pick("De") == 3)
	assert(game._quiz_pick("Edvard Munk") == 1)
	assert(game._quiz_pick("Picasso!") == 0)
	assert(game._quiz_pick("Ingen anelse") == -1)
	game.quiz = ["Hva er verdens største hav?", ["Atlanterhavet", "Indiahavet", "Stillehavet", "Nordishavet"], 2]
	assert(game._quiz_pick("Jeg tror det er Stillehavet") == 2)
	game.quiz = ["Hvor mange planeter er det i solsystemet vårt?", ["Sju", "Åtte", "Ni", "Ti"], 1]
	assert(game._quiz_pick("Det er 8") == 1)
	assert(game._quiz_pick("Jeg tror det er åtte") == 1)
	game.quiz = []
	# True or false: the spoken answer maps to sant (1) / løgn (0), unclear is -1.
	assert(game._tf_pick("Det er sant!") == 1)
	assert(game._tf_pick("Jeg tror det er løgn") == 0)
	assert(game._tf_pick("Usant.") == 0)
	assert(game._tf_pick("Ja") == 1)
	assert(game._tf_pick("Hmm, vet ikke") == -1)
	# Line rotation: every line once before any repeats.
	var seen := {}
	for i in game.WAIT_LINES.size():
		seen[game._pick(game.WAIT_LINES)] = true
	assert(seen.size() == game.WAIT_LINES.size())
	print("guard ok")
	await process_frame  # _ready (and the menu) runs on the first frame
	game.menu.hide()  # skip the main menu; the game itself waits there
	await create_timer(4.0).timeout  # whisper-server loading
	var text: String = await game._transcribe(FileAccess.get_file_as_bytes(OS.get_environment("TEST_WAV")))
	print("transcribed: ", text)
	assert("spøkelse" in text.to_lower())
	# Pre-roll: hold for 1 s after 2 s of always-on recording; the answer must start 0.5 s before the press.
	game.riddle = ["x", "y", []]
	game.busy = false
	await create_timer(2.0).timeout
	game._talk(true)
	await create_timer(1.0).timeout
	game._talk(false)
	await create_timer(0.5).timeout
	var saved := AudioStreamWAV.load_from_file(ProjectSettings.globalize_path("user://svar.wav"))
	print("answer length: ", saved.get_length())
	assert(saved.get_length() > 1.3 and saved.get_length() < 2.2)  # 0.5 pre + 1.0 hold + 0.3 post, minus mic start latency
	# A held key auto-releases after MAX_HOLD_MS.
	game.busy = false
	game._talk(true)
	await create_timer(game.MAX_HOLD_MS / 1000.0 + 0.5).timeout
	assert(not game.holding)
	# LLM failure (timeout or error code): Grim says the error line and repeats the riddle.
	assert(game.http.timeout == 10.0)
	game.riddle = ["Hva har fire bein om morgenen?", "et menneske", []]
	game._on_llm(HTTPRequest.RESULT_TIMEOUT, 0, PackedStringArray(), PackedByteArray())
	assert("åndene forstyrrer meg" in game.debug_label.text and "fire bein" in game.debug_label.text)
	# No talking over Grim: the button is locked while he speaks, and opens when he is done.
	var wait_ms := Time.get_ticks_msec() + 15000  # an uncached line goes to Gemini first: a few seconds
	while not game.speaker.playing and Time.get_ticks_msec() < wait_ms:
		await process_frame
	assert(game.speaker.playing)
	game._talk(true)
	assert(not game.holding)
	while game.busy:
		await process_frame
	assert(not game.speaker.playing)
	# Silence while waiting: after WAIT_TALK_AFTER seconds he says a wait line.
	await create_timer(game.WAIT_TALK_AFTER + 1.0).timeout
	assert(game.debug_label.text.split("\n")[-1].trim_prefix("Grim: ") in game.WAIT_LINES.map(func(l): return l.replace("*", "")))
	print("all ok")
	quit()
