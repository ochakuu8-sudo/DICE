extends SceneTree

# The expedition is a directed, fully revealed route map. A D6 translates to
# one through three connection steps, not a Manhattan-distance board jump.

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
	check("map has eight stages", main.map_nodes.size(), main.MAP_ROWS)
	check("map keeps its layout width", (main.map_nodes[0] as Array).size(), main.MAP_COLS)
	check("start is centred", Vector2i(main.map_col, main.map_row), Vector2i(3, 0))
	check("boss is the final single node", str(main.map_nodes[7][4]["type"]), "boss")

	var row_counts := []
	var forward_only := true
	var shortcut_found := false
	for row in range(main.MAP_ROWS):
		var count := 0
		for col in range(main.MAP_COLS):
			var node = main.map_nodes[row][col]
			if node == null:
				continue
			count += 1
			for target in main._node_link_positions(node):
				if target.y <= row:
					forward_only = false
			if str(node["type"]) == "shortcut":
				shortcut_found = true
				for target in main._node_link_positions(node):
					if target.y != row + 2:
						shortcut_found = false
		row_counts.append(count)
	check("each route stage has two or three choices", row_counts, [1, 2, 3, 3, 3, 2, 2, 1])
	check("all links move toward the boss", forward_only, true)
	check("a shortcut skips exactly one stage", shortcut_found, true)

	main.rng.seed = 7
	var fatigue_before: int = int(main.player_fatigue)
	await main._on_explore_roll_pressed()
	check("exploration roll has a face", main.explore_roll >= 1 and main.explore_roll <= 6, true)
	check("rolling costs fatigue", main.player_fatigue, fatigue_before + main.EXPLORE_FATIGUE_PER_ROLL)
	var targets: Array = main._map_reachable()
	check("a roll produces connected destinations", targets.is_empty(), false)
	var forward_targets := true
	for target in targets:
		var p: Vector2i = target
		if p.y <= main.map_row or main._map_node_at(p.y, p.x) == null:
			forward_targets = false
	check("destinations are only forward connected nodes", forward_targets, true)

	main.explore_roll = 1
	check("low roll means one stage", main._explore_steps(), 1)
	var low_targets: Array = main._map_reachable()
	check("low roll reaches only the next stage", low_targets.map(func(p): return p.y), [1, 1])
	main.explore_roll = 6
	check("die pips equal movement links", main._explore_steps(), 6)
	check("high roll reaches the sixth stage", main._map_reachable().any(func(p): return p.y >= 6), true)
	check("reachable paths are highlighted as edges", main._map_reachable_edges().is_empty(), false)

	await main._on_explore_reroll_pressed()
	check("reroll costs fatigue", main.player_fatigue,
		fatigue_before + main.EXPLORE_FATIGUE_PER_ROLL + main.EXPLORE_REROLL_FATIGUE)
	check("a reroll was recorded", main.explore_rerolls, 1)

	# A legal rest route resolves outside combat and consumes the movement roll.
	main.map_row = 5
	main.map_col = 3
	main.explore_roll = 1
	main._on_map_node_pressed(6, 2)
	check("movement updates the route position", Vector2i(main.map_col, main.map_row), Vector2i(2, 6))
	check("movement consumes the exploration roll", main.explore_roll, 0)
	check("rest node resolves outside battle", main.state, "node_event")
	main._close_overlay()
	main._show_map()

	var saved: Array = main._serialize_map()
	main._deserialize_map(saved)
	check("saved map preserves a shortcut", str(main.map_nodes[3][6]["type"]), "shortcut")
	check("saved map preserves route links", main._node_link_positions(main.map_nodes[3][6]).map(func(p): return p.y), [5, 5])

	main._finish_floor()
	check("boss win advances the floor", main.floor_index, 2)
	check("next floor has a fresh route map", main.map_nodes.size(), main.MAP_ROWS)

	print("\n%d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
