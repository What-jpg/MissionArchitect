extends Node
# Sound effects, looping engine sounds and per-screen music. Files come from tools/gen_audio.py.

const SFX := ["click","toggle","coin","research","alert","touchdown","crash","success","fail"]
const LOOPS := ["engine_loop","thruster_loop","music_base","music_flight","music_landing"]
var streams := {}
var music_player: AudioStreamPlayer
var engine_player: AudioStreamPlayer
var thruster_player: AudioStreamPlayer
var sfx_players: Array = []
var current_music := ""
# Player settings, kept outside the game save so a new expedition does not reset them.
const SETTINGS_PATH := "user://audio.cfg"
var music_volume := 0.7
var sfx_volume := 0.8
var muted := false
signal settings_changed

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	load_settings()
	for name in SFX + LOOPS:
		var path := "res://assets/audio/%s.wav" % name
		if not ResourceLoader.exists(path): continue
		var stream: AudioStreamWAV = load(path)
		if name in LOOPS:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0
			stream.loop_end = int(stream.get_length() * stream.mix_rate)
		streams[name] = stream
	music_player = make_player(-14.0, "Music")
	engine_player = make_player(-9.0, "SFX")
	thruster_player = make_player(-10.0, "SFX")
	for i in 6: sfx_players.append(make_player(-6.0, "SFX"))
	apply_settings()
	# Every button in the game clicks without wiring each one by hand.
	get_tree().node_added.connect(_on_node_added)

func make_player(volume: float, bus_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.volume_db = volume
	player.bus = bus_name
	add_child(player)
	return player

func _on_node_added(node: Node) -> void:
	if node is CheckBox:
		node.toggled.connect(func(_on): play("toggle"))
	elif node is BaseButton:
		node.pressed.connect(func(): play("click"))

func play(name: String) -> void:
	if not streams.has(name) or sfx_volume <= 0.001 or muted: return
	for player in sfx_players:
		if not player.playing:
			player.stream = streams[name]
			player.play()
			return

func music(name: String) -> void:
	if name == current_music: return
	current_music = name
	music_player.stop()
	if name.is_empty() or not streams.has(name): return
	music_player.stream = streams[name]
	music_player.play()

func loop(player: AudioStreamPlayer, name: String, on: bool) -> void:
	if on and not player.playing:
		player.stream = streams.get(name)
		if player.stream: player.play()
	elif not on and player.playing:
		player.stop()

func engine(on: bool) -> void: loop(engine_player, "engine_loop", on)
func thruster(on: bool) -> void: loop(thruster_player, "thruster_loop", on)

func toggle_mute() -> void:
	set_muted(not muted)

func set_muted(value: bool) -> void:
	muted = value
	apply_settings()

func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	apply_settings()

func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	apply_settings()

func apply_settings() -> void:
	# Buses carry the volumes: 0 on a slider mutes that bus, "mute all" mutes the master.
	var music_bus := AudioServer.get_bus_index("Music")
	var sfx_bus := AudioServer.get_bus_index("SFX")
	AudioServer.set_bus_volume_db(music_bus, linear_to_db(maxf(music_volume, 0.0001)))
	AudioServer.set_bus_mute(music_bus, music_volume <= 0.001)
	AudioServer.set_bus_volume_db(sfx_bus, linear_to_db(maxf(sfx_volume, 0.0001)))
	AudioServer.set_bus_mute(sfx_bus, sfx_volume <= 0.001)
	AudioServer.set_bus_mute(0, muted)
	save_settings()
	settings_changed.emit()

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK: return
	music_volume = clampf(float(config.get_value("audio", "music", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(config.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)
	muted = config.get_value("audio", "muted", false) == true

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "music", music_volume)
	config.set_value("audio", "sfx", sfx_volume)
	config.set_value("audio", "muted", muted)
	config.save(SETTINGS_PATH)
