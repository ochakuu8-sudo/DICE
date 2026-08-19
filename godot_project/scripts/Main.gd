extends Control

const BOARD_W := 5
const BOARD_H := 5
const ACTIONS_PER_TURN := 2
const REROLLS_PER_TURN := 1
# How many squares an enemy can keep fouled at once. Uncapped, a long
# fight ended with most of the ring poisoned and the player's own board
# invisible underneath it. Scaled with the ring: five of sixteen leaves the
# same proportion of the board readable as four of twelve did.
const MAX_DEBUFFS := 5
# Cards on screen at once. The fractional part is deliberate: it leaves a
# sliver of the next card showing so the row reads as scrollable.
const HAND_VISIBLE := 4.7
const HAND_GAP := 7.0
# A die face is normally the count of steps it moves you, signed for
# direction — but some faces are not step counts at all: they warp the
# piece straight to a fixed ring square, spending the action without
# walking it. Sentinels far outside any real rolled distance (±1-8) so
# they can never collide with one, mapped to the ring step each warps to
# and the short label its face and log line show instead of a number.
# RING's four corners are steps 0/4/8/12 — see _build_track_graph.
const RESET_FACE := 99
const CORNER_TL := 90
const CORNER_TR := 91
const CORNER_BR := 92
const CORNER_BL := 93
const WARP_FACES := {
	RESET_FACE: {"label": "帰", "step": 0},
	CORNER_TL: {"label": "左上", "step": 0},
	CORNER_TR: {"label": "右上", "step": 4},
	CORNER_BR: {"label": "右下", "step": 8},
	CORNER_BL: {"label": "左下", "step": 12},
}

# Every size in this file is authored in these units, and the window's
# content scale is pinned to them at startup (see _apply_content_scale).
#
# 16:9 landscape, for desktop and for a phone held sideways. The two-column
# layout in _layout_screen (board left, everything the player reads or
# presses stacked right) needs 536 units of height for its right column, so
# 576 leaves it real slack; and its 423-unit column width lands close to the
# 412 the old portrait build was authored against, which is why every font
# size and card width carries over without retuning.
const DESIGN_SIZE := Vector2i(1024, 576)

# --- art slots ----------------------------------------------------------
# No filename appears anywhere else in this script. Code asks for a *slot*
# — a category, an actor and a state — and the slot resolves to a path by
# convention:
#
#     res://art/<category>/<actor>_<state>.png          a still
#     res://art/<category>/<actor>_<state>_0.png, _1…   an animation
#
# So installing art is copying files into a folder; nothing here has to be
# edited to accept them, and a slot that has no file yet draws a magenta
# placeholder carrying its own id rather than silently drawing nothing.
#
# Actors are named by the "art" field on enemy_defs / hero_defs / event_defs
# rather than by their display name, so renaming a character in Japanese
# does not orphan its art.
# A slot either *must* be filled or merely *may* be. The difference is
# whether something already does that job: a missing standing figure leaves
# a hole nothing else can cover, so it shouts; a missing background leaves
# the painted table top that the game shipped with, which is real art and
# not a gap. "placeholder" is that distinction, and it is the only reason
# the loud magenta does not appear everywhere.
const ART_ROOT := "res://art"
const ART_KINDS := {
	# The standing figure on the battle stage. Tall — roughly 3:4 or
	# narrower — because it shares the screen with the board.
	"stage": {"dir": "stage", "fps": 10.0, "placeholder": true},
	# Full-frame scene art shown when a fight is decided. 16:9.
	"cg": {"dir": "cg", "fps": 8.0, "placeholder": true},
	# Behind everything. 16:9. Falls back to the drawn table top.
	"bg": {"dir": "bg", "fps": 6.0, "placeholder": false},
	# Square crops for the map nodes. Falls back to the vector icon.
	"face": {"dir": "face", "fps": 6.0, "placeholder": false},
}
# States a stage actor can be in. "hit" is the one that plays on being
# struck; the others idle.
const ART_STAGE_STATES := ["idle", "hit", "down", "win"]
const ART_CG_STATES := ["win", "lose"]
# How far the loader probes for numbered frames before giving up.
const ART_MAX_FRAMES := 24

# --- palette -----------------------------------------------------------
# A lit tabletop rather than a dark dungeon: light ground, saturated pieces,
# and an ink outline on everything that is a "piece". The outline is what
# lets the bright fills sit on a bright ground without turning to mush.
const COL_INK := Color("#2A2320")
const COL_PANEL := Color("#FFF7E6")
const COL_PANEL_SUNK := Color("#E6D6B4")
const COL_TEXT := Color("#2A2320")
const COL_TEXT_SOFT := Color("#6B5C49")
const COL_TEXT_ON_DARK := Color("#FFF7E6")
const COL_GOLD := Color("#F2B33D")
const COL_DANGER := Color("#FF7A18")
const COL_HP := Color("#3EA95E")
const COL_HP_LOW := Color("#E4453A")
const COL_SHIELD := Color("#2E7BD6")
const COL_ENEMY := Color("#C2453A")
const COL_TRACK := Color("#BFA87F")
const COL_ROUTE := Color("#F2B33D")
const COL_NEXT := Color("#2E7BD6")

# Font sizes. Five steps, not the nine the old build drifted into.
const FS_TITLE := 30
const FS_HEAD := 21
const FS_BODY := 16
const FS_SMALL := 13
const FS_NUM_BIG := 38
const FS_NUM := 22

# Pacing. The turn used to resolve in well under a second: six hops, every
# tile effect, the enemy's attack and the next hand all landed in one blur.
# A step is only worth pausing on when something actually happened, so an
# empty stretch of road stays quick and a hit gets a beat to be read.
const STEP_TIME := 0.24
const BEAT_EFFECT := 0.45
const BEAT_STOP := 0.55
const BEAT_PHASE := 0.6

# Backdrop: a warm lit ground that reddens as the run climbs toward the
# boss. Same "the run has a temperature" idea as before, moved into the
# light half of the value range so the pieces on top can be the dark ones.
class Backdrop:
	extends Control

	var tint_progress: float = 0.0:
		set(v):
			tint_progress = clamp(v, 0.0, 1.0)
			queue_redraw()

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		var top_color := Color("#F7EDD6").lerp(Color("#F7E2CB"), tint_progress)
		var mid_color := Color("#EFE0BE").lerp(Color("#EDCFB0"), tint_progress)
		var bottom_color := Color("#DFCCA2").lerp(Color("#DDB894"), tint_progress)
		var w: float = size.x
		var h: float = size.y
		var mid_y: float = h * 0.45
		draw_polygon(
			PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, mid_y), Vector2(0, mid_y)]),
			PackedColorArray([top_color, top_color, mid_color, mid_color])
		)
		draw_polygon(
			PackedVector2Array([Vector2(0, mid_y), Vector2(w, mid_y), Vector2(w, h), Vector2(0, h)]),
			PackedColorArray([mid_color, mid_color, bottom_color, bottom_color])
		)
		# A soft light pooled over the board, so the middle of the screen
		# reads as the lit part of the table.
		var glow_center := Vector2(w * 0.5, h * 0.42)
		var glow_radius: float = max(w, h) * 0.55
		for i in range(5, 0, -1):
			var t: float = float(i) / 5.0
			draw_circle(glow_center, glow_radius * t, Color(1.0, 0.98, 0.9, 0.05))

# Vector icons drawn with an ink outline so a bright fill still reads on a
# bright ground. Every shape is painted twice: once grown into the outline
# color, once at true size in the glyph color.
class IconGlyph:
	extends Control

	var kind := ""
	var glyph_color := Color.WHITE
	var outline_color := Color("#2A2320")
	var outlined := true

	func set_kind(k: String) -> void:
		kind = k
		queue_redraw()

	func _draw() -> void:
		if kind == "" or kind == "empty":
			return
		var s: float = min(size.x, size.y)
		var c: Vector2 = size * 0.5
		if outlined:
			_paint(c, s, outline_color, max(1.5, s * 0.075))
		_paint(c, s, glyph_color, 0.0)

	func _paint(c: Vector2, s: float, col: Color, grow: float) -> void:
		match kind:
			"slash":
				_sword(c, s, col, grow)
			"guard":
				_shield(c, s, col, grow)
			"fire":
				_flame(c, s, col, grow)
			"heal":
				_heart(c, s, col, grow)
			"bow":
				_bow(c, s, col, grow)
			"trap":
				_jaws(c, s, col, grow)
			"warp":
				_warp(c, s, col, grow)
			"shock":
				_bolt(c, s, col, grow)
			"focus":
				_focus(c, s, col, grow)
			"poison":
				_poison(c, s, col, grow)
			"skull":
				_skull(c, s, col, grow)
			"enemy_grunt":
				_enemy_grunt(c, s, col, grow)
			"enemy_archer":
				_enemy_archer(c, s, col, grow)
			"enemy_heavy":
				_enemy_heavy(c, s, col, grow)
			"enemy_boss":
				_enemy_boss(c, s, col, grow)
			"flag_start":
				_flag(c, s, col, grow)
			"boot":
				_boot(c, s, col, grow)
			"dice":
				_dice(c, s, col, grow)
			"chain":
				_chain(c, s, col, grow)
			"pip_on":
				_disc(c, s * 0.34, col, grow)
			"pip_off":
				_ring(c, s * 0.30, s * 0.09, col, grow)

	# --- primitives ---
	func _poly(pts: PackedVector2Array, col: Color, grow: float) -> void:
		if grow > 0.0:
			for grown in Geometry2D.offset_polygon(pts, grow):
				draw_colored_polygon(grown, col)
		else:
			draw_colored_polygon(pts, col)

	func _stroke(a: Vector2, b: Vector2, width: float, col: Color, grow: float) -> void:
		draw_line(a, b, col, width + grow * 2.0, true)

	func _disc(c: Vector2, r: float, col: Color, grow: float) -> void:
		draw_circle(c, r + grow, col)

	func _ring(c: Vector2, r: float, width: float, col: Color, grow: float) -> void:
		draw_arc(c, r, 0.0, TAU, 24, col, width + grow * 2.0, true)

	func _arc(c: Vector2, r: float, from_a: float, to_a: float, width: float, col: Color, grow: float) -> void:
		draw_arc(c, r, from_a, to_a, 20, col, width + grow * 2.0, true)

	# --- glyphs ---
	func _sword(c: Vector2, s: float, col: Color, grow: float) -> void:
		var p1 := c + Vector2(-0.28, 0.30) * s
		var p2 := c + Vector2(0.30, -0.32) * s
		_stroke(p1, p2, s * 0.13, col, grow)
		var dir := (p2 - p1).normalized()
		var perp := Vector2(-dir.y, dir.x)
		var guard := p1.lerp(p2, 0.40)
		_stroke(guard - perp * 0.17 * s, guard + perp * 0.17 * s, s * 0.09, col, grow)
		_disc(p1, s * 0.08, col, grow)

	func _shield(c: Vector2, s: float, col: Color, grow: float) -> void:
		_poly(PackedVector2Array([
			c + Vector2(-0.28, -0.30) * s, c + Vector2(0.28, -0.30) * s,
			c + Vector2(0.30, 0.00) * s, c + Vector2(0.0, 0.36) * s,
			c + Vector2(-0.30, 0.00) * s,
		]), col, grow)

	func _flame(c: Vector2, s: float, col: Color, grow: float) -> void:
		_poly(PackedVector2Array([
			c + Vector2(0.0, -0.38) * s, c + Vector2(0.20, -0.10) * s,
			c + Vector2(0.26, 0.16) * s, c + Vector2(0.10, 0.36) * s,
			c + Vector2(-0.14, 0.34) * s, c + Vector2(-0.26, 0.10) * s,
			c + Vector2(-0.16, -0.12) * s,
		]), col, grow)

	func _heart(c: Vector2, s: float, col: Color, grow: float) -> void:
		_poly(PackedVector2Array([
			c + Vector2(0.0, -0.14) * s, c + Vector2(0.16, -0.32) * s,
			c + Vector2(0.34, -0.18) * s, c + Vector2(0.30, 0.06) * s,
			c + Vector2(0.0, 0.36) * s, c + Vector2(-0.30, 0.06) * s,
			c + Vector2(-0.34, -0.18) * s, c + Vector2(-0.16, -0.32) * s,
		]), col, grow)

	func _bow(c: Vector2, s: float, col: Color, grow: float) -> void:
		var center := c + Vector2(-0.10, 0.0) * s
		var radius := s * 0.32
		_arc(center, radius, -1.15, 1.15, s * 0.09, col, grow)
		var top := center + Vector2(cos(-1.15), sin(-1.15)) * radius
		var bot := center + Vector2(cos(1.15), sin(1.15)) * radius
		_stroke(top, bot, s * 0.05, col, grow)
		var arrow_end := c + Vector2(0.34, 0.0) * s
		_stroke(center, arrow_end, s * 0.07, col, grow)
		_poly(PackedVector2Array([
			arrow_end + Vector2(0.06, 0.0) * s,
			arrow_end + Vector2(-0.10, -0.12) * s,
			arrow_end + Vector2(-0.10, 0.12) * s,
		]), col, grow)

	# Bear-trap jaws: the permanent "trap" tile hurts the *enemy*, so it gets
	# a mechanical, deliberate shape. The poison swamp (which hurts the
	# player) is deliberately nothing like it — see _poison.
	func _jaws(c: Vector2, s: float, col: Color, grow: float) -> void:
		_arc(c, s * 0.30, deg_to_rad(200.0), deg_to_rad(340.0), s * 0.10, col, grow)
		_arc(c, s * 0.30, deg_to_rad(20.0), deg_to_rad(160.0), s * 0.10, col, grow)
		for i in range(4):
			var x: float = -0.21 + 0.14 * float(i)
			_poly(PackedVector2Array([
				c + Vector2(x, -0.16) * s, c + Vector2(x + 0.07, -0.16) * s,
				c + Vector2(x + 0.035, -0.01) * s,
			]), col, grow)
			_poly(PackedVector2Array([
				c + Vector2(x, 0.16) * s, c + Vector2(x + 0.07, 0.16) * s,
				c + Vector2(x + 0.035, 0.01) * s,
			]), col, grow)

	# Poison swamp: bubbles rising out of a pool. Rounded, organic, and in a
	# sickly yellow-green — the one thing on the board that costs the player
	# HP just for walking over it, so it must not look like anything else.
	func _poison(c: Vector2, s: float, col: Color, grow: float) -> void:
		_poly(PackedVector2Array([
			c + Vector2(-0.36, 0.10) * s, c + Vector2(-0.20, 0.02) * s,
			c + Vector2(0.0, 0.12) * s, c + Vector2(0.20, 0.02) * s,
			c + Vector2(0.36, 0.10) * s, c + Vector2(0.34, 0.34) * s,
			c + Vector2(-0.34, 0.34) * s,
		]), col, grow)
		_disc(c + Vector2(-0.16, -0.16) * s, s * 0.09, col, grow)
		_disc(c + Vector2(0.10, -0.26) * s, s * 0.12, col, grow)
		_disc(c + Vector2(0.26, -0.06) * s, s * 0.07, col, grow)

	func _warp(c: Vector2, s: float, col: Color, grow: float) -> void:
		var radius := s * 0.28
		var end_ang := deg_to_rad(250.0)
		_arc(c, radius, deg_to_rad(-40.0), end_ang, s * 0.10, col, grow)
		var end_pt := c + Vector2(cos(end_ang), sin(end_ang)) * radius
		var tangent := Vector2(-sin(end_ang), cos(end_ang))
		_poly(PackedVector2Array([
			end_pt + tangent * 0.17 * s,
			end_pt + Vector2(cos(end_ang), sin(end_ang)) * 0.16 * s,
			end_pt - tangent * 0.17 * s,
		]), col, grow)

	func _bolt(c: Vector2, s: float, col: Color, grow: float) -> void:
		_poly(PackedVector2Array([
			c + Vector2(0.08, -0.38) * s, c + Vector2(-0.24, 0.04) * s,
			c + Vector2(-0.02, 0.04) * s, c + Vector2(-0.12, 0.38) * s,
			c + Vector2(0.26, -0.08) * s, c + Vector2(0.02, -0.08) * s,
		]), col, grow)

	func _focus(c: Vector2, s: float, col: Color, grow: float) -> void:
		_ring(c, s * 0.30, s * 0.08, col, grow)
		_disc(c, s * 0.12, col, grow)

	func _skull(c: Vector2, s: float, col: Color, grow: float) -> void:
		_disc(c + Vector2(0.0, -0.06) * s, s * 0.30, col, grow)
		_poly(PackedVector2Array([
			c + Vector2(-0.16, 0.14) * s, c + Vector2(0.16, 0.14) * s,
			c + Vector2(0.12, 0.34) * s, c + Vector2(-0.12, 0.34) * s,
		]), col, grow)
		if grow <= 0.0:
			var hole := Color(0.0, 0.0, 0.0, 0.6)
			draw_circle(c + Vector2(-0.12, -0.08) * s, s * 0.08, hole)
			draw_circle(c + Vector2(0.12, -0.08) * s, s * 0.08, hole)

	func _enemy_grunt(c: Vector2, s: float, col: Color, grow: float) -> void:
		_poly(PackedVector2Array([
			c + Vector2(-0.24, 0.06) * s, c + Vector2(0.24, 0.06) * s,
			c + Vector2(0.32, 0.42) * s, c + Vector2(-0.32, 0.42) * s,
		]), col, grow)
		_disc(c + Vector2(0.0, -0.16) * s, s * 0.20, col, grow)
		_poly(PackedVector2Array([
			c + Vector2(-0.10, -0.30) * s, c + Vector2(-0.20, -0.46) * s, c + Vector2(-0.01, -0.32) * s,
		]), col, grow)
		_poly(PackedVector2Array([
			c + Vector2(0.10, -0.30) * s, c + Vector2(0.20, -0.46) * s, c + Vector2(0.01, -0.32) * s,
		]), col, grow)

	func _enemy_archer(c: Vector2, s: float, col: Color, grow: float) -> void:
		_poly(PackedVector2Array([
			c + Vector2(-0.16, 0.02) * s, c + Vector2(0.12, 0.02) * s,
			c + Vector2(0.18, 0.42) * s, c + Vector2(-0.22, 0.42) * s,
		]), col, grow)
		_disc(c + Vector2(-0.02, -0.18) * s, s * 0.16, col, grow)
		var bow_center := c + Vector2(0.28, 0.04) * s
		_arc(bow_center, s * 0.26, deg_to_rad(-100.0), deg_to_rad(100.0), s * 0.06, col, grow)
		_stroke(bow_center + Vector2(0.0, -0.24) * s, bow_center + Vector2(0.0, 0.24) * s, s * 0.04, col, grow)

	func _enemy_heavy(c: Vector2, s: float, col: Color, grow: float) -> void:
		_poly(PackedVector2Array([
			c + Vector2(-0.36, -0.02) * s, c + Vector2(0.36, -0.02) * s,
			c + Vector2(0.30, 0.42) * s, c + Vector2(-0.30, 0.42) * s,
		]), col, grow)
		_disc(c + Vector2(0.0, -0.18) * s, s * 0.18, col, grow)
		_poly(PackedVector2Array([
			c + Vector2(-0.36, -0.02) * s, c + Vector2(-0.50, -0.10) * s, c + Vector2(-0.24, 0.0) * s,
		]), col, grow)
		_poly(PackedVector2Array([
			c + Vector2(0.36, -0.02) * s, c + Vector2(0.50, -0.10) * s, c + Vector2(0.24, 0.0) * s,
		]), col, grow)

	func _enemy_boss(c: Vector2, s: float, col: Color, grow: float) -> void:
		_poly(PackedVector2Array([
			c + Vector2(-0.32, 0.02) * s, c + Vector2(0.32, 0.02) * s,
			c + Vector2(0.38, 0.44) * s, c + Vector2(-0.38, 0.44) * s,
		]), col, grow)
		_disc(c + Vector2(0.0, -0.16) * s, s * 0.23, col, grow)
		_poly(PackedVector2Array([
			c + Vector2(-0.17, -0.30) * s, c + Vector2(-0.25, -0.52) * s, c + Vector2(-0.05, -0.34) * s,
		]), col, grow)
		_poly(PackedVector2Array([
			c + Vector2(-0.05, -0.32) * s, c + Vector2(0.0, -0.58) * s, c + Vector2(0.05, -0.32) * s,
		]), col, grow)
		_poly(PackedVector2Array([
			c + Vector2(0.17, -0.30) * s, c + Vector2(0.25, -0.52) * s, c + Vector2(0.05, -0.34) * s,
		]), col, grow)
		if grow <= 0.0:
			var eye := Color("#FFD34D")
			draw_circle(c + Vector2(-0.09, -0.16) * s, s * 0.05, eye)
			draw_circle(c + Vector2(0.09, -0.16) * s, s * 0.05, eye)

	func _flag(c: Vector2, s: float, col: Color, grow: float) -> void:
		var base := c + Vector2(-0.18, 0.34) * s
		var top := c + Vector2(-0.18, -0.36) * s
		_stroke(base, top, s * 0.08, col, grow)
		_poly(PackedVector2Array([
			top, top + Vector2(0.38, 0.12) * s, top + Vector2(0.0, 0.24) * s,
		]), col, grow)

	func _boot(c: Vector2, s: float, col: Color, grow: float) -> void:
		_poly(PackedVector2Array([
			c + Vector2(-0.18, -0.32) * s, c + Vector2(0.04, -0.32) * s,
			c + Vector2(0.06, 0.06) * s, c + Vector2(0.34, 0.16) * s,
			c + Vector2(0.34, 0.32) * s, c + Vector2(-0.20, 0.32) * s,
		]), col, grow)

	func _chain(c: Vector2, s: float, col: Color, grow: float) -> void:
		_ring(c + Vector2(-0.15, 0.0) * s, s * 0.20, s * 0.09, col, grow)
		_ring(c + Vector2(0.15, 0.0) * s, s * 0.20, s * 0.09, col, grow)

	func _dice(c: Vector2, s: float, col: Color, grow: float) -> void:
		_poly(PackedVector2Array([
			c + Vector2(-0.32, -0.32) * s, c + Vector2(0.32, -0.32) * s,
			c + Vector2(0.32, 0.32) * s, c + Vector2(-0.32, 0.32) * s,
		]), col, grow)
		if grow <= 0.0:
			var pip := Color("#2A2320")
			draw_circle(c + Vector2(-0.14, -0.14) * s, s * 0.07, pip)
			draw_circle(c, s * 0.07, pip)
			draw_circle(c + Vector2(0.14, 0.14) * s, s * 0.07, pip)

# Chunky segmented gauge with an ink frame. The trailing display_value is
# kept from the old build — on a hit the bar drains through a red band, on
# a heal it fills through a bright one — but it now moves the instant the
# value changes instead of waiting for the end of the turn.
class GaugeBar:
	extends Control

	var value := 0
	var max_value := 1
	var segments := 10
	var fill_color := Color("#3EA95E")
	var track_color := Color("#E6D6B4")
	var frame_color := Color("#2A2320")

	var display_value: float = 0.0:
		set(v):
			display_value = v
			queue_redraw()

	func _draw() -> void:
		if segments <= 0 or size.x <= 0.0 or size.y <= 0.0:
			return
		draw_rect(Rect2(Vector2.ZERO, size), track_color, true)
		var inset := 3.0
		var inner := Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0)
		if inner.size.x <= 0.0 or inner.size.y <= 0.0:
			return
		var gap := 2.0
		var seg_w: float = (inner.size.x - gap * float(segments - 1)) / float(segments)
		var filled := 0
		var trail := 0
		if max_value > 0:
			filled = int(round(float(value) / float(max_value) * float(segments)))
			trail = int(round(display_value / float(max_value) * float(segments)))
			# Never let a nonzero value round away to an empty bar: "1 HP
			# left" and "dead" must not draw the same.
			if value > 0:
				filled = max(filled, 1)
		filled = clamp(filled, 0, segments)
		trail = clamp(trail, 0, segments)
		var lo: int = min(filled, trail)
		var hi: int = max(filled, trail)
		var gaining: bool = filled > trail
		for i in range(segments):
			var x: float = inner.position.x + i * (seg_w + gap)
			var col: Color
			if i < lo:
				col = fill_color
			elif i < hi:
				col = Color("#FFFFFF") if gaining else Color("#FF6A56")
			else:
				continue
			draw_rect(Rect2(Vector2(x, inner.position.y), Vector2(seg_w, inner.size.y)), col, true)
		draw_rect(Rect2(Vector2.ZERO, size), frame_color, false, 2.0)

# A die face with real pips and an ink border.
class DiceFace:
	extends Control

	var value := 1
	var dot_color := Color("#2A2320")
	var face_color := Color("#FFF7E6")
	# An unthrown die: the frame is drawn but the pips are not, so the "?"
	# laid over the card sits on a blank face instead of on top of a number
	# the die has not actually rolled yet.
	var query := false
	# A negative face (逆走) reads as a photographic negative of a normal
	# die — same pip count, opposite fill — so "this moves you backwards"
	# is visible on the face itself, not just in the card's text below it.
	var invert := false

	func _draw() -> void:
		var bg: Color = dot_color if invert else face_color
		var fg: Color = face_color if invert else dot_color
		draw_rect(Rect2(Vector2.ZERO, size), bg, true)
		draw_rect(Rect2(Vector2.ZERO, size), fg, false, max(2.0, size.x * 0.06))
		if query:
			return
		var dot_r: float = min(size.x, size.y) * 0.10
		for p in _pip_positions(absi(value)):
			draw_circle(Vector2(p.x * size.x, p.y * size.y), dot_r, fg)

	func _pip_positions(v: int) -> Array:
		var l := 0.26
		var c := 0.5
		var r := 0.74
		var t := 0.26
		var m := 0.5
		var b := 0.74
		match v:
			0:
				# A 0 face is a blank die: nothing rolled, nowhere to walk.
				return []
			1:
				return [Vector2(c, m)]
			2:
				return [Vector2(l, t), Vector2(r, b)]
			3:
				return [Vector2(l, t), Vector2(c, m), Vector2(r, b)]
			4:
				return [Vector2(l, t), Vector2(r, t), Vector2(l, b), Vector2(r, b)]
			5:
				return [Vector2(l, t), Vector2(r, t), Vector2(c, m), Vector2(l, b), Vector2(r, b)]
			6:
				return [Vector2(l, t), Vector2(r, t), Vector2(l, m), Vector2(r, m), Vector2(l, b), Vector2(r, b)]
			# 大車輪 rolls past six, and three faces that all drew as a six
			# would make it unreadable. The pattern keeps growing the same
			# way rather than switching to a printed numeral.
			7:
				return [Vector2(l, t), Vector2(r, t), Vector2(l, m), Vector2(r, m),
					Vector2(l, b), Vector2(r, b), Vector2(c, m)]
			8:
				return [Vector2(l, t), Vector2(c, t), Vector2(r, t), Vector2(l, m),
					Vector2(r, m), Vector2(l, b), Vector2(c, b), Vector2(r, b)]
			_:
				return [Vector2(l, t), Vector2(c, t), Vector2(r, t),
					Vector2(l, m), Vector2(c, m), Vector2(r, m),
					Vector2(l, b), Vector2(c, b), Vector2(r, b)]

class BurstEffect:
	extends Control

	var center := Vector2.ZERO
	var token := 40.0
	var tint := Color("#F2B33D")
	var progress: float = 0.0:
		set(v):
			progress = v
			queue_redraw()

	func _draw() -> void:
		var a: float = 1.0 - progress
		if a <= 0.0:
			return
		var ring_r: float = token * (0.32 + progress * 0.95)
		draw_arc(center, ring_r, 0.0, TAU, 24, Color(tint.r, tint.g, tint.b, a * 0.9), token * 0.12 * (1.0 - progress * 0.6), true)
		for i in range(7):
			var ang: float = i * TAU / 7.0
			var dir := Vector2(cos(ang), sin(ang))
			draw_line(center + dir * token * 0.25, center + dir * ring_r, Color(tint.r, tint.g, tint.b, a), token * 0.06, true)

# Draws one art slot. It is deliberately dumb: it holds a list of frames
# and a name, and when the frames are missing it says so at the top of its
# voice. A pretty fallback would hide the fact that a slot is still empty,
# and with a few hundred slots to fill that is the one failure mode worth
# engineering against.
class SpriteView:
	extends Control

	var frames: Array = []
	var fps: float = 12.0
	var loop := true
	var slot := ""              # the id the missing art would have had
	# Fit (the default) shows the whole image and lets the ground show at
	# the edges — right for a figure or a scene, where cropping loses the
	# subject. Cover fills the frame and lets the edges fall outside, which
	# is what a background wants when the window is not 16:9.
	var cover := false
	var finished := true
	var flash: float = 0.0:
		set(v):
			flash = v
			queue_redraw()
	var _time := 0.0

	func _ready() -> void:
		clip_contents = true
		set_process(true)

	func play(new_frames: Array, new_slot: String, new_fps: float = 12.0, new_loop: bool = true) -> void:
		frames = new_frames
		slot = new_slot
		fps = max(new_fps, 0.001)
		loop = new_loop
		_time = 0.0
		finished = frames.size() <= 1
		queue_redraw()

	# How long one pass of this clip lasts, so a caller can wait for it
	# without knowing how many frames the artist ended up drawing.
	func duration() -> float:
		return float(max(frames.size(), 1)) / max(fps, 0.001)

	func _process(delta: float) -> void:
		if frames.size() <= 1 or finished:
			return
		_time += delta
		if not loop and _time >= duration():
			_time = duration() - 0.0001
			finished = true
		queue_redraw()

	func _frame() -> Texture2D:
		if frames.is_empty():
			return null
		var i := int(_time * fps)
		i = posmod(i, frames.size()) if loop else clampi(i, 0, frames.size() - 1)
		return frames[i]

	func _draw() -> void:
		if size.x <= 1.0 or size.y <= 1.0:
			return
		var tex := _frame()
		if tex == null:
			_draw_missing()
			return
		var source := Vector2(float(tex.get_width()), float(tex.get_height()))
		if source.x <= 0.0 or source.y <= 0.0:
			return
		# Art is authored at whatever size suits it and the frame it lands
		# in changes with the window, so one of the two axes always gives.
		var factor: float = max(size.x / source.x, size.y / source.y) if cover \
			else min(size.x / source.x, size.y / source.y)
		var span := source * factor
		var at := ((size - span) * 0.5).floor()
		draw_texture_rect(tex, Rect2(at, span), false)
		if flash > 0.0:
			draw_rect(Rect2(at, span), Color(1.0, 1.0, 1.0, clampf(flash, 0.0, 1.0) * 0.55))

	func _draw_missing() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.0, 0.85))
		var stripe := Color(0.10, 0.0, 0.10, 0.5)
		var x: float = -size.y
		while x < size.x:
			draw_line(Vector2(x, size.y), Vector2(x + size.y, 0.0), stripe, 7.0)
			x += 26.0
		var font: Font = ThemeDB.fallback_font
		if font == null:
			return
		var mid: float = size.y * 0.5
		draw_string(font, Vector2(9.0, mid - 4.0), "NO ART",
			HORIZONTAL_ALIGNMENT_LEFT, size.x - 18.0, 19, Color.WHITE)
		draw_string(font, Vector2(9.0, mid + 15.0), slot,
			HORIZONTAL_ALIGNMENT_LEFT, size.x - 18.0, 12, Color.WHITE)
		# The frame it would have filled, so whoever is generating the art
		# can read the target shape straight off the screen.
		draw_string(font, Vector2(9.0, mid + 32.0),
			"%d x %d  (%.2f)" % [int(size.x), int(size.y), size.x / max(size.y, 1.0)],
			HORIZONTAL_ALIGNMENT_LEFT, size.x - 18.0, 12, Color(1, 1, 1, 0.8))

# The hero's own face, big enough to actually read, with a silhouette that
# differs per class instead of one shared circle.
class HeroPortrait:
	extends Control

	var hp_ratio: float = 1.0:
		set(v):
			hp_ratio = v
			queue_redraw()
	var hero_key := "knight"
	var face_color := Color("#2E7BD6")

	func _draw() -> void:
		var s: float = min(size.x, size.y)
		var c: Vector2 = size * 0.5
		var ink := Color("#2A2320")
		draw_circle(c, s * 0.46, face_color)
		draw_arc(c, s * 0.44, 0.0, TAU, 32, ink, s * 0.07, true)
		_headgear(c, s, ink)
		if hp_ratio <= 0.3:
			draw_line(c + Vector2(-0.22, -0.12) * s, c + Vector2(-0.08, -0.01) * s, ink, s * 0.06, true)
			draw_line(c + Vector2(-0.22, 0.08) * s, c + Vector2(-0.08, -0.01) * s, ink, s * 0.06, true)
			draw_line(c + Vector2(0.08, -0.01) * s, c + Vector2(0.22, -0.12) * s, ink, s * 0.06, true)
			draw_line(c + Vector2(0.08, -0.01) * s, c + Vector2(0.22, 0.08) * s, ink, s * 0.06, true)
		else:
			draw_circle(c + Vector2(-0.15, -0.04) * s, s * 0.06, ink)
			draw_circle(c + Vector2(0.15, -0.04) * s, s * 0.06, ink)
		if hp_ratio > 0.6:
			draw_arc(c + Vector2(0.0, 0.10) * s, s * 0.16, deg_to_rad(20.0), deg_to_rad(160.0), 12, ink, s * 0.055, false)
		elif hp_ratio > 0.3:
			draw_line(c + Vector2(-0.11, 0.22) * s, c + Vector2(0.11, 0.22) * s, ink, s * 0.055, true)
		else:
			draw_arc(c + Vector2(0.0, 0.34) * s, s * 0.16, deg_to_rad(200.0), deg_to_rad(340.0), 12, ink, s * 0.055, false)

	func _headgear(c: Vector2, s: float, ink: Color) -> void:
		match hero_key:
			"mage":
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(-0.40, -0.24) * s, c + Vector2(0.40, -0.24) * s,
					c + Vector2(0.0, -0.66) * s,
				]), ink)
			"rogue":
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(-0.46, -0.20) * s, c + Vector2(0.46, -0.20) * s,
					c + Vector2(0.30, -0.36) * s, c + Vector2(-0.30, -0.36) * s,
				]), ink)
			_:
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(-0.40, -0.22) * s, c + Vector2(0.40, -0.22) * s,
					c + Vector2(0.40, -0.40) * s, c + Vector2(0.12, -0.40) * s,
					c + Vector2(0.0, -0.30) * s, c + Vector2(-0.12, -0.40) * s,
					c + Vector2(-0.40, -0.40) * s,
				]), ink)

# The run as six stations with the boss at the end, so "how far in am I"
# is a picture instead of the number in the header.
class RunTrack:
	extends Control

	var total := 6
	var current := 0

	func _draw() -> void:
		if size.x <= 0.0 or total <= 0:
			return
		var r: float = min(size.y * 0.5, size.x / float(total * 3))
		var span: float = size.x - r * 2.0
		var y: float = size.y * 0.5
		var ink := Color("#2A2320")
		draw_line(Vector2(r, y), Vector2(r + span, y), Color("#BFA87F"), max(3.0, r * 0.45), true)
		for i in range(total):
			var x: float = r + span * (float(i) / float(total - 1))
			var done: bool = i + 1 < current
			var here: bool = i + 1 == current
			var boss: bool = i == total - 1
			var fill: Color = Color("#BFA87F")
			if done:
				fill = Color("#3EA95E")
			if here:
				fill = Color("#F2B33D")
			if boss and not done and not here:
				fill = Color("#C2453A")
			var radius: float = r * (1.25 if here else 1.0)
			draw_circle(Vector2(x, y), radius, fill)
			draw_arc(Vector2(x, y), radius, 0.0, TAU, 20, ink, 2.0, true)
			if boss:
				# A crown notch marks the last station as the boss.
				draw_colored_polygon(PackedVector2Array([
					Vector2(x - radius * 0.8, y - radius * 1.25),
					Vector2(x - radius * 0.3, y - radius * 1.95),
					Vector2(x, y - radius * 1.3),
					Vector2(x + radius * 0.3, y - radius * 1.95),
					Vector2(x + radius * 0.8, y - radius * 1.25),
				]), ink)

# The track itself: a one-way ring drawn as a road with direction arrows,
# the travelled part lit gold and the next few steps lit blue.
class BoardView:
	extends Control

	var main: Control
	var glow_phase := 0.0
	# "road" draws under the cell buttons, "token" over them. Children of a
	# Control always paint after its own _draw, so the player marker needs
	# its own layer added after the cells or it hides behind one.
	var layer := "road"

	func _ready() -> void:
		set_process(true)

	func _process(delta: float) -> void:
		glow_phase = fmod(glow_phase + delta, TAU)
		if main != null and (main.state == "player" or main.state == "moving"):
			queue_redraw()

	func _draw() -> void:
		if main == null or main.ring_cells.is_empty():
			return
		if layer == "token":
			_draw_debuff_rings()
			_draw_danger_pulse()
			_draw_player_marker()
			return
		var count: int = main.ring_cells.size()
		# Road bed first, then the highlighted segments on top of it, so the
		# lit part of the route reads as light falling on one road rather
		# than as two different roads.
		for pass_index in range(2):
			for i in range(count):
				var a: Vector2i = main.ring_cells[i]
				var b: Vector2i = main.ring_cells[(i + 1) % count]
				var pa: Vector2 = main._board_cell_center(a)
				var pb: Vector2 = main._board_cell_center(b)
				if pass_index == 0:
					draw_line(pa, pb, Color("#2A2320"), 16.0, true)
					draw_line(pa, pb, main.COL_TRACK, 12.0, true)
					_draw_arrow(pa, pb, Color("#8C7A55"))
					continue
				var lit := Color.TRANSPARENT
				if main._segment_is_recent(a, b):
					lit = main.COL_ROUTE
				elif main._segment_is_next(a, b):
					lit = main.COL_NEXT
				if lit.a > 0.0:
					draw_line(pa, pb, lit, 12.0, true)
					_draw_arrow(pa, pb, lit.darkened(0.25))
		_draw_landing_marks()

	# Telegraphed cells breathe, so "this one will hurt" is motion as well as
	# a colour — the old build marked danger with a border alone.
	func _draw_danger_pulse() -> void:
		if main.danger_cells.is_empty():
			return
		var token: float = main._board_token_size()
		var pulse: float = 0.5 + sin(glow_phase * 3.4) * 0.5
		for cell in main.danger_cells.keys():
			var p: Vector2 = main._board_cell_center(cell)
			draw_arc(p, token * 0.5 + 5.0 + pulse * 4.0, 0.0, TAU, 28,
				Color(1.0, 0.48, 0.09, 0.30 + pulse * 0.35), 3.0 + pulse * 2.0, true)

	# One ring, on the square the die under consideration would land on, in
	# that die's own colour. Drawing every die's landing at once put three
	# or four rings on the board before the player had asked anything, and a
	# board pre-marked with every possible answer is noise rather than a
	# preview — the marks now appear only for the die actually being asked
	# about, and the board is clean until then.
	func _draw_landing_marks() -> void:
		if main.state != "player" or not main.dice_rolled:
			return
		var die: Dictionary = main._previewed_die()
		if die.is_empty():
			return
		var token: float = main._board_token_size()
		var cell: Vector2i = main._landing_cell_for(int(die.get("roll", 0)))
		var p: Vector2 = main._board_cell_center(cell)
		var radius: float = token * 0.5 + 7.0
		var col: Color = main._die_color(die)
		draw_arc(p, radius, 0.0, TAU, 30, Color("#2A2320"), 6.0, true)
		draw_arc(p, radius, 0.0, TAU, 30, col, 4.0, true)
		draw_arc(p, radius + 5.0, 0.0, TAU, 30, Color("#F2B33D"), 3.0, true)

	# A ring right on the rim of a fouled cell: visible at a glance without
	# covering the tile's own icon or number.
	func _draw_debuff_rings() -> void:
		var token: float = main._board_token_size()
		for cell in main.ring_cells:
			var deb: Dictionary = main._debuff_at(cell)
			if deb.is_empty():
				continue
			var p: Vector2 = main._board_cell_center(cell)
			draw_arc(p, token * 0.5 - 3.0, 0.0, TAU, 30,
				Color(deb["color"]).lightened(0.35), 3.0, true)

	func _draw_player_marker() -> void:
		if not main.player_visual_ready:
			return
		var center: Vector2 = main.player_visual_pos
		var token: float = main._board_token_size()
		var lift: Vector2 = center + Vector2(0.0, -token * 0.30 - main.player_hop)
		var pulse: float = 0.5 + sin(glow_phase * 2.2) * 0.5
		var impact: float = main.player_impact
		draw_circle(center + Vector2(0.0, token * 0.06), token * 0.30, Color(0.16, 0.12, 0.08, 0.20))
		var glow_r: float = token * (0.42 + pulse * 0.10 + impact * 0.45)
		draw_circle(lift, glow_r, Color(1.0, 0.78, 0.28, 0.22 + pulse * 0.10 + impact * 0.35))
		draw_circle(lift, token * (0.34 + impact * 0.08), Color("#2A2320"))
		draw_circle(lift, token * (0.28 + impact * 0.08), main.hero_token_color.lerp(Color.WHITE, impact * 0.7))
		# A tiny class mark on the token so the three heroes are not the
		# same anonymous dot.
		var s: float = token * 0.5
		match main.hero_key:
			"mage":
				draw_circle(lift + Vector2(0.0, -s * 0.05), s * 0.20, Color("#FFF7E6"))
			"rogue":
				draw_colored_polygon(PackedVector2Array([
					lift + Vector2(-0.22, 0.06) * s, lift + Vector2(0.22, 0.06) * s,
					lift + Vector2(0.0, -0.24) * s,
				]), Color("#FFF7E6"))
			_:
				draw_line(lift + Vector2(-0.18, 0.18) * s, lift + Vector2(0.18, -0.18) * s, Color("#FFF7E6"), s * 0.16, true)

	func _draw_arrow(a: Vector2, b: Vector2, color: Color) -> void:
		var dir := b - a
		if dir.length() < 1.0:
			return
		dir = dir.normalized()
		var mid := a.lerp(b, 0.56)
		var side := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([
			mid + dir * 8.0, mid - dir * 6.0 + side * 6.0, mid - dir * 6.0 - side * 6.0,
		]), color)

# Sound, synthesised on the fly. The project ships no audio assets and new
# ones would need an editor import step, so the six sounds the game needs
# are generated as samples here instead. Any failure is swallowed: audio is
# feedback, never a dependency for play.
class Sfx:
	extends AudioStreamPlayer

	const RATE := 22050.0

	var rng := RandomNumberGenerator.new()
	var playback: AudioStreamGeneratorPlayback
	var enabled := true

	func _ready() -> void:
		rng.randomize()
		var generator := AudioStreamGenerator.new()
		generator.mix_rate = RATE
		generator.buffer_length = 0.4
		stream = generator
		volume_db = -9.0
		# The web build defaults to "sample" playback, which a generated
		# stream cannot use — it has to be mixed as a stream instead.
		playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		play()
		playback = get_stream_playback() as AudioStreamGeneratorPlayback

	func _ensure() -> bool:
		if not enabled:
			return false
		if not playing:
			play()
		if playback == null:
			playback = get_stream_playback() as AudioStreamGeneratorPlayback
		return playback != null

	func emit(kind: String) -> void:
		if not _ensure():
			return
		var buffer := PackedVector2Array()
		match kind:
			"roll":
				for i in range(5):
					_tone(buffer, 320.0 + i * 40.0, 0.022, "noise", 0.35, 0.0)
					_silence(buffer, 0.018)
			"step":
				_tone(buffer, 520.0, 0.045, "square", 0.22, -0.25)
			"hit":
				_tone(buffer, 180.0, 0.05, "noise", 0.5, 0.0)
				_tone(buffer, 300.0, 0.07, "square", 0.3, -0.4)
			"hurt":
				_tone(buffer, 260.0, 0.16, "square", 0.4, -0.55)
			"shield":
				_tone(buffer, 380.0, 0.06, "tri", 0.3, 0.6)
			"kill":
				_tone(buffer, 330.0, 0.07, "square", 0.32, 0.0)
				_tone(buffer, 440.0, 0.07, "square", 0.32, 0.0)
				_tone(buffer, 660.0, 0.14, "square", 0.32, 0.0)
			"reward":
				_tone(buffer, 523.0, 0.08, "tri", 0.34, 0.0)
				_tone(buffer, 659.0, 0.08, "tri", 0.34, 0.0)
				_tone(buffer, 784.0, 0.18, "tri", 0.34, 0.0)
			"lose":
				_tone(buffer, 300.0, 0.30, "square", 0.34, -0.6)
			_:
				_tone(buffer, 600.0, 0.03, "square", 0.2, 0.0)
		if buffer.is_empty():
			return
		var room: int = playback.get_frames_available()
		if room <= 0:
			return
		if buffer.size() > room:
			buffer = buffer.slice(0, room)
		playback.push_buffer(buffer)

	func _tone(buffer: PackedVector2Array, freq: float, dur: float, wave: String, vol: float, sweep: float) -> void:
		var count: int = int(RATE * dur)
		if count <= 0:
			return
		var phase := 0.0
		for i in range(count):
			var t: float = float(i) / float(count)
			# Fast attack, exponential decay: reads as a hit, not a hum.
			var env: float = min(1.0, t * 12.0) * pow(1.0 - t, 1.6)
			var f: float = freq * (1.0 + sweep * t)
			phase += TAU * f / RATE
			var sample := 0.0
			match wave:
				"noise":
					sample = rng.randf_range(-1.0, 1.0)
				"tri":
					sample = asin(sin(phase)) * 0.637
				_:
					sample = 1.0 if sin(phase) >= 0.0 else -1.0
			var v: float = sample * env * vol
			buffer.append(Vector2(v, v))

	func _silence(buffer: PackedVector2Array, dur: float) -> void:
		for i in range(int(RATE * dur)):
			buffer.append(Vector2.ZERO)

var rng := RandomNumberGenerator.new()

# --- nodes -------------------------------------------------------------
var backdrop_view: Backdrop
var bg_view: SpriteView
var sfx: Sfx

var zone_top: Control
var zone_hero: Control
var zone_enemy: Control
var zone_board: Control
var zone_hand: Control
var zone_cmd: Control
var zone_log: Control
var zone_map: Control
var zone_gallery: Control

var run_track: RunTrack
var run_label: Label
var hero_portrait: HeroPortrait
var hp_bar: GaugeBar
var hp_label: Label
var shield_chip: PanelContainer
var shield_label: Label
var gold_chip: PanelContainer
var gold_label: Label

var map_scroll: ScrollContainer
var map_canvas: Control
var map_links: Control
var map_title: Label
var map_buttons: Dictionary = {}   # "row,col" -> Button
var action_pip_box: HBoxContainer

var hero_panel: PanelContainer
var hero_sprite: SpriteView
var hero_stage_name: Label

var enemy_panel: Control
var enemy_sprite: SpriteView
var enemy_name_label: Label
var enemy_hp_bar: GaugeBar
var enemy_hp_label: Label
var intent_panel: PanelContainer
var intent_icon: IconGlyph
var intent_label: Label
var intent_note: Label

var board_view: BoardView
var token_view: BoardView
var ribbon_box: VBoxContainer
var ribbon_row: HBoxContainer
var ribbon_caption: Label
var roll_readout: Label

var hand_row: HBoxContainer
var hand_scroll: ScrollContainer
var hand_left_button: Button
var hand_right_button: Button
var hand_slots: Array = []

var end_turn_button: Button
var restart_button: Button
var catalog_button: Button
var reroll_button: Button
var roll_catcher: Button
var log_label: Label
var banner: PanelContainer
var banner_label: Label

var overlay: Control
var overlay_card: VBoxContainer
var overlay_title: Label
var overlay_body: Label
var overlay_art: SpriteView
var overlay_list: VBoxContainer

# The full-frame scene layer: one image over everything, dismissed by a
# tap. It is its own layer rather than a mode of the overlay because it
# must cover the card too when a scene plays into a result screen.
var scene_layer: Control
var scene_sprite: SpriteView
var scene_caption: Label
var scene_hint: Label
var scene_after := Callable()

var gallery_grid: GridContainer
var gallery_scroll: ScrollContainer
var gallery_title: Label

var ui_font: Font
var ui_font_heavy: Font

var cell_buttons: Array = []
var cell_icons: Array = []
var cell_step_labels: Array = []
var cell_value_labels: Array = []
var cell_danger_labels: Array = []
var cell_debuff_labels: Array = []

# --- state -------------------------------------------------------------
var state := "title"
var hero_key := ""
var hero_name := ""
var hero_token_color := Color("#2E7BD6")
var encounter := 0
var player_hp := 30
var player_max_hp := 30
var player_shield := 0
var player_pos := Vector2i(0, 0)
var player_step := 0
var actions_left := 0
var player_visual_pos := Vector2.ZERO
var player_visual_ready := false
var player_hop := 0.0
var player_impact := 0.0
var combo_hits := 0
var run_damage_dealt := 0
var run_turns := 0
# Spending money for the map's shop nodes. Earned by killing things, so the
# only way to afford a removal is to have fought for it.
var gold := 0

var ring_cells: Array[Vector2i] = []
var ring_index_map: Dictionary = {}
var ring_forward: Dictionary = {}
var preview_path: Array[Vector2i] = []

var permanent_board: Array = []
var temp_board: Array = []
var enemies: Array = []
var next_enemy_uid := 0

var dice_bag: Array = []
var draw_pile: Array = []
var discard_pile: Array = []
var hand: Array = []

var selected_die := {}
var selected_roll := 0
var move_dir := 1
var steps_left := 0
var route_path: Array[Vector2i] = []
# Combo is the whole of the base system's arithmetic: it counts the dice
# spent this turn, and attack tiles add it to their damage. The old build
# had two separate hidden accumulators (a per-die tag bonus and a count of
# attack tiles hit) that no part of the UI ever showed.
var combo := 0
var pending_reward_type := ""
var pending_reward_name := ""
var preview_place_pos := Vector2i(-1, -1)
# Both of the game's committing taps are two-stage: the first one shows what
# the tap would do, the second one does it. Touch has no hover, so a preview
# has to be a tap — and the alternative, committing on the first one, means
# the player is told the consequences of a move only after making it.
# preview_die_index is the die currently being *considered*; -1 is "nothing
# picked yet".
var preview_die_index := -1
# A warp face jumps rather than walks: nothing along the way fires, so its
# crossed-count is zero however far it travelled.
var preview_warp := false
# The considered die's route. Separate from preview_path, which is the fixed
# six-square strip and does not move with the die.
var preview_route: Array[Vector2i] = []
var catalog_return_state := "title"
var settings_return_state := "title"
var gallery_return_state := "title"
# A fight resolves once, so its scene plays once — a win that arrives
# through two different code paths must not show the CG twice.
var scene_played_this_fight := false
# The hand is rolled once, up front, and the faces then stay put: the
# player picks which of the known results to walk. Rolling at the moment a
# die is chosen meant the stop-type tiles could never be aimed at, which
# made half the board a lottery.
var hand_limit := 3
# Actions per turn, same story as hand_limit: a hero property, not a global
# rule — 盗賊's extra action point is what its small, weak faces are for.
var actions_per_turn := ACTIONS_PER_TURN
var last_cleanse_count := 0
var dice_rolled := false
var rerolls_left := 0

# --- counters the effect system can read and scale against ---------------
# Each of these is the spine of one build concept rather than a rule that
# applies to everything. combo still counts every die spent this turn —
# that increment is the one common baseline, shared by every hero — but it
# is no longer added to every attack's damage. It only pays out through
# content that names it (連鎖路, 連撃, 供物台, ...), the same as charge, lap
# and poison. That is what makes "a combo build" a choice instead of a tax
# everyone pays, without also making the counter itself invisible to
# anyone who never picked combo content up.
# Charge belongs to squares, not to the player. Every square on the ring
# carries its own, climbing by one at the start of each player turn and
# dropping to nothing when something on that square cashes it in — so what
# a square's charge measures is how long it has been since anyone fired it.
# Leaving the far side of the ring alone is what makes the far side worth
# walking to.
#
# charge_cell is which square is being asked about: the one currently
# resolving an effect, the one a readout is being drawn for, or the one the
# piece is standing on while a die's spend effects run.
var charge_map: Dictionary = {}
var charge_cell := Vector2i(-1, -1)
var action_index := 0       # 1st or 2nd action of this turn
var crossed_this_action := 0

# --- the effect system -------------------------------------------------
# The whole base system is: a die fires its effects, and the squares it
# runs over fire theirs. Nothing else is hardcoded. Every tile and every
# die is a list of effects, and an effect is:
#
#   {"on": when, "op": what, "amount": n, "scale": counter, "cond": {...}}
#
#   on     "pass"  every square entered, including the one landed on
#          "stop"  only the square the action ended on
#          "spend" the moment the die is chosen (dice only)
#   op     what actually changes — see _apply_op
#   scale  multiply amount by a counter (combo / charge / shield / roll /
#          crossed / poison). This is how a build "cashes in".
#   cond   optional gate on the player's own state — never on anything the
#          player cannot control, or a board can lock itself out.
#
# Adding content means adding rows here, not branches in code. Anything
# expressible as (when × what × how much × scaled by × gated on) needs no
# new GDScript at all.
#
# Shape on the board still carries when a tile pays: round = pass,
# square = stop, and the cut-corner shape = both.
var tile_defs := {
	# --- 基本 ---
	"empty": {"name": "道", "kind": "基本", "color": Color("#CBB68F"), "icon": "boot",
		"trigger": "stop", "effect": "盾+1",
		"effects": [{"on": "stop", "op": "shield", "amount": 1}],
		"detail": "何も置いていないただの道。止まれば盾が1つだけ手に入る。"},

	# --- 疾走: 通過型。1マスあたりは軽いが、長い出目で何枚も踏むほど伸びる ---
	"slash": {"name": "斬撃路", "kind": "疾走", "color": Color("#E4453A"), "icon": "slash",
		"trigger": "pass", "effect": "通過ごとに3ダメージ",
		"effects": [{"on": "pass", "op": "attack", "amount": 3}],
		"detail": "通り抜けざまに斬る。大きい出目で何枚も踏み抜くほど伸びる、攻めの基本。"},
	"fire": {"name": "火走り", "kind": "疾走", "color": Color("#F2762B"), "icon": "fire",
		"trigger": "pass", "effect": "通過ごとに2ダメージ、毒+1",
		"effects": [{"on": "pass", "op": "attack", "amount": 2},
			{"on": "pass", "op": "poison", "amount": 1}],
		"detail": "走った跡が燃える。1枚あたりは軽いが、通るたびに敵を焼き続ける毒を残す。"},
	"guard": {"name": "防御路", "kind": "疾走", "color": Color("#2E7BD6"), "icon": "guard",
		"trigger": "pass", "effect": "通過ごとに盾+2",
		"effects": [{"on": "pass", "op": "shield", "amount": 2}],
		"detail": "通るたびに盾を拾う。盾はターン開始で消えるので、殴られる前に集めること。"},
	"heal": {"name": "癒し道", "kind": "疾走", "color": Color("#3EA95E"), "icon": "heal",
		"trigger": "pass", "effect": "通過ごとにHP+1",
		"effects": [{"on": "pass", "op": "heal", "amount": 1}],
		"detail": "少しずつしか戻らない。長い出目で何度も通り抜けるのが回復の近道。"},
	"gale": {"name": "疾風路", "kind": "疾走", "color": Color("#C2453A"), "icon": "slash",
		"trigger": "stop", "effect": "この行動で進んだマス数ぶんダメージ",
		"effects": [{"on": "stop", "op": "attack", "amount": 1, "scale": "crossed"}],
		"detail": "遠くから走り込むほど重い。小さい出目で止まっても意味がなく、大きい出目の着地点にして初めて活きる。"},
	"tailwind": {"name": "追い風", "kind": "疾走", "color": Color("#2AA1A8"), "icon": "warp",
		"trigger": "stop", "effect": "進んだマス数ぶん盾",
		"effects": [{"on": "stop", "op": "shield", "amount": 1, "scale": "crossed"}],
		"detail": "駆け抜けた勢いをそのまま構えに変える。長距離を走ったターンの着地点に。"},
	"warp": {"name": "跳躍路", "kind": "移動", "color": Color("#16A0C8"), "icon": "warp",
		"trigger": "pass", "effect": "1歩多く進む",
		"effects": [{"on": "pass", "op": "step", "amount": 1}],
		"detail": "出目を1つ伸ばす。止まりたいマスに足りないときの調整に使う。"},
	"assault": {"name": "突進", "kind": "移動", "color": Color("#D6491F"), "icon": "slash",
		"trigger": "stop", "effect": "4ダメージ＋出目（逆走では出目ぶん弱まる）",
		"effects": [{"on": "stop", "op": "attack", "amount": 4, "add_scale": "roll"}],
		"detail": "大きい出目で踏み込むほど重い。逆走で辿り着くと出目ぶん弱まり、出目次第では不発にもなる — 前進で使うためのマス。"},
	"caution": {"name": "慎重", "kind": "移動", "color": Color("#2E6B8C"), "icon": "guard",
		"trigger": "stop", "effect": "9ダメージ－出目（逆走では出目ぶん強まる）",
		"effects": [{"on": "stop", "op": "attack", "amount": 9, "add_scale": "roll", "add_scale_sign": -1}],
		"detail": "突進の裏返し。小さい出目、あるいは逆走で辿り着くほど重くなる — 大きく動いた勢いそのままでは弱く、抑えて止まるか押し戻されて初めて活きる。"},

	# --- 小刻み: 小さい出目でだけ開く。疾走の裏返し ---
	# Every die in the game wants to roll big, so a 1 was purely an
	# accident. These make the small half of the range the half you aim
	# for. 逆走's faces are all negative and so satisfy every max_roll
	# condition automatically — the two axes fit together without either
	# knowing about the other.
	"pinpoint": {"name": "寸止め", "kind": "小刻み", "color": Color("#2E7BD6"), "icon": "bow",
		"trigger": "stop", "effect": "出目2以下なら18ダメージ",
		"effects": [{"on": "stop", "op": "attack", "amount": 18, "cond": {"max_roll": 2}}],
		"detail": "刻んで踏み込んだときだけ火を噴く。大きい出目で辿り着いても完全な空振りで、狙いを絞るためのマス。逆走で入っても条件を満たす。"},
	"shuffle": {"name": "摺り足", "kind": "小刻み", "color": Color("#4F8C8A"), "icon": "guard",
		"trigger": "pass", "effect": "出目3以下なら通過ごとに盾+3",
		"effects": [{"on": "pass", "op": "shield", "amount": 3, "cond": {"max_roll": 3}}],
		"detail": "小さく動く限りは硬い。通過型なのに大きい出目で得をしない、数少ないマス。"},
	"measure": {"name": "間合い", "kind": "小刻み", "color": Color("#5B8C2A"), "icon": "focus",
		"trigger": "stop", "effect": "出目3以下ならダイス1枚、振り直し+1",
		"effects": [{"on": "stop", "op": "draw", "amount": 1, "cond": {"max_roll": 3}},
			{"on": "stop", "op": "reroll", "amount": 1, "cond": {"max_roll": 3}}],
		"detail": "小さい目を事故から立て直しに変える。悪い手札を引いたターンほど価値が上がる。"},
	"read": {"name": "見切り", "kind": "小刻み", "color": Color("#C9A227"), "icon": "dice",
		"trigger": "stop", "effect": "出目1なら行動+1、コンボ+2",
		"effects": [{"on": "stop", "op": "action", "amount": 1, "cond": {"max_roll": 1}},
			{"on": "stop", "op": "combo", "amount": 2, "cond": {"max_roll": 1}}],
		"detail": "1でしか開かない代わりに、その1が実質タダになる。盤上で唯一、最低の目が最高の目になるマス。"},

	# --- 連鎖: コンボを積み、コンボを参照するマスで清算する ---
	"chain": {"name": "連鎖路", "kind": "連鎖", "color": Color("#F2C230"), "icon": "chain",
		"trigger": "pass", "effect": "通過ごとにコンボ+1",
		"effects": [{"on": "pass", "op": "combo", "amount": 1}],
		"detail": "通り抜けるとコンボが1増える。コンボ自体は何もしないが、コンボを参照するマスとダイスが一気に重くなる。"},
	"volley": {"name": "連撃台", "kind": "連鎖", "color": Color("#D98A1F"), "icon": "slash",
		"trigger": "stop", "effect": "コンボ×3ダメージ",
		"effects": [{"on": "stop", "op": "attack", "amount": 3, "scale": "combo"}],
		"detail": "積んだコンボをそのまま打点に変える。連鎖路を踏んでから着地するのが基本の形。"},
	"resonance": {"name": "共鳴盤", "kind": "連鎖", "color": Color("#B8862B"), "icon": "shock",
		"trigger": "stop", "effect": "コンボ3以上なら14ダメージ",
		"effects": [{"on": "stop", "op": "attack", "amount": 14, "cond": {"min_combo": 3}}],
		"detail": "条件を満たせば盤上最大級。満たせなければ完全な空振りで、コンボを積む算段とセットで置くマス。"},
	"spiral": {"name": "螺旋路", "kind": "連鎖", "color": Color("#E0A32B"), "icon": "chain",
		"trigger": "both", "effect": "通過でコンボ+1／停止でコンボ×2ダメージ",
		"effects": [{"on": "pass", "op": "combo", "amount": 1},
			{"on": "stop", "op": "attack", "amount": 2, "scale": "combo"}],
		"detail": "自分で積んで自分で清算する一枚完結型。通過と停止の両方で働く。"},

	# --- 狙撃: チャージを溜め、撃ち切る ---
	"battery": {"name": "蓄積砲台", "kind": "狙撃", "color": Color("#7C4DD6"), "icon": "focus",
		"trigger": "both", "effect": "通過でチャージ+1／停止でチャージ×4ダメージ（消費）",
		"effects": [{"on": "pass", "op": "charge", "amount": 1},
			{"on": "stop", "op": "attack", "amount": 4, "scale": "charge"},
			{"on": "stop", "op": "spend_charge", "amount": 0}],
		"detail": "踏むたびに溜まり、止まった瞬間に全部吐き出す。チャージは撃たずに待ったターン数そのものなので、我慢するほど重い一発になり、撃った瞬間にゼロへ戻る。"},
	"aim": {"name": "照準台", "kind": "狙撃", "color": Color("#8E6BD6"), "icon": "focus",
		"trigger": "stop", "effect": "盤上すべてのマスのチャージ+2",
		"effects": [{"on": "stop", "op": "charge_all", "amount": 2}],
		"detail": "盤上のすべてのマスを2ターンぶん進める。自分では何も撃たないが、砲台を何門も並べた盤面ほど見返りが大きくなる、狙撃ビルドの司令塔。"},
	"lance": {"name": "貫通砲", "kind": "狙撃", "color": Color("#5B3AA8"), "icon": "bow",
		"trigger": "stop", "effect": "チャージ×3ダメージ（消費しない）",
		"effects": [{"on": "stop", "op": "attack", "amount": 3, "scale": "charge"}],
		"detail": "時計を止めずに撃てる代わりに倍率が低い。チャージは減らないので、待ちながら毎ターン撃ち続けられる。"},
	"heavy": {"name": "大斬撃", "kind": "狙撃", "color": Color("#B5302A"), "icon": "slash",
		"trigger": "stop", "effect": "7ダメージ＋出目ぶん",
		# One row, not two. Written as two attacks it landed as two hits and
		# paid 装甲 twice over, which its own text ("7ダメージ＋出目ぶん")
		# never promised. "N plus the roll" already has a first-class form —
		# the one 突進/慎重 use — and as one row it is one strike.
		"effects": [{"on": "stop", "op": "attack", "amount": 7, "add_scale": "roll"}],
		"detail": "踏み込みが深いほど重い。大きい出目のダイスをここに当てるのが剣士の基本。"},
	"bow": {"name": "射撃台", "kind": "狙撃", "color": Color("#C9971F"), "icon": "bow",
		"trigger": "stop", "effect": "出目×2ダメージ",
		"effects": [{"on": "stop", "op": "attack", "amount": 2, "scale": "roll"}],
		"detail": "威力が完全に出目任せ。6で止まれば12だが、1なら2しか出ない。大きい目のダイスと組む。"},
	"trap": {"name": "罠道", "kind": "狙撃", "color": Color("#C2457E"), "icon": "trap",
		"trigger": "stop", "effect": "HP3を払って16ダメージ",
		"effects": [{"on": "stop", "op": "self_damage", "amount": 3},
			{"on": "stop", "op": "attack", "amount": 16}],
		"detail": "盤上で最も重い一撃だが、自分のHPを削って撃つ。押し切れる場面かどうかの判断を迫るマス。"},
	"firststrike": {"name": "先手", "kind": "狙撃", "color": Color("#8E6BD6"), "icon": "bow",
		"trigger": "stop", "effect": "1手目なら12ダメージ、行動+1",
		"effects": [{"on": "stop", "op": "attack", "amount": 12, "cond": {"action": 1}},
			{"on": "stop", "op": "action", "amount": 1, "cond": {"action": 1}}],
		"detail": "そのターンの1手目で止まった時だけ働き、使った行動をそのまま返す。狙撃点が2手目を条件にするのに対し、こちらは1手目 — 両方を盤に置くと、ターンの組み立てそのものが道筋になる。"},
	"snipe": {"name": "狙撃点", "kind": "狙撃", "color": Color("#A8791F"), "icon": "bow",
		"trigger": "stop", "effect": "2回目の行動なら12ダメージ",
		"effects": [{"on": "stop", "op": "attack", "amount": 12, "cond": {"action": 2}}],
		"detail": "そのターンの2手目で止まった時だけ火を噴く。行動の順番そのものが条件になる一枚。"},

	# --- 要塞: 盾を溜め、盾で殴る ---
	"fort": {"name": "砦", "kind": "要塞", "color": Color("#1F5FA8"), "icon": "guard",
		"trigger": "stop", "effect": "盾+6",
		"effects": [{"on": "stop", "op": "shield", "amount": 6}],
		"detail": "腰を据えて構える。盾はターン開始で消えるので、殴られるターンに合わせて止まること。"},
	"thorns": {"name": "棘壁", "kind": "要塞", "color": Color("#2E5FA8"), "icon": "shock",
		"trigger": "stop", "effect": "今ある盾ぶんダメージ",
		"effects": [{"on": "stop", "op": "attack", "amount": 1, "scale": "shield"}],
		"detail": "守りをそのまま刃に変える。先に盾を集めてから止まらないと、ただの空振りになる。"},
	"bastion": {"name": "鉄壁", "kind": "要塞", "color": Color("#16457C"), "icon": "guard",
		"trigger": "stop", "effect": "HP半分以下なら盾+12",
		"effects": [{"on": "stop", "op": "shield", "amount": 12, "cond": {"hp_below": 0.5}}],
		"detail": "追い詰められてから初めて働く。余裕のあるうちは死にマスで、劣勢でこそ盤面を支える。"},
	# 棘壁 and 反射盤 turn shield into damage by spending its size. These
	# three ask only that you have some, so they pay a flat rate and stack
	# with the scaling ones instead of competing with them.
	"shieldbash": {"name": "盾撃", "kind": "要塞", "color": Color("#2E5FA8"), "icon": "slash",
		"trigger": "stop", "effect": "盾があれば14ダメージ",
		"effects": [{"on": "stop", "op": "attack", "amount": 14, "cond": {"has_shield": true}}],
		"detail": "盾を減らさずに殴れる。1枚でも盾があれば満額なので、棘壁のように大量に貯める必要がない。"},
	"rampart": {"name": "城壁路", "kind": "要塞", "color": Color("#3A72C2"), "icon": "shock",
		"trigger": "pass", "effect": "盾があれば通過ごとに2ダメージ",
		"effects": [{"on": "pass", "op": "attack", "amount": 2, "cond": {"has_shield": true}}],
		"detail": "盾を持ったまま走ると刃になる。先に盾を作ってから踏むという、ターン内の順番が問われるマス。"},
	"redoubt": {"name": "堅陣", "kind": "要塞", "color": Color("#16457C"), "icon": "guard",
		"trigger": "stop", "effect": "盾があれば盾+8、HP+4",
		"effects": [{"on": "stop", "op": "shield", "amount": 8, "cond": {"has_shield": true}},
			{"on": "stop", "op": "heal", "amount": 4, "cond": {"has_shield": true}}],
		"detail": "持っている者だけがさらに固くなる。盾ゼロで踏むと完全な空振りで、守りを切らさない立ち回りを要求する。"},
	"reflect": {"name": "反射盤", "kind": "要塞", "color": Color("#3A72C2"), "icon": "guard",
		"trigger": "both", "effect": "通過で盾+1／停止で盾の2倍ダメージ",
		"effects": [{"on": "pass", "op": "shield", "amount": 1},
			{"on": "stop", "op": "attack", "amount": 2, "scale": "shield"}],
		"detail": "自分で盾を集めながら走り、最後に叩きつける。要塞ビルドの一枚完結型。"},

	# --- 毒: 継続ダメージを盛り、時間を味方にする ---
	"venom": {"name": "毒沼", "kind": "毒", "color": Color("#6F9C1F"), "icon": "poison",
		"trigger": "stop", "effect": "敵に毒+4",
		"effects": [{"on": "stop", "op": "poison", "amount": 4}],
		"detail": "毒は敵のターン終わりに毒の数だけダメージを与え、1減る。長い戦いほど総ダメージが伸びる。"},
	"rot": {"name": "腐食路", "kind": "毒", "color": Color("#8FB53A"), "icon": "poison",
		"trigger": "pass", "effect": "通過ごとに毒+1",
		"effects": [{"on": "pass", "op": "poison", "amount": 1}],
		"detail": "走り抜けるだけで毒が積み上がる。大きい出目と組むと一気に盛れる。"},
	"blight": {"name": "蝕み台", "kind": "毒", "color": Color("#4F7A16"), "icon": "trap",
		"trigger": "stop", "effect": "毒×3ダメージ（毒は残る）",
		"effects": [{"on": "stop", "op": "attack", "amount": 3, "scale": "poison"}],
		"detail": "盛った毒を即座に打点へ変換する。毒を撒く手段とセットで初めて意味を持つ。"},

	# --- 手負い: 失ったHPそのものを資源にする ---
	# The HP-paying content already existed — 供物台, 罠道, 献身, 血の祭壇 —
	# with nothing anywhere that paid it back. These close that loop: the
	# cost those squares charge is the fuel these squares burn. 不屈壁 is
	# what stops the axis being a straight line into death, and it is
	# deliberately the same counter, so surviving and killing pull on the
	# same resource.
	"lastblade": {"name": "背水刃", "kind": "手負い", "color": Color("#A8324A"), "icon": "slash",
		"trigger": "stop", "effect": "失ったHPぶんダメージ",
		"effects": [{"on": "stop", "op": "attack", "amount": 1, "scale": "wounds"}],
		"detail": "傷が深いほど重い一撃。満身創痍で最大になり、回復すると弱くなる — 癒しを取るかどうかの判断ごと変えてしまうマス。"},
	"unbowed": {"name": "不屈壁", "kind": "手負い", "color": Color("#8C3A5E"), "icon": "guard",
		"trigger": "stop", "effect": "失ったHPぶん盾",
		"effects": [{"on": "stop", "op": "shield", "amount": 1, "scale": "wounds"}],
		"detail": "追い詰められるほど硬くなる。背水刃と同じ傷を見ているので、殴るか耐えるかを毎ターン選ぶことになる。"},
	"bloodpath": {"name": "鮮血路", "kind": "手負い", "color": Color("#C2453A"), "icon": "poison",
		"trigger": "pass", "effect": "通過ごとにHP-1、3ダメージ",
		"effects": [{"on": "pass", "op": "self_damage", "amount": 1},
			{"on": "pass", "op": "attack", "amount": 3}],
		"detail": "走り抜けながら自分を削る。斬撃路より重い代わりに代価を払う — そして払った傷は、手負いのマスがそのまま火力に変える。"},
	"deathline": {"name": "死線", "kind": "手負い", "color": Color("#6B1F3A"), "icon": "skull",
		"trigger": "stop", "effect": "HP35%以下なら25ダメージ",
		"effects": [{"on": "stop", "op": "attack", "amount": 25, "cond": {"hp_below": 0.35}}],
		"detail": "余裕のあるうちは完全な死にマス。本当に後がなくなってから初めて開く、盤上で最も重い一撃。"},

	# Thresholds, so 毒 has a shape: slow to open, heavy once it does.
	"plaguefang": {"name": "疫の刃", "kind": "毒", "color": Color("#4F7A16"), "icon": "slash",
		"trigger": "stop", "effect": "毒5以上なら22ダメージ",
		"effects": [{"on": "stop", "op": "attack", "amount": 22, "cond": {"min_poison": 5}}],
		"detail": "毒を5まで盛ってから初めて開く。毒沼ひとつでは届かず、撒く手段を揃えた盤面への報酬。毒は減らないので、盛り直さずに何度でも撃てる。"},
	"fester": {"name": "腐敗路", "kind": "毒", "color": Color("#6F9C1F"), "icon": "poison",
		"trigger": "pass", "effect": "毒4以上なら通過ごとに3ダメージ",
		"effects": [{"on": "pass", "op": "attack", "amount": 3, "cond": {"min_poison": 4}}],
		"detail": "毒が回りきった相手の上を走ると、通過そのものが打点になる。毒ビルドが疾走ビルドの走り方を手に入れるマス。"},

	# --- 補助: 手札と行動そのものを増やす ---
	"focus": {"name": "集中路", "kind": "補助", "color": Color("#5B8C2A"), "icon": "focus",
		"trigger": "stop", "effect": "ダイスを1枚引く",
		"effects": [{"on": "stop", "op": "draw", "amount": 1}],
		"detail": "手札を1枚補充する。引いたダイスはその場で振られ、まだ行動が残っていればそのまま使える。"},
	"spring": {"name": "泉", "kind": "補助", "color": Color("#2E8449"), "icon": "heal",
		"trigger": "stop", "effect": "HP+6",
		"effects": [{"on": "stop", "op": "heal", "amount": 6}],
		"detail": "汲むには足を止めるしかない。倍率も条件もない、素直な回復。"},
	"shock": {"name": "雷線", "kind": "補助", "color": Color("#7C4DD6"), "icon": "shock",
		"trigger": "stop", "effect": "5ダメージ、盾+3",
		"effects": [{"on": "stop", "op": "attack", "amount": 5},
			{"on": "stop", "op": "shield", "amount": 3}],
		"detail": "攻めと守りを同時にこなす。尖ってはいないが、どちらも欲しいターンの着地点に。"},
	"relay": {"name": "転換炉", "kind": "補助", "color": Color("#4F8C8A"), "icon": "warp",
		"trigger": "stop", "effect": "ダイス1枚、振り直し+1",
		"effects": [{"on": "stop", "op": "draw", "amount": 1},
			{"on": "stop", "op": "reroll", "amount": 1}],
		"detail": "打点は一切ないが、手札と選択肢を回復する。事故ったターンを立て直すためのマス。"},
	"windfall": {"name": "好機", "kind": "補助", "color": Color("#C9A227"), "icon": "dice",
		"trigger": "stop", "effect": "出目5以上で止まると行動+1",
		"effects": [{"on": "stop", "op": "action", "amount": 1, "cond": {"min_roll": 5}}],
		"detail": "大きい出目で踏み込めば、そのターンにもう一度動ける。条件を満たせない出目では何も起きない。"},
	"one_more": {"name": "ワンモア", "kind": "補助", "color": Color("#E0A32B"), "icon": "dice",
		"trigger": "stop", "effect": "行動+1",
		"effects": [{"on": "stop", "op": "action", "amount": 1}],
		"detail": "出目に関係なく必ず行動が1回戻る。好機より控えめだが、条件なしで確実に手数を伸ばせる。"},
	"altar": {"name": "供物台", "kind": "補助", "color": Color("#9C3A6B"), "icon": "skull",
		"trigger": "stop", "effect": "HP4を払ってコンボ+3、チャージ+3",
		"effects": [{"on": "stop", "op": "self_damage", "amount": 4},
			{"on": "stop", "op": "combo", "amount": 3},
			{"on": "stop", "op": "charge", "amount": 3}],
		"detail": "HPを資源に変える。連鎖と狙撃のどちらのビルドにも刺さるが、払うものは自分の命。"}
}

# Enemies do not build their own squares — they foul yours. A debuff sits
# on top of whatever tile is already there: the tile keeps its colour, its
# icon and its effect, and picks up a cost for walking over it. Killing the
# enemy that cast them clears the board.
#
# Like tiles and dice, a debuff is data. Four flags cover everything the
# roster does, and they compose, so a new one is a row here rather than a
# branch in the movement code:
#
#   damage / on   HP lost on entering ("pass") or on ending there ("stop")
#   nullify       the square underneath does not fire at all
#   halt          entering ends the move here, whatever the die rolled
#   clear_on      when the square shakes the debuff off: "pass" (walked
#                 over), "stop" (ended on) or "halt" (halted by). One
#                 reason, or a list of them
#
# "mark" is the one character the board prints in the corner of a fouled
# square. It has to be one character: the square is already carrying its
# own icon and number.
var temp_defs := {
	"none": {"short": "", "color": Color("#00000000"), "desc": ""},

	# The two that simply cost HP, split by when they charge it. 炎上 is the
	# old hazard under a name that says what it does: it punishes the long
	# sweeping rolls that 疾走 builds live on. 毒 is its opposite number and
	# punishes the aimed landing, so between them there is no roll that is
	# safe by default.
	"burn": {"name": "炎上", "icon": "fire", "color": Color("#E2701F"), "mark": "炎",
		"damage": 2, "on": "pass",
		"trigger": "pass", "effect": "通過ごとにHP-2",
		"desc": "炎上: 通過するとHP-2。踏み抜くほど痛い",
		"detail": "敵がマスにかける。マスの効果はそのまま残るが、通過するたびにHPを2失う。大きい出目で何枚も踏み抜く走り方ほど損をする。かけた敵を倒すと全て消える。"},
	"venom": {"name": "毒", "icon": "poison", "color": Color("#7FA82B"), "mark": "毒",
		"damage": 4, "on": "stop",
		"trigger": "stop", "effect": "止まるとHP-4",
		"desc": "毒: 止まるとHP-4。通過するだけなら無傷",
		"detail": "敵がマスにかける。通り抜けるぶんには何も起きないが、そこで行動を終えるとHPを4失う。狙って止まりたいマスに乗ると、着地そのものに値段がつく。かけた敵を倒すと全て消える。"},

	# 凍結 costs no HP at all. It takes the square away — which against a
	# board the player spent the whole run building is the more expensive
	# of the two things an enemy can do to them.
	#
	# It melts under any foot, walking or landing, and that is the whole of
	# the choice it poses. Sweeping over it costs the walk nothing it was
	# not already spending, so a long roll clears the ice on its way past;
	# landing on it clears the ice too, but the landing itself buys nothing,
	# which is a whole action spent on thawing one square. The ice is
	# therefore never a wall, only a bill — and the player picks which of
	# the two prices to pay.
	"freeze": {"name": "凍結", "icon": "shock", "color": Color("#4E9BD6"), "mark": "氷",
		"nullify": true, "clear_on": ["pass", "stop"],
		"trigger": "both", "effect": "マスの効果を無効化。一度踏めば溶ける",
		"desc": "凍結: そのマスの効果が出ない。通っても止まっても溶ける",
		"detail": "凍りついたマスは、通過効果も停止効果も一切発動しない。ダメージは受けないが、盛り上げた盤面の一番おいしい一枚を黙らせてくる。一度踏めば溶けるので、走り抜けざまに割ってしまえば次からはまた働く。直接止まって溶かすこともできるが、その着地ではマスが働かないので、行動を1回まるごと氷を割るために使うことになる。かけた敵を倒しても消える。"},

	# 茨 spends the player's distance instead of their HP. It is the only
	# debuff that makes the preview's landing square move, which is why the
	# route has to know about it (see _route_for_roll) — a preview that
	# promised a landing the briar will not allow would be a lie.
	"briar": {"name": "茨", "icon": "trap", "color": Color("#8E5A9C"), "mark": "茨",
		"halt": true, "clear_on": "halt",
		"trigger": "pass", "effect": "出目に関わらずここで止まる",
		"desc": "茨: 踏むと出目に関わらずそこで止まる。踏み倒すと消える",
		"detail": "足を取られ、残りの歩数を捨ててそのマスで行動が終わる。止まった扱いなのでそのマスの停止効果は出るが、狙っていた着地点には届かない。踏み倒すと茨自体は消える。かけた敵を倒しても消える。"},

	"block": {"name": "壁", "color": Color("#4A4038"), "desc": "通れない"}
}

# The board holds debuff ids; everything that has to know how one behaves
# asks here rather than naming a type. "none" and "block" are not debuffs
# with behaviour, so they answer empty and every caller falls through.
func _debuff_at(pos: Vector2i) -> Dictionary:
	var id := str(temp_board[pos.y][pos.x])
	if id == "none" or id == "block" or not temp_defs.has(id):
		return {}
	return temp_defs[id]

# HP a fouled square charges for entering it ("pass") or for ending the
# action on it ("stop"). 軽業 pays neither: its pierce is written against
# the damage half of the system, not against 凍結 or 茨, which cost no HP
# and so have nothing for it to ignore.
func _debuff_damage(pos: Vector2i, timing: String, die: Dictionary) -> int:
	var deb := _debuff_at(pos)
	if deb.is_empty() or int(deb.get("damage", 0)) <= 0:
		return 0
	if str(deb.get("on", "pass")) != timing:
		return 0
	if bool(die.get("pierce", false)):
		return 0
	return int(deb["damage"])

func _debuff_nullifies(pos: Vector2i) -> bool:
	return bool(_debuff_at(pos).get("nullify", false))

func _debuff_halts(pos: Vector2i) -> bool:
	return bool(_debuff_at(pos).get("halt", false))

# A debuff that has done its job gets shaken off. "clear_on" is one reason
# or a list of them, so a debuff that comes off two different ways — 凍結
# melts whether it is walked over or landed on — stays a row rather than a
# branch. Returns the name it went by so the log can say so.
func _consume_debuff(pos: Vector2i, reason: String) -> String:
	var deb := _debuff_at(pos)
	if deb.is_empty():
		return ""
	var reasons = deb.get("clear_on", "")
	if not (reasons if reasons is Array else [reasons]).has(reason):
		return ""
	temp_board[pos.y][pos.x] = "none"
	_spawn_floating_text(pos, "解除", COL_HP)
	_refresh_board()
	return _t(deb["name"])

# A die is three things: the faces say how far this action reaches,
# "effects" fire the moment it is spent, and "mods" multiply what the
# squares it runs over pay out. All three use the same effect vocabulary as
# tile_defs, so a new die is data, not code.
#
# A mod is {"op": which operation, "on": "pass"/"stop" (optional), "x": n}
# and applies only for the action that die was spent on. Multiplying the
# board's own numbers rather than adding flat ones is deliberate: a die is
# worth more on a board built to suit it, so the tile-build and the
# dice-build pull on each other instead of being two separate piles.
#
# A face's sign is its direction: a positive face steps forward, a negative
# one steps back. Every ordinary die only ever has positive faces, so this
# costs nothing for the rest of the roster — it exists for 逆走, whose
# faces are all negative, and it is also why 突進/慎重 below can read the
# turn's signed roll directly instead of needing their own "which way did
# this die point" logic.
var dice_defs := {
	# --- 基本 ---
	"normal": {"name": "標準", "faces": [1, 2, 3, 4, 5, 6],
		"color": Color("#54687F"), "short": "均等", "effect": "効果なし",
		"detail": "1から6まで素直に出る、なんの仕掛けもないダイス。効果はない代わりに出目の幅が最も広く、止まれる場所の選択肢を一番多くくれる。"},
	"heavydie": {"name": "重撃", "faces": [3, 4, 4, 5, 6, 6],
		"color": Color("#B5502A"), "short": "大きめ", "effect": "効果なし・大きい目",
		"detail": "小さい目が出ない。遠くまで一息に運ぶので、通過型マスを何枚も踏み抜きたいときや、出目を参照するマスと相性が良い。"},
	"precise": {"name": "精密", "faces": [3, 3, 4, 4, 5, 5],
		"color": Color("#4F8C8A"), "short": "安定", "effect": "効果なし・ばらつかない",
		"detail": "3から5しか出ない。着地点の予測が立てやすい代わりに、選べる場所の幅は狭い。"},
	"gamble": {"name": "賭博", "faces": [1, 1, 1, 6, 6, 6],
		"color": Color("#C2457E"), "short": "両極端", "effect": "効果なし・1か6",
		"detail": "1か6しか出ない。手札に複数あると着地候補が両極に散り、どちらかは必ず遠くへ届く。"},

	# --- 倍率系: 盤面の数字を掛け算する ---
	"blade": {"name": "攻撃", "faces": [1, 2, 3, 3, 4, 5],
		"color": Color("#E4453A"), "short": "停止攻撃2倍", "effect": "停止型マスのダメージが2倍",
		"mods": [{"op": "attack", "on": "stop", "x": 2}],
		"detail": "止まった先の攻撃がまるごと2倍になる。狙って止まれた時の見返りが最も大きい。"},
	"rush": {"name": "疾走", "faces": [3, 4, 5, 5, 6, 6],
		"color": Color("#2AA1A8"), "short": "通過2倍", "effect": "通過型マスの効果が2倍",
		"mods": [{"on": "pass", "x": 2}],
		"detail": "走り抜けざまに踏んだマスの効果が全部2倍。斬撃路や腐食路を敷いた盤面ほど伸びる、攻撃ダイスとは正反対の使い方。"},
	"bulwark": {"name": "守勢", "faces": [1, 2, 2, 3, 3, 4],
		"color": Color("#2E7BD6"), "short": "盾2倍", "effect": "得られる盾が2倍",
		"mods": [{"op": "shield", "x": 2}],
		"detail": "砦に止まれば盾+12。盾を打点に変える棘壁や反射盤と組むと、守りがそのまま火力になる。"},
	"mend": {"name": "治癒", "faces": [1, 2, 2, 3, 3, 4],
		"color": Color("#3EA95E"), "short": "回復2倍", "effect": "回復量が2倍",
		"mods": [{"op": "heal", "x": 2}],
		"detail": "戦闘間にHPは戻らないので、盤面に回復を仕込んでいるほど効く。"},
	"toxin": {"name": "猛毒", "faces": [1, 2, 2, 3, 3, 4],
		"color": Color("#6F9C1F"), "short": "毒2倍", "effect": "与える毒が2倍",
		"mods": [{"op": "poison", "x": 2}],
		"detail": "腐食路を走れば一度に大量の毒が乗る。毒は敵のターンごとに効くので、長引くほど得をする。"},
	"dynamo": {"name": "蓄電", "faces": [2, 2, 3, 3, 4, 4],
		"color": Color("#7C4DD6"), "short": "チャージ2倍", "effect": "得られるチャージが2倍",
		"mods": [{"op": "charge", "x": 2}, {"op": "charge_all", "x": 2}],
		"detail": "マスが与えるチャージが倍になる。毎ターン自然に増える1は倍にならないので、照準台や蓄積砲台と組んで初めて効く。"},
	"tempest": {"name": "嵐撃", "faces": [4, 5, 5, 6, 6, 6],
		"color": Color("#B5302A"), "short": "通過攻撃3倍", "effect": "通過型マスのダメージが3倍",
		"mods": [{"op": "attack", "on": "pass", "x": 3}],
		"detail": "通過ダメージだけを極端に伸ばす。斬撃路を並べた盤面での決め手になるが、盾も回復も伸びない。"},

	# --- 使用時効果系: 選んだ瞬間に発動する ---
	"chainb": {"name": "連撃", "faces": [1, 1, 2, 2, 3, 3],
		"color": Color("#F2C230"), "short": "コンボ+2", "effect": "使うとコンボ+2",
		"effects": [{"on": "spend", "op": "combo", "amount": 2}],
		"detail": "出目は小さいが、先に使えばそのターンのコンボ参照マスが一気に重くなる。刻んで積むための一本。"},
	"delve": {"name": "発掘", "faces": [2, 2, 3, 3, 4, 4],
		"color": Color("#5B8C2A"), "short": "1枚補充", "effect": "使うとダイスを1枚引く",
		"effects": [{"on": "spend", "op": "draw", "amount": 1}],
		"detail": "使っても手札が減らない。行動回数は増えないが、選択肢の幅を保てる。"},
	"augur": {"name": "予知", "faces": [1, 1, 3, 5, 6, 6],
		"color": Color("#8E6BD6"), "short": "振り直し+1", "effect": "使うと振り直しが1回戻る",
		"effects": [{"on": "spend", "op": "reroll", "amount": 1}],
		"detail": "両極端な出目で当たり外れが激しいが、1手目に使えば残りの手札を振り直して2手目を選び直せる。"},
	"charger": {"name": "充填", "faces": [1, 1, 2, 2, 3, 3],
		"color": Color("#5B3AA8"), "short": "全マス電+2", "effect": "使うと盤上すべてのマスのチャージ+2",
		"effects": [{"on": "spend", "op": "charge_all", "amount": 2}],
		"detail": "盤上のすべてのマスに2ターンぶん装填する。撃ちたい砲台に間に合わせるための一本で、砲台が多いほど得をする。"},
	"ember": {"name": "火種", "faces": [1, 2, 3, 4, 5, 6],
		"color": Color("#8FB53A"), "short": "毒+3", "effect": "使うと敵に毒+3",
		"effects": [{"on": "spend", "op": "poison", "amount": 3}],
		"detail": "毒マスが一枚も無くても毒ビルドを始められる。出目は標準と同じで扱いやすい。"},
	"rally": {"name": "号令", "faces": [1, 2, 3, 4, 5, 6],
		"color": Color("#1F5FA8"), "short": "盾+4", "effect": "使うと盾+4",
		"effects": [{"on": "spend", "op": "shield", "amount": 4}],
		"detail": "着地点に関係なく盾が手に入る。棘壁や反射盤の前準備としても使える。"},
	"devote": {"name": "献身", "faces": [4, 5, 5, 6, 6, 6],
		"color": Color("#9C3A6B"), "short": "HP2でコンボ+3", "effect": "使うとHP-2、コンボ+3",
		"effects": [{"on": "spend", "op": "self_damage", "amount": 2},
			{"on": "spend", "op": "combo", "amount": 3}],
		"detail": "HPを払ってコンボを買う。出目も大きく、連鎖ビルドの主力になるが、払い続けると保たない。"},
	"nimble": {"name": "軽業", "faces": [1, 1, 2, 2, 3, 4],
		"color": Color("#9BC53D"), "short": "毒炎無効", "effect": "毒と炎上のダメージを受けない",
		"pierce": true,
		"detail": "毒と炎上でHPを失わなくなる。荒らされた盤面を平気で渡り歩けるが、無効になるのはダメージだけ — 凍結でマスが黙るのも、茨で足を取られるのも防げない。"},

	# --- 移動そのものを変える ---
	"reverse": {"name": "逆走", "faces": [-1, -2, -3, -4, -5, -6],
		"color": Color("#C25A2B"), "short": "逆向きに進む", "effect": "リングを逆向きに進む",
		"detail": "出目がすべて負の、唯一まっすぐ戻れるダイス。前進だけでは届かない手前のマスに止まれるので着地点の選択肢が別物になり、突進マスは弱まり慎重マスは強まる。"},
	"vault": {"name": "跳躍", "faces": [2, 2, 3, 3, 4, 4],
		"color": Color("#16A0C8"), "short": "+2歩", "effect": "使うと2歩多く進む",
		"effects": [{"on": "spend", "op": "step", "amount": 2}],
		"detail": "実質4から6の移動になる。通過型マスを多く踏みたいときに。"},
	"reset": {"name": "帰還", "faces": [2, 3, 4, 5, RESET_FACE, RESET_FACE],
		"color": Color("#C9A227"), "short": "帰の目でスタートへ", "effect": "「帰」の目が出るとスタート地点へ戻る",
		"detail": "6面のうち2面が「帰」。出ればどこにいてもスタート地点まで飛んで戻る、歩数を消費しない移動。危険な予告マスから逃げたり、盛った盤面を素通りしたくない時の緊急脱出に。"},
	"teleport": {"name": "テレポート", "faces": [1, 1, CORNER_TR, CORNER_TL, CORNER_BR, CORNER_BL],
		"color": Color("#5B3AA8"), "short": "四隅へ瞬間移動", "effect": "四隅のいずれかへ、現在地に関係なく瞬間移動",
		"detail": "6面のうち4面が盤の四隅（右上・左上・右下・左下）。出目どおりの角へ、今どこにいるかに関係なく飛ぶ — 歩数は消費しない。残り2面はただの1で、狙った角に賭けるか小さく刻むかの両極端なダイス。"},
	"tempo": {"name": "コンボ", "faces": [3, 3, 3, 4, 4, 4],
		"color": Color("#D6812B"), "short": "行動+1", "effect": "使うと行動+1（実質タダで使える）",
		"effects": [{"on": "spend", "op": "action", "amount": 1}],
		"detail": "使った瞬間に行動が1回戻るので、実質タダで手札を1枚消費できる。出目も3か4としっかり進むので、コンボを積みながら移動そのものにも困らない。"},
	"kodachi": {"name": "小太刀", "faces": [1, 1, 1, 2, 2, 2],
		"color": Color("#2E7BD6"), "short": "停止攻撃2倍", "effect": "停止型マスのダメージが2倍・出目は2以下",
		"mods": [{"op": "attack", "on": "stop", "x": 2}],
		"detail": "攻撃ダイスと同じ倍率を、1か2でしか出ない面と引き換えに持つ。遠くへは運べないが、出目2以下を条件にするマスを常に満たせる唯一のダイス。"},
	"iai": {"name": "居合", "faces": [0, 0, 1, 2, 3, 4],
		"color": Color("#B5302A"), "short": "0で踏み直し", "effect": "「0」の目は動かず、今いるマスの停止効果をもう一度",
		"detail": "6面のうち2面が0。動かないので歩数も距離も稼げないが、いま立っているマスの停止効果がもう一度発動する。重い停止型マスに乗ったまま、そこを撃ち続けるためのダイス。"},
	"wheel": {"name": "大車輪", "faces": [7, 7, 8, 8, 9, 9],
		"color": Color("#D6491F"), "short": "7〜9歩・HP-1", "effect": "使うとHP-1。7から9マス進む",
		"effects": [{"on": "spend", "op": "self_damage", "amount": 1}],
		"detail": "盤の半分以上を一息に走る。通過型マスを何枚も踏み抜けるが、振り回すたびにHPを1払う。止まりたいマスを狙うには大きすぎる、走るためだけのダイス。"},
	"guard_die": {"name": "防御", "faces": [1, 1, 2, 2, 3, 4],
		"color": Color("#2E7BD6"), "short": "出目ぶん盾", "effect": "使うと出目と同じ数だけ盾",
		"effects": [{"on": "spend", "op": "shield", "amount": 1, "scale": "roll"}],
		"detail": "出目が小さいほど得るものも小さい、正直な盾ダイス。大きい目を引いた時ほど嬉しい、数少ない「出目そのものが報酬」のダイス。"}
}

# Everything except the plain road and the two 標準-tier dice is on offer,
# so a run can actually reach any of the build concepts from any hero.
var die_reward_pool := [
	"heavydie", "precise", "gamble",
	"blade", "rush", "bulwark", "mend", "toxin", "dynamo", "tempest",
	"chainb", "delve", "augur", "charger", "ember", "rally", "devote", "nimble",
	"reverse", "vault", "reset", "tempo", "guard_die", "teleport",
	"kodachi", "iai", "wheel"
]

var reward_pool := [
	{"type": "slash"}, {"type": "fire"}, {"type": "guard"}, {"type": "heal"},
	{"type": "gale"}, {"type": "tailwind"}, {"type": "warp"},
	{"type": "assault"}, {"type": "caution"},
	{"type": "chain"}, {"type": "volley"}, {"type": "resonance"}, {"type": "spiral"},
	{"type": "battery"}, {"type": "aim"}, {"type": "lance"},
	{"type": "heavy"}, {"type": "bow"}, {"type": "trap"}, {"type": "snipe"},
	{"type": "fort"}, {"type": "thorns"}, {"type": "bastion"}, {"type": "reflect"},
	{"type": "venom"}, {"type": "rot"}, {"type": "blight"},
	{"type": "lastblade"}, {"type": "unbowed"}, {"type": "bloodpath"}, {"type": "deathline"},
	{"type": "pinpoint"}, {"type": "shuffle"}, {"type": "measure"}, {"type": "read"},
	{"type": "shieldbash"}, {"type": "rampart"}, {"type": "redoubt"},
	{"type": "plaguefang"}, {"type": "fester"}, {"type": "firststrike"},
	{"type": "focus"}, {"type": "spring"}, {"type": "shock"},
	{"type": "relay"}, {"type": "windfall"}, {"type": "one_more"}, {"type": "altar"}
]

var hero_defs := {
	"knight": {
		"name": "剣士",
		"art": "knight",
		"hp": 36,
		"hand": 3,
		"color": Color("#2E7BD6"),
		"desc": "狙って止まり、重く殴る。攻撃と防御、両極端な二本を持って始まる。",
		# The starting board is deliberately almost empty: the player should
		# be the author of the ring, not the editor of someone else's.
		"dice": ["normal", "normal", "blade", "guard_die"],
		# Steps 3, 7 and 11 of sixteen — the same even thirds of the lap the
		# twelve-square ring put them on.
		"tiles": [
			[3, 0, "heavy"], [4, 3, "fort"], [1, 4, "heavy"]
		]
	},
}

# 魔導士 and 盗賊 are shelved, not deleted — everything that reads heroes
# still walks hero_defs, so adding a row here is all it takes to bring one
# back in an update. Kept verbatim so their kits do not have to be
# reinvented later.
#
#	"mage": {
#		"name": "魔導士", "hp": 28, "hand": 3, "color": Color("#7C4DD6"),
#		"desc": "溜めて撃ち抜く。チャージの芯と、四隅へ飛ぶテレポートを持つ。",
#		"dice": ["normal", "normal", "charger", "teleport"],
#		"tiles": [[3, 0, "battery"], [4, 3, "aim"], [1, 4, "spring"]]
#	},
#	"rogue": {
#		"name": "盗賊", "hp": 22, "hand": 4, "color": Color("#5B8C2A"),
#		"desc": "手札4枚。HPは全キャラ最低だが、とにかく手数で押し切る。",
#		"dice": ["normal", "normal", "tempo", "nimble", "gamble"],
#		"tiles": [[3, 0, "slash"], [4, 3, "volley"], [1, 4, "chain"]]
#	}

func _ready() -> void:
	rng.randomize()
	_build_track_graph()
	_apply_content_scale()
	# DotGothic16 is the only font packed with the project, so it carries
	# both the display and the body role; the fix for the old build's
	# unreadable text is the size scale above, not a different face.
	var base_font: Font = load("res://assets/DotGothic16.ttf")
	var regular := FontVariation.new()
	regular.base_font = base_font
	regular.variation_embolden = 0.12
	ui_font = regular
	var heavy := FontVariation.new()
	heavy.base_font = base_font
	heavy.variation_embolden = 0.75
	ui_font_heavy = heavy
	_build_ui()
	_load_profile()
	_apply_locale()
	_apply_audio_settings()
	_layout_screen()
	_show_title()

# Pin the logical viewport to DESIGN_SIZE at runtime as well as in
# project.godot: the exported pack carries whatever the project file said
# when it was built, and the whole type scale depends on this being right.
func _apply_content_scale() -> void:
	var win := get_window()
	if win == null:
		return
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	win.content_scale_size = DESIGN_SIZE

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_screen()

func _is_landscape() -> bool:
	var vp := get_viewport_rect().size
	return vp.x > vp.y * 1.15

# --- construction ------------------------------------------------------

func _build_ui() -> void:
	backdrop_view = Backdrop.new()
	backdrop_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop_view)

	# The painted background, over the drawn one. Where a scene has art it
	# covers the table top completely; where it has none it is invisible
	# and the table top is what the player sees, exactly as before.
	bg_view = SpriteView.new()
	bg_view.cover = true
	bg_view.visible = false
	bg_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg_view)

	sfx = Sfx.new()
	add_child(sfx)

	zone_top = Control.new()
	zone_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(zone_top)
	_build_top_zone()

	zone_hero = Control.new()
	zone_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(zone_hero)
	_build_hero_zone()

	zone_enemy = Control.new()
	zone_enemy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(zone_enemy)
	_build_enemy_zone()

	zone_board = Control.new()
	zone_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(zone_board)
	_build_board_zone()

	zone_hand = Control.new()
	zone_hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(zone_hand)
	_build_hand_zone()

	zone_cmd = Control.new()
	zone_cmd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(zone_cmd)
	_build_command_zone()

	zone_log = Control.new()
	zone_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(zone_log)
	_build_log_zone()

	zone_map = Control.new()
	zone_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone_map.visible = false
	add_child(zone_map)
	_build_map_zone()

	zone_gallery = Control.new()
	zone_gallery.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone_gallery.visible = false
	add_child(zone_gallery)
	_build_gallery_zone()

	# A tap anywhere over the board and hand throws the dice. It sits above
	# the cells, so while the hand is unrolled the whole play area is one
	# big "roll" button, and it disappears the moment they are thrown.
	roll_catcher = Button.new()
	roll_catcher.flat = true
	roll_catcher.focus_mode = Control.FOCUS_NONE
	roll_catcher.visible = false
	roll_catcher.pressed.connect(Callable(self, "_on_roll_area_pressed"))
	add_child(roll_catcher)

	_build_overlay()
	_build_scene_layer()

func _build_top_zone() -> void:
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone_top.add_child(col)

	var track_row := HBoxContainer.new()
	track_row.add_theme_constant_override("separation", 8)
	track_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(track_row)

	run_label = _make_label(FS_SMALL, COL_TEXT_SOFT, HORIZONTAL_ALIGNMENT_LEFT, true)
	run_label.custom_minimum_size = Vector2(74, 0)
	run_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	track_row.add_child(run_label)

	run_track = RunTrack.new()
	run_track.custom_minimum_size = Vector2(0, 20)
	run_track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	run_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track_row.add_child(run_track)

	var stat_row := HBoxContainer.new()
	stat_row.add_theme_constant_override("separation", 8)
	stat_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stat_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(stat_row)

	hero_portrait = HeroPortrait.new()
	hero_portrait.custom_minimum_size = Vector2(34, 34)
	hero_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hero_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stat_row.add_child(hero_portrait)

	# One row, not two: the second row used to spill past the zone's fixed
	# height and slide under the enemy panel.
	var hp_row := stat_row
	hp_bar = GaugeBar.new()
	hp_bar.custom_minimum_size = Vector2(0, 22)
	hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_row.add_child(hp_bar)

	hp_label = _make_label(FS_NUM, COL_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, true)
	hp_label.custom_minimum_size = Vector2(84, 0)
	hp_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	hp_row.add_child(hp_label)

	# The chips get their own row rather than sharing the HP row. The status
	# strip now lives in the character column, which is narrow, and five
	# widgets abreast there ran off the end.
	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 8)
	chip_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(chip_row)

	# Shield is a chip, not a bar: it has no maximum, so a bar's tick marks
	# never meant anything. A number with a shield on it always does.
	shield_chip = PanelContainer.new()
	shield_chip.add_theme_stylebox_override("panel", _flat_style(COL_SHIELD, COL_INK, 2, 6, 4))
	shield_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shield_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip_row.add_child(shield_chip)
	var shield_inner := HBoxContainer.new()
	shield_inner.add_theme_constant_override("separation", 4)
	shield_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shield_chip.add_child(shield_inner)
	var shield_icon := IconGlyph.new()
	shield_icon.kind = "guard"
	shield_icon.glyph_color = Color("#FFF7E6")
	shield_icon.custom_minimum_size = Vector2(18, 18)
	shield_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	shield_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shield_inner.add_child(shield_icon)
	shield_label = _make_label(FS_BODY, Color("#FFF7E6"), HORIZONTAL_ALIGNMENT_LEFT, true)
	shield_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	shield_inner.add_child(shield_label)

	# Gold sits next to shield as another chip. It survives the whole run
	# rather than the turn, so unlike shield it is never dimmed to zero.
	gold_chip = PanelContainer.new()
	gold_chip.add_theme_stylebox_override("panel", _flat_style(COL_GOLD, COL_INK, 2, 6, 4))
	gold_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gold_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip_row.add_child(gold_chip)
	var gold_inner := HBoxContainer.new()
	gold_inner.add_theme_constant_override("separation", 4)
	gold_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gold_chip.add_child(gold_inner)
	var gold_icon := IconGlyph.new()
	gold_icon.kind = "pip_on"
	gold_icon.glyph_color = COL_INK
	gold_icon.outlined = false
	gold_icon.custom_minimum_size = Vector2(16, 16)
	gold_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gold_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gold_inner.add_child(gold_icon)
	gold_label = _make_label(FS_BODY, COL_INK, HORIZONTAL_ALIGNMENT_LEFT, true)
	gold_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	gold_inner.add_child(gold_label)

	var chip_spacer := Control.new()
	chip_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip_row.add_child(chip_spacer)

	var action_caption := _make_label(FS_SMALL, COL_TEXT_SOFT, HORIZONTAL_ALIGNMENT_RIGHT)
	action_caption.text = tr("行動")
	action_caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	action_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip_row.add_child(action_caption)

	action_pip_box = HBoxContainer.new()
	action_pip_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	action_pip_box.add_theme_constant_override("separation", 6)
	action_pip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip_row.add_child(action_pip_box)

# The player's own stage: their figure at the size the art is drawn for,
# with the status strip parked beneath it. This is where the hit animation
# plays, so it has to be big enough for that to read as an event rather
# than as a flicker — it is the single largest thing on the screen.
func _build_hero_zone() -> void:
	hero_panel = PanelContainer.new()
	hero_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	hero_panel.add_theme_stylebox_override("panel", _flat_style(COL_PANEL, COL_INK, 3, 6, 6))
	hero_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone_hero.add_child(hero_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero_panel.add_child(col)

	hero_sprite = SpriteView.new()
	hero_sprite.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_sprite.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(hero_sprite)

	hero_stage_name = _make_label(FS_SMALL, COL_TEXT_SOFT, HORIZONTAL_ALIGNMENT_CENTER, true)
	hero_stage_name.autowrap_mode = TextServer.AUTOWRAP_OFF
	col.add_child(hero_stage_name)

func _build_enemy_zone() -> void:
	enemy_panel = PanelContainer.new()
	enemy_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	enemy_panel.add_theme_stylebox_override("panel", _flat_style(COL_PANEL, COL_INK, 3, 8, 8))
	enemy_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone_enemy.add_child(enemy_panel)

	# Figure above, dossier below. The old side-by-side row capped the
	# figure at 96px, which is a token, not a character.
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 5)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	enemy_panel.add_child(col)

	enemy_sprite = SpriteView.new()
	enemy_sprite.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enemy_sprite.size_flags_vertical = Control.SIZE_EXPAND_FILL
	enemy_sprite.custom_minimum_size = Vector2(0, 120)
	enemy_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(enemy_sprite)

	enemy_name_label = _make_label(FS_HEAD, COL_TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	enemy_name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	col.add_child(enemy_name_label)

	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 8)
	hp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(hp_row)

	enemy_hp_bar = GaugeBar.new()
	enemy_hp_bar.fill_color = COL_ENEMY
	enemy_hp_bar.segments = 14
	enemy_hp_bar.custom_minimum_size = Vector2(0, 20)
	enemy_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enemy_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	enemy_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_row.add_child(enemy_hp_bar)

	enemy_hp_label = _make_label(FS_BODY, COL_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, true)
	enemy_hp_label.custom_minimum_size = Vector2(74, 0)
	enemy_hp_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	hp_row.add_child(enemy_hp_label)

	var intent_row := HBoxContainer.new()
	intent_row.add_theme_constant_override("separation", 8)
	intent_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(intent_row)

	# The intent badge: what is coming, as an icon and a number, big enough
	# to read across the room. The sentence next to it is secondary.
	intent_panel = PanelContainer.new()
	intent_panel.add_theme_stylebox_override("panel", _flat_style(COL_ENEMY, COL_INK, 3, 8, 3))
	intent_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	intent_row.add_child(intent_panel)
	var intent_inner := HBoxContainer.new()
	intent_inner.add_theme_constant_override("separation", 4)
	intent_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	intent_panel.add_child(intent_inner)
	intent_icon = IconGlyph.new()
	intent_icon.kind = "slash"
	intent_icon.glyph_color = Color("#FFF7E6")
	intent_icon.custom_minimum_size = Vector2(22, 22)
	intent_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	intent_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	intent_inner.add_child(intent_icon)
	intent_label = _make_label(FS_NUM, Color("#FFF7E6"), HORIZONTAL_ALIGNMENT_LEFT, true)
	intent_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	intent_inner.add_child(intent_label)

	# The sentence wraps under the badge instead of beside it: the column is
	# narrow now, and "行動を終えた時に光ったマスにいると当たる" beside a badge
	# was two words per line.
	intent_note = _make_label(FS_SMALL, COL_TEXT_SOFT, HORIZONTAL_ALIGNMENT_LEFT)
	intent_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(intent_note)

func _build_board_zone() -> void:
	board_view = BoardView.new()
	board_view.main = self
	board_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	board_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone_board.add_child(board_view)

	for i in range(BOARD_W * BOARD_H):
		var cell := Button.new()
		cell.focus_mode = Control.FOCUS_NONE
		_apply_font(cell)
		cell.pressed.connect(Callable(self, "_on_cell_pressed").bind(i))
		board_view.add_child(cell)
		cell_buttons.append(cell)

		var icon := IconGlyph.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 6
		icon.offset_top = 4
		icon.offset_right = -6
		icon.offset_bottom = -10
		cell.add_child(icon)
		cell_icons.append(icon)

		# "+3" — how many steps ahead this cell is right now. The old build
		# printed an absolute ring index, which never lined up with anything
		# the player was deciding; steps-ahead is exactly what a die rolls.
		var step_label := _make_label(FS_SMALL, Color("#FFF7E6"), HORIZONTAL_ALIGNMENT_CENTER, true)
		step_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		step_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
		step_label.offset_top = -17
		step_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		step_label.add_theme_constant_override("outline_size", 5)
		step_label.add_theme_color_override("font_outline_color", COL_INK)
		cell.add_child(step_label)
		cell_step_labels.append(step_label)

		# The effect number, on the tile. Previously the only way to learn
		# what a tile did was to tap it and read a sentence.
		var value_label := _make_label(FS_BODY, Color("#FFF7E6"), HORIZONTAL_ALIGNMENT_CENTER, true)
		value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		value_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		value_label.offset_top = -20
		value_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		value_label.add_theme_constant_override("outline_size", 5)
		value_label.add_theme_color_override("font_outline_color", COL_INK)
		cell.add_child(value_label)
		cell_value_labels.append(value_label)

		var danger_label := _make_label(FS_SMALL, Color("#FFF7E6"), HORIZONTAL_ALIGNMENT_CENTER, true)
		danger_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		danger_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		danger_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		danger_label.offset_top = -2
		danger_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		danger_label.add_theme_constant_override("outline_size", 5)
		danger_label.add_theme_color_override("font_outline_color", Color("#7A2A00"))
		cell.add_child(danger_label)
		cell_danger_labels.append(danger_label)

		var debuff_label := _make_label(FS_SMALL - 1, Color("#D9F27A"), HORIZONTAL_ALIGNMENT_CENTER, true)
		debuff_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		debuff_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
		debuff_label.offset_left = -6
		debuff_label.offset_top = -4
		debuff_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		debuff_label.add_theme_constant_override("outline_size", 5)
		debuff_label.add_theme_color_override("font_outline_color", COL_INK)
		cell.add_child(debuff_label)
		cell_debuff_labels.append(debuff_label)

	# The ring's middle is the one piece of free space on the board, so the
	# lookahead lives there — right next to the road it describes, instead
	# of floating above the board as an unlabelled row of chips.
	ribbon_box = VBoxContainer.new()
	ribbon_box.add_theme_constant_override("separation", 4)
	ribbon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_view.add_child(ribbon_box)

	# Neither combo nor charge gets a chip. Combo is spelled out by the
	# squares that read it, and charge now lives on the squares themselves,
	# so a single shared number would have been describing nothing.
	ribbon_caption = _make_label(FS_SMALL, COL_TEXT_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	ribbon_caption.text = tr("この先のマス　●通過 ■停止")
	ribbon_caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	ribbon_box.add_child(ribbon_caption)

	ribbon_row = HBoxContainer.new()
	ribbon_row.alignment = BoxContainer.ALIGNMENT_CENTER
	ribbon_row.add_theme_constant_override("separation", 3)
	ribbon_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ribbon_box.add_child(ribbon_row)

	roll_readout = _make_label(FS_NUM_BIG, COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER, true)
	roll_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	roll_readout.autowrap_mode = TextServer.AUTOWRAP_OFF
	roll_readout.add_theme_constant_override("outline_size", 6)
	roll_readout.add_theme_color_override("font_outline_color", COL_PANEL)
	ribbon_box.add_child(roll_readout)

	# Added last so it paints over the cell buttons (see BoardView.layer).
	token_view = BoardView.new()
	token_view.main = self
	token_view.layer = "token"
	token_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	token_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_view.add_child(token_view)

	banner = PanelContainer.new()
	banner.add_theme_stylebox_override("panel", _flat_style(COL_GOLD, COL_INK, 3, 12, 6))
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.visible = false
	zone_board.add_child(banner)
	banner_label = _make_label(FS_BODY, COL_INK, HORIZONTAL_ALIGNMENT_CENTER, true)
	banner_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	banner.add_child(banner_label)

func _build_hand_zone() -> void:
	# One sliding row rather than a fixed set of slots: the hand holds
	# however many dice were drawn, cards keep a constant width, and the
	# row scrolls when there are more than fit. The width is set so a
	# little under five cards are on screen — the part-visible fifth is
	# what tells the player the row keeps going.
	hand_scroll = ScrollContainer.new()
	hand_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	hand_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	hand_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hand_scroll.scroll_deadzone = 12
	hand_scroll.gui_input.connect(Callable(self, "_on_hand_scroll_input"))
	zone_hand.add_child(hand_scroll)

	hand_row = HBoxContainer.new()
	hand_row.add_theme_constant_override("separation", HAND_GAP)
	hand_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hand_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hand_scroll.add_child(hand_row)

	# Dragging the row works, but only a real finger can do it. These
	# appear only when the hand is longer than the screen, so a card can
	# always be reached by tapping as well.
	hand_left_button = _make_hand_arrow("<", -1)
	zone_hand.add_child(hand_left_button)
	hand_right_button = _make_hand_arrow(">", 1)
	zone_hand.add_child(hand_right_button)

	# Slots are built by _refresh_hand once the hand is known.

func _build_command_zone() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 8)
	zone_cmd.add_child(row)

	reroll_button = Button.new()
	reroll_button.text = tr("振り直す")
	reroll_button.focus_mode = Control.FOCUS_NONE
	reroll_button.custom_minimum_size = Vector2(132, 0)
	reroll_button.add_theme_font_size_override("font_size", FS_SMALL)
	_style_button(reroll_button, COL_SHIELD, COL_INK)
	reroll_button.pressed.connect(Callable(self, "_on_reroll_pressed"))
	row.add_child(reroll_button)

	end_turn_button = Button.new()
	end_turn_button.text = tr("行動終了")
	end_turn_button.focus_mode = Control.FOCUS_NONE
	end_turn_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	end_turn_button.add_theme_font_size_override("font_size", FS_BODY)
	_style_button(end_turn_button, COL_GOLD, COL_INK)
	end_turn_button.add_theme_color_override("font_color", COL_INK)
	end_turn_button.pressed.connect(Callable(self, "_on_end_turn_pressed"))
	row.add_child(end_turn_button)

	catalog_button = Button.new()
	catalog_button.text = tr("図鑑")
	catalog_button.focus_mode = Control.FOCUS_NONE
	catalog_button.custom_minimum_size = Vector2(74, 0)
	catalog_button.add_theme_font_size_override("font_size", FS_SMALL)
	_style_button(catalog_button, COL_PANEL_SUNK, COL_INK)
	catalog_button.add_theme_color_override("font_color", COL_INK)
	catalog_button.pressed.connect(Callable(self, "_show_catalog"))
	row.add_child(catalog_button)

	# 最初から used to sit next to 行動終了 with no confirmation, one slip
	# away from throwing a run out. It lives in the 図鑑 sheet now.
	restart_button = Button.new()
	restart_button.visible = false

func _build_log_zone() -> void:
	log_label = _make_label(FS_SMALL, COL_TEXT_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	log_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	log_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	log_label.clip_text = true
	log_label.max_lines_visible = 2
	zone_log.add_child(log_label)

func _build_overlay() -> void:
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	add_child(overlay)

	var shade := ColorRect.new()
	shade.color = Color(0.20, 0.15, 0.10, 0.30)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(shade)

	# A CenterContainer sizes the card from its content instead of the card
	# being measured by hand — hand-measuring a panel whose labels wrap is
	# how it ended up filling the whole screen.
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)

	var card := PanelContainer.new()
	card.name = "Card"
	card.add_theme_stylebox_override("panel", _flat_style(COL_PANEL, COL_INK, 3, 16, 16))
	center.add_child(card)

	overlay_card = VBoxContainer.new()
	overlay_card.add_theme_constant_override("separation", 10)
	card.add_child(overlay_card)

	overlay_title = _make_label(FS_TITLE, COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER, true)
	overlay_card.add_child(overlay_title)

	overlay_body = _make_label(FS_BODY, COL_TEXT_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	overlay_card.add_child(overlay_body)

	# An illustration slot on the card itself, for the screens that are a
	# moment rather than a menu — events, mostly. Hidden unless a caller
	# asks for it, so every other overlay looks exactly as it did.
	overlay_art = SpriteView.new()
	overlay_art.visible = false
	overlay_art.custom_minimum_size = Vector2(0, 180)
	overlay_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_card.add_child(overlay_art)

	overlay_list = VBoxContainer.new()
	overlay_list.add_theme_constant_override("separation", 10)
	overlay_card.add_child(overlay_list)

# The scene layer sits above everything, including the overlay card, so a
# resolution scene can play *into* the result screen rather than beside it.
func _build_scene_layer() -> void:
	scene_layer = Control.new()
	scene_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	scene_layer.visible = false
	scene_layer.z_index = 60
	add_child(scene_layer)

	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.03, 0.04, 1.0)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene_layer.add_child(shade)

	scene_sprite = SpriteView.new()
	scene_sprite.set_anchors_preset(Control.PRESET_FULL_RECT)
	scene_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene_layer.add_child(scene_sprite)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	scene_layer.add_child(col)

	scene_caption = _make_label(FS_HEAD, COL_TEXT_ON_DARK, HORIZONTAL_ALIGNMENT_CENTER, true)
	scene_caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	col.add_child(scene_caption)

	scene_hint = _make_label(FS_SMALL, COL_TEXT_ON_DARK, HORIZONTAL_ALIGNMENT_CENTER)
	scene_hint.text = tr("画面をタップで進む")
	scene_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	col.add_child(scene_hint)

	# A transparent button over the whole layer, so anywhere is "continue".
	var catcher := Button.new()
	catcher.flat = true
	catcher.focus_mode = Control.FOCUS_NONE
	catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.pressed.connect(Callable(self, "_dismiss_scene"))
	scene_layer.add_child(catcher)

# The recollection room. A grid of every scene the game can show, with the
# ones this profile has not reached still locked — so the count of empty
# frames is the "how much is left" the player is playing toward.
func _build_gallery_zone() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", _flat_style(COL_PANEL, COL_INK, 3, 10, 8))
	zone_gallery.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)

	gallery_title = _make_label(FS_HEAD, COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER, true)
	gallery_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	col.add_child(gallery_title)

	gallery_scroll = ScrollContainer.new()
	gallery_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	gallery_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(gallery_scroll)

	gallery_grid = GridContainer.new()
	gallery_grid.columns = 4
	gallery_grid.add_theme_constant_override("h_separation", 8)
	gallery_grid.add_theme_constant_override("v_separation", 8)
	gallery_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gallery_scroll.add_child(gallery_grid)

	var close_button := Button.new()
	close_button.text = tr("閉じる")
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(0, 42)
	close_button.add_theme_font_size_override("font_size", FS_BODY)
	_style_button(close_button, COL_GOLD, COL_INK)
	close_button.add_theme_color_override("font_color", COL_INK)
	close_button.pressed.connect(Callable(self, "_close_gallery"))
	col.add_child(close_button)

# --- layout ------------------------------------------------------------

# Zone heights are fixed and the board takes the slack. Nothing that
# appears or disappears mid-turn (a log line, a badge, a chip) can move
# another zone, which is what made the old single-column build jump around
# by up to a third of a screen between turns.
func _layout_screen() -> void:
	var vp := get_viewport_rect().size
	if backdrop_view != null:
		backdrop_view.position = Vector2.ZERO
		backdrop_view.size = vp
		backdrop_view.queue_redraw()
	if bg_view != null:
		bg_view.position = Vector2.ZERO
		bg_view.size = vp
		bg_view.queue_redraw()
	if zone_top == null:
		return

	var margin := 10.0
	var gap := 8.0
	# The map and the gallery are their own screens rather than panels
	# sharing space with the board, so they take the whole frame.
	var full := Rect2(margin, margin, vp.x - margin * 2.0, vp.y - margin * 2.0)
	_place(zone_map, full)
	_place(zone_gallery, full)
	if _is_landscape():
		# Three columns. The two outer ones are the characters — this is a
		# game whose art is the point, so the art gets a little over half
		# the frame and the board is sized to fit what is left, not the
		# other way round. The centre column stacks board, hand, buttons,
		# log at fixed heights so nothing that appears mid-turn can shift
		# anything else.
		var body_h: float = vp.y - margin * 2.0
		var hero_w: float = clamp(vp.x * 0.28, 220.0, 320.0)
		var enemy_w: float = clamp(vp.x * 0.245, 200.0, 288.0)
		var mid_x: float = margin + hero_w + gap
		var mid_w: float = vp.x - margin - enemy_w - gap - mid_x

		# Left: the player's figure, with their own status strip beneath it.
		var top_h := 100.0
		_place(zone_hero, Rect2(margin, margin, hero_w, body_h - top_h - gap))
		_place(zone_top, Rect2(margin, margin + body_h - top_h, hero_w, top_h))

		# Right: the enemy's figure and dossier, one full-height column.
		_place(zone_enemy, Rect2(vp.x - margin - enemy_w, margin, enemy_w, body_h))

		# Centre: the game.
		var cmd_h := 42.0
		var log_h := 32.0
		var hand_h: float = clamp(body_h * 0.21, 104.0, 136.0)
		var board_h: float = max(body_h - hand_h - cmd_h - log_h - gap * 3.0, 180.0)
		var y: float = margin
		_place(zone_board, Rect2(mid_x, y, mid_w, board_h))
		y += board_h + gap
		_place(zone_hand, Rect2(mid_x, y, mid_w, hand_h))
		y += hand_h + gap
		_place(zone_cmd, Rect2(mid_x, y, mid_w, cmd_h))
		y += cmd_h + gap
		_place(zone_log, Rect2(mid_x, y, mid_w, log_h))
	else:
		# Portrait is no longer the shipping shape, but it still has to be
		# playable in a window someone drags narrow. The two figures share
		# one band under the status strip instead of taking columns.
		var width: float = vp.x - margin * 2.0
		var top_h := 74.0
		var stage_h: float = clamp(vp.y * 0.24, 150.0, 220.0)
		var cmd_h := 46.0
		var log_h := 34.0
		var hand_h: float = clamp(vp.y * 0.19, 128.0, 168.0)
		var used: float = top_h + stage_h + hand_h + cmd_h + log_h + gap * 5.0 + margin * 2.0
		var board_h: float = max(vp.y - used, 200.0)
		var y: float = margin
		_place(zone_top, Rect2(margin, y, width, top_h))
		y += top_h + gap
		var hero_w: float = (width - gap) * 0.42
		_place(zone_hero, Rect2(margin, y, hero_w, stage_h))
		_place(zone_enemy, Rect2(margin + hero_w + gap, y, width - hero_w - gap, stage_h))
		y += stage_h + gap
		_place(zone_board, Rect2(margin, y, width, board_h))
		y += board_h + gap
		_place(zone_hand, Rect2(margin, y, width, hand_h))
		y += hand_h + gap
		_place(zone_cmd, Rect2(margin, y, width, cmd_h))
		y += cmd_h + gap
		_place(zone_log, Rect2(margin, y, width, log_h))

	if roll_catcher != null and zone_board != null and zone_hand != null:
		var top: float = min(zone_board.position.y, zone_hand.position.y)
		var bottom: float = max(zone_board.position.y + zone_board.size.y, zone_hand.position.y + zone_hand.size.y)
		var left: float = min(zone_board.position.x, zone_hand.position.x)
		var right: float = max(zone_board.position.x + zone_board.size.x, zone_hand.position.x + zone_hand.size.x)
		roll_catcher.position = Vector2(left, top)
		roll_catcher.size = Vector2(right - left, bottom - top)
	if overlay != null:
		overlay.size = vp
		_layout_overlay()
	if scene_layer != null:
		scene_layer.position = Vector2.ZERO
		scene_layer.size = vp
	if gallery_grid != null:
		gallery_grid.columns = clampi(int((vp.x - 60.0) / 168.0), 2, 6)
	_layout_board_buttons()

func _place(node: Control, rect: Rect2) -> void:
	if node == null:
		return
	node.position = rect.position
	node.size = rect.size

func _layout_overlay() -> void:
	var card := overlay.get_node_or_null("Center/Card") as Control
	if card == null:
		return
	var vp := get_viewport_rect().size
	var card_w: float = min(vp.x - 28.0, 420.0)
	card.custom_minimum_size = Vector2(card_w, 0)
	# Wrapping labels need a width to wrap against before they can report a
	# height, so every wrapping child is told the card's inner width.
	var inner: float = card_w - 38.0
	for node in [overlay_title, overlay_body, overlay_list]:
		if node != null:
			node.custom_minimum_size = Vector2(inner, node.custom_minimum_size.y)

func _layout_board_buttons() -> void:
	if board_view == null or cell_buttons.is_empty():
		return
	var token := _board_token_size()
	for y in range(BOARD_H):
		for x in range(BOARD_W):
			var index := _idx(x, y)
			var button: Button = cell_buttons[index]
			var center := _board_cell_center(Vector2i(x, y))
			# Pass tiles are small round beads threaded onto the road; stop
			# tiles are full-size plates raised off it. Corner radius alone
			# was too quiet a difference to carry a rule this important.
			var span: float = token if _is_stop_cell(Vector2i(x, y)) else token * 0.84
			button.position = center - Vector2(span, span) * 0.5
			button.size = Vector2(span, span)
	_layout_ribbon()
	if token_view != null:
		token_view.queue_redraw()
	if banner != null and zone_board != null:
		var wanted: Vector2 = banner.get_combined_minimum_size()
		banner.size = wanted
		banner.position = ((zone_board.size - wanted) * 0.5).floor()
	board_view.queue_redraw()

func _layout_ribbon() -> void:
	if ribbon_box == null or board_view == null:
		return
	var wanted: Vector2 = ribbon_box.get_combined_minimum_size()
	ribbon_box.size = wanted
	var step := _board_spacing()
	var center := _board_origin() + Vector2(float(BOARD_W - 1), float(BOARD_H - 1)) * 0.5 * step
	ribbon_box.position = (center - wanted * 0.5).floor()

func _is_stop_cell(pos: Vector2i) -> bool:
	if not ring_index_map.has(pos):
		return false
	# The first layout pass runs from _ready, before any board exists.
	if permanent_board.size() <= pos.y or (permanent_board[pos.y] as Array).size() <= pos.x:
		return false
	return str(tile_defs[str(permanent_board[pos.y][pos.x])]["trigger"]) != "pass"

func _board_token_size() -> float:
	var step := _board_spacing()
	# Never smaller than a comfortable touch target.
	return clamp(step * 0.58, 46.0, 74.0)

func _board_spacing() -> float:
	if board_view == null:
		return 64.0
	var available := board_view.size - Vector2(72, 72)
	var raw: float = min(available.x / float(BOARD_W - 1), available.y / float(BOARD_H - 1))
	return clamp(raw, 52.0, 132.0)

func _board_origin() -> Vector2:
	var step := _board_spacing()
	var board_size := Vector2(step * float(BOARD_W - 1), step * float(BOARD_H - 1))
	return ((board_view.size - board_size) * 0.5).floor()

func _board_cell_center(pos: Vector2i) -> Vector2:
	var origin := _board_origin()
	var step := _board_spacing()
	return origin + Vector2(float(pos.x) * step, float(pos.y) * step)

# --- small builders ----------------------------------------------------

func _make_label(font_size: int, color: Color, align: HorizontalAlignment, heavy: bool = false) -> Label:
	var label := Label.new()
	label.horizontal_alignment = align
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_font(label, heavy)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _apply_font(control: Control, heavy: bool = false) -> void:
	var font: Font = ui_font_heavy if heavy else ui_font
	if font != null:
		control.add_theme_font_override("font", font)

func _flat_style(bg: Color, border: Color, border_width: int, margin_x: float, margin_y: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.border_width_left = border_width
	box.border_width_top = border_width
	box.border_width_right = border_width
	box.border_width_bottom = border_width
	box.corner_radius_top_left = 4
	box.corner_radius_top_right = 4
	box.corner_radius_bottom_left = 4
	box.corner_radius_bottom_right = 4
	box.content_margin_left = margin_x
	box.content_margin_right = margin_x
	box.content_margin_top = margin_y
	box.content_margin_bottom = margin_y
	box.shadow_color = Color(0.16, 0.12, 0.08, 0.18)
	box.shadow_size = 0
	box.shadow_offset = Vector2(0, 3)
	return box

# Buttons get a printed-cardboard treatment: flat fill, thick ink edge, and
# a press that pushes the face down instead of only darkening it.
func _style_button(button: Button, color: Color, border: Color, border_width: int = 3) -> void:
	_apply_font(button, true)
	var normal := _flat_style(color, border, border_width, 8, 6)
	normal.shadow_size = 3
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = color.lightened(0.10)
	button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate()
	pressed.bg_color = color.darkened(0.10)
	pressed.shadow_size = 0
	pressed.content_margin_top = normal.content_margin_top + 2.0
	pressed.content_margin_bottom = max(0.0, normal.content_margin_bottom - 2.0)
	button.add_theme_stylebox_override("pressed", pressed)
	var disabled := normal.duplicate()
	disabled.bg_color = color.lerp(COL_PANEL_SUNK, 0.65)
	disabled.border_color = border.lerp(COL_PANEL_SUNK, 0.45)
	disabled.shadow_size = 0
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", COL_TEXT_ON_DARK)
	button.add_theme_color_override("font_hover_color", COL_TEXT_ON_DARK)
	button.add_theme_color_override("font_pressed_color", COL_TEXT_ON_DARK)
	button.add_theme_color_override("font_disabled_color", Color(COL_INK.r, COL_INK.g, COL_INK.b, 0.45))

# Cells the living enemies have telegraphed this turn. Cached so BoardView
# can pulse them every frame without recomputing the union each time.
var danger_cells: Dictionary = {}
var cell_info_timer := 0.0
var log_hold := ""

# The considered die, resolved once per board refresh rather than per cell.
# Empty when nothing is being previewed, which is what makes every readout
# fall back to the square's plain face value.
var _readout_die: Dictionary = {}
var _readout_route: Array[Vector2i] = []
var _readout_crossed := 0

func _process(delta: float) -> void:
	if cell_info_timer > 0.0:
		cell_info_timer -= delta
		if cell_info_timer <= 0.0 and log_label != null:
			log_label.text = log_hold

func _refresh_all() -> void:
	_refresh_top()
	_refresh_hero_stage()
	_refresh_enemy()
	_refresh_board()
	_refresh_hand()
	_refresh_command()
	_refresh_map()
	_refresh_backdrop()
	if zone_gallery != null:
		zone_gallery.visible = state == "gallery"

# Which background this screen is standing in. Returned as a fallback chain
# so a project with one painting still looks intentional: bg/default alone
# covers every screen, and each id added after that carves a place out of
# it. 強敵 and ボス borrow the ordinary battle background until they are
# given their own.
func _backdrop_chain() -> Array:
	match state:
		"title", "game_over", "victory":
			return ["title", "default"]
		"map":
			return ["map", "default"]
		"gallery":
			return ["gallery", "map", "default"]
	var node = _map_node_at(map_row, map_col)
	var kind: String = "battle" if node == null else str(node.get("type", "battle"))
	if kind == "elite" or kind == "boss":
		return [kind, "battle", "default"]
	return [kind, "default"]

# Only swap the painting when the chain actually changes — _refresh_all
# runs many times a turn, and re-playing a clip every time would pin an
# animated background to its first frame forever.
var _bg_chain_key := ""

func _refresh_backdrop() -> void:
	if bg_view == null:
		return
	var chain := _backdrop_chain()
	var key := "|".join(PackedStringArray(chain))
	if key == _bg_chain_key:
		return
	_bg_chain_key = key
	# The chain is walked as states of one actor, so every background lives
	# in art/bg/scene_<id>.png and there is no second naming rule to learn.
	_show_art(bg_view, "bg", "scene", chain)

# The screens that show the two figures. The map, the gallery and the title
# each take the whole frame instead.
func _in_battle_view() -> bool:
	return state != "title" and state != "map" and state != "node_event" \
		and state != "gallery" and state != "settings"

func _set_log(text: String) -> void:
	log_hold = text
	cell_info_timer = 0.0
	if log_label != null:
		log_label.text = text

func _refresh_top() -> void:
	var in_run: bool = state != "title" and state != "gallery"
	zone_top.visible = in_run
	if not in_run:
		return
	run_label.text = tr("第%d戦") % max(encounter, 1)
	run_track.total = MAP_ROWS
	run_track.current = encounter
	run_track.queue_redraw()

	hero_portrait.hero_key = hero_key
	hero_portrait.face_color = hero_token_color
	hero_portrait.hp_ratio = float(player_hp) / float(max(player_max_hp, 1))

	hp_bar.max_value = player_max_hp
	hp_bar.segments = 12
	hp_bar.value = max(player_hp, 0)
	hp_bar.fill_color = COL_HP if float(player_hp) / float(max(player_max_hp, 1)) > 0.35 else COL_HP_LOW
	_animate_gauge(hp_bar)
	hp_label.text = "%d/%d" % [max(player_hp, 0), player_max_hp]
	hp_label.add_theme_color_override("font_color", COL_TEXT if float(player_hp) / float(max(player_max_hp, 1)) > 0.35 else COL_HP_LOW)

	shield_label.text = str(player_shield)
	shield_chip.modulate = Color(1, 1, 1, 1.0 if player_shield > 0 else 0.45)

	gold_label.text = str(gold)
	gold_chip.visible = state != "title"

	_clear_children(action_pip_box)
	for i in range(actions_per_turn):
		var pip := IconGlyph.new()
		pip.kind = "pip_on" if i < actions_left else "pip_off"
		pip.glyph_color = COL_GOLD if i < actions_left else COL_TEXT_SOFT
		pip.outline_color = COL_INK
		pip.outlined = i < actions_left
		pip.custom_minimum_size = Vector2(20, 20)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		action_pip_box.add_child(pip)

func _animate_gauge(bar: GaugeBar) -> void:
	# The bar's trailing value chases the real one, so a hit reads as a
	# drain rather than a jump — but the real value is already there.
	var target := float(bar.value)
	if is_equal_approx(bar.display_value, target):
		return
	var tween := create_tween()
	tween.tween_property(bar, "display_value", target, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# While a hit clip is playing, the idle refresh must keep its hands off the
# sprite — a _refresh_all landing mid-animation would otherwise snap the
# figure back to idle a frame after it was struck.
var _hero_clip_lock := false
var _enemy_clip_lock := false

func _refresh_hero_stage() -> void:
	if zone_hero == null:
		return
	zone_hero.visible = _in_battle_view()
	if not zone_hero.visible or _hero_clip_lock:
		return
	hero_stage_name.text = hero_name
	# A badly hurt character stands differently. If only an idle has been
	# drawn, "down" falls through to it and nothing looks broken.
	var hurt: bool = float(player_hp) / float(max(player_max_hp, 1)) <= 0.35
	_show_art(hero_sprite, "stage", _hero_art_id(),
		["down", "idle"] if hurt else ["idle"])

func _refresh_enemy() -> void:
	var show: bool = state != "title" and not enemies.is_empty()
	zone_enemy.visible = _in_battle_view()
	enemy_panel.modulate = Color(1, 1, 1, 1.0 if show else 0.0)
	if not show:
		return
	var enemy: Dictionary = enemies[0]
	if not _enemy_clip_lock:
		_show_art(enemy_sprite, "stage", _enemy_art_id(), ["idle"])
	enemy_name_label.text = "%s%s" % [str(enemy["type"]), "（ボス）" if str(enemy["type"]) == "ボス" else ""]
	enemy_hp_bar.max_value = int(enemy["max_hp"])
	enemy_hp_bar.value = max(int(enemy["hp"]), 0)
	_animate_gauge(enemy_hp_bar)
	enemy_hp_label.text = "%d/%d" % [max(int(enemy["hp"]), 0), int(enemy["max_hp"])]
	if int(enemy.get("poison", 0)) > 0:
		enemy_hp_label.text += "　毒%d" % int(enemy["poison"])

	var guaranteed: bool = str(enemy.get("attack_kind", "cell")) == "guaranteed"
	intent_icon.set_kind("slash" if guaranteed else "focus")
	intent_label.text = str(int(enemy["damage"]))
	intent_panel.add_theme_stylebox_override("panel", _flat_style(COL_ENEMY if guaranteed else COL_DANGER, COL_INK, 3, 8, 3))
	var note_lines := []
	note_lines.append(tr("毎ターン必ず当たる") if guaranteed else "行動を終えた時に光ったマスにいると当たる")
	var kind := str(enemy.get("debuff", ""))
	if kind != "" and temp_defs.has(kind):
		note_lines.append("%s をマスにかける（%s）" % [
			_t(temp_defs[kind]["name"]), _t(temp_defs[kind]["effect"])])
	var traits := _enemy_trait_text(enemy)
	if traits != "":
		note_lines.append(traits)
	intent_note.text = "\n".join(note_lines)

func _refresh_command() -> void:
	var playing: bool = state == "player"
	if roll_catcher != null:
		roll_catcher.visible = playing and not dice_rolled and not hand.is_empty()
	zone_cmd.visible = state != "title" and state != "map" and state != "node_event"
	zone_hand.visible = state == "player" or state == "moving" or state == "enemy"
	end_turn_button.visible = playing or state == "moving" or state == "enemy"
	end_turn_button.disabled = not playing
	catalog_button.visible = state != "title"
	reroll_button.visible = playing or state == "moving" or state == "enemy"
	reroll_button.disabled = not (playing and dice_rolled and rerolls_left > 0 and not hand.is_empty())
	reroll_button.text = tr("振り直す %d") % rerolls_left

func _refresh_board() -> void:
	_rebuild_preview_path()
	_rebuild_preview_route()
	_layout_board_buttons()
	danger_cells = _telegraphed_cells()
	_readout_die = _previewed_die()
	_readout_route = preview_route
	_readout_crossed = _readout_route.size() if _preview_walks() else 0
	var placing: bool = state == "reward_place"
	for y in range(BOARD_H):
		for x in range(BOARD_W):
			var idx := _idx(x, y)
			var button: Button = cell_buttons[idx]
			var icon: IconGlyph = cell_icons[idx]
			var step_label: Label = cell_step_labels[idx]
			var value_label: Label = cell_value_labels[idx]
			var danger_label: Label = cell_danger_labels[idx]
			var debuff_label: Label = cell_debuff_labels[idx]
			var pos := Vector2i(x, y)

			if not ring_index_map.has(pos):
				button.visible = false
				button.disabled = true
				continue
			button.visible = state != "title" and state != "map" and state != "node_event"

			var perm_type: String = str(permanent_board[pos.y][pos.x])
			var temp_type: String = str(temp_board[pos.y][pos.x])
			var tile: Dictionary = tile_defs[perm_type]
			var color: Color = tile["color"]
			var icon_kind: String = str(tile["icon"])
			# Held in a variable because the placement preview replaces it:
			# the square has to take on the *offered* tile's shape, or a
			# stop-type tile previews as the round road it is replacing.
			var trigger: String = str(tile["trigger"])
			var value_text := ""
			var value_color := Color("#FFF7E6")

			var readout := _tile_readout(tile, pos)
			value_text = str(readout["text"])
			var boosted: bool = bool(readout["scaled"])
			var blocked: bool = bool(readout.get("blocked", false))
			if temp_type == "block":
				color = temp_defs["block"]["color"]
				icon_kind = ""
				value_text = ""

			var is_player_cell := pos == player_pos and state != "reward_place"
			var is_start := pos == _start_pos()
			if is_start and perm_type == "empty":
				icon_kind = "flag_start"

			var border_color := COL_INK
			var border_width := 3
			var ahead := _steps_ahead(pos)
			step_label.text = ""
			danger_label.text = ""

			var considering: bool = not _readout_die.is_empty()
			var on_route: bool = considering and _readout_route.has(pos)
			var is_landing: bool = on_route and pos == _readout_route[_readout_route.size() - 1]

			if state == "player" and ahead > 0:
				step_label.text = "+%d" % ahead
			if danger_cells.has(pos):
				border_color = COL_DANGER
				border_width = 5
				danger_label.text = "▲%d" % _telegraph_damage()
			if route_path.has(pos) and state == "moving":
				border_color = COL_ROUTE
				border_width = 5
			# The considered die's route, and the square it would stop on. The
			# landing square wins over the danger border on purpose: a lit
			# danger cell that is also where this die puts you is exactly the
			# thing the first tap exists to show, and it keeps its ▲ label.
			if on_route:
				border_color = COL_ROUTE
				border_width = 4
			if is_landing:
				border_color = COL_GOLD
				border_width = 6
			if is_player_cell and not on_route:
				border_color = COL_GOLD
				border_width = 5

			button.disabled = state == "moving" or state == "title" or state == "reward_select"
			var dim := false
			if placing:
				if _can_place_reward(pos):
					border_color = COL_NEXT
					border_width = 4
					if pos == preview_place_pos:
						# The square wears the tile it is being offered —
						# colour, icon, shape and number — so the preview is
						# the thing itself rather than a question mark.
						var pending: Dictionary = tile_defs[pending_reward_type]
						color = pending["color"]
						icon_kind = str(pending["icon"])
						value_text = str(_tile_readout(pending)["text"])
						trigger = str(pending["trigger"])
						border_color = COL_GOLD
						border_width = 6
				else:
					button.disabled = true
					dim = true
			elif state == "player" and ahead <= 0 and not is_player_cell and not on_route:
				# Out of reach this turn: still legible, just quieter. A
				# square the considered die runs over is never quiet, even
				# when it sits behind the piece — which is where 逆走 puts
				# its whole route.
				dim = true

			icon.set_kind(icon_kind)
			var plain: bool = perm_type == "empty" and temp_type == "none"
			icon.glyph_color = Color(1.0, 0.97, 0.90, 0.45 if plain else 1.0)
			icon.outline_color = Color(COL_INK.r, COL_INK.g, COL_INK.b, 0.45 if plain else 1.0)
			value_label.text = value_text
			if boosted:
				value_color = COL_GOLD
			if blocked:
				value_color = Color("#FFC9BE")
			value_label.add_theme_color_override("font_color", Color(value_color.r, value_color.g, value_color.b, 0.55 if plain else 1.0))
			button.tooltip_text = _cell_tooltip(pos, perm_type, temp_type)
			# A fouled tile darkens and takes a mark, but keeps its own
			# shape and icon: the board a player built stays legible under
			# whatever the enemy throws at it.
			debuff_label.text = ""
			var cell_debuff := _debuff_at(pos)
			if not cell_debuff.is_empty():
				# Pulled toward the debuff's own colour rather than one
				# shared murk, so four kinds of trouble are four colours.
				color = color.lerp(Color(cell_debuff["color"]).darkened(0.25), 0.42)
				debuff_label.text = str(cell_debuff["mark"])
				debuff_label.add_theme_color_override(
					"font_color", Color(cell_debuff["color"]).lightened(0.45))
			_apply_cell_style(button, color, border_color, border_width, dim, trigger)
	_refresh_ribbon()
	board_view.queue_redraw()

# The number printed on a square, derived from its effects rather than a
# separate hand-maintained field, so a tile can never show one thing and do
# another. A scaled effect prints what it would pay *right now* and is
# highlighted, because that value moves as the run's counters move.
const OP_GLYPHS := {
	"attack": "", "shield": "+", "heal": "+", "poison": "毒",
	"charge": "電", "charge_all": "電", "combo": "連", "step": "歩", "draw": "引",
	"reroll": "振", "action": "行", "self_damage": "-",
}

# While a die is being considered, the squares it will actually run over
# print what *that die* would pay there — its multipliers applied, its roll
# and its combo point counted, and its conditions already answered. Squares
# the die cannot reach keep printing their plain face value.
func _tile_readout(tile: Dictionary, pos: Vector2i = Vector2i(-1, -1)) -> Dictionary:
	# Charge is a property of the square, so a readout has to ask about the
	# square it is drawing rather than about a single shared counter.
	if pos.x >= 0:
		charge_cell = pos
	# Frozen squares print nothing, whether or not a die is being weighed:
	# the number they used to advertise is exactly what they will not pay.
	if pos.x >= 0 and _debuff_nullifies(pos):
		return {"text": "×", "scaled": false, "blocked": true}
	var die := _readout_die
	var on_route: bool = not die.is_empty() and pos.x >= 0 and _readout_route.has(pos)
	var lands: bool = on_route and pos == _readout_route[_readout_route.size() - 1]
	# Totals per operation, not the single biggest effect. 大斬撃 is written
	# as two attack rows ("7" and "+the roll") and the old readout printed
	# whichever row was larger, so a square that deals 7+roll advertised 7.
	# A preview that undercounts is the exact failure this readout exists to
	# prevent, so same-op rows are summed the way the engine sums them.
	var totals := {}
	var scaled_ops := {}
	var order := []
	var blocked := false
	# A square's own effects run in written order, and 蓄積砲台 loads itself
	# on the way in before firing on the stop. Reading its charge once at the
	# top would under-report the shot by exactly that loading, so the walk
	# through the rows carries the loading with it.
	var charge_delta := 0
	for raw in tile.get("effects", []):
		var eff: Dictionary = raw
		var op := str(eff["op"])
		if not OP_GLYPHS.has(op) or op == "self_damage":
			continue
		var timing := str(eff.get("on", "stop"))
		if on_route:
			# Only the timings this die will actually trigger here: a square
			# it runs across never fires its stop half.
			if timing == "stop" and not lands:
				continue
			if not _projected_cond_ok(eff.get("cond", {}), die, _readout_crossed):
				blocked = true
				continue
		var amount := int(eff.get("amount", 0))
		var scale := str(eff.get("scale", ""))
		if scale != "":
			var factor := _scale_value(scale)
			if on_route:
				factor = _projected_counter(scale, die, _readout_crossed)
			if scale == "charge":
				factor += charge_delta
			amount *= factor
		var add_scale := str(eff.get("add_scale", ""))
		if add_scale != "":
			var counter := _scale_value(add_scale)
			if on_route:
				counter = _projected_counter(add_scale, die, _readout_crossed)
			amount += counter * int(eff.get("add_scale_sign", 1))
		if on_route:
			amount *= _mod_multiplier(die, op, timing)
		# 装甲 comes off every individual hit, so a printed attack number
		# that ignores it promises damage the square cannot deliver. It is
		# applied per contributing row and floored at zero, exactly the way
		# _damage_enemy applies it, so the board and the enemy agree.
		if op == "charge" or op == "charge_all":
			charge_delta += amount
		if op == "attack":
			# Mirrors _damage_enemy exactly, floor included. An attack that
			# was already zero or negative before armour never swings at
			# all, so it stays at zero rather than being floored up to one.
			if amount > 0:
				amount = max(1, amount - _enemy_armor())
		if not totals.has(op):
			totals[op] = 0
			order.append(op)
		totals[op] = int(totals[op]) + amount
		if scale != "" or add_scale != "":
			scaled_ops[op] = true

	# The square has room for one number, so the heaviest operation gets it.
	var best_op := ""
	var best_amount := -1
	for op in order:
		if int(totals[op]) > best_amount:
			best_amount = int(totals[op])
			best_op = str(op)

	# Everything this square had to offer is gated behind a condition this
	# die does not meet: say so, rather than printing a number it will not pay.
	if best_op == "":
		if blocked:
			return {"text": "×", "scaled": false, "blocked": true}
		return {"text": "", "scaled": false, "blocked": false}

	var glyph := str(OP_GLYPHS[best_op])
	var best_text := ""
	if best_op == "draw" or best_op == "reroll" or best_op == "action":
		best_text = glyph
	elif best_op == "attack":
		best_text = str(best_amount)
	else:
		best_text = "%s%d" % [glyph, best_amount]
	# On the route, a number this die inflates is worth flagging as "this is
	# not the resting value of this square".
	return {
		"text": best_text,
		"scaled": scaled_ops.has(best_op) or on_route,
		"blocked": false,
	}

func _telegraph_damage() -> int:
	for enemy in enemies:
		if int(enemy["hp"]) > 0:
			return int(enemy["damage"])
	return 0

func _apply_cell_style(button: Button, color: Color, border_color: Color, border_width: int, dim: bool, trigger: String = "pass") -> void:
	var fill: Color = color if not dim else color.lerp(COL_PANEL_SUNK, 0.55)
	# Round tiles fire when you run through them, square tiles when you land
	# on them, and the rounded-square in between does both. Shape says it
	# without spending any of the tile's space on a word.
	var radius: int = int(max(20.0, _board_token_size() * 0.5))
	if trigger == "stop":
		radius = 6
	elif trigger == "both":
		radius = 14
	var normal := StyleBoxFlat.new()
	normal.bg_color = fill
	normal.corner_radius_top_left = radius
	normal.corner_radius_top_right = radius
	normal.corner_radius_bottom_left = radius
	normal.corner_radius_bottom_right = radius
	normal.border_width_left = border_width
	normal.border_width_top = border_width
	normal.border_width_right = border_width
	normal.border_width_bottom = border_width
	normal.border_color = border_color
	# A stop tile casts a shadow because it stands above the road. A pass
	# tile does not, because it is part of it.
	normal.shadow_color = Color(0.16, 0.12, 0.08, 0.30)
	normal.shadow_size = 5 if trigger == "stop" else (3 if trigger == "both" else 0)
	normal.shadow_offset = Vector2(0, 4)
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = fill.lightened(0.12)
	button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate()
	pressed.bg_color = fill.darkened(0.10)
	button.add_theme_stylebox_override("pressed", pressed)
	var disabled := normal.duplicate()
	button.add_theme_stylebox_override("disabled", disabled)

func _refresh_ribbon() -> void:
	if ribbon_box == null:
		return
	var interior: float = _board_spacing() * float(BOARD_W - 2) - _board_token_size() - 12.0
	var moving: bool = state == "moving"
	ribbon_caption.visible = state == "player" and dice_rolled and interior >= 96.0
	ribbon_row.visible = ribbon_caption.visible
	roll_readout.visible = moving
	ribbon_box.visible = (state == "player" and dice_rolled) or moving

	if moving:
		roll_readout.visible = steps_left > 0
		roll_readout.text = tr("あと%d") % steps_left
		_clear_children(ribbon_row)
		_layout_ribbon()
		return
	_clear_children(ribbon_row)
	if not ribbon_row.visible:
		_layout_ribbon()
		return
	ribbon_caption.text = tr("この先のマス　●通過 ■停止")
	var chip: float = clamp((interior - 15.0) / 6.0, 14.0, 28.0)
	for i in range(preview_path.size()):
		ribbon_row.add_child(_make_ribbon_chip(preview_path[i], i + 1, chip))
	_layout_ribbon()

func _make_ribbon_chip(pos: Vector2i, step_index: int, chip: float) -> Control:
	var perm_type: String = str(permanent_board[pos.y][pos.x])
	var temp_type: String = str(temp_board[pos.y][pos.x])
	var tile: Dictionary = tile_defs[perm_type]
	var color: Color = tile["color"]
	var kind: String = str(tile["icon"])
	var chip_debuff := _debuff_at(pos)
	if not chip_debuff.is_empty():
		color = color.lerp(Color(chip_debuff["color"]).darkened(0.25), 0.5)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var stop_chip: bool = str(tile["trigger"]) != "pass"
	var box := Panel.new()
	box.custom_minimum_size = Vector2(chip, chip) if stop_chip else Vector2(chip * 0.84, chip * 0.84)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var style := _flat_style(color, COL_INK, 2, 0, 0)
	var chip_radius: int = 3 if stop_chip else int(chip * 0.5)
	style.corner_radius_top_left = chip_radius
	style.corner_radius_top_right = chip_radius
	style.corner_radius_bottom_left = chip_radius
	style.corner_radius_bottom_right = chip_radius
	if stop_chip:
		style.shadow_color = Color(0.16, 0.12, 0.08, 0.30)
		style.shadow_size = 3
		style.shadow_offset = Vector2(0, 2)
	if danger_cells.has(pos):
		style.border_color = COL_DANGER
		style.border_width_left = 3
		style.border_width_top = 3
		style.border_width_right = 3
		style.border_width_bottom = 3
	box.add_theme_stylebox_override("panel", style)
	col.add_child(box)

	var icon := IconGlyph.new()
	icon.kind = kind
	icon.glyph_color = Color("#FFF7E6")
	icon.outline_color = COL_INK
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 3
	icon.offset_top = 3
	icon.offset_right = -3
	icon.offset_bottom = -3
	box.add_child(icon)

	var step_label := _make_label(FS_SMALL - 2, COL_TEXT_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	step_label.text = "+%d" % step_index
	step_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	col.add_child(step_label)
	return col

# --- hand --------------------------------------------------------------

# Card width comes from the zone, not from the hand size, so a hand of
# three and a hand of nine draw cards the same size — only the row gets
# longer.
# Touch drags the row directly; a wheel is vertical on most desks, so it
# is mapped onto the row's one axis rather than doing nothing.
func _make_hand_arrow(label: String, direction: int) -> Button:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	button.visible = false
	button.add_theme_font_size_override("font_size", FS_HEAD)
	_style_button(button, COL_PANEL, COL_INK, 2)
	button.add_theme_color_override("font_color", COL_INK)
	button.pressed.connect(Callable(self, "_scroll_hand").bind(direction))
	return button

func _scroll_hand(direction: int) -> void:
	if hand_scroll == null:
		return
	var target: float = hand_scroll.scroll_horizontal + float(direction) * (_card_width() + HAND_GAP) * 2.0
	var tween := create_tween()
	tween.tween_property(hand_scroll, "scroll_horizontal", int(target), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(Callable(self, "_update_hand_arrows"))

func _update_hand_arrows() -> void:
	if hand_left_button == null or hand_scroll == null or zone_hand == null:
		return
	var content: float = hand_row.get_combined_minimum_size().x
	var view: float = hand_scroll.size.x
	var overflowing: bool = content > view + 2.0
	var arrow_w := 30.0
	var arrow_h: float = min(zone_hand.size.y * 0.44, 60.0)
	var top: float = (zone_hand.size.y - arrow_h) * 0.5
	hand_left_button.position = Vector2(0.0, top)
	hand_left_button.size = Vector2(arrow_w, arrow_h)
	hand_right_button.position = Vector2(zone_hand.size.x - arrow_w, top)
	hand_right_button.size = Vector2(arrow_w, arrow_h)
	hand_left_button.visible = overflowing and hand_scroll.scroll_horizontal > 2
	hand_right_button.visible = overflowing and hand_scroll.scroll_horizontal < int(content - view) - 2

func _on_hand_scroll_input(event: InputEvent) -> void:
	if hand_scroll == null or not (event is InputEventMouseButton):
		return
	var button_event := event as InputEventMouseButton
	if not button_event.pressed:
		return
	var step := 70
	match button_event.button_index:
		MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT:
			hand_scroll.scroll_horizontal += step
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT:
			hand_scroll.scroll_horizontal -= step
	_update_hand_arrows()

func _card_width() -> float:
	var available: float = zone_hand.size.x if zone_hand != null and zone_hand.size.x > 0.0 else 400.0
	return max((available - HAND_GAP * (HAND_VISIBLE - 1.0)) / HAND_VISIBLE, 62.0)

func _ensure_hand_slots(count: int) -> void:
	if hand_slots.size() == count:
		return
	_clear_children(hand_row)
	hand_slots = []
	for i in range(count):
		var slot := Control.new()
		slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hand_row.add_child(slot)
		hand_slots.append(slot)

func _refresh_hand() -> void:
	if hand_row == null:
		return
	# One entry per die drawn this turn. A spent die leaves its place
	# behind rather than closing the gap, so nothing slides out from under
	# a thumb mid-turn.
	var count: int = max(hand.size(), hand_slots.size())
	if state == "player" and not dice_rolled:
		count = hand.size()
	_ensure_hand_slots(count)
	var slot_w: float = _card_width()
	var slot_h: float = zone_hand.size.y
	for i in range(hand_slots.size()):
		var slot: Control = hand_slots[i]
		slot.custom_minimum_size = Vector2(slot_w, 0)
		_clear_children(slot)
		if i < hand.size():
			slot.add_child(_make_die_card(hand[i], i, slot_w, slot_h))
		else:
			slot.add_child(_make_empty_slot(slot_w))
	await get_tree().process_frame
	_update_hand_arrows()

func _make_empty_slot(slot_w: float = 120.0) -> Control:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.custom_minimum_size = Vector2(slot_w, 0)
	var style := _flat_style(Color(0.85, 0.78, 0.63, 0.35), Color(COL_INK.r, COL_INK.g, COL_INK.b, 0.30), 2, 6, 6)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := _make_label(FS_SMALL, Color(COL_TEXT_SOFT.r, COL_TEXT_SOFT.g, COL_TEXT_SOFT.b, 0.7), HORIZONTAL_ALIGNMENT_CENTER)
	label.text = tr("使用済み") if slot_w >= 86.0 else "済"
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(label)
	return panel

# A die card built out of real containers, with the whole face of the card
# as one hit target. The six faces are drawn as pips instead of printed as
# "1/2/3/4/5/6", so a loaded die looks loaded at a glance.
func _make_die_card(die: Dictionary, index: int, slot_w: float = 120.0, slot_h: float = 140.0) -> Control:
	var faces: Array = die["faces"]
	var roll := int(die.get("roll", 0))
	var tight: bool = slot_w < 92.0
	var face_size: float = clamp(min(slot_w * 0.56, slot_h * 0.40), 26.0, 54.0)
	var pip_size: float = clamp((slot_w - 14.0) / float(max(faces.size(), 1)) - 2.0, 6.0, 13.0)
	# The card under consideration wears a gold frame, so "which die am I
	# being asked about" is answered on the card as well as on the board.
	var considered: bool = index == preview_die_index and dice_rolled and state == "player"
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.custom_minimum_size = Vector2(slot_w, 0)
	panel.add_theme_stylebox_override("panel", _flat_style(
		_die_color(die), COL_GOLD if considered else COL_INK, 6 if considered else 3,
		4 if tight else 5, 5))

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)

	var name_label := _make_label(FS_SMALL - (2 if tight else 0), COL_TEXT_ON_DARK, HORIZONTAL_ALIGNMENT_CENTER, true)
	name_label.text = _t(die["name"])
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.clip_text = true
	col.add_child(name_label)

	# The result, big. Before the hand is rolled this is a question mark:
	# the card is a die you have not thrown yet, not a die with no value.
	var face_holder := Control.new()
	face_holder.custom_minimum_size = Vector2(0, face_size)
	face_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	face_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(face_holder)

	# "Not yet rolled" used to be inferred from roll<=0, but two of this
	# die's own faces can legitimately roll a real 0 or a negative number
	# now, so the turn's own dice_rolled flag is the only honest signal.
	var unrolled: bool = not dice_rolled
	var is_warp: bool = dice_rolled and _is_warp_face(roll)

	var face := DiceFace.new()
	face.name = "RolledFace"
	face.value = roll
	face.invert = roll < 0
	face.query = unrolled or is_warp
	var half: float = face_size * 0.5
	face.custom_minimum_size = Vector2(face_size, face_size)
	face.size = Vector2(face_size, face_size)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face_holder.add_child(face)
	face.set_anchors_preset(Control.PRESET_CENTER)
	face.offset_left = -half
	face.offset_top = -half
	face.offset_right = half
	face.offset_bottom = half
	face.pivot_offset = Vector2(half, half)

	if unrolled or is_warp:
		var overlay_text := "?" if unrolled else _warp_face_label(roll)
		# The corner labels are two characters (左上/右上/...) where "?"
		# and 帰 are one, so the font has to shrink to still fit the face.
		var overlay_size := face_size * (0.72 if overlay_text.length() <= 1 else 0.40)
		var overlay := _make_label(int(overlay_size), COL_INK, HORIZONTAL_ALIGNMENT_CENTER, true)
		overlay.text = overlay_text
		overlay.autowrap_mode = TextServer.AUTOWRAP_OFF
		overlay.set_anchors_preset(Control.PRESET_CENTER)
		overlay.offset_left = -half
		overlay.offset_top = -half - 7.0
		overlay.offset_right = half
		overlay.offset_bottom = half + 7.0
		face_holder.add_child(overlay)

	# The die's own range stays on the card, small, so a good result can be
	# read against what this die is capable of.
	var faces_row := HBoxContainer.new()
	faces_row.alignment = BoxContainer.ALIGNMENT_CENTER
	faces_row.add_theme_constant_override("separation", 2)
	faces_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(faces_row)
	var sorted_faces: Array = faces.duplicate()
	sorted_faces.sort()
	for face_value in sorted_faces:
		var pip := DiceFace.new()
		var fv := int(face_value)
		pip.value = fv
		pip.invert = fv < 0
		pip.query = _is_warp_face(fv)
		pip.custom_minimum_size = Vector2(pip_size, pip_size)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.modulate = Color(1, 1, 1, 1.0 if (dice_rolled and fv == roll) else 0.55)
		faces_row.add_child(pip)

	# What this die *does* when spent. This is the line the choice is now
	# actually made on, so unlike the old trait label it stays on the card
	# even when the cards get narrow — a power the player cannot see is a
	# power they will not plan around.
	var power_label := _make_label(FS_SMALL - (2 if tight else 1),
		COL_GOLD if considered else Color(1, 1, 1, 0.95), HORIZONTAL_ALIGNMENT_CENTER, true)
	power_label.text = tr("もう一度で確定") if considered else str(die.get("short", ""))
	power_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	power_label.clip_text = true
	col.add_child(power_label)

	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.text = ""
	hit.disabled = state != "player" or actions_left <= 0
	hit.pressed.connect(Callable(self, "_on_die_pressed").bind(index))
	panel.add_child(hit)
	panel.modulate = Color(1, 1, 1, 1.0 if not hit.disabled else 0.55)
	return panel

# --- feedback ----------------------------------------------------------

func _spawn_floating_text(pos: Vector2i, text: String, color: Color, big: bool = false) -> void:
	if board_view == null or not is_instance_valid(board_view):
		return
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_font(label, true)
	label.add_theme_font_size_override("font_size", FS_NUM_BIG if big else FS_NUM)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_outline_color", COL_INK)
	var center: Vector2 = _board_cell_center(pos)
	label.position = center + Vector2(-24, -_board_token_size() * 1.15)
	label.z_index = 25
	label.scale = Vector2(0.4, 0.4)
	board_view.add_child(label)
	label.pivot_offset = label.size / 2.0
	var base_y: float = label.position.y
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "scale", Vector2(1.1, 1.1), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "position:y", base_y - 40.0, 1.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.4).set_delay(0.75)
	tween.chain().tween_callback(label.queue_free)

func _spawn_enemy_popup(text: String, color: Color, big: bool = false) -> void:
	if enemy_sprite == null or not is_instance_valid(enemy_sprite):
		return
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_font(label, true)
	label.add_theme_font_size_override("font_size", FS_NUM_BIG if big else FS_NUM)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_outline_color", COL_INK)
	label.z_index = 30
	add_child(label)
	label.pivot_offset = label.size / 2.0
	var anchor: Vector2 = enemy_sprite.get_global_transform_with_canvas().origin
	label.position = anchor + Vector2(enemy_sprite.size.x * 0.5 - 20.0, enemy_sprite.size.y * 0.32)
	label.scale = Vector2(0.4, 0.4)
	var base_y: float = label.position.y
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "scale", Vector2(1.15, 1.15), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "position:y", base_y - 34.0, 1.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.4).set_delay(0.65)
	tween.chain().tween_callback(label.queue_free)

func _lunge_enemy() -> void:
	if zone_enemy == null or not is_instance_valid(zone_enemy):
		return
	# The whole column lunges, not the figure inside it: the figure is laid
	# out by a container, which would fight the tween for its position.
	var base: Vector2 = zone_enemy.position
	var tween := create_tween()
	tween.tween_property(zone_enemy, "position", base + Vector2(-14, 6), 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(zone_enemy, "position", base, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished

func _flash_enemy() -> void:
	if enemy_sprite == null:
		return
	var tween := create_tween()
	tween.tween_property(enemy_sprite, "flash", 1.0, 0.04)
	tween.tween_property(enemy_sprite, "flash", 0.0, 0.22)

# --- being hit ----------------------------------------------------------
# The one animation that plays in the middle of the board rather than over
# it. A fight runs twenty-odd turns, so this cannot be a full-screen
# interruption; it is the stage figure changing clip for under a second
# while play continues around it.

func _play_hit_clip(view: SpriteView, actor: String, lock_hero: bool) -> void:
	if view == null or not is_instance_valid(view):
		return
	if lock_hero:
		_hero_clip_lock = true
	else:
		_enemy_clip_lock = true
	_show_art(view, "stage", actor, ["hit", "idle"], false)
	view.flash = 0.9
	var tween := create_tween()
	tween.tween_property(view, "flash", 0.0, 0.20)
	# A clip that is only one frame long still has to hold the screen long
	# enough to be seen, so the floor is the beat, not the frame count.
	await get_tree().create_timer(max(view.duration(), 0.5)).timeout
	if lock_hero:
		_hero_clip_lock = false
		_refresh_hero_stage()
	else:
		_enemy_clip_lock = false
		_refresh_enemy()

# Only a heavy hit shakes the screen. If everything shakes, nothing reads
# as heavy.
func _shake(node: Control, amount: float) -> void:
	if node == null or not is_instance_valid(node):
		return
	var base: Vector2 = node.position
	var tween := create_tween()
	for i in range(4):
		var offset := Vector2(rng.randf_range(-amount, amount), rng.randf_range(-amount, amount))
		tween.tween_property(node, "position", base + offset, 0.035)
	tween.tween_property(node, "position", base, 0.05)

func _punch(node: Control, scale_to: float = 1.1) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.pivot_offset = node.size / 2.0
	var tween := create_tween()
	tween.tween_property(node, "scale", Vector2(scale_to, scale_to), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _spawn_burst_at_enemy() -> void:
	if enemy_sprite == null:
		return
	var burst := BurstEffect.new()
	burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	burst.set_anchors_preset(Control.PRESET_FULL_RECT)
	burst.center = enemy_sprite.get_global_transform_with_canvas().origin + enemy_sprite.size * 0.5
	burst.token = 60.0
	burst.z_index = 28
	add_child(burst)
	var tween := create_tween()
	tween.tween_property(burst, "progress", 1.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(burst.queue_free)

# --- overlay screens ---------------------------------------------------

func _open_overlay(title: String, body: String) -> void:
	overlay.visible = true
	overlay_title.text = title
	overlay_body.text = body
	overlay_body.visible = body != ""
	if overlay_art != null:
		overlay_art.visible = false
	_clear_children(overlay_list)

# Put an illustration on the card that is already open. Opening a card
# clears it again, so a screen has to ask for its picture every time —
# which is what keeps a stale image from following the player around.
func _open_overlay_art(kind: String, actor: String, art_state: String) -> void:
	if overlay_art == null or not _has_art(kind, actor, art_state):
		return
	_show_art(overlay_art, kind, actor, [art_state])
	overlay_art.visible = true

func _close_overlay() -> void:
	overlay.visible = false
	_clear_children(overlay_list)

# One option row: a real container card with a transparent button laid over
# it. Building the card *inside* a Button was what collapsed the reward
# text to one character per line in the old build — a Button is not a
# container, so its children never got a width to wrap against.
func _add_overlay_option(title: String, subtitle: String, color: Color, icon_kind: String, on_press: Callable) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _flat_style(color, COL_INK, 3, 12, 10))
	panel.custom_minimum_size = Vector2(0, 64)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)

	if icon_kind != "":
		var icon := IconGlyph.new()
		icon.kind = icon_kind
		icon.glyph_color = COL_TEXT_ON_DARK
		icon.outline_color = COL_INK
		icon.custom_minimum_size = Vector2(34, 34)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)

	var title_label := _make_label(FS_BODY, COL_TEXT_ON_DARK, HORIZONTAL_ALIGNMENT_LEFT, true)
	title_label.text = title
	col.add_child(title_label)

	if subtitle != "":
		var sub_label := _make_label(FS_SMALL, Color(1, 1, 1, 0.92), HORIZONTAL_ALIGNMENT_LEFT)
		sub_label.text = subtitle
		col.add_child(sub_label)

	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.pressed.connect(on_press)
	panel.add_child(hit)

	overlay_list.add_child(panel)

# The build concepts, in the order the catalogue lists them. Each one is a
# counter plus the content that feeds and spends it; a tile's "kind" is the
# claim that it belongs to that build.
const TILE_KINDS := [
	["基本", "どの盤面にもある土台"],
	["疾走", "通過型。長い出目で何枚も踏み抜く"],
	["連鎖", "コンボを積み、コンボを参照するマスで清算する"],
	["狙撃", "チャージを溜め、止まって撃ち切る"],
	["要塞", "盾を集め、盾そのものを打点に変える"],
	["小刻み", "小さい出目でだけ開く。疾走の裏返し"],
	["毒", "毒を盛り、敵のターンごとに削る"],
	["手負い", "失ったHPを打点と守りに変える"],
	["移動", "移動そのものを変える"],
	["補助", "手札・行動・立て直し"],
]

# A catalogue of every tile, grouped by when it fires. Reachable from the
# title and from inside a turn, because the question "what does that one
# do again" turns up mid-run, not before it.
func _show_catalog() -> void:
	catalog_return_state = state
	overlay.visible = true
	overlay_title.text = tr("図鑑")
	overlay_body.text = tr("○丸は通過で、□四角は止まって効くマス。攻撃マスのダメージには、そのターンに使ったダイスの数（コンボ）が加算されます。ダイスは出目に加えて、使った行動のあいだだけ効果を発揮します。")
	overlay_body.visible = true
	_clear_children(overlay_list)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, min(get_viewport_rect().size.y * 0.52, 380.0))
	overlay_list.add_child(scroll)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 6)
	scroll.add_child(column)

	# Grouped by build concept rather than by trigger: with this many tiles,
	# "which build is this for" is the question a player actually has.
	for kind in TILE_KINDS:
		var heading := _make_label(FS_BODY, COL_TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
		heading.text = "%s — %s" % [str(kind[0]), str(kind[1])]
		heading.autowrap_mode = TextServer.AUTOWRAP_OFF
		column.add_child(heading)
		for key in tile_defs.keys():
			var tile: Dictionary = tile_defs[key]
			if _t(tile["kind"]) != str(kind[0]):
				continue
			column.add_child(_make_catalog_row(tile))
	var debuff_heading := _make_label(FS_BODY, COL_TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	debuff_heading.text = tr("◇ 敵のデバフ — マスに重ねてかけられる")
	debuff_heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	column.add_child(debuff_heading)
	for debuff_key in ["burn", "venom", "freeze", "briar"]:
		column.add_child(_make_catalog_row(temp_defs[debuff_key]))

	var dice_heading := _make_label(FS_BODY, COL_TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	dice_heading.text = tr("⚄ ダイス — 使った行動のあいだだけ効果が続く")
	dice_heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	column.add_child(dice_heading)
	var owned := {}
	for die in dice_bag:
		owned[str(die.get("id", ""))] = int(owned.get(str(die.get("id", "")), 0)) + 1
	for die_id in dice_defs.keys():
		column.add_child(_make_die_catalog_row(str(die_id), int(owned.get(str(die_id), 0))))

	var settings_row := Button.new()
	settings_row.text = tr("設定")
	settings_row.focus_mode = Control.FOCUS_NONE
	settings_row.custom_minimum_size = Vector2(0, 40)
	settings_row.add_theme_font_size_override("font_size", FS_SMALL)
	_style_button(settings_row, COL_PANEL_SUNK, COL_INK)
	settings_row.add_theme_color_override("font_color", COL_INK)
	settings_row.pressed.connect(Callable(self, "_show_settings"))
	overlay_list.add_child(settings_row)

	if catalog_return_state != "title":
		var quit_row := Button.new()
		quit_row.text = tr("この挑戦をやめてタイトルへ")
		quit_row.focus_mode = Control.FOCUS_NONE
		quit_row.custom_minimum_size = Vector2(0, 40)
		quit_row.add_theme_font_size_override("font_size", FS_SMALL)
		_style_button(quit_row, COL_PANEL_SUNK, COL_INK)
		quit_row.add_theme_color_override("font_color", COL_INK)
		quit_row.pressed.connect(Callable(self, "_show_title"))
		overlay_list.add_child(quit_row)

	var close_button := Button.new()
	close_button.text = tr("閉じる")
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(0, 44)
	close_button.add_theme_font_size_override("font_size", FS_BODY)
	_style_button(close_button, COL_GOLD, COL_INK)
	close_button.add_theme_color_override("font_color", COL_INK)
	close_button.pressed.connect(Callable(self, "_close_catalog"))
	overlay_list.add_child(close_button)
	_layout_overlay()

func _make_catalog_row(tile: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _flat_style(COL_PANEL_SUNK, COL_INK, 2, 8, 7))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 9)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)

	# The swatch repeats the board's shape language, so the catalogue reads
	# as the same object the player is looking at on the board.
	var swatch := Panel.new()
	swatch.custom_minimum_size = Vector2(38, 38)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := _flat_style(Color(tile["color"]), COL_INK, 3, 0, 0)
	var radius: int = 19 if str(tile.get("trigger", "pass")) == "pass" else 5
	if not tile.has("detail"):
		radius = 19
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	swatch.add_theme_stylebox_override("panel", style)
	line.add_child(swatch)
	var icon := IconGlyph.new()
	icon.kind = str(tile["icon"])
	icon.glyph_color = COL_TEXT_ON_DARK
	icon.outline_color = COL_INK
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 5
	icon.offset_top = 5
	icon.offset_right = -5
	icon.offset_bottom = -5
	swatch.add_child(icon)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(col)

	var head := _make_label(FS_BODY, COL_TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	head.text = "%s　%s" % [_t(tile["name"]), _t(tile["effect"])]
	col.add_child(head)

	var detail := _make_label(FS_SMALL, COL_TEXT_SOFT, HORIZONTAL_ALIGNMENT_LEFT)
	detail.text = _t(tile["detail"])
	col.add_child(detail)
	return row

# Same row shape as a tile, but the swatch is a real die face showing the
# highest number this die can roll, and the header carries how many of it
# the run currently holds — the one number a build decision needs.
func _make_die_catalog_row(die_id: String, owned_count: int) -> Control:
	var die_def: Dictionary = dice_defs[die_id]
	var faces: Array = die_def["faces"]
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _flat_style(COL_PANEL_SUNK, COL_INK, 2, 8, 7))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 9)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)

	var swatch := Panel.new()
	swatch.custom_minimum_size = Vector2(38, 38)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swatch.add_theme_stylebox_override("panel", _flat_style(Color(die_def["color"]), COL_INK, 3, 0, 0))
	line.add_child(swatch)
	var pip := DiceFace.new()
	# The representative face is whichever has the biggest magnitude, not
	# the biggest number — for 逆走 (all negative) that is its -6, not the
	# least-negative -1 a plain max() would pick.
	var showcase: int = int(faces[0])
	for f in faces:
		if absi(int(f)) > absi(showcase):
			showcase = int(f)
	pip.value = showcase
	pip.invert = showcase < 0
	pip.query = _is_warp_face(showcase)
	pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pip.set_anchors_preset(Control.PRESET_FULL_RECT)
	pip.offset_left = 6
	pip.offset_top = 6
	pip.offset_right = -6
	pip.offset_bottom = -6
	swatch.add_child(pip)
	if _is_warp_face(showcase):
		var label_text := _warp_face_label(showcase)
		var flag := _make_label(18 if label_text.length() <= 1 else 11, COL_INK, HORIZONTAL_ALIGNMENT_CENTER, true)
		flag.text = label_text
		flag.set_anchors_preset(Control.PRESET_FULL_RECT)
		flag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		swatch.add_child(flag)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(col)

	var head := _make_label(FS_BODY, COL_TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	head.text = tr("%sダイス　%s") % [_t(die_def["name"]), _t(die_def["effect"])]
	if owned_count > 0:
		head.text += "　（所持 %d）" % owned_count
	col.add_child(head)

	var faces_label := _make_label(FS_SMALL, COL_TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	faces_label.text = tr("出目: %s") % _faces_text(faces)
	col.add_child(faces_label)

	var detail := _make_label(FS_SMALL, COL_TEXT_SOFT, HORIZONTAL_ALIGNMENT_LEFT)
	detail.text = _t(die_def["detail"])
	col.add_child(detail)
	return row

func _close_catalog() -> void:
	if catalog_return_state == "title":
		_show_title()
		return
	_close_overlay()

func _show_title() -> void:
	state = "title"
	encounter = 0
	hero_key = ""
	enemies = []
	if backdrop_view != null:
		backdrop_view.tint_progress = 0.0
	permanent_board = _make_empty_board("empty")
	temp_board = _make_empty_board("none")
	_refresh_all()
	_set_log("")
	_open_overlay("Dice Board Rogue", "手札のダイスを全部振り、出た目から1つ選んで進む。踏んだマスの効果で戦う、すごろくローグライク。全%d層。" % MAP_ROWS)
	if _has_run_save():
		_add_overlay_option("続きから", "中断した挑戦を再開します。", COL_GOLD, "warp", Callable(self, "_continue_run"))
	for key in hero_defs.keys():
		var hero: Dictionary = hero_defs[key]
		_add_overlay_option(
			"%s   HP %d   手札%d   行動%d" % [
				_t(hero["name"]), int(hero["hp"]), int(hero.get("hand", 3)),
				int(hero.get("actions", ACTIONS_PER_TURN))],
			"%s\nダイス: %s" % [_t(hero["desc"]), _hero_dice_names(hero)],
			Color(hero["color"]),
			"slash" if key == "knight" else ("fire" if key == "mage" else "trap"),
			Callable(self, "_start_run").bind(key)
		)
	_add_overlay_option("図鑑", "マスとダイスが何をするかの一覧。", COL_TEXT_SOFT, "focus", Callable(self, "_show_catalog"))
	var seen := 0
	for raw in _gallery_entries():
		if _is_unlocked(str((raw as Dictionary)["key"])):
			seen += 1
	_add_overlay_option("回想", "見た場面をもう一度。%d / %d" % [seen, _gallery_entries().size()],
		Color("#9C3A6B"), "warp", Callable(self, "_show_gallery"))
	_add_overlay_option("設定", "音量を調整します。", COL_TEXT_SOFT, "dice", Callable(self, "_show_settings"))
	_layout_overlay()

func _show_reward() -> void:
	state = "reward_select"
	if _is_boss_node():
		_show_victory()
		return
	sfx.emit("reward")
	_refresh_all()
	_open_overlay(tr("戦闘に勝利"), tr("マスかダイスを1つ選びます。マスはコースに置いて残り、ダイスは手札に加わります。"))

	# One tile and one die are always on offer, so neither build axis can be
	# shut off by a bad shuffle; the third slot goes either way and is what
	# makes a given run lean one direction.
	var tiles := reward_pool.duplicate(true)
	tiles.shuffle()
	var dice_ids := die_reward_pool.duplicate()
	dice_ids.shuffle()
	var slots := [
		{"kind": "tile", "id": str(tiles[0]["type"])},
		{"kind": "die", "id": str(dice_ids[0])},
	]
	if rng.randi_range(0, 1) == 0:
		slots.append({"kind": "tile", "id": str(tiles[1]["type"])})
	else:
		slots.append({"kind": "die", "id": str(dice_ids[1])})
	slots.shuffle()

	for slot in slots:
		if _t(slot["kind"]) == "tile":
			var reward_type := str(slot["id"])
			var tile: Dictionary = tile_defs[reward_type]
			_add_overlay_option(
				"%s［%s］" % [_t(tile["name"]), _t(tile["kind"])],
				"%s　%s" % [_trigger_label(str(tile["trigger"])), _t(tile["effect"])],
				Color(tile["color"]),
				str(tile["icon"]),
				Callable(self, "_on_reward_selected").bind(reward_type, "%sマス" % _t(tile["name"]))
			)
		else:
			var die_id := str(slot["id"])
			var die_def: Dictionary = dice_defs[die_id]
			_add_overlay_option(
				"%sダイス［出目 %s］" % [_t(die_def["name"]), _faces_text(die_def["faces"])],
				_t(die_def["effect"]),
				Color(die_def["color"]),
				"dice",
				Callable(self, "_on_die_reward_selected").bind(die_id)
			)
	_layout_overlay()

# "通過型" / "停止型" — the one word that says when a tile pays out.
func _trigger_label(trigger: String) -> String:
	match trigger:
		"pass":
			return "○通過型"
		"both":
			return "◎複合型"
	return "□停止型"

func _show_victory() -> void:
	state = "victory"
	_delete_run_save()
	_bump_lifetime("wins")
	_save_profile()
	sfx.emit("kill")
	_refresh_all()
	_open_overlay("踏破成功", "%s は全%d層を踏破しました。" % [hero_name, MAP_ROWS])
	_add_result_stats()
	_add_overlay_option("もう一度、同じキャラで", "同じ盤面構成から新しいランを始めます。", COL_HP, "warp", Callable(self, "_restart_same_hero"))
	_add_overlay_option("キャラを選び直す", "タイトルに戻ります。", COL_TEXT_SOFT, "dice", Callable(self, "_show_title"))
	_layout_overlay()
	_play_result_flourish(Color(1.0, 0.85, 0.45, 0.45))

# `by_enemy` is what separates "the enemy finished you" from "you walked
# onto one poison square too many". Only the first has a scene, because
# only the first has someone standing over you at the end of it.
func _show_game_over(reason: String, by_enemy: bool = false) -> void:
	if by_enemy and not scene_played_this_fight:
		scene_played_this_fight = true
		_play_scene(encounter_art, "lose", tr("%s に敗れた") % encounter_name,
			Callable(self, "_show_game_over").bind(reason, false))
		return
	state = "game_over"
	_delete_run_save()
	_bump_lifetime("losses")
	_save_profile()
	sfx.emit("lose")
	_refresh_all()
	_open_overlay("ゲームオーバー", reason)
	_add_result_stats()
	_add_overlay_option("もう一度、同じキャラで", "%s で第1戦から挑み直します。" % hero_name, COL_GOLD, "warp", Callable(self, "_restart_same_hero"))
	_add_overlay_option("キャラを選び直す", "タイトルに戻ります。", COL_TEXT_SOFT, "dice", Callable(self, "_show_title"))
	_layout_overlay()
	_play_result_flourish(Color(0.75, 0.2, 0.1, 0.4))

# A run that ends with no record of what happened gives the player nothing
# to carry into the next one.
func _add_result_stats() -> void:
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 8)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_list.add_child(stats)
	var entries := [
		["到達", "%d / %d層" % [max(map_row + 1, 0), MAP_ROWS]],
		["与ダメージ", str(run_damage_dealt)],
		["ターン", str(run_turns)],
	]
	for entry in entries:
		var box := PanelContainer.new()
		box.add_theme_stylebox_override("panel", _flat_style(COL_PANEL_SUNK, COL_INK, 2, 8, 6))
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stats.add_child(box)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 1)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(col)
		var caption := _make_label(FS_SMALL - 1, COL_TEXT_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
		caption.text = str(entry[0])
		caption.autowrap_mode = TextServer.AUTOWRAP_OFF
		col.add_child(caption)
		var value := _make_label(FS_BODY, COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER, true)
		value.text = str(entry[1])
		value.autowrap_mode = TextServer.AUTOWRAP_OFF
		col.add_child(value)

func _restart_same_hero() -> void:
	if hero_key == "":
		_show_title()
		return
	_start_run(hero_key)

func _play_result_flourish(flash_color: Color) -> void:
	var flash := ColorRect.new()
	flash.color = flash_color
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.z_index = 100
	add_child(flash)
	var tween := create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(flash.queue_free)

# --- run flow ----------------------------------------------------------

func _start_run(key: String) -> void:
	_close_overlay()
	hero_key = key
	var hero: Dictionary = hero_defs[key]
	hero_name = _t(hero["name"])
	hero_token_color = Color(hero["color"])
	player_max_hp = int(hero["hp"])
	hand_limit = int(hero.get("hand", 3))
	actions_per_turn = int(hero.get("actions", ACTIONS_PER_TURN))
	player_hp = player_max_hp
	player_shield = 0
	next_enemy_uid = 0
	run_damage_dealt = 0
	run_turns = 0
	gold = 0
	encounter = 0
	player_step = _track_index(_start_pos())
	player_pos = _pos_for_step(player_step)
	permanent_board = _make_empty_board("empty")
	for entry in hero["tiles"]:
		permanent_board[int(entry[1])][int(entry[0])] = str(entry[2])
	dice_bag = []
	for die_id in hero["dice"]:
		dice_bag.append(_make_die(str(die_id)))
	hp_bar.display_value = float(player_hp)
	_generate_map()
	_snap_player_visual()
	_show_map()

func _start_encounter() -> void:
	encounter += 1
	if backdrop_view != null:
		backdrop_view.tint_progress = float(max(map_row, 0)) / float(max(MAP_ROWS - 1, 1))
	player_pos = _pos_for_step(player_step)
	player_shield = 0
	actions_left = actions_per_turn
	selected_die = {}
	selected_roll = 0
	move_dir = 1
	steps_left = 0
	route_path = []
	combo = 0
	charge_map = {}
	temp_board = _make_empty_board("none")
	enemies = []
	_setup_encounter()
	_reset_dice_for_encounter()
	enemy_hp_bar.display_value = float(enemies[0]["hp"]) if not enemies.is_empty() else 0.0
	_snap_player_visual()
	var intro := "第%d戦。ダイスを選んで進みましょう。" % encounter
	if encounter == 1:
		intro = "画面をタップして手札を全部振り、出た目から1つ選んで進みます。"
	_start_player_turn(intro)

# Every non-boss enemy in the game is one of exactly two attack kinds:
# "cell" (マス指定攻撃) telegraphs specific squares and only lands on
# whichever square the player is standing on once their turn is over, and
# "guaranteed" (必中攻撃) always lands regardless of position. A "cell"
# enemy's squares come from one of two patterns — "relative", which reads
# off the player's own step count and re-paints itself every turn, or
# "fixed", a set of squares on the physical board that never moves. The
# two patterns are what give same-kind enemies a different feel: a
# relative enemy is punishing a distance, a fixed one is punishing a place.
# Enemies are a table too. A trait is what makes a fight ask a different
# question of the build rather than just a bigger number: 装甲 blanks small
# repeated hits, 再生 outpaces slow poison, 棘 punishes hitting often. Each
# one makes some build wrong for that fight, which is what stops a single
# board from being the answer to the whole run.
const ENEMY_TRAIT_TEXT := {
	"armor": "装甲%d：受けるダメージが1回ごとに%d減る（最低1は通る）",
	"regen": "再生%d：毎ターンHPが%d回復する",
	"thorns": "棘%d：攻撃するたびこちらが%dダメージ受ける",
}

# "art" is the actor id its stage figure and its scene art resolve under —
# res://art/stage/scout_idle.png, res://art/cg/scout_lose.png and so on. It
# is a separate field from "name" so the Japanese name can be rewritten
# without touching a single filename.
# "debuff" is the second half of an enemy's attack pattern: the swing it
# telegraphs, and the mess it leaves on the board between swings. Which
# kind it leaves is as much of its identity as its damage number — 疫病持ち
# charges for landing, 射手 charges for running, 重装 takes the square away
# and 斥候 takes the distance — so the same board asks a different question
# depending on who is standing across it. "foul" is the percent chance per
# enemy turn; an enemy with no debuff never fouls anything, which is what
# keeps the opening fight a place to learn the rules rather than survive
# them.
var enemy_defs := [
	{"name": "はぐれ兵", "art": "stray", "hp": 20, "damage": 5, "kind": "cell",
		"mode": "relative", "cells": [2], "gold": 12},
	{"name": "斥候", "art": "scout", "hp": 28, "damage": 6, "kind": "cell",
		"mode": "relative", "cells": [2, 5], "gold": 15,
		"debuff": "briar", "foul": 35},
	{"name": "射手", "art": "archer", "hp": 36, "damage": 7, "kind": "guaranteed",
		"mode": "relative", "cells": [], "armor": 2, "gold": 18,
		"debuff": "burn", "foul": 45},
	{"name": "重装", "art": "heavy", "hp": 44, "damage": 8, "kind": "cell",
		"mode": "fixed", "cells": [2, 6, 10, 14], "armor": 3, "gold": 21,
		"debuff": "freeze", "foul": 40},
	{"name": "疫病持ち", "art": "plague", "hp": 46, "damage": 8, "kind": "cell",
		"mode": "relative", "cells": [1, 2, 3], "regen": 4, "gold": 22,
		"debuff": "venom", "foul": 55},
	{"name": "隊長", "art": "captain", "hp": 52, "damage": 9, "kind": "cell",
		"mode": "relative", "cells": [2, 3, 4, 5], "thorns": 2, "gold": 25,
		"debuff": "burn", "foul": 50},
	{"name": "ボス", "art": "boss", "hp": 62, "damage": 10, "kind": "guaranteed",
		"mode": "relative", "cells": [], "armor": 2, "regen": 3, "gold": 40,
		"debuff": "freeze", "foul": 55},
]

# --- map screen ---------------------------------------------------------
# The map is a tall column inside a scroll view: row 0 sits at the bottom
# and the boss at the top, so climbing it reads as climbing. The links are
# painted by a single Control behind the buttons rather than by each node,
# which keeps the lines beneath every node no matter the draw order.
const MAP_NODE_SIZE := 62.0
const MAP_ROW_H := 92.0
const MAP_COL_W := 150.0

class MapLinks:
	extends Control

	var main = null

	func _draw() -> void:
		if main == null or main.map_nodes.is_empty():
			return
		for row in range(main.MAP_ROWS - 1):
			for col in range(main.MAP_COLS):
				var node = main.map_nodes[row][col]
				if node == null:
					continue
				var a: Vector2 = main._map_node_center(row, col)
				for raw in (node["links"] as Dictionary).keys():
					var to_col := int(raw)
					if main.map_nodes[row + 1][to_col] == null:
						continue
					var b: Vector2 = main._map_node_center(row + 1, to_col)
					# A link the player could take right now is lit; the rest
					# of the map stays visible but recedes.
					var live: bool = row == main.map_row and col == main.map_col
					var walked: bool = row < main.map_row
					var col_line := Color("#8C7A55")
					var width := 4.0
					if walked:
						col_line = Color("#C0AC84")
					if live:
						col_line = main.COL_GOLD
						width = 6.0
					draw_line(a, b, Color("#2A2320"), width + 4.0, true)
					draw_line(a, b, col_line, width, true)

func _map_canvas_size() -> Vector2:
	return Vector2(MAP_COL_W * float(MAP_COLS), MAP_ROW_H * float(MAP_ROWS))

# Row 0 is drawn at the bottom, so the map is climbed upward.
func _map_node_center(row: int, col: int) -> Vector2:
	var x: float = MAP_COL_W * (float(col) + 0.5)
	var y: float = MAP_ROW_H * (float(MAP_ROWS - 1 - row) + 0.5)
	return Vector2(x, y)

func _build_map_zone() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", _flat_style(COL_PANEL, COL_INK, 3, 10, 8))
	zone_map.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)

	map_title = _make_label(FS_HEAD, COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER, true)
	map_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	col.add_child(map_title)

	map_scroll = ScrollContainer.new()
	map_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	map_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(map_scroll)

	# A centring row, so the fixed-width map column sits in the middle of a
	# wide landscape window instead of hugging the left edge.
	var centre := HBoxContainer.new()
	centre.alignment = BoxContainer.ALIGNMENT_CENTER
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_scroll.add_child(centre)

	map_canvas = Control.new()
	map_canvas.custom_minimum_size = _map_canvas_size()
	map_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(map_canvas)

	map_links = MapLinks.new()
	map_links.main = self
	map_links.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_links.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_canvas.add_child(map_links)

func _show_map() -> void:
	state = "map"
	_hide_banner()
	_close_overlay()
	_save_run(false)
	_refresh_all()
	_refresh_map()
	# Keep the row the player is standing on in view as they climb.
	await get_tree().process_frame
	_scroll_map_to_current()

func _scroll_map_to_current() -> void:
	if map_scroll == null:
		return
	var focus_row: int = max(map_row, 0)
	var centre_y: float = _map_node_center(focus_row, 0).y
	var target: float = centre_y - map_scroll.size.y * 0.5
	map_scroll.scroll_vertical = int(clampf(target, 0.0, max(_map_canvas_size().y - map_scroll.size.y, 0.0)))

func _refresh_map() -> void:
	if zone_map == null:
		return
	zone_map.visible = state == "map"
	if not zone_map.visible or map_nodes.is_empty():
		return
	map_canvas.custom_minimum_size = _map_canvas_size()
	map_title.text = tr("第%d層 / %d層") % [max(map_row + 1, 0) + (1 if map_row < 0 else 0), MAP_ROWS]
	if map_row < 0:
		map_title.text = tr("出発地点を選ぶ（全%d層）") % MAP_ROWS

	for row in range(MAP_ROWS):
		for c in range(MAP_COLS):
			var key := "%d,%d" % [row, c]
			var node = map_nodes[row][c]
			if node == null:
				if map_buttons.has(key):
					(map_buttons[key] as Button).visible = false
				continue
			var button: Button
			if map_buttons.has(key):
				button = map_buttons[key]
			else:
				button = _make_map_node_button(row, c)
				map_buttons[key] = button
			button.visible = true
			_style_map_node(button, node, row, c)

func _make_map_node_button(row: int, c: int) -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(MAP_NODE_SIZE, MAP_NODE_SIZE)
	button.size = Vector2(MAP_NODE_SIZE, MAP_NODE_SIZE)
	var centre := _map_node_center(row, c)
	button.position = centre - Vector2(MAP_NODE_SIZE, MAP_NODE_SIZE) * 0.5
	button.pressed.connect(Callable(self, "_on_map_node_pressed").bind(row, c))
	map_canvas.add_child(button)

	var icon := IconGlyph.new()
	icon.name = "NodeIcon"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 12
	icon.offset_top = 10
	icon.offset_right = -12
	icon.offset_bottom = -18
	button.add_child(icon)

	# Choosing a route is choosing who to meet, so a node shows a face when
	# there is one to show. Without it the icon carries the node, which is
	# what happened before this existed.
	var face := SpriteView.new()
	face.name = "NodeFace"
	face.cover = true
	face.visible = false
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.set_anchors_preset(Control.PRESET_FULL_RECT)
	face.offset_left = 4
	face.offset_top = 3
	face.offset_right = -4
	face.offset_bottom = -17
	button.add_child(face)

	var label := _make_label(FS_SMALL - 2, COL_TEXT_ON_DARK, HORIZONTAL_ALIGNMENT_CENTER, true)
	label.name = "NodeLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	label.offset_top = -18
	label.offset_bottom = -2
	button.add_child(label)
	return button

func _style_map_node(button: Button, node: Dictionary, row: int, c: int) -> void:
	var kind := str(node["type"])
	var def: Dictionary = NODE_DEFS[kind]
	var here: bool = row == map_row and c == map_col
	var reachable: bool = _is_map_reachable(row, c)
	var done: bool = bool(node.get("cleared", false))

	var icon: IconGlyph = button.find_child("NodeIcon", true, false)
	icon.set_kind(str(def["icon"]))
	icon.glyph_color = COL_TEXT_ON_DARK
	icon.outline_color = COL_INK

	# A fight is identified by who is in it; everything else by what it is.
	var face: SpriteView = button.find_child("NodeFace", true, false)
	var face_id := kind
	if int(node.get("enemy", -1)) >= 0:
		face_id = str((enemy_defs[int(node["enemy"])] as Dictionary).get("art", kind))
	icon.visible = not _show_art(face, "face", face_id, ["node"])

	var label: Label = button.find_child("NodeLabel", true, false)
	# A combat node says who is waiting there. Hiding it would defeat the
	# point of letting the player choose a route.
	var text := _t(def["label"])
	if int(node.get("enemy", -1)) >= 0:
		text = str(enemy_defs[int(node["enemy"])]["name"])
	label.text = text

	var fill: Color = Color(def["color"])
	var border := COL_INK
	var width := 3
	if here:
		border = COL_GOLD
		width = 5
	elif reachable:
		border = COL_NEXT
		width = 4
	var dim: bool = not (here or reachable)
	if done:
		fill = fill.lerp(COL_PANEL_SUNK, 0.55)
	button.disabled = not reachable
	button.modulate = Color(1, 1, 1, 1.0 if (here or reachable) else 0.5)
	_apply_cell_style(button, fill, border, width, dim and not done, "stop")

func _on_map_node_pressed(row: int, c: int) -> void:
	if state != "map" or not _is_map_reachable(row, c):
		return
	sfx.emit("step")
	map_row = row
	map_col = c
	_enter_map_node()

# Every node type funnels through here, so adding one is a branch in a
# single place rather than a change to the run flow.
func _enter_map_node() -> void:
	var node = _map_node_at(map_row, map_col)
	if node == null:
		return
	node["cleared"] = true
	# Recorded before the node resolves, so closing the game mid-fight
	# resumes into this node instead of back onto the map.
	_save_run(true)
	match str(node["type"]):
		"rest":
			_resolve_rest_node()
		"shop":
			_resolve_shop_node()
		"event":
			_resolve_event_node()
		_:
			_start_encounter()

func _resolve_rest_node() -> void:
	var healed: int = min(player_max_hp - player_hp, int(round(player_max_hp * 0.3)))
	player_hp += healed
	hp_bar.display_value = float(player_hp)
	sfx.emit("shield")
	_refresh_top()
	_open_overlay("休憩", "傷を癒した。HPが %d 回復（%d / %d）。" % [healed, player_hp, player_max_hp])
	_add_overlay_option("地図に戻る", "次の層を選びます。", COL_HP, "boot", Callable(self, "_leave_node"))
	_layout_overlay()
	state = "node_event"

func _resolve_shop_node() -> void:
	state = "node_event"
	_open_overlay("店", "所持金 %dG。ダイスの購入と、いらないダイスの処分ができます。" % gold)
	var stock := die_reward_pool.duplicate()
	stock.shuffle()
	for i in range(min(2, stock.size())):
		var die_id := str(stock[i])
		var die_def: Dictionary = dice_defs[die_id]
		var price: int = 25
		var affordable: bool = gold >= price
		_add_overlay_option(
			"%sダイス　%dG%s" % [_t(die_def["name"]), price, "" if affordable else "（所持金が足りない）"],
			_t(die_def["effect"]),
			Color(die_def["color"]) if affordable else COL_PANEL_SUNK,
			"dice",
			Callable(self, "_buy_die").bind(die_id, price)
		)
	var removal_price := 20
	_add_overlay_option(
		"ダイスを1つ処分　%dG%s" % [removal_price, "" if gold >= removal_price else "（所持金が足りない）"],
		"バッグからダイスを取り除きます。手札に来る確率が上がります。",
		COL_DANGER if gold >= removal_price else COL_PANEL_SUNK,
		"trap",
		Callable(self, "_open_removal").bind(removal_price)
	)
	_add_overlay_option("店を出る", "次の層を選びます。", COL_TEXT_SOFT, "boot", Callable(self, "_leave_node"))
	_layout_overlay()

func _buy_die(die_id: String, price: int) -> void:
	if gold < price:
		return
	gold -= price
	dice_bag.append(_make_die(die_id))
	sfx.emit("reward")
	_refresh_top()
	_resolve_shop_node()

func _open_removal(price: int) -> void:
	if gold < price or dice_bag.size() <= 1:
		return
	state = "node_event"
	_open_overlay("処分するダイスを選ぶ", "所持 %d 個。1つ選ぶと %dG かかります。" % [dice_bag.size(), price])
	for i in range(dice_bag.size()):
		var die: Dictionary = dice_bag[i]
		_add_overlay_option(
			"%sダイス［出目 %s］" % [_t(die["name"]), _faces_text(die["faces"])],
			str(die.get("short", "")),
			_die_color(die),
			"dice",
			Callable(self, "_remove_die").bind(i, price)
		)
	_add_overlay_option("やめる", "店に戻ります。", COL_TEXT_SOFT, "boot", Callable(self, "_resolve_shop_node"))
	_layout_overlay()

func _remove_die(index: int, price: int) -> void:
	if gold < price or index < 0 or index >= dice_bag.size() or dice_bag.size() <= 1:
		return
	gold -= price
	dice_bag.remove_at(index)
	sfx.emit("hit")
	_refresh_top()
	_resolve_shop_node()

func _resolve_event_node() -> void:
	state = "node_event"
	var ids: Array = event_defs.keys()
	var event_id := str(ids[rng.randi_range(0, ids.size() - 1)])
	var event: Dictionary = event_defs[event_id]
	_open_overlay(_t(event["name"]), _t(event["body"]))
	# An event is a place, so it gets a picture of one when there is a file
	# for it: res://art/cg/<event id>_scene.png. Nothing changes if there
	# is not — the card is the same card it has always been.
	_open_overlay_art("cg", str(event.get("art", event_id)), "scene")
	for raw in event["choices"]:
		var choice: Dictionary = raw
		_add_overlay_option(
			_t(choice["label"]),
			str(choice.get("detail", "")),
			Color(choice.get("color", COL_TEXT_SOFT)),
			str(choice.get("icon", "focus")),
			Callable(self, "_take_event_choice").bind(choice)
		)
	_layout_overlay()

# An event choice is just a list of ops, run through the same engine tiles
# and dice use — so a new event is a table row, not code.
func _take_event_choice(choice: Dictionary) -> void:
	var notes := []
	for raw in choice.get("effects", []):
		var eff: Dictionary = raw
		var op := str(eff["op"])
		var amount := int(eff.get("amount", 0))
		match op:
			"gold":
				gold = max(0, gold + amount)
				notes.append("%dG" % amount if amount < 0 else "+%dG" % amount)
			"heal":
				var gained: int = min(player_max_hp - player_hp, amount)
				player_hp += gained
				notes.append("HP+%d" % gained)
			"max_hp":
				player_max_hp += amount
				player_hp = max(1, player_hp + amount)
				notes.append("最大HP%+d" % amount)
			"self_damage":
				player_hp -= amount
				notes.append("HP-%d" % amount)
			"die":
				dice_bag.append(_make_die(str(eff["id"])))
				notes.append("%sダイスを入手" % str(dice_defs[str(eff["id"])]["name"]))
			"random_die":
				var pool := die_reward_pool.duplicate()
				pool.shuffle()
				dice_bag.append(_make_die(str(pool[0])))
				notes.append("%sダイスを入手" % str(dice_defs[str(pool[0])]["name"]))
	hp_bar.display_value = float(player_hp)
	sfx.emit("reward")
	_refresh_top()
	if player_hp <= 0:
		_show_game_over("道中で力尽きました。")
		return
	_open_overlay(_t(choice["label"]), " / ".join(notes) if not notes.is_empty() else "何も起きなかった。")
	_add_overlay_option("地図に戻る", "次の層を選びます。", COL_HP, "boot", Callable(self, "_leave_node"))
	_layout_overlay()

func _leave_node() -> void:
	_close_overlay()
	_show_map()

# Events are pure data: a body, and choices whose effects are a list of ops
# run by _take_event_choice. Adding one is a row here.
var event_defs := {
	"shrine": {"name": "打ち捨てられた祠", "body": "供物を求める祠がある。金貨を投げ入れれば、何かが応えるかもしれない。",
		"choices": [
			{"label": "20G を捧げる", "detail": "ダイスを1つ授かる", "color": Color("#C9A227"), "icon": "dice",
				"effects": [{"op": "gold", "amount": -20}, {"op": "random_die"}]},
			{"label": "立ち去る", "detail": "何も起きない", "color": Color("#6B5C49"), "icon": "boot",
				"effects": []},
		]},
	"spring": {"name": "湧き水", "body": "澄んだ水が湧いている。飲めば傷が癒えそうだ。",
		"choices": [
			{"label": "飲む", "detail": "HP+12", "color": Color("#3EA95E"), "icon": "heal",
				"effects": [{"op": "heal", "amount": 12}]},
			{"label": "水を汲んで売る", "detail": "+18G", "color": Color("#C9A227"), "icon": "dice",
				"effects": [{"op": "gold", "amount": 18}]},
		]},
	"bargain": {"name": "怪しい行商", "body": "フードの奥は見えない。「いい取引がある」とだけ言う。",
		"choices": [
			{"label": "血を分ける", "detail": "HP-8 と引き換えにダイスを1つ", "color": Color("#9C3A6B"), "icon": "skull",
				"effects": [{"op": "self_damage", "amount": 8}, {"op": "random_die"}]},
			{"label": "鍛えてもらう", "detail": "最大HP+6", "color": Color("#2E7BD6"), "icon": "guard",
				"effects": [{"op": "max_hp", "amount": 6}]},
			{"label": "断る", "detail": "何も起きない", "color": Color("#6B5C49"), "icon": "boot",
				"effects": []},
		]},
	"cache": {"name": "隠し袋", "body": "岩陰に袋が押し込まれている。持ち主はもういないだろう。",
		"choices": [
			{"label": "金を取る", "detail": "+30G", "color": Color("#C9A227"), "icon": "dice",
				"effects": [{"op": "gold", "amount": 30}]},
			{"label": "中のダイスを取る", "detail": "ダイスを1つ", "color": Color("#5B8C2A"), "icon": "focus",
				"effects": [{"op": "random_die"}]},
		]},
	"altar": {"name": "血の祭壇", "body": "刃の跡が残る石。力を求めるなら、代価がいる。",
		"choices": [
			{"label": "捧げる", "detail": "最大HP-5、ダイスを1つ", "color": Color("#C2453A"), "icon": "trap",
				"effects": [{"op": "max_hp", "amount": -5}, {"op": "random_die"}]},
			{"label": "祈るだけにする", "detail": "HP+8", "color": Color("#3EA95E"), "icon": "heal",
				"effects": [{"op": "heal", "amount": 8}]},
		]},
}

func _continue_run() -> void:
	_close_overlay()
	if _load_run():
		return
	# A save that will not load is worse than none: drop it and go back to
	# the title rather than leaving a button that does nothing.
	_delete_run_save()
	_show_title()

# --- settings -----------------------------------------------------------
# Volume only, for now. Reachable from the title and from the 図鑑 sheet, so
# it is available mid-run without abandoning the climb.
func _show_settings() -> void:
	settings_return_state = state
	state = "settings"
	_open_overlay(tr("設定"), tr("音量を調整します。設定は自動的に保存されます。"))
	_add_volume_row("効果音", "sfx")
	_add_volume_row("BGM", "bgm")
	_add_locale_row()
	var close_button := Button.new()
	close_button.text = tr("閉じる")
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(0, 44)
	close_button.add_theme_font_size_override("font_size", FS_BODY)
	_style_button(close_button, COL_GOLD, COL_INK)
	close_button.add_theme_color_override("font_color", COL_INK)
	close_button.pressed.connect(Callable(self, "_close_settings"))
	overlay_list.add_child(close_button)
	_layout_overlay()

func _add_volume_row(label_text: String, which: String) -> void:
	var value: float = sfx_volume if which == "sfx" else bgm_volume
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _flat_style(COL_PANEL_SUNK, COL_INK, 2, 10, 8))
	overlay_list.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)

	var caption := _make_label(FS_BODY, COL_TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	caption.text = "%s  %d%%" % [label_text, int(round(value * 100.0))]
	caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	col.add_child(caption)

	# Buttons rather than a Slider: this UI is built for touch, and five
	# fixed steps are far easier to hit than a thin drag target.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	col.add_child(row)
	for step in range(5):
		var level: float = float(step) / 4.0
		var button := Button.new()
		button.text = "%d" % int(round(level * 100.0))
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 38)
		button.add_theme_font_size_override("font_size", FS_SMALL)
		var chosen: bool = absf(level - value) < 0.13
		_style_button(button, COL_GOLD if chosen else COL_PANEL, COL_INK)
		button.add_theme_color_override("font_color", COL_INK)
		button.pressed.connect(Callable(self, "_set_volume").bind(which, level))
		row.add_child(button)

func _add_locale_row() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _flat_style(COL_PANEL_SUNK, COL_INK, 2, 10, 8))
	overlay_list.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	var caption := _make_label(FS_BODY, COL_TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	caption.text = tr("言語 / Language")
	caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	col.add_child(caption)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	col.add_child(row)
	for entry in [["ja", "日本語"], ["en", "English"]]:
		var code := str(entry[0])
		var button := Button.new()
		button.text = str(entry[1])
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 38)
		button.add_theme_font_size_override("font_size", FS_SMALL)
		_style_button(button, COL_GOLD if code == locale else COL_PANEL, COL_INK)
		button.add_theme_color_override("font_color", COL_INK)
		button.pressed.connect(Callable(self, "_set_locale").bind(code))
		row.add_child(button)

func _set_locale(code: String) -> void:
	locale = code
	_apply_locale()
	_save_profile()
	_show_settings()

func _set_volume(which: String, level: float) -> void:
	if which == "sfx":
		sfx_volume = level
	else:
		bgm_volume = level
	_apply_audio_settings()
	_save_profile()
	if which == "sfx":
		sfx.emit("step")
	_show_settings()

func _close_settings() -> void:
	state = settings_return_state
	if state == "title":
		_show_title()
		return
	_close_overlay()
	if state == "map":
		_show_map()
	else:
		_refresh_all()

# --- scenes and the gallery ---------------------------------------------
# A fight ends in a picture. That is the whole contract: the board decides
# who won, and the scene layer shows what that meant, once, full frame.
# Everything below is the plumbing for that one sentence — which slot to
# show, remembering that it was shown, and letting the player see it again
# afterwards.

const CG_STATE_TEXT := {"win": "勝利", "lose": "敗北"}

# The art id and display name of the fight in progress, kept separately from
# `enemies` because the scene plays *after* the loser has been cleared off
# the board.
var encounter_art := "unknown"
var encounter_name := ""

func _play_scene(actor: String, art_state: String, caption: String, after: Callable) -> void:
	scene_after = after
	# Reaching a scene is what unlocks it, whether or not its file exists
	# yet — so once art lands, a player's gallery already reflects every
	# fight they have actually finished.
	if _unlock("cg:%s:%s" % [actor, art_state]):
		_bump_lifetime("scenes")
	scene_caption.text = caption
	_show_art(scene_sprite, "cg", actor, [art_state], false)
	scene_layer.visible = true

func _dismiss_scene() -> void:
	if scene_layer == null or not scene_layer.visible:
		return
	scene_layer.visible = false
	var next := scene_after
	scene_after = Callable()
	if next.is_valid():
		next.call()

# Every scene the game can contain, unlocked or not. Derived from the enemy
# table rather than listed by hand, so a new enemy brings its gallery rows
# with it.
func _gallery_entries() -> Array:
	var out := []
	for raw in enemy_defs:
		var def: Dictionary = raw
		for art_state in ART_CG_STATES:
			out.append({
				"actor": str(def.get("art", "unknown")),
				"state": str(art_state),
				"name": _t(def["name"]),
				"key": "cg:%s:%s" % [str(def.get("art", "unknown")), str(art_state)],
			})
	return out

func _show_gallery() -> void:
	gallery_return_state = state
	state = "gallery"
	_close_overlay()
	var entries := _gallery_entries()
	var found := 0
	for raw in entries:
		if _is_unlocked(str((raw as Dictionary)["key"])):
			found += 1
	gallery_title.text = tr("回想　%d / %d") % [found, entries.size()]
	_clear_children(gallery_grid)
	for raw in entries:
		gallery_grid.add_child(_make_gallery_cell(raw))
	_refresh_all()

func _make_gallery_cell(entry: Dictionary) -> Control:
	var open: bool = _is_unlocked(str(entry["key"]))
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(160, 122)
	panel.add_theme_stylebox_override("panel",
		_flat_style(COL_PANEL_SUNK if open else Color("#C4B394"), COL_INK, 2, 5, 5))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)

	if open:
		var thumb := SpriteView.new()
		thumb.custom_minimum_size = Vector2(0, 84)
		thumb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(thumb)
		_show_art(thumb, "cg", str(entry["actor"]), [str(entry["state"])], false)
	else:
		# A locked cell is a blank plate, not a dimmed picture: the point of
		# the grid is that the player can count what they have not seen.
		var blank := PanelContainer.new()
		blank.custom_minimum_size = Vector2(0, 84)
		blank.add_theme_stylebox_override("panel", _flat_style(Color("#8E7F66"), COL_INK, 2, 0, 0))
		blank.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(blank)
		var lock := _make_label(FS_HEAD, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER, true)
		lock.text = "？"
		lock.size_flags_vertical = Control.SIZE_EXPAND_FILL
		lock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		blank.add_child(lock)

	var caption := _make_label(FS_SMALL, COL_TEXT if open else COL_TEXT_SOFT, HORIZONTAL_ALIGNMENT_CENTER, true)
	caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	caption.text = _scene_title(entry) if open else tr("未開放")
	col.add_child(caption)

	if open:
		var hit := Button.new()
		hit.flat = true
		hit.focus_mode = Control.FOCUS_NONE
		hit.pressed.connect(Callable(self, "_replay_scene").bind(entry))
		panel.add_child(hit)
	return panel

func _scene_title(entry: Dictionary) -> String:
	var art_state := str(entry["state"])
	return "%s・%s" % [str(entry["name"]), _t(CG_STATE_TEXT.get(art_state, art_state))]

func _replay_scene(entry: Dictionary) -> void:
	_play_scene(str(entry["actor"]), str(entry["state"]), _scene_title(entry), Callable())

func _close_gallery() -> void:
	state = gallery_return_state
	if state == "title":
		_show_title()
		return
	if state == "map":
		_show_map()
		return
	_refresh_all()

# --- localisation -------------------------------------------------------
# Every string bound for the screen goes through _t. The Japanese text is
# its own translation key, so an untranslated build returns it unchanged —
# wrapping is behaviour-preserving — and no key names have to be invented
# for 483 strings. The CSV is generated from source by
# tools/extract_strings.py rather than maintained by hand, which is what
# lets the content tables keep churning without translation bookkeeping.
#
# Data-table text is wrapped where it is *read*, not where it is defined:
# 30 read sites cover all 315 strings in tile_defs/dice_defs/event_defs/
# hero_defs, and any content added later is localisable for free.
func _t(value) -> String:
	return tr(str(value))

# --- art loading ---------------------------------------------------------
# Slots resolve to files here and nowhere else. Results are cached — both
# hits and misses — because the answer cannot change while the game runs
# and a miss otherwise costs a filesystem probe every frame a placeholder
# is on screen.

var _art_cache: Dictionary = {}

func _art_slot(kind: String, actor: String, state: String) -> String:
	return "%s/%s/%s" % [kind, actor, state]

func _art_frames(kind: String, actor: String, state: String) -> Array:
	var slot := _art_slot(kind, actor, state)
	if _art_cache.has(slot):
		return _art_cache[slot]
	var dir := str((ART_KINDS.get(kind, {}) as Dictionary).get("dir", kind))
	var base := "%s/%s/%s_%s" % [ART_ROOT, dir, actor, state]
	var frames := []
	# A still and a numbered sequence are the same thing to the caller; a
	# lone "<slot>.png" is just a one-frame clip.
	if ResourceLoader.exists("%s.png" % base, "Texture2D"):
		frames.append(load("%s.png" % base))
	else:
		for i in range(ART_MAX_FRAMES):
			var path := "%s_%d.png" % [base, i]
			if not ResourceLoader.exists(path, "Texture2D"):
				break
			frames.append(load(path))
	_art_cache[slot] = frames
	return frames

func _has_art(kind: String, actor: String, state: String) -> bool:
	return not _art_frames(kind, actor, state).is_empty()

func _art_fps(kind: String) -> float:
	return float((ART_KINDS.get(kind, {}) as Dictionary).get("fps", 12.0))

# Show a slot in a view, falling back down a chain of states so a character
# with only an idle drawn still animates *something* rather than flipping
# to a placeholder the moment it is hit.
func _show_art(view: SpriteView, kind: String, actor: String, states: Array, loop: bool = true) -> bool:
	if view == null or states.is_empty():
		return false
	for state in states:
		var frames := _art_frames(kind, actor, str(state))
		if not frames.is_empty():
			view.play(frames, _art_slot(kind, actor, str(state)), _art_fps(kind), loop)
			view.visible = true
			return true
	# Nothing in the chain exists. A slot that must be filled says so at the
	# top of its voice, naming the state that was actually wanted rather
	# than the last one tried; a slot that has a standing fallback simply
	# gets out of the way and lets the fallback show through.
	if bool((ART_KINDS.get(kind, {}) as Dictionary).get("placeholder", true)):
		view.play([], _art_slot(kind, actor, str(states[0])), _art_fps(kind), loop)
		view.visible = true
	else:
		view.play([], "", _art_fps(kind), loop)
		view.visible = false
	return false

# The actor id for whatever the player is currently fighting, and for the
# player themselves. Both fall back to a fixed id so a half-filled data
# table still resolves to a slot instead of to an empty string.
func _enemy_art_id() -> String:
	if enemies.is_empty():
		return encounter_art
	return str((enemies[0] as Dictionary).get("art", encounter_art))

func _hero_art_id() -> String:
	if hero_key == "" or not hero_defs.has(hero_key):
		return "hero"
	return str((hero_defs[hero_key] as Dictionary).get("art", "hero"))

# --- persistence --------------------------------------------------------
# Two files, because they have different lifetimes. The profile outlives
# every run and holds settings plus whatever the player has permanently
# unlocked; the run file is the current climb and is deleted the moment it
# ends. JSON rather than ConfigFile because the run is a nested structure
# (a whole map, a board, a bag) and ConfigFile flattens badly.
const PROFILE_PATH := "user://profile.json"
const RUN_PATH := "user://run.json"
const SAVE_VERSION := 2

var sfx_volume: float = 0.8
var bgm_volume: float = 0.7
var locale := "ja"
# Permanent unlocks, keyed by a string the caller invents ("enemy:はぐれ兵").
# Phase 4's gallery reads this; nothing writes it yet except _unlock.
var unlocked: Dictionary = {}
var lifetime: Dictionary = {}

func _load_profile() -> void:
	var data := _read_json(PROFILE_PATH)
	if data.is_empty():
		return
	sfx_volume = clampf(float(data.get("sfx_volume", sfx_volume)), 0.0, 1.0)
	bgm_volume = clampf(float(data.get("bgm_volume", bgm_volume)), 0.0, 1.0)
	locale = str(data.get("locale", locale))
	unlocked = data.get("unlocked", {})
	lifetime = data.get("lifetime", {})

func _save_profile() -> void:
	_write_json(PROFILE_PATH, {
		"version": SAVE_VERSION,
		"sfx_volume": sfx_volume,
		"bgm_volume": bgm_volume,
		"locale": locale,
		"unlocked": unlocked,
		"lifetime": lifetime,
	})

func _unlock(key: String) -> bool:
	if unlocked.has(key):
		return false
	unlocked[key] = true
	_save_profile()
	return true

func _is_unlocked(key: String) -> bool:
	return unlocked.has(key)

func _bump_lifetime(key: String, amount: int = 1) -> void:
	lifetime[key] = int(lifetime.get(key, 0)) + amount

func _apply_locale() -> void:
	TranslationServer.set_locale(locale)

func _apply_audio_settings() -> void:
	if sfx == null:
		return
	sfx.enabled = sfx_volume > 0.0
	# -9 dB was the hand-tuned level for "full"; scale down from there and
	# mute outright at zero rather than trailing off into -80.
	sfx.volume_db = -80.0 if sfx_volume <= 0.0 else linear_to_db(sfx_volume) - 9.0

# --- run save ---
# Saved at map level only. A node records that it was entered *before* it
# resolves, so quitting mid-fight and reloading drops the player back into
# that same node rather than back onto the map with a free re-pick.
func _has_run_save() -> bool:
	return FileAccess.file_exists(RUN_PATH)

func _delete_run_save() -> void:
	if _has_run_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RUN_PATH))
		# globalize_path does not resolve user:// on every platform, so try
		# the virtual path too — one of the two always lands.
		if _has_run_save():
			DirAccess.open("user://").remove("run.json")

func _save_run(node_in_progress: bool = false) -> void:
	if hero_key == "":
		return
	var bag := []
	for die in dice_bag:
		bag.append(str(die["id"]))
	var board := []
	for row in permanent_board:
		board.append((row as Array).duplicate())
	_write_json(RUN_PATH, {
		"version": SAVE_VERSION,
		"hero": hero_key,
		"hp": player_hp,
		"max_hp": player_max_hp,
		"hand_limit": hand_limit,
		"actions": actions_per_turn,
		"gold": gold,
		"step": player_step,
		"damage": run_damage_dealt,
		"turns": run_turns,
		"bag": bag,
		"board": board,
		"map": _serialize_map(),
		"map_row": map_row,
		"map_col": map_col,
		"in_node": node_in_progress,
	})

func _serialize_map() -> Array:
	var rows := []
	for row in range(MAP_ROWS):
		var cells := []
		for col in range(MAP_COLS):
			var node = map_nodes[row][col]
			if node == null:
				cells.append(null)
				continue
			var links := []
			for key in (node["links"] as Dictionary).keys():
				links.append(int(key))
			cells.append({
				"type": str(node["type"]),
				"enemy": int(node.get("enemy", -1)),
				"cleared": bool(node.get("cleared", false)),
				"links": links,
			})
		rows.append(cells)
	return rows

func _deserialize_map(rows: Array) -> void:
	map_nodes = []
	for row in range(MAP_ROWS):
		var cells := []
		for col in range(MAP_COLS):
			var raw = rows[row][col] if row < rows.size() and col < (rows[row] as Array).size() else null
			if raw == null:
				cells.append(null)
				continue
			var links := {}
			for c in (raw as Dictionary).get("links", []):
				links[int(c)] = true
			cells.append({
				"row": row, "col": col,
				"type": str((raw as Dictionary).get("type", "battle")),
				"enemy": int((raw as Dictionary).get("enemy", -1)),
				"cleared": bool((raw as Dictionary).get("cleared", false)),
				"links": links,
			})
		map_nodes.append(cells)

func _load_run() -> bool:
	var data := _read_json(RUN_PATH)
	if data.is_empty() or int(data.get("version", 0)) != SAVE_VERSION:
		return false
	var key := str(data.get("hero", ""))
	if not hero_defs.has(key):
		return false
	hero_key = key
	var hero: Dictionary = hero_defs[key]
	hero_name = _t(hero["name"])
	hero_token_color = Color(hero["color"])
	player_max_hp = int(data.get("max_hp", hero["hp"]))
	player_hp = int(data.get("hp", player_max_hp))
	hand_limit = int(data.get("hand_limit", hero.get("hand", 3)))
	actions_per_turn = int(data.get("actions", ACTIONS_PER_TURN))
	gold = int(data.get("gold", 0))
	player_step = int(data.get("step", 0))
	run_damage_dealt = int(data.get("damage", 0))
	run_turns = int(data.get("turns", 0))
	player_pos = _pos_for_step(player_step)

	dice_bag = []
	for id in data.get("bag", []):
		if dice_defs.has(str(id)):
			dice_bag.append(_make_die(str(id)))
	if dice_bag.is_empty():
		return false

	permanent_board = _make_empty_board("empty")
	var board: Array = data.get("board", [])
	for y in range(min(board.size(), BOARD_H)):
		var row: Array = board[y]
		for x in range(min(row.size(), BOARD_W)):
			if tile_defs.has(str(row[x])):
				permanent_board[y][x] = str(row[x])

	_deserialize_map(data.get("map", []))
	if map_nodes.is_empty():
		return false
	map_row = int(data.get("map_row", -1))
	map_col = int(data.get("map_col", 0))
	temp_board = _make_empty_board("none")
	enemies = []
	next_enemy_uid = 0
	hp_bar.display_value = float(player_hp)
	_snap_player_visual()

	# Mid-node when the game was closed: re-enter that node rather than
	# handing back a free choice on the map.
	if bool(data.get("in_node", false)) and map_row >= 0:
		_enter_map_node()
	else:
		_show_map()
	return true

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}

func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("could not write %s" % path)
		return
	file.store_string(JSON.stringify(data))
	file.close()

# --- the run map --------------------------------------------------------
# A column of rows the player climbs one step at a time, bottom to top,
# choosing between the nodes each row offers. Combat nodes name their enemy
# on the map rather than hiding it, because steering toward a particular
# fight is the whole point of having a map.
#
# The map is generated by carving paths rather than by scattering nodes and
# hoping they connect: a handful of walkers each climb from the bottom row
# to the top, stepping at most one column sideways per row, and only the
# cells a walker touched become real nodes. Connectivity, and "every node
# can still reach the boss", are therefore true by construction — no repair
# pass, and no possibility of a dead end.
const MAP_ROWS := 12          # row 0 is the first choice, row 11 is the boss
const MAP_COLS := 3
const MAP_WALKERS := 4        # paths carved; more walkers = wider map

const NODE_DEFS := {
	"battle": {"label": "戦闘", "color": Color("#C2453A"), "icon": "slash"},
	"elite": {"label": "強敵", "color": Color("#8E2F6B"), "icon": "skull"},
	"rest": {"label": "休憩", "color": Color("#3EA95E"), "icon": "heal"},
	"shop": {"label": "店", "color": Color("#C9A227"), "icon": "dice"},
	"event": {"label": "イベント", "color": Color("#4F8C8A"), "icon": "focus"},
	"boss": {"label": "ボス", "color": Color("#8E2F6B"), "icon": "enemy_boss"},
}

# Row -> what may appear there, as a weighted bag. The early rows are plain
# fights so the game gets taught before it gets complicated; 強敵 only turn
# up once there is a deck to beat them with; 休憩 get commoner as the run
# wears the player down. This lands around 7 fights in the 12 stops.
const NODE_WEIGHTS := [
	{"battle": 1},                                        # row 0
	{"battle": 4, "event": 2},                            # row 1
	{"battle": 4, "event": 2, "shop": 1},                 # row 2
	{"battle": 4, "rest": 2, "event": 2},                 # row 3
	{"battle": 4, "elite": 1, "event": 2, "shop": 1},     # row 4
	{"battle": 3, "elite": 2, "rest": 2, "event": 2},     # row 5
	{"battle": 3, "elite": 2, "event": 2, "shop": 2},     # row 6
	{"battle": 3, "elite": 2, "rest": 3, "event": 2},     # row 7
	{"battle": 3, "elite": 3, "event": 2, "shop": 1},     # row 8
	{"battle": 3, "elite": 3, "rest": 3, "event": 1},     # row 9
	{"rest": 3, "shop": 2},                               # row 10 — before the boss
	{"boss": 1},                                          # row 11
]

var map_nodes: Array = []          # [row][col] -> node Dictionary, or null
var map_row := -1                  # -1 = the run has not entered the map yet
var map_col := 0

func _generate_map() -> void:
	map_nodes = []
	for row in range(MAP_ROWS):
		var cells := []
		for col in range(MAP_COLS):
			cells.append(null)
		map_nodes.append(cells)
	map_row = -1
	map_col = 0

	for w in range(MAP_WALKERS):
		var col := rng.randi_range(0, MAP_COLS - 1)
		var prev_col := -1
		for row in range(MAP_ROWS):
			# The boss row is one node wide, so every walker funnels into it.
			var here: int = 1 if row == MAP_ROWS - 1 else col
			_ensure_map_node(row, here)
			if prev_col >= 0:
				(map_nodes[row - 1][prev_col] as Dictionary)["links"][here] = true
			prev_col = here
			if row < MAP_ROWS - 1:
				col = clampi(here + rng.randi_range(-1, 1), 0, MAP_COLS - 1)

	for row in range(MAP_ROWS):
		for col in range(MAP_COLS):
			var node = map_nodes[row][col]
			if node == null:
				continue
			node["type"] = _pick_node_type(row)
			if node["type"] in ["battle", "elite", "boss"]:
				node["enemy"] = _pick_enemy_for(row, str(node["type"]))

func _ensure_map_node(row: int, col: int) -> void:
	if map_nodes[row][col] == null:
		map_nodes[row][col] = {
			"row": row, "col": col, "type": "battle", "enemy": -1,
			"links": {}, "cleared": false,
		}

func _pick_node_type(row: int) -> String:
	var weights: Dictionary = NODE_WEIGHTS[clampi(row, 0, NODE_WEIGHTS.size() - 1)]
	var total := 0
	for key in weights.keys():
		total += int(weights[key])
	var roll := rng.randi_range(1, max(total, 1))
	for key in weights.keys():
		roll -= int(weights[key])
		if roll <= 0:
			return str(key)
	return "battle"

# Enemies are drawn from the same table as before, but indexed by how far up
# the map the fight sits rather than by a global counter — so two runs that
# take different routes meet different rosters.
func _pick_enemy_for(row: int, kind: String) -> int:
	var last: int = enemy_defs.size() - 1
	if kind == "boss":
		return last
	var span: float = float(row) / float(max(MAP_ROWS - 2, 1))
	var base: int = int(round(span * float(last - 1)))
	if kind == "elite":
		base += 1
	return clampi(base, 0, last - 1)

func _is_boss_node() -> bool:
	var node = _map_node_at(map_row, map_col)
	return node != null and str(node.get("type", "")) == "boss"

func _map_node_at(row: int, col: int):
	if row < 0 or row >= MAP_ROWS or col < 0 or col >= MAP_COLS:
		return null
	return map_nodes[row][col]

# What the player may enter next: any node on the bottom row before the run
# has started, otherwise whatever the current node links up to.
func _map_reachable() -> Array:
	var out := []
	if map_nodes.is_empty():
		return out
	if map_row < 0:
		for col in range(MAP_COLS):
			if map_nodes[0][col] != null:
				out.append(Vector2i(col, 0))
		return out
	var node = _map_node_at(map_row, map_col)
	if node == null:
		return out
	for col in (node["links"] as Dictionary).keys():
		if _map_node_at(map_row + 1, int(col)) != null:
			out.append(Vector2i(int(col), map_row + 1))
	return out

func _is_map_reachable(row: int, col: int) -> bool:
	for p in _map_reachable():
		if p.x == col and p.y == row:
			return true
	return false

func _setup_encounter() -> void:
	# Which enemy is decided by the map node the player walked into, not by
	# a global counter — that is what makes choosing a route mean something.
	var node = _map_node_at(map_row, map_col)
	var index: int = enemy_defs.size() - 1
	if node != null and int(node.get("enemy", -1)) >= 0:
		index = clampi(int(node["enemy"]), 0, enemy_defs.size() - 1)
	var def: Dictionary = enemy_defs[index]
	var enemy := _make_enemy(
		_t(def["name"]), int(def["hp"]), int(def["damage"]),
		_t(def["kind"]), str(def["mode"]), def["cells"])
	# The art id travels with the fight, so the stage and the resolution
	# scene both know who is on screen without re-deriving it from a
	# translated display name.
	enemy["art"] = str(def.get("art", "unknown"))
	encounter_art = str(enemy["art"])
	encounter_name = str(enemy["type"])
	scene_played_this_fight = false
	for trait_key in ["armor", "regen", "thorns", "gold", "foul"]:
		if def.has(trait_key):
			enemy[trait_key] = int(def[trait_key])
	enemy["debuff"] = str(def.get("debuff", ""))
	if node != null and str(node.get("type", "")) == "elite":
		enemy["max_hp"] = int(enemy["max_hp"]) * 3 / 2
		enemy["hp"] = int(enemy["max_hp"])
		enemy["damage"] = int(enemy["damage"]) + 2
		enemy["gold"] = int(enemy["gold"]) * 2
		enemy["type"] = "%s（強敵）" % str(enemy["type"])
	enemies.append(enemy)

	# The board starts already fouled deeper into the run, in whatever the
	# enemy standing there deals — so a fight's terrain reads as belonging
	# to that enemy from the first turn rather than only after it acts.
	var seed_kind := str(enemies[0].get("debuff", "")) if not enemies.is_empty() else ""
	if seed_kind != "":
		for n in range(clamp(map_row / 3, 0, MAX_DEBUFFS - 1)):
			var p := _random_empty_cell()
			if p.x >= 0:
				temp_board[p.y][p.x] = seed_kind

	for e in enemies:
		_generate_telegraph(e)

func _enemy_trait_text(enemy: Dictionary) -> String:
	var parts := []
	for trait_key in ["armor", "regen", "thorns"]:
		var amount := int(enemy.get(trait_key, 0))
		if amount > 0:
			parts.append(str(ENEMY_TRAIT_TEXT[trait_key]) % [amount, amount])
	return " / ".join(parts)

func _make_enemy(type_name: String, hp: int, damage: int, attack_kind: String, telegraph_mode: String, cell_spec: Array) -> Dictionary:
	next_enemy_uid += 1
	return {
		"type": type_name,
		"uid": next_enemy_uid,
		"hp": hp,
		"max_hp": hp,
		"damage": damage,
		"attack_kind": attack_kind,
		"poison": 0,
		"armor": 0,
		"regen": 0,
		"thorns": 0,
		"gold": 0,
		"telegraph_mode": telegraph_mode,
		# Only one of these is ever read, picked by telegraph_mode — kept
		# as two named fields instead of one ambiguous "offsets" so a
		# glance at the dictionary says which kind of number it holds.
		"attack_offsets": cell_spec if telegraph_mode == "relative" else [],
		"attack_steps": cell_spec if telegraph_mode == "fixed" else [],
		"telegraph_cells": [],
	}

func _generate_telegraph(enemy: Dictionary) -> void:
	if str(enemy.get("attack_kind", "cell")) == "guaranteed":
		enemy["telegraph_cells"] = []
		return
	var cells: Array = []
	if str(enemy.get("telegraph_mode", "relative")) == "fixed":
		for step in enemy.get("attack_steps", []):
			cells.append(_pos_for_step(int(step)))
	else:
		for offset in enemy.get("attack_offsets", []):
			cells.append(_pos_for_step(player_step + int(offset)))
	enemy["telegraph_cells"] = cells

func _reset_dice_for_encounter() -> void:
	draw_pile = []
	discard_pile = []
	hand = []
	for die in dice_bag:
		draw_pile.append(die.duplicate(true))
	draw_pile.shuffle()
	_draw_to_hand()

func _start_player_turn(message: String = "") -> void:
	state = "player"
	run_turns += 1
	player_shield = 0
	actions_left = actions_per_turn
	selected_die = {}
	selected_roll = 0
	steps_left = 0
	route_path = []
	combo = 0
	action_index = 0
	crossed_this_action = 0
	move_dir = 1
	dice_rolled = false
	rerolls_left = REROLLS_PER_TURN
	preview_die_index = -1
	# Every square banks a turn of waiting. Squares that reference charge
	# are the only ones that will ever spend it, but the clock runs on all
	# of them so that walking away from a battery is what loads it.
	for cell in ring_cells:
		_set_cell_charge(cell, _cell_charge(cell) + 1)
	hand_slots = []
	if hand_scroll != null:
		hand_scroll.scroll_horizontal = 0
	_draw_to_hand()
	for die in hand:
		die["roll"] = 0
	if message != "":
		_set_log(message)
	_refresh_all()
	_set_banner(tr("タップしてダイスを振る"))

func _draw_to_hand() -> void:
	while hand.size() < hand_limit:
		if draw_pile.is_empty():
			if discard_pile.is_empty():
				break
			draw_pile = discard_pile.duplicate(true)
			discard_pile = []
			draw_pile.shuffle()
		var drawn: Dictionary = draw_pile.pop_back()
		drawn["roll"] = _random_face(drawn) if dice_rolled else 0
		hand.append(drawn)

# --- player turn -------------------------------------------------------

func _random_face(die: Dictionary) -> int:
	var faces: Array = die["faces"]
	return int(faces[rng.randi_range(0, faces.size() - 1)])

# Rolls the whole hand at once. The first roll of a turn is free; after
# that it costs the turn's single reroll, and a reroll re-rolls everything
# still in hand rather than letting the player fish with one die.
func _roll_hand(is_reroll: bool) -> void:
	if state != "player" or hand.is_empty():
		return
	if is_reroll:
		if rerolls_left <= 0:
			return
		rerolls_left -= 1
	dice_rolled = true
	# Every face on the table just changed, so whatever was being considered
	# is no longer the move it was.
	preview_die_index = -1
	_hide_banner()
	sfx.emit("roll")
	for die in hand:
		die["roll"] = _random_face(die)
	_refresh_hand()
	_refresh_board()
	_refresh_command()
	await _animate_hand_roll()
	_refresh_all()

# Every die tumbles at once but settles in turn, so three results land as
# three separate beats instead of one indistinguishable flicker.
func _animate_hand_roll() -> void:
	var faces_by_slot := []
	for i in range(hand_slots.size()):
		faces_by_slot.append(_slot_face(i))
	var frames := 7
	for step in range(frames):
		for i in range(faces_by_slot.size()):
			var face: DiceFace = faces_by_slot[i]
			if face == null:
				continue
			# Later slots keep tumbling for a few extra frames.
			if step >= frames - 2 + i - 1 and i < hand.size():
				face.value = int(hand[i]["roll"])
			elif i < hand.size():
				face.value = _random_face(hand[i])
			face.rotation = deg_to_rad(rng.randf_range(-16.0, 16.0)) * (1.0 - float(step) / float(frames))
			face.queue_redraw()
		await get_tree().create_timer(0.05).timeout
	for i in range(faces_by_slot.size()):
		var settled: DiceFace = faces_by_slot[i]
		if settled == null or i >= hand.size():
			continue
		settled.value = int(hand[i]["roll"])
		settled.rotation = 0.0
		settled.queue_redraw()
		_punch(settled, 1.25)
		sfx.emit("step")
		await get_tree().create_timer(0.07).timeout

func _slot_face(index: int) -> DiceFace:
	if index >= hand_slots.size():
		return null
	var slot: Control = hand_slots[index]
	if slot.get_child_count() == 0:
		return null
	return slot.get_child(0).find_child("RolledFace", true, false) as DiceFace

func _on_roll_area_pressed() -> void:
	if state == "player" and not dice_rolled:
		await _roll_hand(false)

func _on_reroll_pressed() -> void:
	if state == "player" and dice_rolled and rerolls_left > 0:
		await _roll_hand(true)

func _on_die_pressed(index: int) -> void:
	if state != "player" or index < 0 or index >= hand.size() or actions_left <= 0:
		return
	if not dice_rolled:
		await _roll_hand(false)
		return

	# First tap on a die is a question, not a move: it paints that die's route
	# and landing square, prints what the squares along it would actually pay
	# with this die's own multipliers applied, and says so in the log. Only a
	# second tap on the *same* die spends it. Tapping a different die moves
	# the question over to that one.
	if preview_die_index != index:
		preview_die_index = index
		sfx.emit("step")
		_set_log(_die_preview_text(index))
		# Deliberately no banner: it centres itself on the board and would
		# sit right on top of the lookahead row this preview exists to fill
		# in. The card the thumb is already touching says もう一度で確定 in
		# gold, which is both the affordance and where the player is looking.
		_refresh_all()
		return

	var die: Dictionary = hand[index]
	var final_roll := int(die.get("roll", 0))

	preview_die_index = -1
	_hide_banner()

	# Lock the state before the first await so a second tap during the move
	# cannot spend a second die.
	state = "moving"
	selected_die = die.duplicate(true)
	selected_roll = final_roll
	action_index += 1
	crossed_this_action = 0
	# The baseline every hero shares: combo counts dice spent this turn.
	# Nothing pays it out automatically — 連鎖路/連撃/供物台 and the rest
	# are what turn that count into something, which is the build.
	combo += 1
	route_path = [player_pos]
	discard_pile.append(selected_die)
	hand.remove_at(index)
	sfx.emit("hit")

	# The die's own effects fire before the piece moves, so a die that pays
	# combo or charge has already paid it by the time the squares are read.
	# Anything it charges lands on the square the piece is standing on.
	charge_cell = player_pos
	var spend_note := _run_effects(selected_die.get("effects", []), "spend", _t(selected_die["name"]))
	var roll_text := _warp_face_label(final_roll) if _is_warp_face(final_roll) else str(final_roll)
	_set_log(tr("%sダイス：出目 %s%s") % [
		_t(selected_die["name"]), roll_text, ("　" + spend_note) if spend_note != "" else ""])
	_refresh_all()
	await get_tree().create_timer(0.2).timeout

	if _is_warp_face(final_roll):
		await _warp_to_step(_warp_face_step(final_roll))
	else:
		# The roll's own sign is the direction: 逆走's faces are all
		# negative, so no separate "which way" field is needed anywhere
		# else in the movement code.
		move_dir = -1 if final_roll < 0 else 1
		steps_left = absi(final_roll)
		await _advance_player()

# The sentence the first tap prints: where this die puts you, what waits
# there, and what it costs to get there. Everything in it is derived from
# the same functions the move itself runs, so it cannot describe a move the
# game will not make.
func _die_preview_text(index: int) -> String:
	var die: Dictionary = hand[index]
	var roll := int(die.get("roll", 0))
	var warp: bool = _is_warp_face(roll)
	var route := _route_for_roll(roll)
	var landing: Vector2i = route[route.size() - 1]
	# 居合's 0 does not walk either: the action resolves on the square the
	# piece is already standing on.
	var walks: bool = not warp and roll != 0
	var crossed: int = route.size() if walks else 0
	# The readout context this text is about to ask questions against. The
	# board refresh that follows sets the same three from the same source;
	# doing it here means the sentence never reads a stale route.
	_readout_die = die
	_readout_route = route
	_readout_crossed = crossed

	var parts := []
	parts.append("%s：出目 %s" % [
		_t(die["name"]), _warp_face_label(roll) if warp else str(roll)])
	var power := str(die.get("short", ""))
	if power != "":
		parts.append(power)

	# What the square it stops on will do, with this die's own multipliers
	# already folded in — the number here is the number that will be dealt.
	var tile: Dictionary = tile_defs[str(permanent_board[landing.y][landing.x])]
	var stop_note := "停止効果なし"
	if _debuff_nullifies(landing):
		stop_note = "%sで不発。着地で溶かす" % _t(_debuff_at(landing)["name"])
	elif _tile_has_timing(tile, "stop"):
		stop_note = _t(tile["effect"])
		var readout := _tile_readout(tile, landing)
		if bool(readout.get("blocked", false)):
			stop_note = "%s（条件を満たさず不発）" % _t(tile["effect"])
		elif str(readout["text"]) != "":
			stop_note = "%s → %s" % [_t(tile["effect"]), str(readout["text"])]
	parts.append("着地：%s（%s）" % [_t(tile["name"]), stop_note])

	# The cost of the walk itself, totalled per debuff so three burning
	# squares read as one number rather than three warnings. The landing
	# square is charged at its stop rate and every earlier square at its
	# pass rate, which is the same split the move will actually apply.
	var toll := {}
	var ignored := {}
	for i in range(route.size()):
		var cell: Vector2i = route[i]
		var deb := _debuff_at(cell)
		if deb.is_empty():
			continue
		# The square an action ends on fires both halves — the walk enters
		# it and the action stops on it — so it is charged at whichever
		# rate its debuff uses. A warp never enters anything, so its one
		# square is charged at the stop rate alone.
		var timings := []
		if walks:
			timings.append("pass")
		if i == route.size() - 1:
			timings.append("stop")
		for timing in timings:
			var hurt := _debuff_damage(cell, str(timing), die)
			if hurt > 0:
				toll[_t(deb["name"])] = int(toll.get(_t(deb["name"]), 0)) + hurt
			elif int(deb.get("damage", 0)) > 0 and str(deb.get("on", "pass")) == str(timing):
				ignored[_t(deb["name"])] = true
	for name in toll.keys():
		parts.append("%s HP-%d" % [str(name), int(toll[name])])
	for name in ignored.keys():
		parts.append("%s（無効化）" % str(name))
	# 茨 already shortened the route, so saying so explains why the landing
	# is not where the die's number pointed.
	if _debuff_halts(landing) and walks:
		var unobstructed := _route_for_roll(roll, true).size()
		if unobstructed > route.size():
			parts.append("⚠ %sで停止（残り%d歩を失う）" % [
				_t(_debuff_at(landing)["name"]), unobstructed - route.size()])
	# Every frozen square on the route comes off it — the ones walked over
	# melt under the foot, the one landed on melts under the landing — so a
	# route worth nothing in damage can still be the one that clears the
	# ice. The board says where with its ×; a player weighing two dice is
	# asking how many.
	var thaws := {}
	var counted := {}
	for cell in route:
		if counted.has(cell) or not _debuff_nullifies(cell):
			continue
		counted[cell] = true
		var deb_name := _t(_debuff_at(cell)["name"])
		thaws[deb_name] = int(thaws.get(deb_name, 0)) + 1
	for deb_name in thaws.keys():
		parts.append("%s%d枚を溶かす" % [str(deb_name), int(thaws[deb_name])])
	if danger_cells.has(landing):
		parts.append("⚠ 敵の攻撃予告マス（%dダメージ）" % _telegraph_damage())
	if crossed > 0:
		parts.append("%dマス通過" % crossed)
	return " / ".join(parts)

func _advance_player() -> void:
	while steps_left > 0:
		player_step = _normalize_step(player_step + move_dir)
		player_pos = _pos_for_step(player_step)
		route_path.append(player_pos)
		steps_left -= 1
		crossed_this_action += 1
		sfx.emit("step")
		_refresh_board()
		await _animate_player_step(STEP_TIME)
		var pass_message := _resolve_pass_tile(player_pos)
		if pass_message != "":
			_set_log(pass_message)
		_refresh_all()
		if pass_message != "":
			await get_tree().create_timer(BEAT_EFFECT).timeout
		if player_hp <= 0:
			_show_game_over("移動の途中で倒れました。")
			return
		if not _any_enemy_alive():
			_finish_encounter()
			return
		# 茨 spends the rest of the roll. The square still resolves as a
		# stop — the piece did end its action here — so this drops straight
		# into the same tail every other move ends on.
		if _debuff_halts(player_pos):
			var lost := steps_left
			var trampled := _consume_debuff(player_pos, "halt")
			if trampled == "":
				trampled = "茨"
			steps_left = 0
			# Landing on one exactly is still trampling it; there were just
			# no steps left for it to take.
			if lost > 0:
				_set_log("%sに足を取られた。残り%d歩を失う" % [trampled, lost])
			else:
				_set_log("%sを踏み倒した" % trampled)
			_refresh_all()
			await get_tree().create_timer(BEAT_EFFECT).timeout
			break
	await _resolve_landing()

# A warp face (帰還's "帰", テレポート's four corners) skips the walk
# entirely — it is a jump, not a sweep, so nothing along the way fires and
# 疾走's crossed-count stays at zero. The square the player lands on still
# resolves normally, through the same _resolve_landing tail every ordinary
# move ends on.
func _warp_to_step(target_step: int) -> void:
	player_step = _normalize_step(target_step)
	player_pos = _pos_for_step(player_step)
	route_path.append(player_pos)
	sfx.emit("step")
	_refresh_board()
	await _animate_player_step(STEP_TIME * 1.4)
	await _resolve_landing()

# The tail every move shares once the piece has stopped moving: resolve the
# landing square, spend the action, and either hand control back to the
# player or pass to the enemy.
func _resolve_landing() -> void:
	var stop_message := _resolve_stop_tile(player_pos)
	if stop_message != "":
		_set_log(stop_message)
	actions_left -= 1
	_refresh_all()
	await get_tree().create_timer(BEAT_STOP).timeout
	if player_hp <= 0:
		_show_game_over("止まったマスで倒れました。")
		return
	if not _any_enemy_alive():
		_finish_encounter()
		return
	if actions_left <= 0 or hand.is_empty():
		state = "player"
		_refresh_all()
		await get_tree().create_timer(BEAT_PHASE).timeout
		await _enemy_turn()
	else:
		state = "player"
		_refresh_all()

func _finish_encounter() -> void:
	_cleanup_dead_enemies()
	_hide_banner()
	_set_log(tr("敵を倒した。マスの毒も消えた。") if last_cleanse_count > 0 else "敵を倒した。")
	# Long enough to watch the enemy actually die before the screen changes.
	await get_tree().create_timer(1.2).timeout
	# The picture comes before the loot. A fight resolves once, so this
	# fires once even if two code paths both notice the enemy is dead.
	if not scene_played_this_fight:
		scene_played_this_fight = true
		_play_scene(encounter_art, "win", tr("%s を下した") % encounter_name,
			Callable(self, "_show_reward"))
		return
	_show_reward()

func _resolve_pass_tile(pos: Vector2i) -> String:
	charge_cell = pos
	var messages := []
	var deb := _debuff_at(pos)
	var burn := _debuff_damage(pos, "pass", selected_die)
	if burn > 0:
		_take_damage(burn)
		messages.append("%sのマス：HP-%d" % [_t(deb["name"]), burn])
	elif not deb.is_empty() and int(deb.get("damage", 0)) > 0 \
			and str(deb.get("on", "pass")) == "pass" and bool(selected_die.get("pierce", false)):
		messages.append("%s：%sを無効化" % [str(selected_die.get("name", "")), _t(deb["name"])])
	var tile: Dictionary = tile_defs[str(permanent_board[pos.y][pos.x])]
	# A frozen square is not there as far as the walk is concerned.
	if _debuff_nullifies(pos):
		messages.append("%s：%sで効果が出ない" % [_t(tile["name"]), _t(deb["name"])])
	else:
		var effect := _run_effects(tile.get("effects", []), "pass", _t(tile["name"]))
		if effect != "":
			messages.append(effect)
	# 凍結 melts under a passing foot as well as a landing one — but only
	# where the foot really is passing. steps_left is already decremented
	# for this square, so zero means the action ends here, and there the
	# stop half is what melts it (see _resolve_stop_tile): thawing it now
	# would hand that landing the stop effect the ice is supposed to cost.
	if steps_left > 0:
		var melted := _consume_debuff(pos, "pass")
		if melted != "":
			messages.append("%sを踏み割った" % melted)
	return " ".join(messages)

func _resolve_stop_tile(pos: Vector2i) -> String:
	charge_cell = pos
	_flash_player_stop()
	var messages := []
	var deb := _debuff_at(pos)
	var venom := _debuff_damage(pos, "stop", selected_die)
	if venom > 0:
		_take_damage(venom)
		messages.append("%sのマス：HP-%d" % [_t(deb["name"]), venom])
	var tile: Dictionary = tile_defs[str(permanent_board[pos.y][pos.x])]
	# Read before the thaw: stopping on a frozen square is what melts it,
	# but the stop being melted is the price, so this landing still gets
	# nothing out of the square.
	var frozen := _debuff_nullifies(pos)
	if frozen:
		messages.append("%s：%sで効果が出ない" % [_t(tile["name"]), _t(deb["name"])])
	else:
		var effect := _run_effects(tile.get("effects", []), "stop", _t(tile["name"]))
		if effect != "":
			messages.append(effect)
		elif not _tile_has_timing(tile, "stop"):
			# A square with nothing to say on landing is not a punishment,
			# but the player still needs to know the stop was spent for
			# nothing.
			messages.append("%sに停止。通過型なので停止効果なし" % _t(tile["name"]))
		else:
			messages.append("%sに停止。条件を満たさず不発" % _t(tile["name"]))
	var thawed := _consume_debuff(pos, "stop")
	if thawed != "":
		messages.append("%sが解けた" % thawed)
	return " ".join(messages)

func _tile_has_timing(tile: Dictionary, timing: String) -> bool:
	for raw in tile.get("effects", []):
		if str((raw as Dictionary).get("on", "stop")) == timing:
			return true
	return false

# --- the effect engine -------------------------------------------------
# Everything a tile or a die does goes through here. No tile type and no
# die power is named anywhere in this code: adding content means adding a
# row to tile_defs or dice_defs, never a branch below.

# A counter an effect can scale its amount by. These are the spines of the
# build concepts — content that names one is content that belongs to that
# build.
func _cell_charge(cell: Vector2i) -> int:
	return int(charge_map.get(cell, 0))

func _set_cell_charge(cell: Vector2i, value: int) -> void:
	if ring_index_map.has(cell):
		charge_map[cell] = max(0, value)

func _scale_value(scale: String) -> int:
	match scale:
		"combo":
			return combo
		"charge":
			return _cell_charge(charge_cell)
		"shield":
			return player_shield
		"roll":
			return selected_roll
		"crossed":
			return crossed_this_action
		"poison":
			return _enemy_poison()
		"wounds":
			# HP already lost. The one counter the player starts a fight
			# with at zero and cannot spend — it only goes up, and the
			# 手負い squares are what make that climb worth something.
			return max(0, player_max_hp - player_hp)
	return 1

# Conditions may only read the player's own state. Gating on something the
# player cannot influence is how a board locks itself out of ever dealing
# damage, so there is deliberately no "enemy is at range" condition here.
func _cond_ok(cond: Dictionary) -> bool:
	if cond.is_empty():
		return true
	if cond.has("min_roll") and selected_roll < int(cond["min_roll"]):
		return false
	if cond.has("max_roll") and selected_roll > int(cond["max_roll"]):
		return false
	if cond.has("min_combo") and combo < int(cond["min_combo"]):
		return false
	if cond.has("min_charge") and _cell_charge(charge_cell) < int(cond["min_charge"]):
		return false
	if cond.has("min_poison") and _enemy_poison() < int(cond["min_poison"]):
		return false
	if cond.has("action") and action_index != int(cond["action"]):
		return false
	if cond.has("has_shield") and player_shield <= 0:
		return false
	if cond.has("hp_below"):
		var ratio := float(player_hp) / float(max(player_max_hp, 1))
		if ratio > float(cond["hp_below"]):
			return false
	return true

# The die currently being walked can multiply a tile's numbers. A mod with
# no "op" matches every operation, and one with no "on" matches both
# timings, so "疾走: everything on pass doubles" is a single row.
func _die_op_multiplier(op: String, timing: String) -> int:
	return _mod_multiplier(selected_die, op, timing)

func _mod_multiplier(die: Dictionary, op: String, timing: String) -> int:
	if die.is_empty():
		return 1
	var total := 1
	for raw in die.get("mods", []):
		var mod: Dictionary = raw
		if mod.has("op") and str(mod["op"]) != op:
			continue
		if mod.has("on") and str(mod["on"]) != timing:
			continue
		total *= int(mod.get("x", 1))
	return total

# --- what a die *would* do, for the first tap ---------------------------
# The preview has to answer with the same arithmetic the move itself will
# use, or the second tap becomes a surprise. Everything below reads the
# considered die instead of the spent one; nothing here mutates state.

func _previewed_die() -> Dictionary:
	if state != "player" or not dice_rolled:
		return {}
	if preview_die_index < 0 or preview_die_index >= hand.size():
		return {}
	return hand[preview_die_index]

# The value a die's own spend-time effects will have added to a counter by
# the time the board is read. These fire before the piece moves, so they are
# part of what the player is being shown, not a later surprise.
func _spend_gain(die: Dictionary, op: String) -> int:
	var total := 0
	for raw in die.get("effects", []):
		var eff: Dictionary = raw
		if str(eff.get("on", "stop")) != "spend" or str(eff["op"]) != op:
			continue
		var amount := int(eff.get("amount", 0))
		var scale := str(eff.get("scale", ""))
		if scale == "roll":
			amount *= int(die.get("roll", 0))
		total += amount * _mod_multiplier(die, op, "spend")
	return total

# A counter as it will read once this die has been spent. Only what is
# knowable at the moment of the tap: the die's own spend effects and the
# combo point every die is worth. What the walk itself piles on along the
# way (連鎖路 and friends) is deliberately not predicted — the board would
# then promise a number that depends on squares the player has not reached.
func _projected_counter(scale: String, die: Dictionary, crossed: int) -> int:
	var roll := int(die.get("roll", 0))
	match scale:
		"combo":
			return combo + 1 + _spend_gain(die, "combo")
		"charge":
			# A die's own 充填-style loading reaches every square, so it is
			# counted here; charge granted to one square is not, because the
			# square being drawn is usually not the one being stood on.
			return _cell_charge(charge_cell) + _spend_gain(die, "charge_all")
		"shield":
			return player_shield + _spend_gain(die, "shield")
		"poison":
			return _enemy_poison() + _spend_gain(die, "poison")
		"wounds":
			# A die that pays HP to be spent (献身) has already paid it by
			# the time the square is read, so the preview counts it.
			return max(0, player_max_hp - player_hp + _spend_gain(die, "self_damage"))
		"roll":
			return roll
		"crossed":
			return crossed
	return 1

# The same gate _cond_ok applies, answered against the projected counters
# instead of the live ones — so a square whose condition this die cannot
# meet says so before the die is spent rather than after.
func _projected_cond_ok(cond: Dictionary, die: Dictionary, crossed: int) -> bool:
	if cond.is_empty():
		return true
	var roll := int(die.get("roll", 0))
	if cond.has("min_roll") and roll < int(cond["min_roll"]):
		return false
	if cond.has("max_roll") and roll > int(cond["max_roll"]):
		return false
	if cond.has("min_combo") and _projected_counter("combo", die, crossed) < int(cond["min_combo"]):
		return false
	if cond.has("min_charge") and _projected_counter("charge", die, crossed) < int(cond["min_charge"]):
		return false
	if cond.has("min_poison") and _projected_counter("poison", die, crossed) < int(cond["min_poison"]):
		return false
	if cond.has("action") and action_index + 1 != int(cond["action"]):
		return false
	if cond.has("has_shield") and _projected_counter("shield", die, crossed) <= 0:
		return false
	if cond.has("hp_below"):
		var ratio := float(player_hp) / float(max(player_max_hp, 1))
		if ratio > float(cond["hp_below"]):
			return false
	return true

# Runs every effect in a list whose timing matches, in the order written —
# so "attack scaled by charge" followed by "spend charge" reads and behaves
# the same way.
func _run_effects(effects: Array, timing: String, label: String) -> String:
	var messages := []
	for raw in effects:
		var eff: Dictionary = raw
		if str(eff.get("on", "stop")) != timing:
			continue
		if not _cond_ok(eff.get("cond", {})):
			continue
		var op := str(eff["op"])
		var amount := int(eff.get("amount", 0))
		var scale := str(eff.get("scale", ""))
		if scale != "":
			amount *= _scale_value(scale)
		# add_scale is additive rather than multiplicative — "4 + the roll"
		# instead of "4 times the roll" — and, combined with add_scale_sign,
		# is what lets 突進/慎重 read the same signed roll in opposite
		# directions without either tile needing to know 逆走 exists.
		var add_scale := str(eff.get("add_scale", ""))
		if add_scale != "":
			var sign_mult := int(eff.get("add_scale_sign", 1))
			amount += _scale_value(add_scale) * sign_mult
		amount *= _die_op_multiplier(op, timing)
		var msg := _apply_op(op, amount, label)
		if msg != "":
			messages.append(msg)
	return " ".join(messages)

# The complete list of things that can happen in this game. A new operation
# is the only kind of change that still needs code — and most new content
# needs none.
func _apply_op(op: String, amount: int, label: String) -> String:
	match op:
		"attack":
			if amount <= 0:
				return ""
			# Reports the HP that came off rather than the number swung.
			# The two differ by 装甲, and the popup over the enemy has
			# always shown the honest one — the log used to disagree
			# with it.
			var dealt := _strike_enemy(amount)
			if dealt > 0:
				return "%s：%dダメージ" % [label, dealt]
			return ""
		"shield":
			if amount <= 0:
				return ""
			_gain_shield(amount)
			return "%s：盾+%d" % [label, amount]
		"heal":
			if amount <= 0:
				return ""
			_heal(amount)
			return "%s：HP+%d" % [label, amount]
		"self_damage":
			if amount <= 0:
				return ""
			player_hp -= amount
			_spawn_floating_text(player_pos, "-%d" % amount, Color("#FF6A4D"))
			sfx.emit("hurt")
			_refresh_top()
			return "%s：HP-%d" % [label, amount]
		"combo":
			if amount <= 0:
				return ""
			combo += amount
			_spawn_floating_text(player_pos, "コンボ+%d" % amount, COL_GOLD)
			return "%s：コンボ+%d（今%d）" % [label, amount, combo]
		"charge":
			if amount <= 0:
				return ""
			_set_cell_charge(charge_cell, _cell_charge(charge_cell) + amount)
			_spawn_floating_text(charge_cell, "チャージ+%d" % amount, Color("#A87CE0"))
			return "%s：このマスのチャージ+%d（今%d）" % [
				label, amount, _cell_charge(charge_cell)]
		"charge_all":
			# 照準台 and 充填 load the whole ring rather than the one square
			# under the piece. With charge living on squares that is what
			# "溜める" has to mean to be worth anything.
			if amount <= 0:
				return ""
			for cell in ring_cells:
				_set_cell_charge(cell, _cell_charge(cell) + amount)
			_refresh_board()
			return "%s：盤上すべてのマスのチャージ+%d" % [label, amount]
		"spend_charge":
			var spent := _cell_charge(charge_cell)
			if spent <= 0:
				return ""
			_set_cell_charge(charge_cell, 0)
			return "%s：このマスのチャージ%dを消費" % [label, spent]
		"poison":
			if amount <= 0:
				return ""
			var target := _living_enemy()
			if target.is_empty():
				return ""
			target["poison"] = int(target.get("poison", 0)) + amount
			_spawn_enemy_popup("毒+%d" % amount, Color("#C6E86B"))
			_refresh_enemy()
			return "%s：毒+%d（今%d）" % [label, amount, int(target["poison"])]
		"step":
			if amount <= 0:
				return ""
			steps_left += amount
			return "%s：%d歩追加" % [label, amount]
		"draw":
			if amount <= 0:
				return ""
			for i in range(amount):
				hand_limit += 1
			_draw_to_hand()
			for i in range(amount):
				hand_limit -= 1
			_refresh_hand()
			return "%s：ダイスを%d枚補充" % [label, amount]
		"reroll":
			if amount <= 0:
				return ""
			rerolls_left += amount
			return "%s：振り直し+%d" % [label, amount]
		"action":
			if amount <= 0:
				return ""
			actions_left += amount
			return "%s：行動+%d" % [label, amount]
	return ""

# The armour the square's damage will actually have to get through. Zero
# when nothing is standing there — on the reward screen, for instance.
func _enemy_armor() -> int:
	var target := _living_enemy()
	return 0 if target.is_empty() else int(target.get("armor", 0))

func _living_enemy() -> Dictionary:
	for enemy in enemies:
		if int(enemy["hp"]) > 0:
			return enemy
	return {}

func _enemy_poison() -> int:
	var target := _living_enemy()
	return 0 if target.is_empty() else int(target.get("poison", 0))

# Returns the HP actually taken off, which is not the amount swung: 装甲
# eats a slice of every individual hit. -1 means there was nothing to hit.
func _strike_enemy(amount: int) -> int:
	var target := _living_enemy()
	if target.is_empty():
		return -1
	return _damage_enemy(target, amount)

# --- state changes, each one visible the moment it happens --------------

func _take_damage(amount: int) -> int:
	var blocked: int = min(player_shield, amount)
	player_shield -= blocked
	var hp_loss := amount - blocked
	player_hp -= hp_loss
	if hp_loss > 0:
		_spawn_floating_text(player_pos, "-%d" % hp_loss, Color("#FF6A4D"), hp_loss >= 6)
		sfx.emit("hurt")
		_shake(zone_board, 5.0)
		_shake(zone_hero, 6.0)
		_punch(hero_portrait, 1.18)
		# Fired, not awaited: the turn does not stop for it, which is the
		# whole reason this plays on the stage instead of over the screen.
		_play_hit_clip(hero_sprite, _hero_art_id(), true)
	elif blocked > 0:
		_spawn_floating_text(player_pos, "盾で防いだ", COL_SHIELD)
		sfx.emit("shield")
	_refresh_top()
	return hp_loss

func _heal(amount: int) -> void:
	var gained: int = min(player_max_hp, player_hp + amount) - player_hp
	player_hp = min(player_max_hp, player_hp + amount)
	if gained <= 0:
		return
	_spawn_floating_text(player_pos, "+%d" % gained, COL_HP)
	sfx.emit("shield")
	_refresh_top()

func _gain_shield(amount: int) -> void:
	if amount <= 0:
		return
	player_shield += amount
	_spawn_floating_text(player_pos, "盾+%d" % amount, COL_SHIELD)
	sfx.emit("shield")
	_refresh_top()

func _damage_enemy(enemy: Dictionary, amount: int) -> int:
	# 装甲 subtracts from every individual hit, so it punishes builds that
	# win by many small hits and barely troubles one big one — but never
	# to nothing. A hit that lands for zero makes a whole square, and with
	# it a whole build, simply not exist against three enemies on the
	# roster; a floor of 1 keeps the answer "bad here" rather than "void".
	amount = max(1, amount - int(enemy.get("armor", 0)))
	enemy["hp"] = int(enemy["hp"]) - amount
	var thorns := int(enemy.get("thorns", 0))
	if thorns > 0:
		_take_damage(thorns)
	run_damage_dealt += amount
	_spawn_enemy_popup("-%d" % amount, Color("#FFE0CF"), amount >= 6)
	if amount >= 6 and _has_art("stage", _enemy_art_id(), "hit"):
		_play_hit_clip(enemy_sprite, _enemy_art_id(), false)
	else:
		_flash_enemy()
	sfx.emit("hit")
	if amount >= 6:
		_shake(zone_enemy, 4.0)
	_refresh_enemy()
	return amount

func _cleanup_dead_enemies() -> void:
	var survivors := []
	var any_died := false
	for enemy in enemies:
		if int(enemy["hp"]) > 0:
			survivors.append(enemy)
		else:
			any_died = true
	if any_died:
		_spawn_enemy_popup("撃破!", COL_GOLD, true)
		_spawn_burst_at_enemy()
		sfx.emit("kill")
		for enemy in enemies:
			if int(enemy["hp"]) <= 0:
				var bounty := int(enemy.get("gold", 0))
				if bounty > 0:
					gold += bounty
					_spawn_enemy_popup("+%dG" % bounty, COL_GOLD)
		_refresh_top()
	enemies = survivors
	if any_died and enemies.is_empty():
		_clear_debuffs()

# Every debuff on the board belongs to the enemy that cast it, so the
# board is cleansed the moment the last one dies.
func _clear_debuffs() -> void:
	last_cleanse_count = 0
	for cell in ring_cells:
		if str(temp_board[cell.y][cell.x]) != "none":
			temp_board[cell.y][cell.x] = "none"
			last_cleanse_count += 1
			_spawn_floating_text(cell, "浄", COL_HP)
	if last_cleanse_count > 0:
		sfx.emit("shield")
		_refresh_board()

func _any_enemy_alive() -> bool:
	for enemy in enemies:
		if int(enemy["hp"]) > 0:
			return true
	return false

# --- enemy turn --------------------------------------------------------

func _enemy_turn() -> void:
	state = "enemy"
	_refresh_all()
	_set_banner(tr("敵のターン"))
	await get_tree().create_timer(BEAT_PHASE).timeout
	var messages := []

	# Poison resolves before the enemy acts, so a lethal stack means the
	# enemy never gets its swing in — that is the payoff for the毒 build.
	for enemy in enemies:
		var stacks := int(enemy.get("poison", 0))
		if stacks > 0 and int(enemy["hp"]) > 0:
			_damage_enemy(enemy, stacks)
			enemy["poison"] = stacks - 1
			messages.append("毒：%dダメージ（残り%d）" % [stacks, stacks - 1])
			_set_log(messages[messages.size() - 1])
			await get_tree().create_timer(BEAT_EFFECT).timeout
		var regen := int(enemy.get("regen", 0))
		if regen > 0 and int(enemy["hp"]) > 0:
			enemy["hp"] = min(int(enemy["max_hp"]), int(enemy["hp"]) + regen)
			_spawn_enemy_popup("+%d" % regen, COL_HP)
			_refresh_enemy()
	_cleanup_dead_enemies()
	if enemies.is_empty():
		_hide_banner()
		_finish_encounter()
		return
	for enemy in enemies:
		if int(enemy["hp"]) <= 0:
			continue
		# マス指定攻撃 cares only about where the turn actually ended, not
		# whether the piece ran across the cell on the way — landing on it
		# and passing through it read the same on the board, but only one
		# of them should cost HP.
		var hit := false
		if str(enemy.get("attack_kind", "cell")) == "guaranteed":
			hit = true
		else:
			hit = enemy.get("telegraph_cells", []).has(player_pos)
		var enemy_label: String = str(enemy["type"])
		if hit:
			await _lunge_enemy()
			var taken := _take_damage(int(enemy["damage"]))
			if taken > 0:
				messages.append("%sの攻撃。%dダメージ" % [enemy_label, taken])
			else:
				messages.append("%sの攻撃を盾で防いだ" % enemy_label)
		else:
			_spawn_enemy_popup("MISS", COL_TEXT_SOFT)
			messages.append("%sの攻撃を回避" % enemy_label)
		_set_log(messages[messages.size() - 1])
		await get_tree().create_timer(BEAT_PHASE).timeout

	# Fouling the board is the enemy's other move, and which kind it leaves
	# is read off the enemy rather than fixed here — so 疫病持ち poisons
	# where 重装 freezes, from one branch. The encounter gate is gone: an
	# enemy that fouls does so from its first turn, because a debuff the
	# player only meets in the back half of a run never gets learned.
	for enemy in enemies:
		if int(enemy["hp"]) <= 0:
			continue
		var kind := str(enemy.get("debuff", ""))
		if kind == "" or _debuff_count() >= MAX_DEBUFFS:
			continue
		if rng.randi_range(0, 99) >= int(enemy.get("foul", 0)):
			continue
		var p := _random_empty_cell()
		if p.x < 0:
			continue
		var deb: Dictionary = temp_defs[kind]
		temp_board[p.y][p.x] = kind
		messages.append("マスに%sがかけられた" % _t(deb["name"]))
		_set_log(messages[messages.size() - 1])
		_refresh_board()
		_spawn_floating_text(p, str(deb["mark"]), Color(deb["color"]).darkened(0.2))
		sfx.emit("hurt")
		await get_tree().create_timer(BEAT_EFFECT).timeout

	_hide_banner()
	_cleanup_dead_enemies()
	if player_hp <= 0:
		_show_game_over("敵の攻撃で倒れました。", true)
		return
	if enemies.is_empty():
		_finish_encounter()
		return
	for enemy in enemies:
		_generate_telegraph(enemy)
	_start_player_turn(" / ".join(messages))

func _on_end_turn_pressed() -> void:
	if state != "player":
		return
	_set_log(tr("行動を終えました。"))
	_enemy_turn()

# --- rewards -----------------------------------------------------------

func _on_reward_selected(tile_type: String, tile_name: String) -> void:
	pending_reward_type = tile_type
	pending_reward_name = tile_name
	preview_place_pos = Vector2i(-1, -1)
	state = "reward_place"
	_close_overlay()
	_set_banner(tr("%s を置くマスをタップ") % tile_name)
	_set_log(tr("始点以外のどのマスにも置けます。置いたマスは次の戦いにも残ります。"))
	_refresh_all()

# A die reward needs no board placement, so it resolves straight into the
# next encounter. It joins the bag rather than the hand: the new die has to
# be shuffled for and drawn like everything else, which is the cost of
# adding to a deck this small.
func _on_die_reward_selected(die_id: String) -> void:
	var die_def: Dictionary = dice_defs[die_id]
	dice_bag.append(_make_die(die_id))
	preview_place_pos = Vector2i(-1, -1)
	_close_overlay()
	_hide_banner()
	sfx.emit("reward")
	_set_log(tr("%sダイスを手に入れた（%s）。手札は全%d個から引かれます。") % [
		_t(die_def["name"]), _t(die_def["effect"]), dice_bag.size()])
	if _is_boss_node():
		_show_victory()
	else:
		_show_map()

func _can_place_reward(pos: Vector2i) -> bool:
	if not _inside(pos):
		return false
	if not ring_index_map.has(pos):
		return false
	if pos == _start_pos():
		return false
	if str(temp_board[pos.y][pos.x]) == "block":
		return false
	return true

func _set_banner(text: String) -> void:
	if banner == null:
		return
	banner_label.text = text
	banner.visible = true
	_layout_board_buttons()

func _hide_banner() -> void:
	if banner != null:
		banner.visible = false

# --- input on the board ------------------------------------------------

func _on_cell_pressed(index: int) -> void:
	var pos := Vector2i(index % BOARD_W, int(index / BOARD_W))
	if state == "reward_place":
		if not _can_place_reward(pos):
			return
		# Tap once to see the tile in place, tap again to commit. Touch has
		# no hover, so this is how a placement preview has to work.
		if preview_place_pos != pos:
			preview_place_pos = pos
			sfx.emit("step")
			_set_banner(tr("ここに置く？ もう一度タップで確定"))
			_set_log(_place_preview_text(pos))
			_refresh_board()
			return
		permanent_board[pos.y][pos.x] = pending_reward_type
		preview_place_pos = Vector2i(-1, -1)
		_hide_banner()
		sfx.emit("reward")
		if _is_boss_node():
			_show_victory()
		else:
			_set_log(tr("%s を配置しました。") % pending_reward_name)
			_show_map()
	elif ring_index_map.has(pos):
		# Tapping the board is also how a considered die is put back down:
		# the hand has no empty space to tap, and the board is the thing the
		# player is looking at while deciding.
		if preview_die_index >= 0:
			preview_die_index = -1
			_hide_banner()
			sfx.emit("step")
			# Restores the resting log line before the cell info borrows it,
			# so the temporary tooltip does not expire back into a sentence
			# about a die the player just put down.
			_set_log(tr("ダイスを戻しました。もう一度ダイスを選んでください。"))
			_refresh_all()
		_show_cell_info(pos)

# The placement equivalent of _die_preview_text. The board only has twelve
# squares and a tile stays for the rest of the run, so the one thing the
# first tap has to answer is what this square is being spent on — including
# what is already standing there, because dropping a tile onto an occupied
# square destroys it and the old build did that silently.
func _place_preview_text(pos: Vector2i) -> String:
	var tile: Dictionary = tile_defs[pending_reward_type]
	var parts := []
	parts.append("%s %s：%s" % [
		_t(tile["name"]), _trigger_label(str(tile["trigger"])), _t(tile["effect"])])
	var existing: String = str(permanent_board[pos.y][pos.x])
	if existing != "empty":
		parts.append("⚠ ここにある「%s」を壊して置き換えます" % _t(tile_defs[existing]["name"]))
	else:
		parts.append("空きマスに置きます")
	var ahead := _steps_ahead(pos)
	if ahead > 0:
		parts.append("現在地から%dマス先" % ahead)
	return " / ".join(parts)

# Tile details go to the fixed log line instead of a popup card over the
# board — the old card covered the lookahead row it was meant to explain.
func _show_cell_info(pos: Vector2i) -> void:
	var perm_type: String = str(permanent_board[pos.y][pos.x])
	var temp_type: String = str(temp_board[pos.y][pos.x])
	var tile: Dictionary = tile_defs[perm_type]
	var parts := []
	var ahead := _steps_ahead(pos)
	if ahead > 0:
		parts.append("%dマス先" % ahead)
	parts.append("%s %s" % [_t(tile["name"]), _trigger_label(str(tile["trigger"]))])
	parts.append(_t(tile["effect"]))
	var info_debuff := _debuff_at(pos)
	if not info_debuff.is_empty():
		parts.append("%s：%s" % [_t(info_debuff["name"]), _t(info_debuff["effect"])])
	if danger_cells.has(pos):
		parts.append("敵の攻撃予告あり（そこで行動を終えると被弾）")
	if log_label != null:
		log_label.text = " / ".join(parts)
	cell_info_timer = 3.5

func _cell_tooltip(pos: Vector2i, perm_type: String, temp_type: String) -> String:
	var lines := []
	var ahead := _steps_ahead(pos)
	if ahead > 0:
		lines.append("現在地から%dマス先" % ahead)
	if danger_cells.has(pos):
		lines.append("敵の攻撃予告（そこで行動を終えると被弾）")
	if temp_type != "none":
		lines.append(str(temp_defs[temp_type]["desc"]))
	var tile: Dictionary = tile_defs[perm_type]
	lines.append("%s %s: %s" % [_t(tile["name"]), _trigger_label(str(tile["trigger"])), _t(tile["effect"])])
	return "\n".join(lines)

# --- token motion ------------------------------------------------------

func _snap_player_visual() -> void:
	player_visual_ready = false
	await get_tree().process_frame
	await get_tree().process_frame
	player_visual_pos = _board_cell_center(player_pos)
	player_visual_ready = true
	player_hop = 0.0
	if board_view != null:
		board_view.queue_redraw()

func _resync_player_visual() -> void:
	if player_visual_ready:
		player_visual_pos = _board_cell_center(player_pos)

func _animate_player_step(duration: float = 0.15) -> void:
	var target: Vector2 = _board_cell_center(player_pos)
	if not player_visual_ready:
		_snap_player_visual()
		return
	var move_tween := create_tween()
	move_tween.tween_property(self, "player_visual_pos", target, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var hop_tween := create_tween()
	hop_tween.tween_property(self, "player_hop", 12.0, duration * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	hop_tween.tween_property(self, "player_hop", 0.0, duration * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await move_tween.finished

func _flash_player_stop() -> void:
	player_impact = 1.0
	var tween := create_tween()
	tween.tween_property(self, "player_impact", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# --- board graph -------------------------------------------------------

func _build_track_graph() -> void:
	# The perimeter of the 5x5 grid, clockwise from the top-left start.
	# Sixteen squares rather than twelve: the extra four are the room the
	# debuffs need to land in without burying the board the player built,
	# and they push the far side of the ring out past a single 6 so a lap
	# is a journey rather than two good rolls.
	ring_cells = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0),
		Vector2i(4, 1), Vector2i(4, 2), Vector2i(4, 3),
		Vector2i(4, 4), Vector2i(3, 4), Vector2i(2, 4), Vector2i(1, 4),
		Vector2i(0, 4), Vector2i(0, 3), Vector2i(0, 2), Vector2i(0, 1),
	]
	ring_index_map = {}
	ring_forward = {}
	for i in range(ring_cells.size()):
		ring_index_map[ring_cells[i]] = i
		ring_forward[ring_cells[i]] = ring_cells[(i + 1) % ring_cells.size()]

func _normalize_step(step: int) -> int:
	if ring_cells.is_empty():
		return 0
	var count := ring_cells.size()
	return ((step % count) + count) % count

func _pos_for_step(step: int) -> Vector2i:
	if ring_cells.is_empty():
		return Vector2i.ZERO
	return ring_cells[_normalize_step(step)]

func _track_index(pos: Vector2i) -> int:
	return int(ring_index_map.get(pos, 0))

# Every square a roll of this size would touch, in order, following 跳躍路
# the same way the move itself will. The last entry is where the action ends.
# A warp face does not walk, so its route is the single square it jumps to.
func _route_for_roll(roll: int, ignore_halt: bool = false) -> Array[Vector2i]:
	var route: Array[Vector2i] = []
	if _is_warp_face(roll):
		route.append(_pos_for_step(_warp_face_step(roll)))
		return route
	var step := player_step
	var dir := -1 if roll < 0 else 1
	var remaining := absi(roll)
	var guard := 0
	while remaining > 0 and guard < 32:
		guard += 1
		step = _normalize_step(step + dir)
		remaining -= 1
		var p := _pos_for_step(step)
		route.append(p)
		# 茨 ends the move where it sits, so the route ends there too. The
		# preview is built on this function; if it walked past a briar the
		# board would ring a landing square the move can never reach.
		if _debuff_halts(p) and not ignore_halt:
			break
		var tile: Dictionary = tile_defs[str(permanent_board[p.y][p.x])]
		# 跳躍路's "one more step" only extends a forward sweep — walking
		# back through it should not also start stretching the walk. A
		# frozen 跳躍路 does not extend it either, for the same reason it
		# does nothing else.
		if dir > 0 and not _debuff_nullifies(p):
			for raw in tile.get("effects", []):
				var eff: Dictionary = raw
				if str(eff.get("on", "stop")) == "pass" and str(eff["op"]) == "step":
					remaining += int(eff.get("amount", 0))
	if route.is_empty():
		route.append(_pos_for_step(step))
	return route

# Where a roll of this size actually finishes.
func _landing_cell_for(roll: int) -> Vector2i:
	var route := _route_for_roll(roll)
	return route[route.size() - 1]

func _steps_ahead(pos: Vector2i) -> int:
	var idx := preview_path.find(pos)
	if idx == -1:
		return -1
	return idx + 1

func _start_pos() -> Vector2i:
	if ring_cells.is_empty():
		return Vector2i.ZERO
	return ring_cells[0]

# The six squares in front of the piece, always the same six. It is a fixed
# reference strip — "here is the road" — and deliberately does not follow
# the die being considered: a strip that resized itself to each die gave the
# player nothing stable to read the dice against, and for 逆走, whose route
# runs the other way, it would have had nothing to show at all. The
# considered die's own route is drawn on the board instead (preview_route),
# which is where a route belongs.
func _rebuild_preview_path() -> void:
	preview_path = []
	if state != "player":
		return
	for i in range(1, 7):
		preview_path.append(_pos_for_step(player_step + i))

# The squares the considered die would actually run over, and whether it
# gets there by jumping. Empty whenever nothing is being considered, which
# is what makes every readout fall back to a square's resting value.
# False for a warp (it jumps) and for 居合's 0 (it stands still). Both end
# an action on a square without entering anything on the way, which is what
# "crossed" counts and what a pass-timing effect needs.
func _preview_walks() -> bool:
	if _readout_die.is_empty() or preview_warp:
		return false
	return int(_readout_die.get("roll", 0)) != 0

func _rebuild_preview_route() -> void:
	preview_route = []
	preview_warp = false
	var die := _previewed_die()
	if die.is_empty():
		return
	var roll := int(die.get("roll", 0))
	preview_warp = _is_warp_face(roll)
	preview_route = _route_for_roll(roll)

func _segment_is_recent(a: Vector2i, b: Vector2i) -> bool:
	if route_path.size() < 2:
		return false
	for i in range(route_path.size() - 1):
		if (route_path[i] == a and route_path[i + 1] == b) or (route_path[i] == b and route_path[i + 1] == a):
			return true
	return false

func _segment_is_next(a: Vector2i, b: Vector2i) -> bool:
	if state != "player" or preview_path.is_empty():
		return false
	var first: Vector2i = preview_path[0]
	if (a == player_pos and b == first) or (b == player_pos and a == first):
		return true
	for i in range(preview_path.size() - 1):
		if (preview_path[i] == a and preview_path[i + 1] == b) or (preview_path[i] == b and preview_path[i + 1] == a):
			return true
	return false

func _telegraphed_cells() -> Dictionary:
	var cells := {}
	if state == "title":
		return cells
	for enemy in enemies:
		if int(enemy["hp"]) <= 0:
			continue
		for c in enemy.get("telegraph_cells", []):
			cells[c] = true
	return cells

func _debuff_count() -> int:
	var total := 0
	for cell in ring_cells:
		if str(temp_board[cell.y][cell.x]) != "none":
			total += 1
	return total

func _random_empty_cell() -> Vector2i:
	var choices := []
	for p in ring_cells:
		if p == player_pos:
			continue
		if str(temp_board[p.y][p.x]) != "none":
			continue
		choices.append(p)
	if choices.is_empty():
		return Vector2i(-1, -1)
	return choices[rng.randi_range(0, choices.size() - 1)]

func _make_empty_board(value: String) -> Array:
	var board := []
	for y in range(BOARD_H):
		var row := []
		for x in range(BOARD_W):
			row.append(value)
		board.append(row)
	return board

func _idx(x: int, y: int) -> int:
	return y * BOARD_W + x

func _inside(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < BOARD_W and pos.y >= 0 and pos.y < BOARD_H

# --- lookups -----------------------------------------------------------

# A playable copy of a die out of the catalogue. "roll" is the only field
# that changes during play; everything else is the die's printed identity.
func _make_die(die_id: String) -> Dictionary:
	var def: Dictionary = dice_defs[die_id]
	return {
		"id": die_id,
		"name": _t(def["name"]),
		"faces": (def["faces"] as Array).duplicate(),
		"effects": (def.get("effects", []) as Array).duplicate(true),
		"mods": (def.get("mods", []) as Array).duplicate(true),
		"pierce": bool(def.get("pierce", false)),
		"color": Color(def["color"]),
		"short": _t(def["short"]),
		"roll": 0,
	}

func _die_color(die: Dictionary) -> Color:
	return Color(die.get("color", Color("#54687F")))

func _is_warp_face(v: int) -> bool:
	return WARP_FACES.has(v)

func _warp_face_label(v: int) -> String:
	return str((WARP_FACES.get(v, {}) as Dictionary).get("label", "?"))

func _warp_face_step(v: int) -> int:
	return int((WARP_FACES.get(v, {}) as Dictionary).get("step", 0))

func _faces_text(faces: Array) -> String:
	var sorted_faces: Array = faces.duplicate()
	sorted_faces.sort()
	var parts := []
	for f in sorted_faces:
		var fv := int(f)
		parts.append(_warp_face_label(fv) if _is_warp_face(fv) else str(fv))
	return "・".join(parts)

func _hero_dice_names(hero: Dictionary) -> String:
	var names := []
	for die_id in hero["dice"]:
		names.append(str(dice_defs[str(die_id)]["name"]))
	return "・".join(names)

func _clear_children(node: Node) -> void:
	if node == null:
		return
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
