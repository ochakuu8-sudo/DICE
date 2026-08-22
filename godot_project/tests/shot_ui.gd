extends SceneTree

# Not a test: a screenshot harness. Drives the real screen to a given
# 昂り level and writes a PNG, so the UI can be looked at at each stage
# of the ramp instead of guessed at. Excluded from exports along with
# the rest of tests/.

func _init() -> void:
	var main = load("res://scripts/Main.gd").new()
	root.add_child(main)
	await process_frame
	await process_frame

	main._start_run("knight")
	main.map_row = 0
	main.map_col = 0
	main._start_encounter()
	main._close_overlay()
	await process_frame

	# The last enemy in the table is the boss: it carries a part, a debuff
	# and two traits, so the dossier is at its fullest here rather than at
	# its emptiest. はぐれ兵 would have shown an empty note and proved
	# nothing about whether the note fits.
	main.enemies = []
	main.map_row = 6
	main.map_col = 0
	main._ensure_map_node(6, 0)
	main.map_nodes[6][0]["type"] = "boss"
	main.map_nodes[6][0]["enemy"] = main.enemy_defs.size() - 1
	main._setup_encounter()
	main._refresh_all()

	for shot in [
		{"name": "ui_00", "hp_frac": 1.0, "parts": {"chest": 0, "depths": 0, "tail": 0}},
		{"name": "ui_50", "hp_frac": 0.5, "parts": {"chest": 2, "depths": 1, "tail": 0}},
		{"name": "ui_85", "hp_frac": 0.15, "parts": {"chest": 5, "depths": 3, "tail": 1}},
	]:
		main.player_hp = int(round(float(main.player_max_hp) * float(shot["hp_frac"])))
		main.part_dev = (shot["parts"] as Dictionary).duplicate()
		main.hp_bar.display_value = float(main.player_max_hp - main.player_hp)
		main._refresh_all()
		await process_frame
		await process_frame
		await process_frame
		var img: Image = root.get_viewport().get_texture().get_image()
		img.save_png("user://%s.png" % str(shot["name"]))
		print("wrote %s (hp=%d/%d)" % [str(shot["name"]), main.player_hp, main.player_max_hp])

	print(ProjectSettings.globalize_path("user://"))
	quit(0)
