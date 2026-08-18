extends SceneTree

# The squares added on top of conditions nothing used before (max_roll,
# has_shield, min_poison, action), plus the two dice whose faces sit outside
# the 1-6 range the rest of the roster lives in. Each is checked the same
# way the rest of the content is: what the board printed against what the
# move actually did.

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

	# --- 小刻み: opens at or below its roll, shut above it -------------
	await tile_case(main, "pinpoint", "normal", 2, 18)
	await tile_case(main, "pinpoint", "normal", 3, 0, true)
	# 逆走's faces are negative, so they satisfy every max_roll condition.
	await tile_case(main, "pinpoint", "reverse", -5, 18)
	await tile_case(main, "read", "normal", 1, 0, false, {"actions": 2})
	await tile_case(main, "read", "normal", 2, 0, true)

	# --- 要塞: has_shield, held rather than spent ---------------------
	await tile_case(main, "shieldbash", "normal", 3, 0, true)           # no shield
	await tile_case(main, "shieldbash", "normal", 3, 14, false, {"shield": 4})
	# The shield is not consumed by it.
	await tile_case(main, "shieldbash", "normal", 3, 14, false, {"shield": 4, "keeps_shield": 4})

	# --- 毒: thresholds ------------------------------------------------
	await tile_case(main, "plaguefang", "normal", 3, 0, true, {"poison": 4})
	await tile_case(main, "plaguefang", "normal", 3, 22, false, {"poison": 5})

	# --- 狙撃: the first action ---------------------------------------
	await tile_case(main, "firststrike", "normal", 3, 12)
	# On the second action of a turn it is shut.
	await tile_case(main, "firststrike", "normal", 3, 0, true, {"action_index": 1})

	# --- 居合: the standing 0 ------------------------------------------
	await iai_case(main)
	# --- 大車輪: nine squares, and the HP it charges -------------------
	await wheel_case(main)

	print("\n%d failure(s)" % fails)
	quit(1 if fails > 0 else 0)

# Puts the tile one roll ahead, walks the die into it, and compares the
# board's printed number with the damage actually dealt.
func tile_case(main, tile_id: String, die_id: String, roll: int, want: int,
		want_blocked: bool = false, opts: Dictionary = {}) -> void:
	_reset(main)
	var target: Vector2i = main._pos_for_step(main.player_step + roll)
	main.permanent_board[target.y][target.x] = tile_id
	main.player_shield = int(opts.get("shield", 0))
	main.action_index = int(opts.get("action_index", 0))
	if int(opts.get("poison", 0)) > 0:
		main.enemies[0]["poison"] = int(opts["poison"])

	main.hand = [main._make_die(die_id), main._make_die("normal")]
	main.hand[0]["roll"] = roll
	main.hand[1]["roll"] = 1
	main.dice_rolled = true
	main.actions_left = 2

	main.preview_die_index = 0
	main._refresh_board()
	var readout: Dictionary = main._tile_readout(main.tile_defs[tile_id], target)
	var tag := "%s + %s(%d)" % [tile_id, die_id, roll]
	check(tag + ": gated", bool(readout.get("blocked", false)), want_blocked)
	var shown: int = 0 if want_blocked else int(readout["text"])

	var hp0: int = int(main.enemies[0]["hp"])
	var actions_before: int = main.actions_left
	await main._on_die_pressed(0)
	var dealt: int = hp0 - int(main.enemies[0]["hp"])

	if not want_blocked and want > 0:
		check(tag + ": preview", shown, want)
	check(tag + ": dealt", dealt, want)
	if opts.has("actions"):
		# 見切り returns the action it cost: spent one, got one back.
		check(tag + ": action returned", main.actions_left, int(opts["actions"]))
	if opts.has("keeps_shield"):
		check(tag + ": shield untouched", main.player_shield, int(opts["keeps_shield"]))

# 0 does not move the piece, and re-fires the square it is already on.
func iai_case(main) -> void:
	_reset(main)
	var here: Vector2i = main.player_pos
	main.permanent_board[here.y][here.x] = "fort"     # 盾+6 on stop
	main.hand = [main._make_die("iai"), main._make_die("normal")]
	main.hand[0]["roll"] = 0
	main.hand[1]["roll"] = 1
	main.dice_rolled = true
	main.actions_left = 2
	main.player_shield = 0

	main.preview_die_index = 0
	main._refresh_board()
	check("居合 0: preview crosses nothing", main._readout_crossed, 0)
	check("居合 0: preview lands where it stands", main._landing_cell_for(0), here)

	var start: int = main.player_step
	await main._on_die_pressed(0)
	check("居合 0: the piece did not move", main.player_step, start)
	check("居合 0: the square fired again", main.player_shield, 6)
	check("居合 0: it still cost an action", main.actions_left, 1)

	# Its faces are legal die faces and the bag can hold it.
	check("居合 is offered as a reward", main.die_reward_pool.has("iai"), true)

func wheel_case(main) -> void:
	_reset(main)
	main.hand = [main._make_die("wheel"), main._make_die("normal")]
	main.hand[0]["roll"] = 9
	main.hand[1]["roll"] = 1
	main.dice_rolled = true
	main.actions_left = 2
	var hp_before: int = main.player_hp
	var start: int = main.player_step
	var predicted: Vector2i = main._landing_cell_for(9)
	main.preview_die_index = 0
	await main._on_die_pressed(0)
	check("大車輪 9: walked nine squares",
		((main.player_step - start) % 16 + 16) % 16, 9)
	check("大車輪 9: landed where predicted", main.player_pos, predicted)
	check("大車輪: charged 1 HP to swing", hp_before - main.player_hp, 1)

func _reset(main) -> void:
	main._start_run("knight")
	main.map_row = 0
	main.map_col = 0
	main._start_encounter()
	main.permanent_board = main._make_empty_board("empty")
	main.temp_board = main._make_empty_board("none")
	main.enemies = [main._make_enemy("かかし", 9999, 0, "cell", "fixed", [])]
	main.player_hp = main.player_max_hp
	main.player_shield = 0
	main.combo = 0
	main.charge_map = {}
	main.action_index = 0
