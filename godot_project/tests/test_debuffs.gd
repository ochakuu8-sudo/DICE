extends SceneTree

# The four enemy debuffs, each checked the same way: set up a board, read
# what the preview promises, then actually walk the move and compare against
# what happened. A debuff the preview cannot predict would break the
# two-stage tap, so prediction is tested as hard as the effect itself.

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

	# --- the board is sixteen squares ---------------------------------
	check("ring size", main.ring_cells.size(), 16)
	check("board is 5x5", [main.BOARD_W, main.BOARD_H], [5, 5])
	check("top-left corner warps to step 0", main.WARP_FACES[main.CORNER_TL]["step"], 0)
	check("top-right corner warps to step 4", main.WARP_FACES[main.CORNER_TR]["step"], 4)
	check("bottom-right corner warps to step 8", main.WARP_FACES[main.CORNER_BR]["step"], 8)
	check("bottom-left corner warps to step 12", main.WARP_FACES[main.CORNER_BL]["step"], 12)
	var perimeter := true
	for cell in main.ring_cells:
		if cell.x != 0 and cell.x != 4 and cell.y != 0 and cell.y != 4:
			perimeter = false
	check("every ring cell is on the perimeter", perimeter, true)
	check("hero tiles all sit on the ring",
		_hero_tiles_on_ring(main), true)

	# --- 炎上: charges for entering, every time ------------------------
	# Roll 3 over two burning squares: 2 + 2 = 4 HP.
	await run_case(main, "burn", [1, 2], 3, "normal", 4, 3)
	# The square it stops on burns too — entering is entering.
	await run_case(main, "burn", [3], 3, "normal", 2, 3)

	# --- 毒: charges only for ending there -----------------------------
	# Two poisoned squares walked over, neither landed on: nothing.
	await run_case(main, "venom", [1, 2], 3, "normal", 0, 3)
	# Landed on: 4.
	await run_case(main, "venom", [3], 3, "normal", 4, 3)

	# --- 軽業 pays neither ---------------------------------------------
	await run_case(main, "burn", [1, 2, 3], 3, "nimble", 0, 3)
	await run_case(main, "venom", [3], 3, "nimble", 0, 3)

	# --- 茨: takes the distance, not the HP ----------------------------
	# Roll 5 into a briar at +2: the move ends at +2, three steps lost.
	await run_case(main, "briar", [2], 5, "normal", 0, 2)

	# --- 凍結: takes the square, and comes off under any foot ----------
	await freeze_case(main)
	await freeze_walked_case(main)

	# --- a trampled briar is gone --------------------------------------
	await briar_consumed_case(main)

	# --- each enemy fouls in its own kind ------------------------------
	enemy_debuff_case(main)

	# --- charge counts turns, not deposits -----------------------------
	charge_clock_case(main)

	print("\n%d failure(s)" % fails)
	quit(1 if fails > 0 else 0)

func _hero_tiles_on_ring(main) -> bool:
	for entry in main.hero_defs["knight"]["tiles"]:
		if not main.ring_index_map.has(Vector2i(int(entry[0]), int(entry[1]))):
			return false
	return true

# Sets the named debuff on the given step offsets, walks one die, and checks
# both the HP the preview promised and the HP actually lost, plus where the
# piece ended up.
func run_case(main, debuff: String, offsets: Array, roll: int, die_id: String,
		want_hp_loss: int, want_steps: int) -> void:
	_reset(main)
	for off in offsets:
		var p: Vector2i = main._pos_for_step(main.player_step + int(off))
		main.temp_board[p.y][p.x] = debuff

	main.hand = [main._make_die(die_id), main._make_die("normal")]
	main.hand[0]["roll"] = roll
	main.hand[1]["roll"] = 1
	main.actions_left = 2

	var start_step: int = main.player_step
	var expected_landing: Vector2i = main._landing_cell_for(roll)

	# What the first tap promises.
	main.preview_die_index = 0
	main._refresh_board()
	var promised := _promised_hp_loss(main, 0)

	var hp_before: int = main.player_hp
	await main._on_die_pressed(0)
	var lost: int = hp_before - main.player_hp
	var walked: int = ((main.player_step - start_step) % 16 + 16) % 16

	var tag := "%s x%d roll%d %s" % [debuff, offsets.size(), roll, die_id]
	check(tag + ": preview HP cost", promised, want_hp_loss)
	check(tag + ": actual HP cost", lost, want_hp_loss)
	check(tag + ": steps walked", walked, want_steps)
	check(tag + ": landed where preview said", main.player_pos, expected_landing)

# Re-derives the preview's HP figure the same way _die_preview_text does,
# so the two cannot drift apart.
func _promised_hp_loss(main, index: int) -> int:
	var die: Dictionary = main.hand[index]
	var roll := int(die["roll"])
	var route: Array = main._route_for_roll(roll)
	var total := 0
	for i in range(route.size()):
		total += main._debuff_damage(route[i], "pass", die)
		if i == route.size() - 1:
			total += main._debuff_damage(route[i], "stop", die)
	return total

# 凍結 landed on: the landing pays nothing and melts the ice, so a whole
# action goes on thawing one square. The order this resolves in is the point
# — the walk enters the landing square before the action stops on it, so a
# thaw applied to the entering foot would hand the landing the very effect
# the ice is supposed to cost.
func freeze_case(main) -> void:
	_reset(main)
	# A 砦 (盾+6 on stop) three squares ahead, frozen solid.
	var target: Vector2i = main._pos_for_step(main.player_step + 3)
	main.permanent_board[target.y][target.x] = "fort"
	main.temp_board[target.y][target.x] = "freeze"

	main.hand = [main._make_die("normal"), main._make_die("normal")]
	main.hand[0]["roll"] = 3
	main.hand[1]["roll"] = 1
	main.actions_left = 2

	main.preview_die_index = 0
	main._refresh_board()
	var readout: Dictionary = main._tile_readout(main.tile_defs["fort"], target)
	check("frozen square reads as blocked", bool(readout.get("blocked", false)), true)
	check("frozen square prints ×", str(readout["text"]), "×")
	check("the preview promises the thaw",
		main._die_preview_text(0).contains("溶かす"), true)

	var shield_before: int = main.player_shield
	await main._on_die_pressed(0)
	check("frozen 砦 grants no shield", main.player_shield, shield_before)
	check("stopping on it thawed it",
		str(main.temp_board[target.y][target.x]), "none")

	# Thawed, the same square now pays out in full.
	main.hand = [main._make_die("normal"), main._make_die("normal")]
	main.hand[0]["roll"] = 16
	main.hand[1]["roll"] = 1
	main.actions_left = 2
	main.player_step = main._track_index(target) - 3
	main.player_pos = main._pos_for_step(main.player_step)
	main.hand[0]["roll"] = 3
	main.player_shield = 0
	main.preview_die_index = 0
	await main._on_die_pressed(0)
	check("thawed 砦 pays out again", main.player_shield, 6)

# 凍結 walked over: the pass gets nothing either, but the ice breaks under
# the foot, so the square is working again from the next time anything
# touches it. This is the cheap way to clear it — the walk was happening
# anyway — and it is what stops the ice being a square the player has to
# spend an action on.
func freeze_walked_case(main) -> void:
	_reset(main)
	# 斬撃路 (通過ごとに3ダメージ) two squares ahead, iced over, and a roll
	# of 5 that runs straight past it.
	var road: Vector2i = main._pos_for_step(main.player_step + 2)
	main.permanent_board[road.y][road.x] = "slash"
	main.temp_board[road.y][road.x] = "freeze"
	_arm(main, 5)

	var hp_before: int = int(main.enemies[0]["hp"])
	await main._on_die_pressed(0)
	check("walking over a frozen 斬撃路 deals nothing",
		int(main.enemies[0]["hp"]), hp_before)
	check("passing over it melted it",
		str(main.temp_board[road.y][road.x]), "none")

	# Same square, same roll, now that the ice is off it.
	main.player_step = main._track_index(road) - 2
	main.player_pos = main._pos_for_step(main.player_step)
	_arm(main, 5)
	hp_before = int(main.enemies[0]["hp"])
	await main._on_die_pressed(0)
	check("a thawed 斬撃路 cuts again",
		hp_before - int(main.enemies[0]["hp"]), 3)

# One 標準 die on the given face, ready to be committed, with a spare in
# hand so the action does not roll straight into the enemy's turn.
func _arm(main, roll: int) -> void:
	main.hand = [main._make_die("normal"), main._make_die("normal")]
	main.hand[0]["roll"] = roll
	main.hand[1]["roll"] = 1
	main.actions_left = 2
	main.preview_die_index = 0

func briar_consumed_case(main) -> void:
	_reset(main)
	var spot: Vector2i = main._pos_for_step(main.player_step + 2)
	main.temp_board[spot.y][spot.x] = "briar"
	main.hand = [main._make_die("normal"), main._make_die("normal")]
	main.hand[0]["roll"] = 5
	main.hand[1]["roll"] = 1
	main.actions_left = 2
	main.preview_die_index = 0
	await main._on_die_pressed(0)
	check("trampled briar is cleared", str(main.temp_board[spot.y][spot.x]), "none")

# Every enemy that fouls names a debuff that actually exists, and the
# opening fight names none — an enemy teaching the rules should not also be
# rewriting the board.
func enemy_debuff_case(main) -> void:
	var named := 0
	for def in main.enemy_defs:
		var kind := str(def.get("debuff", ""))
		if kind == "":
			continue
		named += 1
		check("%s fouls with a real debuff" % str(def["name"]),
			main.temp_defs.has(kind), true)
		check("%s has a foul chance" % str(def["name"]),
			int(def.get("foul", 0)) > 0, true)
	check("the opening enemy fouls nothing",
		str((main.enemy_defs[0] as Dictionary).get("debuff", "")), "")
	check("most of the roster fouls", named >= 5, true)

func _reset(main) -> void:
	main._start_run("knight")
	main.map_row = 0
	main.map_col = 0
	main._start_encounter()
	main.permanent_board = main._make_empty_board("empty")
	main.temp_board = main._make_empty_board("none")
	# A harmless dummy: the map roll can otherwise hand us an enemy whose
	# regen or telegraph moves the numbers under the test.
	main.enemies = [main._make_enemy("かかし", 9999, 0, "cell", "fixed", [])]
	main.player_hp = main.player_max_hp
	main.player_shield = 0
	main.combo = 0
	main.charge_map = {}

# --- charge is a clock -------------------------------------------------
# It climbs by one every player turn and drops to nothing when something
# cashes it in, so what it reads is "turns since you last fired".
func charge_clock_case(main) -> void:
	# Deliberately not _reset(): that helper clears the charge map, which is
	# exactly the value under test here.
	main._start_run("knight")
	main.map_row = 0
	main.map_col = 0
	main._start_encounter()
	var here: Vector2i = main.player_pos
	var far: Vector2i = main._pos_for_step(main._track_index(here) + 8)

	check("a fight opens with one turn on every square",
		main._cell_charge(far), 1)
	main._start_player_turn()
	check("waiting a turn banks another", main._cell_charge(far), 2)
	main._start_player_turn()
	main._start_player_turn()
	check("and another, and another", main._cell_charge(far), 4)
	check("every square runs its own clock at the same rate",
		main._cell_charge(here), main._cell_charge(far))

	# 照準台 loads the whole ring rather than the square it sits on.
	main.charge_cell = here
	main._apply_op("charge_all", 2, "照準台")
	check("照準台 loads the far square too", main._cell_charge(far), 6)
	check("...and the near one", main._cell_charge(here), 6)

	# A square's own loading stays on that square.
	main.charge_cell = here
	main._apply_op("charge", 3, "蓄積砲台")
	check("a square's own charge is its own", main._cell_charge(here), 9)
	check("the far square is untouched by it", main._cell_charge(far), 6)

	# Firing empties the square that fired, and only that one.
	main.charge_cell = here
	main._apply_op("spend_charge", 0, "蓄積砲台")
	check("cashing in empties the square that fired", main._cell_charge(here), 0)
	check("the far square keeps its charge", main._cell_charge(far), 6)
	main._start_player_turn()
	check("the emptied square starts over", main._cell_charge(here), 1)
	check("the far square just keeps climbing", main._cell_charge(far), 7)
