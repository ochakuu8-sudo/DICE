extends SceneTree

# A tile reward grows the ring by exactly one square, at a square the
# player taps, until either that square's own side or the ring as a
# whole hits its ceiling. This checks that growth never loses or
# reorders a square the player already has, that it grows only the
# tapped square's own side (column), that a side stops accepting
# insertions at MAX_SIDE_LEN while others still can, that the ring as a
# whole stops at MAX_RING_LEN, and that the corner warps keep resolving
# to real squares on an asymmetrically grown board.

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

	# --- a single side stops at MAX_SIDE_LEN, well before the ring's own
	# ceiling, while the other three still have room -----------------
	var left_sizes := []
	while true:
		var left_cell: Vector2i = _find_side_cell(main, "left")
		if not main._grow_ring_with_tile("strike", left_cell):
			break
		left_sizes.append(int(main.side_len["left"]))
	check("left grows one at a time up to MAX_SIDE_LEN",
		left_sizes, range(2, main.MAX_SIDE_LEN + 1))
	check("left itself is now capped", int(main.side_len["left"]), main.MAX_SIDE_LEN)
	check("a capped side refuses further insertion",
		main._can_insert_after(_find_side_cell(main, "left")), false)
	check("the board overall can still grow — other sides have room",
		main._can_grow_board(), true)
	check("growing a still-open side succeeds even though left is capped",
		main._grow_ring_with_tile("strike", _find_side_cell(main, "top")), true)

	# --- spread across sides, growth still reaches the ring's own ceiling
	while main._can_grow_board():
		var cell := _any_growable_cell(main)
		main._grow_ring_with_tile("strike", cell)
	check("the ring reaches its own ceiling", main.ring_cells.size(), main.MAX_RING_LEN)
	check("no side exceeds MAX_SIDE_LEN even at the ring ceiling",
		_max_side_len(main) <= main.MAX_SIDE_LEN, true)
	check("no further growth once capped",
		main._grow_ring_with_tile("strike", main.ring_cells[0]), false)

	# --- corners still resolve on an asymmetrically grown board ---------
	check("top-left corner is still the start", main._warp_face_step(main.CORNER_TL), 0)
	check("every corner lands on a distinct square", _corners_distinct(main), true)

	# --- reward flow: tap to grow below the ceiling, replace at cap -----
	await _reward_flow_case()

	# --- the preview shows the real post-insert layout, not a ghost
	# dropped into today's gap while its neighbours stay put ------------
	await _preview_layout_case()

	print("\n%d failure(s)" % fails)
	quit(1 if fails > 0 else 0)

func _ring_content(main) -> Array:
	var out := []
	for cell in main.ring_cells:
		out.append(str(main.permanent_board[cell.y][cell.x]))
	return out

func _find_side_cell(main, side: String) -> Vector2i:
	for cell in main.ring_cells:
		if main._side_of(cell) == side:
			return cell
	return main.ring_cells[0]

func _any_growable_cell(main) -> Vector2i:
	for cell in main.ring_cells:
		if main._can_insert_after(cell):
			return cell
	return main.ring_cells[0]

func _max_side_len(main) -> int:
	var m := 0
	for side in main.SIDE_NAMES:
		m = max(m, int(main.side_len[side]))
	return m

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
	check("the ring has not grown yet — a gap still has to be tapped",
		main.ring_cells.size(), before_len)
	check("a gap marker exists after every square whose side is open",
		main.gap_buttons[0].visible, true)

	# Insertion is a gap between two squares now, not a square itself —
	# tapping a square only inspects it.
	var target: Vector2i = main.ring_cells[2]
	main._on_cell_pressed(main._idx(target.x, target.y))
	check("tapping a square does not start an insertion preview",
		main.preview_gap_index, -1)

	main._on_gap_pressed(2)
	check("the first gap tap previews without growing the ring",
		main.ring_cells.size(), before_len)
	check("the first gap tap marks that gap", main.preview_gap_index, 2)
	check("the previewed gap swells to the size a real square would be",
		main.gap_buttons[2].size, Vector2(main._board_token_size(), main._board_token_size()))

	# Tapping a square while a gap is previewed cancels the preview
	# instead of doing nothing, the same way tapping the board cancels a
	# considered die.
	main._on_cell_pressed(main._idx(target.x, target.y))
	check("tapping a square cancels an active gap preview", main.preview_gap_index, -1)

	main._on_gap_pressed(2)
	main._on_gap_pressed(2)
	check("the second tap on the same gap confirms the insertion",
		main.ring_cells.size(), before_len + 1)
	check("confirming returns to the map", main.state, "map")

	# A capped side has no gap marker after any of its squares at all —
	# while a gap right next to it, on an open side, still works.
	while main._can_insert_after(_find_side_cell(main, "left")):
		main._grow_ring_with_tile("strike", _find_side_cell(main, "left"))
	main._on_reward_selected("strike", "斬撃マス")
	var capped_index: int = int(main.ring_index_map[_find_side_cell(main, "left")])
	var len_before_tap: int = main.ring_cells.size()
	check("no gap marker follows a capped side's square",
		main.gap_buttons[capped_index].visible, false)
	main._on_gap_pressed(capped_index)
	check("tapping where a capped side's marker would be does not preview",
		main.preview_gap_index, -1)
	check("tapping where a capped side's marker would be does not grow the ring",
		main.ring_cells.size(), len_before_tap)

	# Force the board to its ring-wide ceiling, spreading growth across
	# sides so MAX_SIDE_LEN is never what stops it, then confirm the same
	# reward now asks for a replacement instead of an insertion point.
	while main._can_grow_board():
		main._grow_ring_with_tile("strike", _any_growable_cell(main))
	main._on_reward_selected("respite", "息継ぎマス")
	check("a reward at the ceiling falls back to replacement",
		main.state, "reward_place")
	check("the ring does not grow past the ceiling", main.ring_cells.size(), main.MAX_RING_LEN)

# A previewed insert used to drop a ghost into today's gap while every
# other square on that side stayed exactly where it already was — right
# up until confirming, when they all jumped to their real post-insert
# spot at once. The preview should show that final, evenly-spaced layout
# from the first tap: every square on the tapped side answers
# _board_cell_center with where it will actually sit once there is one
# more square to fit in, and the new square's own ghost sits in the one
# slot nothing else owns yet.
func _preview_layout_case() -> void:
	var main = load("res://scripts/Main.gd").new()
	root.add_child(main)
	await process_frame
	await process_frame
	main._start_run("knight")

	# top is 3 squares at ring_cells[0..2]; right is 2 at ring_cells[3..4].
	var top_before := [
		main._board_cell_center(main.ring_cells[0]),
		main._board_cell_center(main.ring_cells[1]),
		main._board_cell_center(main.ring_cells[2]),
	]
	var right_before: Vector2 = main._board_cell_center(main.ring_cells[3])

	main._on_reward_selected("strike", "斬撃マス")
	main._on_gap_pressed(0)  # the gap right after ring_cells[0], on top

	# top grows from 3 squares to 4: the square before the tapped gap
	# keeps its slot, the ghost takes the new one right after it, and
	# both squares that were after the gap shift up by one slot each. Top
	# is the one side that touches both of the frame's fixed corners
	# (nothing else does — see _side_render_pos), so ring_cells[2] is a
	# corner itself before and after: it is the one square on this side
	# unmoved for a different reason than ring_cells[0] is.
	check("the square before the tap keeps its own slot in the new layout",
		main._board_cell_center(main.ring_cells[0]),
		main._board_origin() + main._side_render_pos("top", 0, 4) * main._board_spacing())
	check("the ghost takes the slot right after the tap",
		main._preview_ghost_center(),
		main._board_origin() + main._side_render_pos("top", 1, 4) * main._board_spacing())
	check("the square after the tap shifts into the next slot",
		main._board_cell_center(main.ring_cells[1]),
		main._board_origin() + main._side_render_pos("top", 2, 4) * main._board_spacing())
	check("the square after the tap actually moved from where it opened",
		main._board_cell_center(main.ring_cells[1]) != top_before[1], true)
	check("the last square on top is still the fixed top-right corner",
		main._board_cell_center(main.ring_cells[2]), top_before[2])

	# Every previewed position is distinct — nothing overlaps mid-preview.
	var previewed := [
		main._board_cell_center(main.ring_cells[0]), main._preview_ghost_center(),
		main._board_cell_center(main.ring_cells[1]), main._board_cell_center(main.ring_cells[2]),
	]
	var distinct := {}
	for p in previewed:
		distinct[p] = true
	check("all four top-side slots in the preview are distinct positions",
		distinct.size(), 4)

	# right is a different side; growing top must not move it.
	check("a square on an unrelated side does not move during the preview",
		main._board_cell_center(main.ring_cells[3]), right_before)

	# Cancelling (tapping a square) restores the pre-preview layout.
	main._on_cell_pressed(main._idx(main.ring_cells[0].x, main.ring_cells[0].y))
	check("cancelling the preview restores the square that had moved",
		main._board_cell_center(main.ring_cells[1]), top_before[1])
