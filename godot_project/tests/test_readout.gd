extends SceneTree

# Does the number the first tap prints match the damage the second tap deals?
# Each case sets up a board and a die, reads the preview, then actually walks
# the move and compares against the enemy's real HP loss.

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

	# 大斬撃 = 7 + roll, on a stop. Placed 3 squares ahead of the start.
	# 攻撃 die doubles stop-type attacks, so a roll of 3 must preview as
	# (7 + 3) * 2 = 20 and then actually deal 20.
	await run_case(main, "heavy", "blade", 3, 20)
	# ...and the same square with a plain die previews and deals 7 + 3.
	await run_case(main, "heavy", "normal", 3, 10)
	# 射撃台 = roll * 2, doubled by 攻撃 on stop: 3 * 2 * 2.
	await run_case(main, "bow", "blade", 3, 12)
	# 疾風路 = damage per square crossed; a roll of 3 crosses 3.
	await run_case(main, "gale", "normal", 3, 3)
	# 斬撃路 is a pass-type tile: 3 damage, tripled by 嵐撃's pass-attack mod.
	await run_case(main, "slash", "tempest", 3, 9)
	# 連撃台 = combo * 3. Spending the die is itself the first combo point,
	# so with the counter at 2 the preview must read 3 combo, not 2.
	await run_case(main, "volley", "normal", 3, 9, 2)
	# 共鳴盤 needs combo 3. At combo 2 the die's own point gets it there...
	await run_case(main, "resonance", "normal", 3, 14, 2)
	# ...and at combo 0 it cannot, so the square must say so instead of
	# advertising 14 damage it will not deal.
	await run_case(main, "resonance", "normal", 3, 0, 0, true)

	# --- 装甲 comes off the printed number too --------------------------
	# The board used to advertise the raw swing against armoured enemies,
	# and 大斬撃 — authored as two attack rows — paid the armour twice on
	# top of that. One strike of 7+roll against armour 2 is 8, and that is
	# what the square, the log and the enemy must all say.
	await run_case(main, "heavy", "normal", 3, 8, 0, false, 2)
	await run_case(main, "heavy", "blade", 3, 18, 0, false, 2)
	await run_case(main, "heavy", "normal", 3, 7, 0, false, 3)
	await run_case(main, "bow", "blade", 3, 10, 0, false, 2)
	await run_case(main, "slash", "tempest", 3, 7, 0, false, 2)
	# Armour thicker than the hit no longer erases it: every strike lands
	# for at least 1, so the square is bad here rather than non-existent.
	await run_case(main, "slash", "normal", 3, 1, 0, false, 5)
	await run_case(main, "slash", "normal", 3, 1, 0, false, 99)

	# --- 手負い: the wounds counter ------------------------------------
	# 背水刃 pays the HP already lost. At 36 max and 12 hurt, that is 12.
	await run_case(main, "lastblade", "normal", 3, 12, 0, false, 0, 12)
	# ...and armour still takes its slice off that one strike.
	await run_case(main, "lastblade", "normal", 3, 10, 0, false, 2, 12)
	# Unhurt, the square is worth nothing — it is a payoff, not a source.
	await run_case(main, "lastblade", "normal", 3, 0, 0, false, 0, 0)
	# --- charge now belongs to the square ------------------------------
	# 蓄積砲台 loads itself on the way in (pass) and fires on the stop, so a
	# square sitting on 5 turns of charge is walked onto at 6 and pays 4x6.
	await run_case(main, "battery", "normal", 3, 24, 0, false, 0, 0, 5)
	# An untouched square that has only banked its own turns still pays.
	await run_case(main, "battery", "normal", 3, 8, 0, false, 0, 0, 1)
	# 貫通砲 reads the same square charge but does not empty it.
	await run_case(main, "lance", "normal", 3, 15, 0, false, 0, 0, 5)

	# 死線 only opens below 35%: 36 max, 20 lost leaves 44%, still shut.
	await run_case(main, "deathline", "normal", 3, 0, 0, true, 0, 20)
	# 26 lost leaves 10/36 = 27%, open.
	await run_case(main, "deathline", "normal", 3, 25, 0, false, 0, 26)

	print("\n%d failure(s)" % fails)
	quit(1 if fails > 0 else 0)

func run_case(main, tile_id: String, die_id: String, roll: int, want: int,
		combo_start: int = 0, want_blocked: bool = false, armor: int = 0,
		wounds: int = 0, cell_charge: int = 0) -> void:
	main._start_run("knight")
	main.map_row = 0
	main.map_col = 0
	main._start_encounter()
	await process_frame

	# A clean ring with the one square under test three steps ahead.
	main.permanent_board = main._make_empty_board("empty")
	main.temp_board = main._make_empty_board("none")
	var target: Vector2i = main._pos_for_step(main.player_step + roll)
	main.permanent_board[target.y][target.x] = tile_id

	# A fixed enemy: the map roll can otherwise hand us the boss, whose regen
	# ticks during the enemy turn and makes "HP lost" the wrong measurement.
	main.enemies = [main._make_enemy("かかし", 9999, 0, "cell", "fixed", [])]
	main.enemies[0]["armor"] = armor

	# Two dice in hand and two actions, so spending one does not end the turn
	# and hand control to the enemy before we read the damage.
	main.hand = [main._make_die(die_id), main._make_die("normal")]
	main.hand[0]["roll"] = roll
	main.hand[1]["roll"] = 1
	main.dice_rolled = true
	main.actions_left = 2
	main.combo = combo_start
	main.player_hp = main.player_max_hp - wounds
	main.charge_map = {}
	if cell_charge > 0:
		main._set_cell_charge(target, cell_charge)

	# What the first tap says the square is worth.
	main._refresh_board()
	main.preview_die_index = 0
	main._refresh_board()
	var tile: Dictionary = main.tile_defs[tile_id]
	var readout: Dictionary = main._tile_readout(tile, target)
	check("%s + %s die%s: gated" % [tile_id, die_id,
		("" if armor == 0 else " vs armor %d" % armor) + ("" if wounds == 0 else " at %d wounds" % wounds)],
		bool(readout.get("blocked", false)), want_blocked)
	var previewed: int = 0 if want_blocked else int(readout["text"])

	# What the second tap actually does.
	var enemy: Dictionary = main.enemies[0]
	var hp_before := int(enemy["hp"])
	main.preview_die_index = 0
	await main._on_die_pressed(0)
	var dealt := hp_before - int(enemy["hp"])

	check("%s + %s die%s: preview" % [tile_id, die_id,
		("" if armor == 0 else " vs armor %d" % armor) + ("" if wounds == 0 else " at %d wounds" % wounds)], previewed, want)
	check("%s + %s die%s: dealt" % [tile_id, die_id,
		("" if armor == 0 else " vs armor %d" % armor) + ("" if wounds == 0 else " at %d wounds" % wounds)], dealt, want)
