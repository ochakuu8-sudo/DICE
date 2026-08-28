extends SceneTree

# A tile reward grows the ring by exactly one square, at a square the
# player taps, until the board hits its ceiling. This checks that growth
# never loses or reorders a square the player already has, that it grows
# only the tapped square's own side (column), that the schedule reaches
# the ceiling one square at a time and stops there, and that the corner
# warps keep resolving to real squares on an asymmetrically grown board.

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

	# --- every starting square knows its own side -----------------------
	check("side lengths sum to the ring size",
		int(main.side_len["top"]) + int(main.side_len["right"])
			+ int(main.side_len["bottom"]) + int(main.side_len["left"]),
		main.ring_cells.size())
	var sides := []
	for cell in main.ring_cells:
		sides.append(main._side_of(cell))
	check("sides read top,top,top,right,right,bottom,bottom,left", sides,
		["top", "top", "top", "right", "right", "bottom", "bottom", "left"])

	# --- one insertion grows exactly one square, on the tapped side -----
	var old_ring: Array = main.ring_cells.duplicate()
	for i in range(old_ring.size()):
		var p: Vector2i = old_ring[i]
		main.permanent_board[p.y][p.x] = "mark_%d" % i
	var before := _ring_content(main)
	var tap: Vector2i = old_ring[3]  # the first "right" square
	check("tapped square is on the right side", main._side_of(tap), "right")

	var ok: bool = main._grow_ring_with_tile("respite", tap)
	var after := _ring_content(main)
	check("insertion succeeds", ok, true)
	check("the ring grows by exactly one square", after.size(), before.size() + 1)
	check("only the tapped side's length changed",
		[main.side_len["top"], main.side_len["right"], main.side_len["bottom"], main.side_len["left"]],
		[3, 3, 2, 1])
	check("the new square lands right after the tapped one, in ring order",
		after[4], "respite")

	# Removing that one new entry must reproduce the pre-growth sequence
	# exactly, in order — nothing already on the board was lost or moved.
	var without_new: Array = after.duplicate()
	without_new.remove_at(4)
	check("every old square survives, in its old order", without_new, before)

	# --- repeated growth on one side stays consistent, and stops at cap -
	var sizes := [after.size()]
	while main._can_grow_board():
		var last: Vector2i = main.ring_cells[main.ring_cells.size() - 1]
		main._grow_ring_with_tile("strike", last)
		sizes.append(main.ring_cells.size())
	check("growth reaches the ceiling one square at a time",
		sizes, range(9, 17))
	check("no further growth once capped",
		main._grow_ring_with_tile("strike", main.ring_cells[0]), false)
	check("the ring stays at the ceiling", main.ring_cells.size(), main.MAX_RING_LEN)

	# --- corners still resolve on an asymmetrically grown board ---------
	check("top-left corner is still the start", main._warp_face_step(main.CORNER_TL), 0)
	check("every corner lands on a distinct square", _corners_distinct(main), true)

	# --- reward flow: tap to grow below the ceiling, replace at cap -----
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
	check("a reward below the ceiling asks where to insert, not where to replace",
		main.state, "reward_insert")
	check("the ring has not grown yet — a spot still has to be tapped",
		main.ring_cells.size(), before_len)

	var target: Vector2i = main.ring_cells[2]
	main._on_cell_pressed(main._idx(target.x, target.y))
	check("the first tap previews without growing the ring",
		main.ring_cells.size(), before_len)
	check("the first tap marks the previewed square", main.preview_place_pos, target)
	main._on_cell_pressed(main._idx(target.x, target.y))
	check("the second tap confirms the insertion",
		main.ring_cells.size(), before_len + 1)
	check("confirming returns to the map", main.state, "map")

	# Force the board to its ceiling, then confirm the same reward now
	# asks for a replacement instead of an insertion point.
	while main._can_grow_board():
		var last: Vector2i = main.ring_cells[main.ring_cells.size() - 1]
		main._grow_ring_with_tile("strike", last)
	main._on_reward_selected("respite", "息継ぎマス")
	check("a reward at the ceiling falls back to replacement",
		main.state, "reward_place")
	check("the ring does not grow past the ceiling", main.ring_cells.size(), main.MAX_RING_LEN)
