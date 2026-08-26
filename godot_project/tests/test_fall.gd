extends SceneTree

# A battle HP loss grants no reward and adds expedition fatigue. HP is not
# healed until the next encounter; only a boss defeat while already at the
# fatigue cap becomes a run-ending finisher.

var fails := 0

func check(label: String, got, want) -> void:
	var ok: bool = got == want
	print(("PASS  " if ok else "FAIL  ") + "%s (got %s, want %s)" % [label, str(got), str(want)])
	if not ok:
		fails += 1

func _init() -> void:
	var main = load("res://scripts/Main.gd").new()
	root.add_child(main)
	await process_frame
	await process_frame

	mob_fall_case(main)
	boss_limit_case(main)
	next_encounter_heal_case(main)
	resource_display_case(main)
	part_multiplier_case(main)

	print("\n%d failure(s)" % fails)
	quit(1 if fails > 0 else 0)

func _reset(main) -> void:
	main._start_run("knight")
	main.map_row = 0
	main.map_col = 0
	main._start_encounter()
	main.encounter_name = "粘体"
	main.encounter_art = "stray"
	main._close_overlay()
	# lifetime persists to disk (user://profile.json) across real runs by
	# design, which means it also persists across separate invocations of
	# this test on the same machine. Zeroed here so every case starts from
	# a clean slate instead of accumulating with whatever a previous test
	# run — or a previous case in this same run — already wrote.
	main.lifetime = {}

# A non-boss defeat keeps the run alive, adds fatigue, and does not restore
# encounter HP while the defeat result is being shown.
func mob_fall_case(main) -> void:
	_reset(main)
	main.player_hp = 1
	main._ensure_map_node(0, 0)
	main.map_nodes[0][0]["type"] = "battle"
	var losses_before := int(main.lifetime.get("losses", 0))
	main._resolve_defeat("test", true)
	check("mob fall: run is not over", main.state != "game_over", true)
	check("mob fall: HP stays at its battle result", main.player_hp, 1)
	check("mob fall: fatigue was added", main.player_fatigue, main.BATTLE_DEFEAT_FATIGUE)
	check("mob fall: counted as a fall", int(main.lifetime.get("falls", 0)), 1)
	check("mob fall: not counted as a loss", int(main.lifetime.get("losses", 0)), losses_before)

# A boss is only the finisher once fatigue is already maxed.
func boss_limit_case(main) -> void:
	_reset(main)
	main.player_hp = 1
	main._ensure_map_node(0, 0)
	main.map_nodes[0][0]["type"] = "boss"
	main.player_fatigue = main.FATIGUE_MAX
	main._resolve_defeat("test", true)
	check("boss defeat: run is over", main.state, "game_over")
	check("boss defeat: counted as a loss", int(main.lifetime.get("losses", 0)), 1)

# HP resets only when another battle is actually opened.
func next_encounter_heal_case(main) -> void:
	_reset(main)
	main.player_hp = 1
	main._start_encounter()
	check("new battle: HP restored", main.player_hp, main.player_max_hp)

# HP is the combat gauge. Fatigue uses a percentage in combat and its own
# full gauge while choosing a destination on the exploration map.
func resource_display_case(main) -> void:
	_reset(main)
	main.player_fatigue = 42
	main.state = "player"
	main._refresh_top()
	check("battle display: caption is HP", main.hp_caption.text, "HP")
	check("battle display: bar tracks HP", int(main.hp_bar.max_value), main.player_max_hp)
	check("battle display: fatigue is a percentage", main.hp_label.text.contains("疲労42%"), true)
	main.state = "map"
	main._refresh_top()
	check("map display: caption is fatigue", main.hp_caption.text, "疲労")
	check("map display: bar tracks fatigue", int(main.hp_bar.max_value), main.FATIGUE_MAX)

# A landed part attack scales with development and develops the part
# further; a plain hit with no part tag does neither.
func part_multiplier_case(main) -> void:
	_reset(main)
	main.player_hp = main.player_max_hp
	main.player_shield = 0
	main.part_dev = {"chest": 0, "depths": 0, "tail": 0}

	var taken1: int = main._take_damage(10, "chest")
	check("part hit at dev 0: no multiplier yet", taken1, 10)
	check("part hit at dev 0: develops by one", int(main.part_dev["chest"]), 1)

	main.part_dev["chest"] = 2
	main.player_hp = main.player_max_hp
	var taken2: int = main._take_damage(10, "chest")
	check("part hit at dev 2: x1.5", taken2, 15)
	check("part hit at dev 2: develops to 3", int(main.part_dev["chest"]), 3)
	main._develop_part("chest")
	check("part development caps at 3", int(main.part_dev["chest"]), 3)

	main.player_hp = main.player_max_hp
	var taken3: int = main._take_damage(10, "")
	check("plain hit: no multiplier", taken3, 10)
	check("plain hit: leaves chest development alone", int(main.part_dev["chest"]), 3)

	main.player_shield = 20
	main.player_hp = main.player_max_hp
	var taken4: int = main._take_damage(10, "chest")
	check("part hit fully blocked: nothing gets through", taken4, 0)
	check("part hit fully blocked: does not develop", int(main.part_dev["chest"]), 3)
