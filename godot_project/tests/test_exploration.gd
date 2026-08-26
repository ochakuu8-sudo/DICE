extends SceneTree

# The expedition board is fully visible, costs fatigue to roll, and only
# enables destinations that consume exactly the rolled distance.

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

	main._start_run("knight")
	check("grid has eight rows", main.map_nodes.size(), main.MAP_ROWS)
	check("grid has eight columns", (main.map_nodes[0] as Array).size(), main.MAP_COLS)
	check("start is at origin", Vector2i(main.map_col, main.map_row), Vector2i(0, 0))
	check("boss is published on the map", str(main.map_nodes[7][7]["type"]), "boss")

	main.rng.seed = 7
	var fatigue_before: int = int(main.player_fatigue)
	await main._on_explore_roll_pressed()
	check("exploration roll has a face", main.explore_roll >= 1 and main.explore_roll <= 6, true)
	check("rolling costs fatigue", main.player_fatigue, fatigue_before + main.EXPLORE_FATIGUE_PER_ROLL)
	var targets: Array = main._map_reachable()
	check("a roll produces destinations", targets.is_empty(), false)
	for target in targets:
		var p: Vector2i = target
		check("destination has exact rolled distance",
			abs(p.x - main.map_col) + abs(p.y - main.map_row), main.explore_roll)

	var rolled: int = int(main.explore_roll)
	await main._on_explore_reroll_pressed()
	check("reroll costs fatigue", main.player_fatigue,
		fatigue_before + main.EXPLORE_FATIGUE_PER_ROLL + main.EXPLORE_REROLL_FATIGUE)
	check("reroll remains a legal face", main.explore_roll >= 1 and main.explore_roll <= 6, true)
	check("a reroll was recorded", main.explore_rerolls, 1)
	# Keep the value read so an optimiser cannot turn the test into a no-op.
	check("first roll was recorded", rolled >= 1 and rolled <= 6, true)

	# Movement consumes the pending roll and resolves the selected public node.
	main.explore_roll = 4
	main._on_map_node_pressed(0, 4)
	check("movement updates the map position", Vector2i(main.map_col, main.map_row), Vector2i(4, 0))
	check("movement consumes the exploration roll", main.explore_roll, 0)
	check("rest node resolves outside battle", main.state, "node_event")
	main._close_overlay()
	main._show_map()

	# A boss win advances the floor and creates a fresh public grid.
	main._finish_floor()
	check("boss win advances the floor", main.floor_index, 2)
	check("next floor has a fresh grid", main.map_nodes.size(), main.MAP_ROWS)

	print("\n%d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
