extends SceneTree

# The expedition is a directed, fully revealed route map. Each choice moves
# exactly one connected node, so every fork is a deliberate route decision.

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
	check("map has twelve stages", main.map_nodes.size(), main.MAP_ROWS)
	check("map keeps its layout width", (main.map_nodes[0] as Array).size(), main.MAP_COLS)
	check("start is centred", Vector2i(main.map_col, main.map_row), Vector2i(3, 0))
	check("boss is the final single node", str(main.map_nodes[11][3]["type"]), "boss")

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
	check("each route stage has two or three choices", row_counts, [1, 2, 2, 3, 2, 3, 2, 3, 2, 3, 2, 1])
	check("all links move toward the boss", forward_only, true)
	check("a shortcut skips exactly one stage", shortcut_found, true)

	var targets: Array = main._map_reachable()
	check("start immediately offers connected destinations", targets.is_empty(), false)
	var forward_targets := true
	for target in targets:
		var p: Vector2i = target
		if p.y != main.map_row + 1 or main._map_node_at(p.y, p.x) == null:
			forward_targets = false
	check("destinations are only one forward step", forward_targets, true)
	check("reachable paths are highlighted as edges", main._map_reachable_edges().is_empty(), false)

	# A legal chest route resolves outside combat and costs fatigue for one step.
	main.map_row = 9
	main.map_col = 3
	var fatigue_before: int = int(main.player_fatigue)
	main._on_map_node_pressed(10, 4)
	check("movement updates the route position", Vector2i(main.map_col, main.map_row), Vector2i(4, 10))
	check("one movement costs fatigue", main.player_fatigue, fatigue_before + main.EXPLORE_FATIGUE_PER_MOVE)
	check("chest node opens a reward outside battle", main.state, "reward_select")
	main._close_overlay()
	main._show_map()

	var saved: Array = main._serialize_map()
	main._deserialize_map(saved)
	check("saved map preserves a shortcut", str(main.map_nodes[5][5]["type"]), "shortcut")
	check("saved map preserves route links", main._node_link_positions(main.map_nodes[5][5]).map(func(p): return p.y), [7])

	main._finish_floor()
	check("boss win advances the floor", main.floor_index, 2)
	check("next floor has a fresh route map", main.map_nodes.size(), main.MAP_ROWS)

	# --- the roster actually gets used --------------------------------
	# Ramping one curve over the whole run left the first table entry
	# unreachable (the opening row rounded past it) and clamped every
	# non-boss node on floors 2 and 3 onto the same enemy.
	check("the first battle of the run is the first enemy in the table",
		_first_battle_enemy(main), 0)
	for f in range(1, main.FLOOR_COUNT + 1):
		check("floor %d fields more than one enemy" % f,
			_floor_enemies(main, f).size() > 1, true)
	var all_seen := {}
	for f in range(1, main.FLOOR_COUNT + 1):
		for idx in _floor_enemies(main, f):
			all_seen[idx] = true
	check("every enemy in the table is reachable across a run",
		all_seen.size(), main.enemy_defs.size())

	print("\n%d failure(s)" % fails)
	quit(1 if fails > 0 else 0)

# The enemy index the run's earliest battle node resolves to.
func _first_battle_enemy(main) -> int:
	for row in range(main.MAP_ROWS):
		for raw in main.MAP_LAYOUT[row]:
			var spec: Dictionary = raw
			if str(spec["type"]) == "battle":
				return main._pick_enemy_for(row, "battle")
	return -1

# Every distinct enemy index a given floor can field, boss included.
func _floor_enemies(main, floor_index: int) -> Dictionary:
	var seen := {}
	for row in range(main.MAP_ROWS):
		for raw in main.MAP_LAYOUT[row]:
			var spec: Dictionary = raw
			var kind := str(spec["type"])
			if not (kind in ["battle", "elite", "boss"]):
				continue
			seen[main._pick_enemy_for(row + (floor_index - 1) * main.MAP_ROWS, kind)] = true
	return seen
