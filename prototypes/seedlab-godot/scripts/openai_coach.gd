extends Node
var url = "http://127.0.0.1:4873"
var byot = false
var session_token = ""
var bridge_port = 4873
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
	byot = not OS.has_feature("editor") or "--isolated-coach" in OS.get_cmdline_user_args()
	if byot:
		var socket = TCPServer.new()
		if socket.listen(0, "127.0.0.1") != OK:
			health_done = true
			health_note = "コーチ用のローカル接続を準備できませんでした。"
			return
		bridge_port = socket.get_local_port()
		socket.stop()
		url = "http://127.0.0.1:%d" % bridge_port
		session_token = Crypto.new().generate_random_bytes(32).hex_encode()
	ensure_connection()

func ensure_connection() -> bool:
	if connecting:
		await connection_finished
		return available
	connecting = true
	health_note = "OpenAIコーチに接続中…"
	if not byot or bridge_pid > 0: await check_health()
	if not service_seen:
		var node = _node_path()
		var server = _bridge_path()
		if node != "" and FileAccess.file_exists(server):
			health_note = "コーチの準備をしています…"
			if bridge_pid < 0 or not OS.is_process_running(bridge_pid):
				var arguments = PackedStringArray([server])
				if byot:
					arguments.append_array(PackedStringArray(["--isolated", "--port=%d" % bridge_port, "--session=" + session_token, "--parent=%d" % OS.get_process_id()]))
				bridge_pid = OS.create_process(node, arguments)
			for attempt in range(20):
				await get_tree().create_timer(.15).timeout
				await check_health()
				if service_seen: break
		else:
			health_note = "同梱の接続サービスが見つかりません。配布ファイルをすべて展開してください。" if byot else "AI接続サーバーを起動できません。Node.jsの設定を確認してください。"
	connecting = false
	connection_finished.emit()
	return available

func _node_path() -> String:
	if not OS.has_feature("editor"):
		var name = "node.exe" if OS.get_name() == "Windows" else "node"
		if OS.get_name() == "macOS": name += "-arm64" if OS.has_feature("arm64") else "-x64"
		var bundled = _support_path().path_join("runtime/" + name)
		return bundled if FileAccess.file_exists(bundled) else ""
	var found: Array = []
	OS.execute("where" if OS.get_name() == "Windows" else "/usr/bin/which", PackedStringArray(["node"]), found, false)
	var candidates: Array = []
	if not found.is_empty(): candidates.append(str(found[0]).strip_edges())
	candidates.append_array(["/opt/homebrew/bin/node", "/usr/local/bin/node", OS.get_environment("HOME") + "/.local/share/mise/shims/node"])
	for candidate in candidates:
		if candidate != "" and FileAccess.file_exists(candidate): return candidate
	return ""

func _support_path() -> String:
	var folder = OS.get_executable_path().get_base_dir()
	return folder.path_join("../Resources/seedlab").simplify_path() if OS.get_name() == "macOS" else folder.path_join("seedlab")

func _bridge_path() -> String:
	return ProjectSettings.globalize_path("res://bridge/server.mjs") if OS.has_feature("editor") else _support_path().path_join("prototypes/seedlab-godot/bridge/server.mjs")

func _headers(json: bool = false) -> PackedStringArray:
	var headers = PackedStringArray()
	if byot: headers.append("Authorization: Bearer " + session_token)
	if json: headers.append("Content-Type: application/json")
	return headers

func set_api_key(key: String) -> Dictionary:
	if not byot: return {"ok": false, "message": "配布版から設定してください。"}
	if connecting: await connection_finished
	if not service_seen:
		await ensure_connection()
		if not service_seen: return {"ok": false, "message": health_note}
	var request = HTTPRequest.new()
	add_child(request)
	request.timeout = 3
	request.body_size_limit = 2048
	var error = request.request(url + "/configure", _headers(true), HTTPClient.METHOD_POST, JSON.stringify({"api_key": key}))
	key = ""
	if error != OK:
		request.queue_free()
		return {"ok": false, "message": "キーを設定できませんでした。"}
	var response = await request.request_completed
	request.queue_free()
	var result = JSON.parse_string(response[3].get_string_from_utf8()) if response[0] == HTTPRequest.RESULT_SUCCESS else null
	if response[1] != 200 or not result is Dictionary:
		return {"ok": false, "message": result.get("reason", "キーを設定できませんでした。") if result is Dictionary else "接続サービスに届きませんでした。"}
	cancel()
	available = result.get("configured", false)
	health_note = "自分のAPIキーを設定済み / この起動中のみ" if available else "自分のAPIキーを設定するとコーチを利用できます。"
	return {"ok": true, "message": "キーを設定しました。最初の相談時にOpenAIに接続します。" if available else "APIキーを破棄しました。"}

func check_health() -> void:
	available = false
	service_seen = false
	var request = HTTPRequest.new()
	add_child(request)
	request.timeout = 2
	var err = request.request(url + "/health", _headers())
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
	if byot and service_seen:
		health_note = "自分のAPIキーを設定済み / この起動中のみ" if available else "自分のAPIキーを設定するとコーチを利用できます。"

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
	var err = request.request(url + "/coach", _headers(true), HTTPClient.METHOD_POST, JSON.stringify({"state": state, "image": encoded}))
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
