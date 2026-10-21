extends Node
## Session autoload. One player hosts (and is the DM); friends join by IP address.
## The host owns the authoritative game state and runs every command through the rules engine;
## clients only send commands and receive their (redacted) view of the state.

signal state_changed(events: Array)
signal error_received(message: String)
signal status_changed(status: String, detail: String)
signal players_changed

const DEFAULT_PORT := 24565
const MAX_PLAYERS := 12
const AUTOSAVE_PATH := "user://autosave.save"
const PROTOCOL := 1
const REACTION_SECONDS := 30.0

var state: Dictionary = {}       ## What this machine sees.
var full_state: Dictionary = {}  ## Host only: the real state.
var me: Dictionary = {"name": "", "is_dm": false}
var players: Dictionary = {}     ## peer id -> {name, is_dm} (host's copy is authoritative)
var is_host := false
var status := "offline"
var external_address := ""

var _pending_key := ""
var _upnp_thread: Thread
var _upnp: UPNP


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _exit_tree() -> void:
	if is_host:
		save_game(AUTOSAVE_PATH)
	if _upnp != null:
		_upnp.delete_port_mapping(DEFAULT_PORT, "UDP")
	if _upnp_thread != null and _upnp_thread.is_started():
		_upnp_thread.wait_to_finish()


func is_online() -> bool:
	return multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)


# ---------------- Starting a session ----------------

## Host a game on `port`. The host is the DM. Returns an error message or "".
func host(player_name: String, port: int = DEFAULT_PORT, try_upnp: bool = false) -> String:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return "Couldn't open port %d (%s). Is another game already hosting?" % [port, error_string(err)]
	multiplayer.multiplayer_peer = peer
	_start_host(player_name)
	status = "hosting"
	status_changed.emit(status, "Hosting on port %d" % port)
	if try_upnp:
		_upnp_thread = Thread.new()
		_upnp_thread.start(_upnp_setup.bind(port))
	return ""


## Single-machine play: you are the DM and can control everything.
func play_offline(player_name: String) -> void:
	leave()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_start_host(player_name)
	status = "offline"
	status_changed.emit(status, "Playing offline")


func join(player_name: String, address: String, port: int = DEFAULT_PORT) -> String:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address.strip_edges(), port)
	if err != OK:
		return "Couldn't connect to %s:%d (%s)." % [address, port, error_string(err)]
	multiplayer.multiplayer_peer = peer
	me = {"name": player_name, "is_dm": false}
	is_host = false
	status = "connecting"
	status_changed.emit(status, "Connecting to %s:%d..." % [address, port])
	return ""


func leave() -> void:
	if is_host and not full_state.is_empty():
		save_game(AUTOSAVE_PATH)
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	players.clear()
	is_host = false
	state = {}
	full_state = {}


func _start_host(player_name: String) -> void:
	is_host = true
	me = {"name": player_name, "is_dm": true}
	players = {1: me}
	if not load_game(AUTOSAVE_PATH):
		full_state = RulesEngine.demo_state()
		_seed_demo()
	_broadcast([])
	players_changed.emit()


func _seed_demo() -> void:
	var eng := RulesEngine.new(full_state)
	eng.spawn({"kind": "pregen", "template": "fighter", "level": 3, "pos": Vector2i(8, 8)})
	eng.spawn({"kind": "pregen", "template": "wizard", "level": 3, "pos": Vector2i(8, 10)})
	eng.spawn({"kind": "pregen", "template": "cleric", "level": 3, "pos": Vector2i(9, 9)})
	eng.spawn({"kind": "pregen", "template": "rogue", "level": 3, "pos": Vector2i(8, 6)})
	eng.spawn({"kind": "monster", "template": "goblin", "pos": Vector2i(16, 7)})
	eng.spawn({"kind": "monster", "template": "goblin", "pos": Vector2i(16, 10)})
	eng.spawn({"kind": "monster", "template": "orc", "pos": Vector2i(17, 8)})
	eng.add_log("system", "Welcome to TableTop! Drag with the right mouse button to orbit, scroll to zoom. The DM starts combat from the top bar.")


func _upnp_setup(port: int) -> void:
	var u := UPNP.new()
	var res := u.discover()
	var msg := ""
	if res == UPNP.UPNP_RESULT_SUCCESS and u.get_gateway() and u.get_gateway().is_valid_gateway():
		var a := u.add_port_mapping(port, port, "TableTop", "UDP")
		if a == UPNP.UPNP_RESULT_SUCCESS:
			_upnp = u
			msg = u.query_external_address()
	call_deferred("_upnp_done", msg)


func _upnp_done(addr: String) -> void:
	external_address = addr
	if _upnp_thread != null:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	if addr != "":
		status_changed.emit(status, "Hosting — friends can join at %s" % addr)
	else:
		status_changed.emit(status, "Hosting (UPnP failed: forward UDP port %d on your router, or use a VPN like Tailscale)" % DEFAULT_PORT)


# ---------------- Commands ----------------

## Send a command to the host (or apply it directly when we are the host).
func send(cmd: Dictionary) -> void:
	if is_host:
		_apply_from(1, cmd)
	elif status == "connected":
		_cmd.rpc_id(1, cmd)
	else:
		error_received.emit("Not connected.")


func _apply_from(peer_id: int, cmd: Dictionary) -> void:
	var user: Dictionary = players.get(peer_id, {})
	if user.is_empty():
		return
	if cmd.get("type", "") == "loadState":
		if not user.is_dm:
			_send_error(peer_id, "Only the DM can load a game.")
			return
		full_state = cmd.state
		_broadcast([])
		return
	var res := RulesEngine.apply(full_state, cmd, user)
	if not res.ok:
		_send_error(peer_id, res.error)
		return
	full_state = res.state
	_broadcast(res.events)
	save_game(AUTOSAVE_PATH)


func _send_error(peer_id: int, msg: String) -> void:
	if peer_id == 1:
		error_received.emit(msg)
	else:
		_recv_error.rpc_id(peer_id, msg)


func _broadcast(events: Array) -> void:
	Homebrew.ensure(full_state)
	Homebrew.sync(full_state)
	_watch_pending()
	for pid in players:
		var view := RulesEngine.redact_for(full_state, players[pid], RulesEngine.update_fog(full_state, players[pid]))
		if pid == 1:
			state = view
			state_changed.emit(events)
		else:
			var raw := var_to_bytes(view)
			_recv_state.rpc_id(pid, raw.compress(FileAccess.COMPRESSION_ZSTD), raw.size(), events)


## If nobody answers a reaction prompt in time, the host answers with the sensible default.
func _watch_pending() -> void:
	var p: Dictionary = full_state.get("pending", {})
	var key := "" if p.is_empty() else "%d:%d" % [p.seed, p.decisions.size()]
	if key == _pending_key:
		return
	_pending_key = key
	if key == "":
		return
	get_tree().create_timer(REACTION_SECONDS).timeout.connect(func():
		var cur: Dictionary = full_state.get("pending", {})
		if is_host and not cur.is_empty() and "%d:%d" % [cur.seed, cur.decisions.size()] == key:
			_apply_from(1, {"type": "react", "choice": cur.prompt.default, "timeout": true}))


# ---------------- Save / load ----------------

func save_game(path: String) -> bool:
	if not is_host or full_state.is_empty():
		return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_var(full_state)
	return true


func load_game(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var data = f.get_var()
	if not (data is Dictionary) or data.get("version", 0) != 1:
		return false
	full_state = data
	if is_host and not players.is_empty():
		_broadcast([])
	return true


func new_game() -> void:
	if not is_host:
		return
	full_state = RulesEngine.demo_state()
	_seed_demo()
	_broadcast([])


# ---------------- Peer events ----------------

func _on_peer_connected(_id: int) -> void:
	pass  # Wait for the client's hello before adding them.


func _on_peer_disconnected(id: int) -> void:
	if is_host and players.has(id):
		var who: Dictionary = players[id]
		players.erase(id)
		var eng := RulesEngine.new(full_state)
		eng.add_log("system", "%s left the table." % who.name)
		_broadcast([])
		_push_players()


func _on_connected() -> void:
	status = "connected"
	_hello.rpc_id(1, me.name, PROTOCOL)


func _on_connection_failed() -> void:
	status = "failed"
	multiplayer.multiplayer_peer = null
	status_changed.emit(status, "Couldn't reach the host.")


func _on_server_disconnected() -> void:
	status = "disconnected"
	multiplayer.multiplayer_peer = null
	status_changed.emit(status, "The host closed the game.")


func _push_players() -> void:
	var list := []
	for pid in players:
		list.append({"id": pid, "name": players[pid].name, "is_dm": players[pid].is_dm})
	players_changed.emit()
	if is_online():
		_recv_players.rpc(list)


# ---------------- RPCs ----------------

@rpc("any_peer", "call_remote", "reliable")
func _hello(player_name: String, protocol: int) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if protocol != PROTOCOL:
		_recv_error.rpc_id(id, "Version mismatch: update TableTop to match the host.")
		return
	var name := player_name.strip_edges().left(24)
	if name.is_empty():
		name = "Player"
	var taken := players.values().map(func(p): return p.name)
	var base := name
	var n := 2
	while taken.has(name):
		name = "%s %d" % [base, n]
		n += 1
	players[id] = {"name": name, "is_dm": false}
	_recv_welcome.rpc_id(id, {"name": name, "is_dm": false})
	var eng := RulesEngine.new(full_state)
	eng.add_log("system", "%s joined the table." % name)
	_broadcast([])
	_push_players()


@rpc("any_peer", "call_remote", "reliable")
func _cmd(cmd: Dictionary) -> void:
	if is_host:
		_apply_from(multiplayer.get_remote_sender_id(), cmd)


@rpc("authority", "call_remote", "reliable")
func _recv_state(data: PackedByteArray, size: int, events: Array) -> void:
	var view = bytes_to_var(data.decompress(size, FileAccess.COMPRESSION_ZSTD))
	if view is Dictionary:
		state = view
		Homebrew.sync(state)
		state_changed.emit(events)


@rpc("authority", "call_remote", "reliable")
func _recv_error(msg: String) -> void:
	error_received.emit(msg)


@rpc("authority", "call_remote", "reliable")
func _recv_welcome(info: Dictionary) -> void:
	me = info
	status_changed.emit("connected", "Connected as %s" % me.name)


@rpc("authority", "call_remote", "reliable")
func _recv_players(list: Array) -> void:
	players.clear()
	for p in list:
		players[p.id] = {"name": p.name, "is_dm": p.is_dm}
	players_changed.emit()
