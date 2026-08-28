extends SceneTree

# A tile reward grows the ring instead of overwriting a square on it, until
# the board hits its ceiling. This checks that growth never loses or
# reorders a square the player already has, that both new squares carry
# the tile just picked, that the schedule actually reaches the ceiling and
# stops there, and that the corner warps keep resolving to real squares
# once the board is no longer eight cells.

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

	# Mark every current square with a unique, synthetic id — content the
	# growth function never inspects (it moves strings around opaquely),
	# so this pins down exactly which square is which regardless of what
	# tile actually happens to sit there.
	var old_ring: Array = main.ring_cells.duplicate()
	for i in range(old_ring.size()):
		var p: Vector2i = old_ring[i]
		main.permanent_board[p.y][p.x] = "mark_%d" % i
	var before := _ring_content(main)
	check("starts at eight squares", before.size(), 8)

	var added: int = main._grow_ring_with_tile("respite")
	var after := _ring_content(main)
	check("growth reports two squares added", added, 2)
	check("the ring is now ten squares", after.size(), 10)
	check("board dims grew to 4x3", [main.board_w, main.board_h], [4, 3])
	check("both new squares are the reward tile", after.count("respite"), 2)

	# Every original marker must still be present, and in its original
	# relative order — dropping just the two "respite" entries (which
	# cannot collide with a "mark_N" string) reproduces the old sequence.
	var without_new := after.filter(func(id): return id != "respite")
	check("every old square survives growth, in its old order",
		without_new, before)

	# --- the schedule reaches the ceiling and stops --------------------
	var sizes := [10]
	while main._can_grow_board():
		main._grow_ring_with_tile("strike")
		sizes.append(main.ring_cells.size())
	check("growth schedule reaches the ceiling", sizes, [10, 12, 14, 16])
	check("board sits at the ceiling", [main.board_w, main.board_h],
		[main.MAX_BOARD_W, main.MAX_BOARD_H])
	check("no further growth once capped", main._grow_ring_with_tile("strike"), 0)
	check("the ring stays sixteen squares", main.ring_cells.size(), 16)

	# --- corners still resolve on a grown board -------------------------
	check("top-left corner is still the start", main._warp_face_step(main.CORNER_TL), 0)
	check("top-right corner is the current board's actual corner",
		main.ring_index_map.get(Vector2i(main.board_w - 1, 0), -1),
		main._warp_face_step(main.CORNER_TR))
	check("every corner lands on a distinct square", _corners_distinct(main), true)

	# --- reward flow: grows below the ceiling, replaces once capped ----
	await _reward_flow_case()

	print("\n%d failure(s)" % fails)
	quit(1 if fails > 0 else 0)

func _ring_content(main) -> Array:
	var out := []
	for cell in main.ring_cells:
		out.append(str(main.permanent_board[cell.y][cell.x]))
	return out

func _corners_distinct(main) -> bool:
	var seen := {}
	for face in [main.CORNER_TL, main.CORNER_TR, main.CORNER_BR, main.CORNER_BL]:
		seen[main._normalize_step(main._warp_face_step(face))] = true
	return seen.size() == 4

func _reward_flow_case() -> void:
	var main = load("res://scripts/Main.gd").new()
	root.add_child(main)
	await process_frame
	await process_frame
	main._start_run("knight")

	var before_len: int = main.ring_cells.size()
	main._on_reward_selected("respite", "息継ぎマス")
	check("a reward below the ceiling grows the board, no tap needed",
		main.ring_cells.size(), before_len + 2)
	check("growth does not enter the tap-to-place state", main.state != "reward_place", true)

	# Force the board to its ceiling, then confirm the same call now asks
	# for a placement instead of growing further.
	while main._can_grow_board():
		main._grow_ring_with_tile("strike")
	main._on_reward_selected("respite", "息継ぎマス")
	check("a reward at the ceiling falls back to placement",
		main.state, "reward_place")
	check("the ring does not grow past the ceiling", main.ring_cells.size(), 16)
