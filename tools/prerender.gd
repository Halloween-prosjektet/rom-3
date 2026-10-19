# Renders every fixed line Grim (and the player's inner voice) can say into voice_cache/, so the game
# ships with them and never waits for the TTS on those. LLM replies are not fixed and are made live.
# Run on the Mac (fast network), then copy the game to the Pi:
#   godot --headless --path . --script res://tools/prerender.gd
extends SceneTree

const PARALLEL := 16
var game
var queue := []  # [sentence, fx] pairs, unique
var seen := {}
var done := 0
var failed := 0
var total := 0


func _initialize() -> void:
	game = load("res://main.gd").new()  # not added to the tree: only its constants and helpers are used
	var pid := OS.create_process(game.piper_python, [ProjectSettings.globalize_path("res://tts_server.py"), game.piper_voice, str(game.PIPER_PORT)])
	for anger in [0.0, 50.0]:  # calm and angry Grim
		game.anger = anger
		_grim_lines()
	for line in game.LAND_LINES + [[0, game.DARK_THOUGHT], [0, game.INNER_LINE]]:
		_add(line[1], "Master", "1.0", line[2] if line.size() > 2 else "")
	for line in game.GIRL_ASIDES:
		_add(line[0], "Master", "1.0", line[1] if line.size() > 1 else "")
	for line in game.FALL_LINES:
		_add(line[1], "Master", "1.0", "scream")
	total = queue.size()
	print("%d setninger å lage" % total)
	await create_timer(4.0).timeout  # server start
	for w in PARALLEL:
		_worker()
	while done + failed < total:
		await process_frame
	print("ferdig: %d laget, %d feilet" % [done, failed])
	OS.kill(pid)
	quit()


func _grim_lines() -> void:
	var g = game
	for line in g.INTRO_OPENERS + g.INTRO_RULES + g.GREET_SILENT + [g.GREET_FALLBACK, g.LLM_ERROR_LINE, g.ASK_AGAIN_LINE, "Prøv igjen, lille dødelige.", "Hmpf! Det var riktig.",
			"Du klarte quizen min.", "Det har du allerede prøvd! Velg et annet svar.",
			"Jeg hørte ingenting. Hold inne knappen mens du snakker.",
			"Jeg hørte ingenting. Hold inne mellomromstasten mens du snakker.", "Grr! *Svar nå, lille dødelige!*"]:
		_add(line)
	for list in [g.CORRECT_LINES, g.WRONG_LINES, g.WAIT_LINES, g.WIN_LINES]:
		for line in list:
			_add(line)
	for statement in g.TRUE_FALSE:
		g.tf = statement
		for lead in ["Neste utfordring: sant eller løgn! ", "Påstand nummer to. ", "Ny påstand. ", g.ASK_AGAIN_LINE]:
			_add(lead + g._tf_spoken())
	g.tf = []
	for line in ["Det var faktisk sant.", "Det var faktisk løgn.", "Hehe. Si sant eller løgn, lille dødelige!"]:
		_add(line)
	for r in g.RIDDLES:
		for line in [r[0], "Neste utfordring er en gåte. " + r[0], "Neste: " + r[0], g.REPEAT_LINE + r[0]]:
			_add(line)
	for q in g.QUIZ:
		g.quiz = q
		for lead in ["Her kommer det første spørsmålet. ", "Spørsmål nummer to. "]:
			_add(lead + g._quiz_spoken() + " Si svaret du tror er riktig!")
		for option in q[1]:
			_add("Hehe. Jeg forsto ikke. Si selve svaret, for eksempel %s, lille dødelige." % option)
	g.quiz = []


func _add(text: String, bus := "Voice", length: String = game.voice_length, mood := "") -> void:
	var speech: Array = game._speech_parts(text, bus, length, mood)
	for i in speech[0].size():
		var key := JSON.stringify([speech[0][i], speech[1][i]])
		if not seen.has(key):
			seen[key] = true
			queue.append([speech[0][i], speech[1][i]])


func _worker() -> void:
	while not queue.is_empty():
		var item: Array = queue.pop_back()
		var req := HTTPRequest.new()
		root.add_child(req)
		req.request("http://127.0.0.1:%d/synthesize" % game.PIPER_PORT, ["Content-Type: application/json"],
			HTTPClient.METHOD_POST, JSON.stringify(item[1].merged({"text": item[0]})))
		var res: Array = await req.request_completed
		req.queue_free()
		if res[1] == 200 and "X-Voice: gemini" in res[2]:
			done += 1
		else:
			failed += 1
			print("feilet: ", item[0])
		if (done + failed) % 25 == 0:
			print("%d / %d" % [done + failed, total])
