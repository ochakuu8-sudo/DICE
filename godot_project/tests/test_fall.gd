extends SceneTree

# HP is a run-wide resource. A defeat ends the run and every new encounter
# keeps the HP that the previous encounter left behind.

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

	run_loss_case(main)
	next_encounter_persistence_case(main)
	reroll_persistence_case(main)
	exploration_recovery_case(main)
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

# A defeat consumes the run and records the battle fatigue cost.
func run_loss_case(main) -> void:
	_reset(main)
	main.player_hp = 1
	main._ensure_map_node(0, 0)
	main.map_nodes[0][0]["type"] = "battle"
	var losses_before := int(main.lifetime.get("losses", 0))
	main._resolve_defeat("test", true)
	check("battle defeat: run is over", main.state, "game_over")
	check("battle defeat: HP stays at its battle result", main.player_hp, 1)
	check("battle defeat: fatigue was added", main.player_fatigue, main.BATTLE_DEFEAT_FATIGUE)
	check("battle defeat: counted as a loss", int(main.lifetime.get("losses", 0)), losses_before + 1)

# Opening another battle retains run-wide HP instead of restoring it.
func next_encounter_persistence_case(main) -> void:
	_reset(main)
	check("new run starts at 30 HP", main.player_max_hp, 30)
	main.player_hp = 7
	main._start_encounter()
	check("new battle: HP carries over", main.player_hp, 7)

# Rerolls begin at one, accumulate through the start tile, and do not reset
# when a new combat turn begins.
func reroll_persistence_case(main) -> void:
	_reset(main)
	check("new run starts with one reroll", main.rerolls_left, 1)
	check("start square is a pass reroll tile", str(main.permanent_board[0][0]), "reroll_path")
	main.rerolls_left = 3
	main._start_player_turn()
	check("rerolls persist across turns", main.rerolls_left, 3)

# Recovery nodes replenish run HP and never lower fatigue.
func exploration_recovery_case(main) -> void:
	_reset(main)
	main.player_hp = 5
	main.player_fatigue = 42
	main._resolve_rest_node()
	check("rest restores run HP", main.player_hp, 23)
	check("rest does not recover fatigue", main.player_fatigue, 42)

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

# A landed part attack scales with sensitivity and adds one stack. The
# prescribed Lv0=6 / Lv1=5 / Lv2=4 / Lv3=3 ceilings advance the level only
# when their own meter fills.
func part_multiplier_case(main) -> void:
	_reset(main)
	main.player_hp = main.player_max_hp
	main.player_shield = 0
	main.part_dev = {"chest": 0, "depths": 0, "tail": 0}
	main.part_stacks = {"chest": 0, "depths": 0, "tail": 0}

	var taken1: int = main._take_damage(10, "chest")
	check("part hit at dev 0: no multiplier yet", taken1, 10)
	check("part hit at Lv0: level stays", int(main.part_dev["chest"]), 0)
	check("part hit at Lv0: first of six stacks", int(main.part_stacks["chest"]), 1)
	main.part_stacks["chest"] = 5
	main.player_hp = main.player_max_hp
	main._take_damage(10, "chest")
	check("sixth stack at Lv0 develops to Lv1", int(main.part_dev["chest"]), 1)
	check("Lv0 climax resets the stack", int(main.part_stacks["chest"]), 0)

	main.part_dev["chest"] = 2
	main.part_stacks["chest"] = 3
	main.player_hp = main.player_max_hp
	var taken2: int = main._take_damage(10, "chest")
	check("part hit at dev 2: x1.5", taken2, 15)
	check("fourth stack at Lv2 develops to Lv3", int(main.part_dev["chest"]), 3)
	check("level-up resets the climax stack", int(main.part_stacks["chest"]), 0)
	main.part_stacks["chest"] = 2
	main.player_hp = main.player_max_hp
	main._take_damage(10, "chest")
	check("third stack at Lv3 keeps Lv3", int(main.part_dev["chest"]), 3)
	check("Lv3 climax resets its stack", int(main.part_stacks["chest"]), 0)
	main._develop_part("chest")
	check("part development caps at 3", int(main.part_dev["chest"]), 3)

	main.player_hp = main.player_max_hp
	var taken3: int = main._take_damage(10, "")
	check("plain hit: no multiplier", taken3, 10)
	check("plain hit: leaves chest development alone", int(main.part_dev["chest"]), 3)
	check("plain hit: leaves chest stack alone", int(main.part_stacks["chest"]), 0)

	main.player_shield = 20
	main.player_hp = main.player_max_hp
	var taken4: int = main._take_damage(10, "chest")
	check("part hit fully blocked: nothing gets through", taken4, 0)
	check("part hit fully blocked: does not add a stack", int(main.part_stacks["chest"]), 0)
