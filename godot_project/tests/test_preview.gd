extends SceneTree

# Headless smoke test for the two-stage tap. Drives the real Main node the
# way a player's thumb would and asserts that the first tap only looks and
# the second tap commits.

var fails := 0

# Every face showing in hand is one this die could actually have rolled —
# which is also how "nothing is sitting there unthrown" is checked, since an
# unthrown die used to show a 0 that no die but 居合 has.
func _faces_are_real(main) -> bool:
	for die in main.hand:
		if not (die["faces"] as Array).has(int(die.get("roll", 0))):
			return false
	return true

func _rolls(main) -> Array:
	var out := []
	for die in main.hand:
		out.append(int(die.get("roll", 0)))
	return out

func _six_ahead(main) -> Array:
	var out := []
	for i in range(1, 7):
		out.append(main._pos_for_step(main.player_step + i))
	return out

func check(label: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		fails += 1

func _init() -> void:
	var main = load("res://scripts/Main.gd").new()
	root.add_child(main)
	await process_frame
	await process_frame

	main._start_run("knight")
	main.map_row = 0
	main.map_col = 0
	main._start_encounter()
	await process_frame

	check("hand was dealt", main.hand.size() > 0)
	check("nothing considered at turn start", main.preview_die_index == -1)

	# --- a die is thrown as it is drawn, not when the hand is tapped ---
	check("every die in hand already shows one of its own faces",
		_faces_are_real(main))

	# --- a die that is not spent keeps its face into the next turn ---
	var kept: Array = _rolls(main)
	main._start_player_turn()
	check("a full hand carries every face into the next turn",
		_rolls(main) == kept)

	# Spend one (without walking it — the walk is what the rest of this file
	# is about) and the survivors are still not re-thrown; only the refill is.
	main.hand.remove_at(0)
	var survivors: Array = _rolls(main)
	main._start_player_turn()
	var refilled: Array = _rolls(main)
	check("the hand is refilled to its limit", refilled.size() == main.hand_limit)
	check("the dice left alone keep the faces they had",
		refilled.slice(0, survivors.size()) == survivors)
	check("and the die drawn to replace the spent one arrived thrown",
		_faces_are_real(main))

	main._refresh_board()
	check("the lookahead strip is six squares before any die is picked",
		main.preview_path.size() == 6)
	check("no route is drawn before any die is picked",
		main.preview_route.is_empty())

	var start_step: int = main.player_step
	var actions_before: int = main.actions_left
	var hand_before: int = main.hand.size()

	# --- first tap: information only ---
	await main._on_die_pressed(0)
	check("first tap sets the considered die", main.preview_die_index == 0)
	check("first tap does not move the piece", main.player_step == start_step)
	check("first tap does not spend an action", main.actions_left == actions_before)
	check("first tap does not discard the die", main.hand.size() == hand_before)
	check("first tap leaves state playable", main.state == "player")
	check("preview route is the die's route",
		main.preview_route.size() > 0 and main.preview_route == main._route_for_roll(int(main.hand[0]["roll"])))
	check("the lookahead strip stays six squares while considering",
		main.preview_path.size() == 6)
	check("the strip is the road ahead, not the die's route",
		main.preview_path == _six_ahead(main))
	var text: String = main._die_preview_text(0)
	check("preview text mentions the landing square", text.find("着地") >= 0)
	print("    log: " + text)

	# --- tapping a different die moves the question, still no commit ---
	if main.hand.size() > 1:
		await main._on_die_pressed(1)
		check("tapping another die re-aims the preview", main.preview_die_index == 1)
		check("re-aiming still does not move", main.player_step == start_step)
		check("re-aiming still does not spend", main.actions_left == actions_before)
		# put the question back on die 0
		await main._on_die_pressed(0)

	# --- cancelling by tapping the board ---
	main._on_cell_pressed(main._idx(main.player_pos.x, main.player_pos.y))
	check("board tap cancels the preview", main.preview_die_index == -1)
	check("cancel does not spend an action", main.actions_left == actions_before)

	# --- second tap on the same die commits ---
	await main._on_die_pressed(0)
	check("re-selected after cancel", main.preview_die_index == 0)
	var expected: Vector2i = main._landing_cell_for(int(main.hand[0]["roll"]))
	await main._on_die_pressed(0)
	check("second tap clears the preview", main.preview_die_index == -1)
	main._refresh_board()
	check("committing clears the route", main.preview_route.is_empty())
	check("committing leaves the strip at six", main.preview_path.size() == 6)
	check("second tap spent the die", main.hand.size() == hand_before - 1)
	check("second tap landed where the preview promised",
		main.player_pos == expected or not main._any_enemy_alive() or main.state == "game_over")

	# --- a reroll drops whatever was being considered ---
	if main.state == "player":
		main.preview_die_index = 0
		main.rerolls_left = 1
		await main._reroll_hand()
		check("reroll clears the considered die", main.preview_die_index == -1)
		check("a reroll spends the turn's reroll", main.rerolls_left == 0)

	print("\n%d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
