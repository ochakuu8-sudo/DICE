extends SceneTree

# 陥落: an enemy's own attack finishing the player is not automatically a
# run-ending game over. Only the boss still ends the run outright; every
# other fight heals to full and hands the map back. A hazard-tile death
# (not by_enemy) still ends the run regardless of which node it happened
# on, because there is no enemy attack for a part or a tier to attach to.

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
	boss_defeat_case(main)
	hazard_death_case(main)
	part_multiplier_case(main)

	print("\n%d failure(s)" % fails)
	quit(1 if fails > 0 else 0)

func _reset(main) -> void:
	main._start_run("knight")
	main.map_row = 0
	main.map_col = 0
	main._start_encounter()
	main.encounter_name = "はぐれ兵"
	main.encounter_art = "stray"
	main._close_overlay()
	# lifetime persists to disk (user://profile.json) across real runs by
	# design, which means it also persists across separate invocations of
	# this test on the same machine. Zeroed here so every case starts from
	# a clean slate instead of accumulating with whatever a previous test
	# run — or a previous case in this same run — already wrote.
	main.lifetime = {}

# A non-boss defeat heals to full, keeps the run alive, and is counted
# separately from a real loss.
func mob_fall_case(main) -> void:
	_reset(main)
	main.player_hp = 1
	main._ensure_map_node(0, 0)
	main.map_nodes[0][0]["type"] = "battle"
	var losses_before := int(main.lifetime.get("losses", 0))
	main._resolve_defeat("test", true)
	check("mob fall: run is not over", main.state != "game_over", true)
	check("mob fall: healed to full", main.player_hp, main.player_max_hp)
	check("mob fall: counted as a fall", int(main.lifetime.get("falls", 0)), 1)
	check("mob fall: not counted as a loss", int(main.lifetime.get("losses", 0)), losses_before)

# The boss is the one fight this game cannot be walked away from twice.
func boss_defeat_case(main) -> void:
	_reset(main)
	main.player_hp = 1
	main._ensure_map_node(0, 0)
	main.map_nodes[0][0]["type"] = "boss"
	main._resolve_defeat("test", true)
	check("boss defeat: run is over", main.state, "game_over")
	check("boss defeat: counted as a loss", int(main.lifetime.get("losses", 0)), 1)

# Walking onto one poison square too many still ends the run even on a
# node that would have forgiven an enemy's attack — parts and tiers only
# ever apply to an enemy's own swing.
func hazard_death_case(main) -> void:
	_reset(main)
	main.player_hp = 0
	main._ensure_map_node(0, 0)
	main.map_nodes[0][0]["type"] = "battle"
	main._resolve_defeat("test hazard", false)
	check("hazard death: run is over even off the boss node", main.state, "game_over")

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

	main.player_hp = main.player_max_hp
	var taken3: int = main._take_damage(10, "")
	check("plain hit: no multiplier", taken3, 10)
	check("plain hit: leaves chest development alone", int(main.part_dev["chest"]), 3)

	main.player_shield = 20
	main.player_hp = main.player_max_hp
	var taken4: int = main._take_damage(10, "chest")
	check("part hit fully blocked: nothing gets through", taken4, 0)
	check("part hit fully blocked: does not develop", int(main.part_dev["chest"]), 3)
