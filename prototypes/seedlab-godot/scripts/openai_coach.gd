extends Node
const URL = "http://127.0.0.1:4873"
signal connection_finished
var connecting = false
var service_seen = false
var bridge_pid = -1
var available = false
var health_done = false
var calls = 0
var health_note = "コーチに接続中…"
var generation = 0
var last_trial = -1000
var last_time = -1000.0
var waiting = false

func _ready() -> void:
	ensure_connection()

func ensure_connection() -> bool:
	if connecting:
		await connection_finished
		return available
	connecting = true
	health_note = "OpenAIコーチに接続中…"
	await check_health()
	if not service_seen:
		var node = _node_path()
		var server = ProjectSettings.globalize_path("res://bridge/server.mjs")
		if node != "" and FileAccess.file_exists(server):
			health_note = "コーチの準備をしています…"
			if bridge_pid < 0 or not OS.is_process_running(bridge_pid):
				bridge_pid = OS.create_process(node, PackedStringArray([server]))
			for attempt in range(20):
				await get_tree().create_timer(.15).timeout
				await check_health()
				if service_seen: break
		else:
			health_note = "AI接続サーバーを起動できません。Node.jsの設定を確認してください。"
	connecting = false
	connection_finished.emit()
	return available

func _node_path() -> String:
	var found: Array = []
	OS.execute("/usr/bin/which", PackedStringArray(["node"]), found, false)
	var candidates: Array = []
	if not found.is_empty(): candidates.append(str(found[0]).strip_edges())
	candidates.append_array(["/opt/homebrew/bin/node", "/usr/local/bin/node", OS.get_environment("HOME") + "/.local/share/mise/shims/node"])
	for candidate in candidates:
		if candidate != "" and FileAccess.file_exists(candidate): return candidate
	return ""

func check_health() -> void:
	available = false
	service_seen = false
	var request = HTTPRequest.new()
	add_child(request)
	request.timeout = 2
	var err = request.request(URL + "/health")
	if err != OK:
		request.queue_free()
		health_done = true
		health_note = "コーチとの接続が切れています。「再接続」で準備できます。"
		return
	var response = await request.request_completed
	request.queue_free()
	health_done = true
	if response[0] != HTTPRequest.RESULT_SUCCESS or response[1] != 200:
		health_note = "コーチとの接続が切れています。「再接続」で準備できます。"
		return
	var parsed = JSON.new()
	var valid = parsed.parse(response[3].get_string_from_utf8()) == OK
	var data = parsed.data if valid else null
	service_seen = data is Dictionary and data.get("service") == "seedlab-coach-v1"
	available = service_seen and data.get("configured", false)
	health_note = "OpenAI 接続準備OK" if available else ("OpenAIキーが未設定です。接続サーバーの設定を確認してください。" if service_seen else "別のサービスが接続先を使用しています。")

func _exit_tree() -> void:
	# Leave a launcher-owned or already running bridge alone.
	if bridge_pid > 0 and OS.is_process_running(bridge_pid): OS.kill(bridge_pid)

func due(trials: int) -> bool:
	return not waiting and trials - last_trial >= 24 and Time.get_ticks_msec() / 1000.0 - last_time >= 30.0

func cancel() -> void:
	generation += 1

func review(state: Dictionary, image: Image) -> Dictionary:
	if waiting: return {"source": "cancelled"}
	waiting = true
	last_trial = state.trials
	last_time = Time.get_ticks_msec() / 1000.0
	var ticket = generation
	var request = HTTPRequest.new()
	add_child(request)
	request.timeout = 24
	request.body_size_limit = 16384
	var preview = image.duplicate() as Image
	preview.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	var encoded = "data:image/png;base64," + Marshalls.raw_to_base64(preview.save_png_to_buffer())
	var err = request.request(URL + "/coach", PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, JSON.stringify({"state": state, "image": encoded}))
	if err != OK:
		request.queue_free()
		waiting = false
		return {"source": "unavailable", "reason": "コーチとの接続が切れました。「再接続」を押してください。"}
	var response = await request.request_completed
	request.queue_free()
	waiting = false
	if ticket != generation: return {"source": "cancelled"}
	var parsed = JSON.new()
	var valid = response[0] == HTTPRequest.RESULT_SUCCESS and parsed.parse(response[3].get_string_from_utf8()) == OK
	var data = parsed.data if valid else null
	if not data is Dictionary:
		available = false
		health_note = "コーチとの接続が切れています。「再接続」で準備できます。"
		return {"source": "unavailable", "reason": "コーチとの接続が切れました。「再接続」を押してください。"}
	if data.get("source") == "live" and not data.get("cacheHit", false): calls += 1
	return data
