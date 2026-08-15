extends Control

const BOARD_W := 4
const BOARD_H := 4
const ACTIONS_PER_TURN := 2
const REROLLS_PER_TURN := 1
# How many squares an enemy can keep fouled at once. Uncapped, a long
# fight ended with most of the ring poisoned and the player's own board
# invisible underneath it.
const MAX_DEBUFFS := 4
const MAX_ENCOUNTERS := 6

# Every size in this file is authored in these units, and the window's
# content scale is pinned to them at startup (see _apply_content_scale), so
# one unit lands within a few percent of one real screen pixel on a phone.
# The old build authored against 720x1280, which a 430px-wide phone scaled
# to 0.60 — a font_size of 10 arrived on screen as six physical pixels.
const DESIGN_SIZE := Vector2i(432, 768)

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

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), face_color, true)
		draw_rect(Rect2(Vector2.ZERO, size), dot_color, false, max(2.0, size.x * 0.06))
		var dot_r: float = min(size.x, size.y) * 0.10
		for p in _pip_positions(value):
			draw_circle(Vector2(p.x * size.x, p.y * size.y), dot_r, dot_color)

	func _pip_positions(v: int) -> Array:
		var l := 0.26
		var c := 0.5
		var r := 0.74
		var t := 0.26
		var m := 0.5
		var b := 0.74
		match v:
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
			_:
				return [Vector2(l, t), Vector2(r, t), Vector2(l, m), Vector2(r, m), Vector2(l, b), Vector2(r, b)]

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

# The enemy, drawn as a figure on a plinth rather than a row in a table.
# Carries its own hit flash and idle bob so damage lands on the character
# instead of on a progress bar somewhere else on screen.
class EnemyFigure:
	extends Control

	var kind := "enemy_grunt":
		set(v):
			kind = v
			if glyph != null:
				glyph.set_kind(v)
	var body_color := Color("#C2453A"):
		set(v):
			body_color = v
			_tint()
	var flash: float = 0.0:
		set(v):
			flash = v
			_tint()
	var bob := 0.0
	var glyph: IconGlyph

	func _ready() -> void:
		glyph = IconGlyph.new()
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glyph.kind = kind
		add_child(glyph)
		_tint()
		set_process(true)

	func _tint() -> void:
		if glyph != null:
			glyph.glyph_color = body_color.lerp(Color.WHITE, flash)
			glyph.queue_redraw()

	func _process(delta: float) -> void:
		bob = fmod(bob + delta, TAU)
		_place()
		queue_redraw()

	func _place() -> void:
		if glyph == null or size.x <= 0.0:
			return
		var s: float = min(size.x, size.y)
		var lift: float = sin(bob * 1.8) * s * 0.025
		glyph.size = Vector2(s, s)
		glyph.position = Vector2(size.x * 0.5 - s * 0.5, size.y * 0.52 + lift - s * 0.5)

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		var s: float = min(size.x, size.y)
		# Ground shadow, so the figure sits on the table instead of floating.
		draw_circle(Vector2(size.x * 0.5, size.y * 0.86), s * 0.24, Color(0.16, 0.12, 0.08, 0.10))

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

	# One ring per die still in hand, on the cell that die would land on,
	# in that die's own colour. This is the whole point of rolling up
	# front: the choice of die is now a choice of square.
	func _draw_landing_marks() -> void:
		if main.state != "player" or not main.dice_rolled:
			return
		var token: float = main._board_token_size()
		var seen := {}
		for die in main.hand:
			var roll := int(die.get("roll", 0))
			if roll <= 0:
				continue
			var cell: Vector2i = main._landing_cell_for(roll)
			var ring_index: int = int(seen.get(cell, 0))
			seen[cell] = ring_index + 1
			var p: Vector2 = main._board_cell_center(cell)
			var radius: float = token * 0.5 + 7.0 + float(ring_index) * 6.0
			var col: Color = main._tag_color(str(die["tag"]))
			draw_arc(p, radius, 0.0, TAU, 30, Color("#2A2320"), 6.0, true)
			draw_arc(p, radius, 0.0, TAU, 30, col, 4.0, true)

	# A ring right on the rim of a fouled cell: visible at a glance without
	# covering the tile's own icon or number.
	func _draw_debuff_rings() -> void:
		var token: float = main._board_token_size()
		for cell in main.ring_cells:
			if str(main.temp_board[cell.y][cell.x]) != "hazard":
				continue
			var p: Vector2 = main._board_cell_center(cell)
			draw_arc(p, token * 0.5 - 3.0, 0.0, TAU, 30, Color("#D9F27A"), 3.0, true)

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
var sfx: Sfx

var zone_top: Control
var zone_enemy: Control
var zone_board: Control
var zone_hand: Control
var zone_cmd: Control
var zone_log: Control

var run_track: RunTrack
var run_label: Label
var hero_portrait: HeroPortrait
var hp_bar: GaugeBar
var hp_label: Label
var shield_chip: PanelContainer
var shield_label: Label
var combo_chip: PanelContainer
var combo_label: Label
var action_pip_box: HBoxContainer

var enemy_panel: Control
var enemy_figure: EnemyFigure
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

var hand_row: GridContainer
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
var overlay_list: VBoxContainer

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

var ring_cells: Array[Vector2i] = []
var ring_index_map: Dictionary = {}
var ring_forward: Dictionary = {}
var preview_path: Array[Vector2i] = []
var turn_visited: Dictionary = {}

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
var selected_tag := ""
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
var catalog_return_state := "title"
# The hand is rolled once, up front, and the faces then stay put: the
# player picks which of the known results to walk. Rolling at the moment a
# die is chosen meant the stop-type tiles could never be aimed at, which
# made half the board a lottery.
var hand_limit := 3
var last_cleanse_count := 0
var dice_rolled := false
var rerolls_left := 0

# Tile colors are assigned by what the effect *does to whom*: warm for
# "this hurts the enemy", cool for "this helps me", and one sickly green
# reserved for the only thing that hurts the player.
# Each tile fires on exactly one trigger: "pass" tiles pay out every time
# the piece runs through them, "stop" tiles only when it lands exactly on
# them. Splitting the two halves the amount a player has to read off a
# tile, and it gives the dice a real question to answer — do I want to
# sweep through a lot of road, or land on one particular square?
#
# Because a pass tile fires several times per roll and a stop tile fires
# once per action, pass values are small and stop values are large.
# Shape carries the trigger on the board: pass tiles are drawn round like
# a stretch of road, stop tiles square like a place you can stand.
var tile_defs := {
	"empty": {"name": "道", "kind": "基本", "color": Color("#CBB68F"), "icon": "boot",
		"trigger": "stop", "mode": "shield", "value": 1, "effect": "盾+1",
		"detail": "何も置いていないただの道。止まれば盾が1つだけ手に入る。"},
	"slash": {"name": "斬撃路", "kind": "攻撃", "color": Color("#E4453A"), "icon": "slash",
		"trigger": "pass", "mode": "attack", "target": "lowest", "value": 3, "effect": "敵に3ダメージ",
		"detail": "通り抜けざまに斬る。大きい出目で何枚も踏み抜くほど伸びる、攻めの基本。"},
	"fire": {"name": "火走り", "kind": "攻撃", "color": Color("#F2762B"), "icon": "fire",
		"trigger": "pass", "mode": "attack", "target": "all", "value": 2, "effect": "敵に2ダメージ",
		"detail": "走った跡が燃える。1枚あたりは軽いが、連鎖ボーナスを稼ぎやすい。"},
	"guard": {"name": "防御路", "kind": "防御", "color": Color("#2E7BD6"), "icon": "guard",
		"trigger": "pass", "mode": "shield", "value": 2, "effect": "盾+2",
		"detail": "通るたびに盾を拾う。盾はターン開始で消えるので、殴られる前に集めること。"},
	"heal": {"name": "癒し道", "kind": "回復", "color": Color("#3EA95E"), "icon": "heal",
		"trigger": "pass", "mode": "heal", "value": 1, "effect": "HP+1",
		"detail": "少しずつしか戻らない。長い出目で何度も通り抜けるのが回復の近道。"},
	"chain": {"name": "連鎖路", "kind": "連鎖", "color": Color("#F2C230"), "icon": "chain",
		"trigger": "pass", "mode": "combo", "value": 1, "effect": "コンボ+1",
		"detail": "通り抜けるとコンボが1増える。攻撃マスのダメージはコンボぶん上乗せされるので、踏んでから殴ると伸びる。"},
	"warp": {"name": "跳躍路", "kind": "移動", "color": Color("#16A0C8"), "icon": "warp",
		"trigger": "pass", "mode": "step", "value": 1, "effect": "1歩多く進む",
		"detail": "出目を1つ伸ばす。止まりたいマスに足りないときの調整に使う。"},
	"heavy": {"name": "大斬撃", "kind": "攻撃", "color": Color("#B5302A"), "icon": "slash",
		"trigger": "stop", "mode": "attack", "target": "lowest", "value": 7, "effect": "敵に7ダメージ",
		"detail": "踏み込んで斬る。斬撃路の重い版で、走り抜けざまには出せない。"},
	"fort": {"name": "砦", "kind": "防御", "color": Color("#1F5FA8"), "icon": "guard",
		"trigger": "stop", "mode": "shield", "value": 5, "effect": "盾+5",
		"detail": "腰を据えて構える。盾はターン開始で消えるので、殴られるターンに合わせて止まること。"},
	"spring": {"name": "泉", "kind": "回復", "color": Color("#2E8449"), "icon": "heal",
		"trigger": "stop", "mode": "heal", "value": 5, "effect": "HP+5",
		"detail": "汲むには足を止めるしかない。盤上で最も大きい回復。"},
	"bow": {"name": "射撃台", "kind": "攻撃", "color": Color("#C9971F"), "icon": "bow",
		"trigger": "stop", "mode": "attack", "target": "lowest", "value": 6, "effect": "敵に6ダメージ",
		"detail": "構えて撃つので、走り抜けながらでは撃てない。ぴたりと止まって初めて効く。"},
	"trap": {"name": "罠道", "kind": "攻撃", "color": Color("#C2457E"), "icon": "trap",
		"trigger": "stop", "mode": "attack", "target": "highest", "value": 8, "effect": "敵に8ダメージ",
		"detail": "仕掛けて起動するまで時間がいる。盤上で最も大きい一撃。"},
	"shock": {"name": "雷線", "kind": "複合", "color": Color("#7C4DD6"), "icon": "shock",
		"trigger": "stop", "mode": "shock", "target": "all", "value": 4, "effect": "敵に4ダメージ、盾+2",
		"detail": "攻めと守りを同時にこなす。どちらも欲しいターンの着地点に。"},
	"focus": {"name": "集中路", "kind": "補助", "color": Color("#5B8C2A"), "icon": "focus",
		"trigger": "stop", "mode": "draw", "value": 1, "effect": "ダイスを1枚引く",
		"detail": "手札を1枚補充する。引いたダイスはその場で振られ、まだ行動が残っていればそのまま使える。"}
}

# Enemies do not build their own squares — they foul yours. A debuff sits
# on top of whatever tile is already there: the tile keeps its colour, its
# icon and its effect, and picks up a cost for walking over it. Killing the
# enemy that cast them clears the board.
var temp_defs := {
	"none": {"short": "", "color": Color("#00000000"), "desc": ""},
	"hazard": {"name": "毒", "icon": "poison", "color": Color("#9BC53D"), "value": 2,
		"trigger": "pass", "effect": "通過するとHP-2",
		"desc": "毒: 通過するとHP-2。敵がマスにかける。倒せば消える",
		"detail": "敵がマスにかけるデバフ。マス自体の効果はそのまま残り、通るたびにHPを2失う。かけた敵を倒すと盤面から全て消える。"},
	"block": {"name": "壁", "color": Color("#4A4038"), "desc": "通れない"}
}

var reward_pool := [
	{"type": "slash"}, {"type": "guard"}, {"type": "fire"},
	{"type": "heal"}, {"type": "bow"}, {"type": "trap"},
	{"type": "warp"}, {"type": "shock"}, {"type": "focus"},
	{"type": "heavy"}, {"type": "fort"}, {"type": "spring"},
	{"type": "chain"}
]

var hero_defs := {
	"knight": {
		"name": "剣士",
		"hp": 36,
		"hand": 3,
		"color": Color("#2E7BD6"),
		"desc": "大斬撃と砦の盤面。止まる場所を選んで、堅実に削る。",
		"dice": [
			{"name": "標準ダイス", "faces": [1, 2, 3, 4, 5, 6], "tag": "normal"},
			{"name": "重撃ダイス", "faces": [3, 4, 4, 5, 6, 6], "tag": "heavy"},
			{"name": "守りダイス", "faces": [1, 2, 2, 3, 3, 4], "tag": "steel"},
			{"name": "標準ダイス", "faces": [1, 2, 3, 4, 5, 6], "tag": "normal"}
		],
		"tiles": [
			[0, 0, "heavy"], [1, 0, "fort"], [2, 0, "heavy"],
			[3, 1, "heavy"], [3, 2, "fort"], [2, 3, "fort"],
			[1, 3, "heavy"], [0, 2, "fort"]
		]
	},
	"mage": {
		"name": "魔導士",
		"hp": 28,
		"hand": 3,
		"color": Color("#7C4DD6"),
		"desc": "雷線と泉の盤面。止まって大きく撃ち、泉で保たせる。",
		"dice": [
			{"name": "火花ダイス", "faces": [1, 2, 3, 4, 5, 6], "tag": "fire"},
			{"name": "揺らぎダイス", "faces": [1, 1, 3, 5, 6, 6], "tag": "arcane"},
			{"name": "集中ダイス", "faces": [2, 2, 3, 3, 4, 4], "tag": "focus"},
			{"name": "標準ダイス", "faces": [1, 2, 3, 4, 5, 6], "tag": "normal"}
		],
		"tiles": [
			[0, 0, "shock"], [1, 0, "spring"], [2, 0, "shock"],
			[3, 1, "shock"], [3, 2, "focus"], [2, 3, "shock"],
			[1, 3, "focus"], [0, 2, "spring"]
		]
	},
	"rogue": {
		"name": "盗賊",
		"hp": 31,
		"hand": 4,
		"color": Color("#5B8C2A"),
		"desc": "手札が4枚。射撃台と罠道に、狙って止まる。",
		"dice": [
			{"name": "軽業ダイス", "faces": [1, 1, 2, 2, 3, 4], "tag": "swift"},
			{"name": "仕掛けダイス", "faces": [1, 2, 3, 3, 5, 6], "tag": "trick"},
			{"name": "幸運ダイス", "faces": [1, 2, 2, 4, 4, 6], "tag": "lucky"},
			{"name": "軽業ダイス", "faces": [1, 1, 2, 2, 3, 4], "tag": "swift"},
			{"name": "仕掛けダイス", "faces": [1, 2, 3, 3, 5, 6], "tag": "trick"}
		],
		"tiles": [
			[0, 0, "bow"], [1, 0, "fort"], [2, 0, "trap"],
			[3, 1, "bow"], [3, 2, "fort"], [2, 3, "trap"],
			[1, 3, "bow"], [0, 2, "focus"]
		]
	}
}

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

	sfx = Sfx.new()
	add_child(sfx)

	zone_top = Control.new()
	zone_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(zone_top)
	_build_top_zone()

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
	hero_portrait.custom_minimum_size = Vector2(48, 48)
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

	var chip_row := stat_row

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

	var action_caption := _make_label(FS_SMALL, COL_TEXT_SOFT, HORIZONTAL_ALIGNMENT_RIGHT)
	action_caption.text = "行動"
	action_caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	action_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip_row.add_child(action_caption)

	action_pip_box = HBoxContainer.new()
	action_pip_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	action_pip_box.add_theme_constant_override("separation", 6)
	action_pip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip_row.add_child(action_pip_box)

func _build_enemy_zone() -> void:
	enemy_panel = PanelContainer.new()
	enemy_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	enemy_panel.add_theme_stylebox_override("panel", _flat_style(COL_PANEL, COL_INK, 3, 10, 8))
	enemy_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone_enemy.add_child(enemy_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	enemy_panel.add_child(row)

	enemy_figure = EnemyFigure.new()
	enemy_figure.custom_minimum_size = Vector2(96, 96)
	enemy_figure.size_flags_vertical = Control.SIZE_FILL
	enemy_figure.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(enemy_figure)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 5)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)

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

	intent_note = _make_label(FS_SMALL, COL_TEXT_SOFT, HORIZONTAL_ALIGNMENT_LEFT)
	intent_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	intent_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	intent_row.add_child(intent_note)

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

	combo_chip = PanelContainer.new()
	combo_chip.add_theme_stylebox_override("panel", _flat_style(COL_GOLD, COL_INK, 3, 10, 3))
	combo_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	combo_chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ribbon_box.add_child(combo_chip)
	combo_label = _make_label(FS_BODY, COL_INK, HORIZONTAL_ALIGNMENT_CENTER, true)
	combo_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	combo_chip.add_child(combo_label)

	ribbon_caption = _make_label(FS_SMALL, COL_TEXT_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	ribbon_caption.text = "この先のマス　●通過 ■停止"
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
	# A grid, not a fixed row of three: the hand size is a property of the
	# run, so the slots are built to match it and the cards size themselves
	# to whatever width that leaves.
	hand_row = GridContainer.new()
	hand_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	hand_row.add_theme_constant_override("h_separation", 7)
	hand_row.add_theme_constant_override("v_separation", 7)
	hand_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone_hand.add_child(hand_row)

	# Three permanent slots. The old build re-centred a shrinking row, so
	# spending a die slid the remaining cards sideways under the player's
	# thumb; an empty slot holds its place instead.
	_ensure_hand_slots()

func _build_command_zone() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 8)
	zone_cmd.add_child(row)

	reroll_button = Button.new()
	reroll_button.text = "振り直す"
	reroll_button.focus_mode = Control.FOCUS_NONE
	reroll_button.custom_minimum_size = Vector2(132, 0)
	reroll_button.add_theme_font_size_override("font_size", FS_SMALL)
	_style_button(reroll_button, COL_SHIELD, COL_INK)
	reroll_button.pressed.connect(Callable(self, "_on_reroll_pressed"))
	row.add_child(reroll_button)

	end_turn_button = Button.new()
	end_turn_button.text = "行動終了"
	end_turn_button.focus_mode = Control.FOCUS_NONE
	end_turn_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	end_turn_button.add_theme_font_size_override("font_size", FS_BODY)
	_style_button(end_turn_button, COL_GOLD, COL_INK)
	end_turn_button.add_theme_color_override("font_color", COL_INK)
	end_turn_button.pressed.connect(Callable(self, "_on_end_turn_pressed"))
	row.add_child(end_turn_button)

	catalog_button = Button.new()
	catalog_button.text = "図鑑"
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

	overlay_list = VBoxContainer.new()
	overlay_list.add_theme_constant_override("separation", 10)
	overlay_card.add_child(overlay_list)

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
	if zone_top == null:
		return

	var margin := 10.0
	var gap := 8.0
	if _is_landscape():
		# Two columns: the board keeps the left, everything the player reads
		# or presses stacks on the right — so the end-turn button can never
		# be pushed off the bottom of a wide window the way it used to be.
		var board_w: float = min(vp.x * 0.56, vp.y * 1.05)
		var right_x: float = margin + board_w + gap
		var right_w: float = vp.x - right_x - margin
		_place(zone_board, Rect2(margin, margin, board_w, vp.y - margin * 2.0))
		var y: float = margin
		var top_h := 74.0
		var enemy_h := 126.0
		var cmd_h := 46.0
		var log_h := 38.0
		var hand_h: float = clamp(vp.y - margin * 2.0 - top_h - enemy_h - cmd_h - log_h - gap * 4.0, 120.0, 200.0)
		_place(zone_top, Rect2(right_x, y, right_w, top_h))
		y += top_h + gap
		_place(zone_enemy, Rect2(right_x, y, right_w, enemy_h))
		y += enemy_h + gap
		_place(zone_hand, Rect2(right_x, y, right_w, hand_h))
		y += hand_h + gap
		_place(zone_cmd, Rect2(right_x, y, right_w, cmd_h))
		y += cmd_h + gap
		_place(zone_log, Rect2(right_x, y, right_w, log_h))
	else:
		var width: float = vp.x - margin * 2.0
		var top_h := 74.0
		var enemy_h := 122.0
		var cmd_h := 46.0
		var log_h := 34.0
		var hand_h: float = clamp(vp.y * 0.19, 128.0, 168.0)
		var used: float = top_h + enemy_h + hand_h + cmd_h + log_h + gap * 5.0 + margin * 2.0
		var board_h: float = max(vp.y - used, 200.0)
		var y: float = margin
		_place(zone_top, Rect2(margin, y, width, top_h))
		y += top_h + gap
		_place(zone_enemy, Rect2(margin, y, width, enemy_h))
		y += enemy_h + gap
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
	var center := _board_origin() + Vector2(1.5, 1.5) * step
	ribbon_box.position = (center - wanted * 0.5).floor()

func _is_stop_cell(pos: Vector2i) -> bool:
	if not ring_index_map.has(pos):
		return false
	return str(tile_defs[str(permanent_board[pos.y][pos.x])]["trigger"]) == "stop"

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

func _process(delta: float) -> void:
	if cell_info_timer > 0.0:
		cell_info_timer -= delta
		if cell_info_timer <= 0.0 and log_label != null:
			log_label.text = log_hold

func _refresh_all() -> void:
	_refresh_top()
	_refresh_enemy()
	_refresh_board()
	_refresh_hand()
	_refresh_command()

func _set_log(text: String) -> void:
	log_hold = text
	cell_info_timer = 0.0
	if log_label != null:
		log_label.text = text

func _refresh_top() -> void:
	var in_run: bool = state != "title"
	zone_top.visible = in_run
	if not in_run:
		return
	run_label.text = "第%d戦" % max(encounter, 1)
	run_track.total = MAX_ENCOUNTERS
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

	combo_label.text = "コンボ %d" % combo
	combo_chip.visible = state == "player" or state == "moving"
	combo_chip.modulate = Color(1, 1, 1, 1.0 if combo > 0 else 0.5)

	_clear_children(action_pip_box)
	for i in range(ACTIONS_PER_TURN):
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

func _refresh_enemy() -> void:
	var show: bool = state != "title" and not enemies.is_empty()
	zone_enemy.visible = state != "title"
	enemy_panel.modulate = Color(1, 1, 1, 1.0 if show else 0.0)
	if not show:
		return
	var enemy: Dictionary = enemies[0]
	enemy_figure.kind = _enemy_icon_kind(str(enemy["type"]))
	enemy_figure.body_color = COL_ENEMY if str(enemy["type"]) != "ボス" else Color("#8E2F6B")
	enemy_name_label.text = "%s%s" % [str(enemy["type"]), "（ボス）" if str(enemy["type"]) == "ボス" else ""]
	enemy_hp_bar.max_value = int(enemy["max_hp"])
	enemy_hp_bar.value = max(int(enemy["hp"]), 0)
	_animate_gauge(enemy_hp_bar)
	enemy_hp_label.text = "%d/%d" % [max(int(enemy["hp"]), 0), int(enemy["max_hp"])]

	var guaranteed: bool = str(enemy.get("attack_kind", "positional")) == "guaranteed"
	intent_icon.set_kind("slash" if guaranteed else "focus")
	intent_label.text = str(int(enemy["damage"]))
	intent_panel.add_theme_stylebox_override("panel", _flat_style(COL_ENEMY if guaranteed else COL_DANGER, COL_INK, 3, 8, 3))
	intent_note.text = "毎ターン必ず当たる" if guaranteed else "光ったマスを通ると当たる"

func _refresh_command() -> void:
	var playing: bool = state == "player"
	if roll_catcher != null:
		roll_catcher.visible = playing and not dice_rolled and not hand.is_empty()
	zone_cmd.visible = state != "title"
	zone_hand.visible = state == "player" or state == "moving" or state == "enemy"
	end_turn_button.visible = playing or state == "moving" or state == "enemy"
	end_turn_button.disabled = not playing
	catalog_button.visible = state != "title"
	reroll_button.visible = playing or state == "moving" or state == "enemy"
	reroll_button.disabled = not (playing and dice_rolled and rerolls_left > 0 and not hand.is_empty())
	reroll_button.text = "振り直す %d" % rerolls_left

func _refresh_board() -> void:
	_rebuild_preview_path()
	_layout_board_buttons()
	danger_cells = _telegraphed_cells()
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
			button.visible = state != "title"

			var perm_type: String = str(permanent_board[pos.y][pos.x])
			var temp_type: String = str(temp_board[pos.y][pos.x])
			var tile: Dictionary = tile_defs[perm_type]
			var color: Color = tile["color"]
			var icon_kind: String = str(tile["icon"])
			var value_text := ""
			var value_color := Color("#FFF7E6")

			var boosted := false
			match str(tile["mode"]):
				"attack", "shock":
					value_text = str(int(tile["value"]) + _pending_route_bonus())
					boosted = _pending_route_bonus() > 0
				"shield", "heal", "step":
					value_text = "+%d" % int(tile["value"])
				"draw":
					value_text = "引"
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

			if state == "player" and ahead > 0:
				step_label.text = "+%d" % ahead
			if danger_cells.has(pos):
				border_color = COL_DANGER
				border_width = 5
				danger_label.text = "▲%d" % _telegraph_damage()
			if route_path.has(pos) and state == "moving":
				border_color = COL_ROUTE
				border_width = 5
			if is_player_cell:
				border_color = COL_GOLD
				border_width = 5

			button.disabled = state == "moving" or state == "title" or state == "reward_select"
			var dim := false
			if placing:
				if _can_place_reward(pos):
					border_color = COL_NEXT
					border_width = 4
					if pos == preview_place_pos:
						color = tile_defs[pending_reward_type]["color"]
						icon_kind = str(tile_defs[pending_reward_type]["icon"])
						value_text = "?"
						border_color = COL_GOLD
						border_width = 6
				else:
					button.disabled = true
					dim = true
			elif state == "player" and ahead <= 0 and not is_player_cell:
				# Out of reach this turn: still legible, just quieter.
				dim = true

			icon.set_kind(icon_kind)
			var plain: bool = perm_type == "empty" and temp_type == "none"
			icon.glyph_color = Color(1.0, 0.97, 0.90, 0.45 if plain else 1.0)
			icon.outline_color = Color(COL_INK.r, COL_INK.g, COL_INK.b, 0.45 if plain else 1.0)
			value_label.text = value_text
			if boosted:
				value_color = COL_GOLD
			value_label.add_theme_color_override("font_color", Color(value_color.r, value_color.g, value_color.b, 0.55 if plain else 1.0))
			button.tooltip_text = _cell_tooltip(pos, perm_type, temp_type)
			# A fouled tile darkens and takes a mark, but keeps its own
			# shape and icon: the board a player built stays legible under
			# whatever the enemy throws at it.
			debuff_label.text = ""
			if temp_type == "hazard":
				color = color.lerp(Color("#6F7A2A"), 0.32)
				debuff_label.text = "毒"
			var squared: bool = str(tile["trigger"]) == "stop"
			_apply_cell_style(button, color, border_color, border_width, dim, squared)
	_refresh_ribbon()
	board_view.queue_redraw()

# Attack tiles print what they would really deal. Mid-move that is the
# combo as it stands; while choosing, it is what the combo will be once a
# die is spent — which is the number the choice is actually made on.
func _pending_route_bonus() -> int:
	if state == "moving":
		return combo
	if state == "player":
		return combo + 1
	return 0

func _telegraph_damage() -> int:
	for enemy in enemies:
		if int(enemy["hp"]) > 0:
			return int(enemy["damage"])
	return 0

func _apply_cell_style(button: Button, color: Color, border_color: Color, border_width: int, dim: bool, squared: bool = false) -> void:
	var fill: Color = color if not dim else color.lerp(COL_PANEL_SUNK, 0.55)
	# Round tiles fire when you run through them, square tiles when you
	# land on them. Shape says it without spending any of the tile's space
	# on a word.
	var radius: int = 6 if squared else int(max(20.0, _board_token_size() * 0.5))
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
	normal.shadow_size = 5 if squared else 0
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
	var interior: float = _board_spacing() * 2.0 - _board_token_size() - 12.0
	var moving: bool = state == "moving"
	ribbon_caption.visible = state == "player" and dice_rolled and interior >= 96.0
	ribbon_row.visible = ribbon_caption.visible
	roll_readout.visible = moving
	ribbon_box.visible = (state == "player" and dice_rolled) or moving
	if combo_chip != null:
		combo_chip.visible = ribbon_box.visible

	if moving:
		roll_readout.visible = steps_left > 0
		roll_readout.text = "あと%d" % steps_left
		_clear_children(ribbon_row)
		_layout_ribbon()
		return
	_clear_children(ribbon_row)
	if not ribbon_row.visible:
		_layout_ribbon()
		return
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
	if temp_type == "hazard":
		color = color.lerp(Color("#6F7A2A"), 0.42)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var stop_chip: bool = str(tile["trigger"]) == "stop"
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

func _hand_columns() -> int:
	if hand_limit <= 5:
		return max(hand_limit, 1)
	return int(ceil(float(hand_limit) / 2.0))

func _ensure_hand_slots() -> void:
	var columns := _hand_columns()
	hand_row.columns = columns
	if hand_slots.size() == hand_limit:
		return
	_clear_children(hand_row)
	hand_slots = []
	for i in range(hand_limit):
		var slot := Control.new()
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hand_row.add_child(slot)
		hand_slots.append(slot)

func _refresh_hand() -> void:
	if hand_row == null:
		return
	_ensure_hand_slots()
	var columns := _hand_columns()
	var rows: int = int(ceil(float(hand_limit) / float(columns)))
	var slot_w: float = (zone_hand.size.x - 7.0 * float(columns - 1)) / float(max(columns, 1))
	var slot_h: float = (zone_hand.size.y - 7.0 * float(rows - 1)) / float(max(rows, 1))
	for i in range(hand_slots.size()):
		var slot: Control = hand_slots[i]
		_clear_children(slot)
		if i < hand.size():
			slot.add_child(_make_die_card(hand[i], i, slot_w, slot_h))
		else:
			slot.add_child(_make_empty_slot(slot_w))

func _make_empty_slot(slot_w: float = 120.0) -> Control:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := _flat_style(Color(0.85, 0.78, 0.63, 0.35), Color(COL_INK.r, COL_INK.g, COL_INK.b, 0.30), 2, 6, 6)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := _make_label(FS_SMALL, Color(COL_TEXT_SOFT.r, COL_TEXT_SOFT.g, COL_TEXT_SOFT.b, 0.7), HORIZONTAL_ALIGNMENT_CENTER)
	label.text = "使用済み" if slot_w >= 86.0 else "済"
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(label)
	return panel

# A die card built out of real containers, with the whole face of the card
# as one hit target. The six faces are drawn as pips instead of printed as
# "1/2/3/4/5/6", so a loaded die looks loaded at a glance.
func _make_die_card(die: Dictionary, index: int, slot_w: float = 120.0, slot_h: float = 140.0) -> Control:
	var tag := str(die["tag"])
	var faces: Array = die["faces"]
	var roll := int(die.get("roll", 0))
	var tight: bool = slot_w < 92.0
	var face_size: float = clamp(min(slot_w * 0.56, slot_h * 0.40), 26.0, 54.0)
	var pip_size: float = clamp((slot_w - 14.0) / float(max(faces.size(), 1)) - 2.0, 6.0, 13.0)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", _flat_style(_tag_color(tag), COL_INK, 3, 4 if tight else 5, 5))

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)

	var name_label := _make_label(FS_SMALL - (2 if tight else 0), COL_TEXT_ON_DARK, HORIZONTAL_ALIGNMENT_CENTER, true)
	name_label.text = str(die["name"]).replace("ダイス", "")
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

	var face := DiceFace.new()
	face.name = "RolledFace"
	face.value = max(roll, 1)
	face.query = roll <= 0
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

	if roll <= 0:
		var query := _make_label(int(face_size * 0.72), COL_INK, HORIZONTAL_ALIGNMENT_CENTER, true)
		query.text = "?"
		query.autowrap_mode = TextServer.AUTOWRAP_OFF
		query.set_anchors_preset(Control.PRESET_CENTER)
		query.offset_left = -half
		query.offset_top = -half - 7.0
		query.offset_right = half
		query.offset_bottom = half + 7.0
		face_holder.add_child(query)

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
		pip.value = int(face_value)
		pip.custom_minimum_size = Vector2(pip_size, pip_size)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.modulate = Color(1, 1, 1, 0.55 if int(face_value) != roll else 1.0)
		faces_row.add_child(pip)

	# The trait line is the first thing to go when the cards get narrow —
	# the result and the range are what a choice is actually made on.
	if not tight:
		var tag_label := _make_label(FS_SMALL - 1, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_CENTER)
		tag_label.text = _tag_name(tag)
		tag_label.clip_text = true
		col.add_child(tag_label)

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
	if enemy_figure == null or not is_instance_valid(enemy_figure):
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
	var anchor: Vector2 = enemy_figure.get_global_transform_with_canvas().origin
	label.position = anchor + Vector2(enemy_figure.size.x * 0.5 - 20.0, -10.0)
	label.scale = Vector2(0.4, 0.4)
	var base_y: float = label.position.y
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "scale", Vector2(1.15, 1.15), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "position:y", base_y - 34.0, 1.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.4).set_delay(0.65)
	tween.chain().tween_callback(label.queue_free)

func _lunge_enemy() -> void:
	if enemy_figure == null or not is_instance_valid(enemy_figure):
		return
	var base: Vector2 = enemy_figure.position
	var tween := create_tween()
	tween.tween_property(enemy_figure, "position", base + Vector2(0, 12), 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(enemy_figure, "position", base, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished

func _flash_enemy() -> void:
	if enemy_figure == null:
		return
	var tween := create_tween()
	tween.tween_property(enemy_figure, "flash", 1.0, 0.04)
	tween.tween_property(enemy_figure, "flash", 0.0, 0.22)

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
	if enemy_figure == null:
		return
	var burst := BurstEffect.new()
	burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	burst.set_anchors_preset(Control.PRESET_FULL_RECT)
	burst.center = enemy_figure.get_global_transform_with_canvas().origin + enemy_figure.size * 0.5
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
	_clear_children(overlay_list)

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

# A catalogue of every tile, grouped by when it fires. Reachable from the
# title and from inside a turn, because the question "what does that one
# do again" turns up mid-run, not before it.
func _show_catalog() -> void:
	catalog_return_state = state
	overlay.visible = true
	overlay_title.text = "マス図鑑"
	overlay_body.text = "○丸は通過で、□四角は止まって効くマス。攻撃マスのダメージには、そのターンに使ったダイスの数（コンボ）が加算されます。"
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

	for trigger in ["pass", "stop"]:
		var heading := _make_label(FS_BODY, COL_TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
		heading.text = "○ 通過型 — 走り抜けるたびに効く" if trigger == "pass" else "□ 停止型 — ぴたりと止まったときだけ効く"
		heading.autowrap_mode = TextServer.AUTOWRAP_OFF
		column.add_child(heading)
		for key in tile_defs.keys():
			var tile: Dictionary = tile_defs[key]
			if str(tile["trigger"]) != trigger:
				continue
			column.add_child(_make_catalog_row(tile))
	var debuff_heading := _make_label(FS_BODY, COL_TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	debuff_heading.text = "◇ 敵のデバフ — マスに重ねてかけられる"
	debuff_heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	column.add_child(debuff_heading)
	column.add_child(_make_catalog_row(temp_defs["hazard"]))

	if catalog_return_state != "title":
		var quit_row := Button.new()
		quit_row.text = "この挑戦をやめてタイトルへ"
		quit_row.focus_mode = Control.FOCUS_NONE
		quit_row.custom_minimum_size = Vector2(0, 40)
		quit_row.add_theme_font_size_override("font_size", FS_SMALL)
		_style_button(quit_row, COL_PANEL_SUNK, COL_INK)
		quit_row.add_theme_color_override("font_color", COL_INK)
		quit_row.pressed.connect(Callable(self, "_show_title"))
		overlay_list.add_child(quit_row)

	var close_button := Button.new()
	close_button.text = "閉じる"
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
	head.text = "%s　%s" % [str(tile["name"]), str(tile["effect"])]
	col.add_child(head)

	var detail := _make_label(FS_SMALL, COL_TEXT_SOFT, HORIZONTAL_ALIGNMENT_LEFT)
	detail.text = str(tile["detail"])
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
	_open_overlay("Dice Board Rogue", "手札のダイスを全部振り、出た目から1つ選んで進む。踏んだマスの効果で戦う、すごろくローグライク。全6戦。")
	for key in hero_defs.keys():
		var hero: Dictionary = hero_defs[key]
		var dice_names := []
		for die in hero["dice"]:
			dice_names.append(str(die["name"]).replace("ダイス", ""))
		_add_overlay_option(
			"%s   HP %d   手札%d" % [str(hero["name"]), int(hero["hp"]), int(hero.get("hand", 3))],
			"%s\nダイス: %s" % [str(hero["desc"]), "・".join(dice_names)],
			Color(hero["color"]),
			"slash" if key == "knight" else ("fire" if key == "mage" else "trap"),
			Callable(self, "_start_run").bind(key)
		)
	_add_overlay_option("マス図鑑", "どのマスが何をするかの一覧。", COL_TEXT_SOFT, "focus", Callable(self, "_show_catalog"))
	_layout_overlay()

func _show_reward() -> void:
	state = "reward_select"
	if encounter >= MAX_ENCOUNTERS:
		_show_victory()
		return
	sfx.emit("reward")
	_refresh_all()
	_open_overlay("戦闘に勝利", "マスを1つ選んで、次の戦いに持ち越すコースに置きます。")
	var options := reward_pool.duplicate(true)
	options.shuffle()
	for i in range(3):
		var reward_type := str(options[i]["type"])
		var tile: Dictionary = tile_defs[reward_type]
		_add_overlay_option(
			"%s［%s］" % [str(tile["name"]), str(tile["kind"])],
			"%s　%s" % [_trigger_label(str(tile["trigger"])), str(tile["effect"])],
			Color(tile["color"]),
			str(tile["icon"]),
			Callable(self, "_on_reward_selected").bind(reward_type, "%sマス" % str(tile["name"]))
		)
	_layout_overlay()

# "通過型" / "停止型" — the one word that says when a tile pays out.
func _trigger_label(trigger: String) -> String:
	return "○通過型" if trigger == "pass" else "□停止型"

func _show_victory() -> void:
	state = "victory"
	sfx.emit("kill")
	_refresh_all()
	_open_overlay("踏破成功", "%s は全%d戦を突破しました。" % [hero_name, MAX_ENCOUNTERS])
	_add_result_stats()
	_add_overlay_option("もう一度、同じキャラで", "同じ盤面構成から新しいランを始めます。", COL_HP, "warp", Callable(self, "_restart_same_hero"))
	_add_overlay_option("キャラを選び直す", "タイトルに戻ります。", COL_TEXT_SOFT, "dice", Callable(self, "_show_title"))
	_layout_overlay()
	_play_result_flourish(Color(1.0, 0.85, 0.45, 0.45))

func _show_game_over(reason: String) -> void:
	state = "game_over"
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
		["到達", "%d / %d戦" % [encounter, MAX_ENCOUNTERS]],
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
	hero_name = str(hero["name"])
	hero_token_color = Color(hero["color"])
	player_max_hp = int(hero["hp"])
	hand_limit = int(hero.get("hand", 3))
	player_hp = player_max_hp
	player_shield = 0
	next_enemy_uid = 0
	run_damage_dealt = 0
	run_turns = 0
	encounter = 0
	player_step = _track_index(_start_pos())
	player_pos = _pos_for_step(player_step)
	permanent_board = _make_empty_board("empty")
	for entry in hero["tiles"]:
		permanent_board[int(entry[1])][int(entry[0])] = str(entry[2])
	dice_bag = []
	for die in hero["dice"]:
		dice_bag.append(die.duplicate(true))
	hp_bar.display_value = float(player_hp)
	_start_encounter()
	_snap_player_visual()

func _start_encounter() -> void:
	encounter += 1
	if backdrop_view != null:
		backdrop_view.tint_progress = float(encounter - 1) / float(max(MAX_ENCOUNTERS - 1, 1))
	player_pos = _pos_for_step(player_step)
	player_shield = 0
	actions_left = ACTIONS_PER_TURN
	selected_die = {}
	selected_roll = 0
	selected_tag = ""
	steps_left = 0
	route_path = []
	combo = 0
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

func _setup_encounter() -> void:
	if encounter == MAX_ENCOUNTERS:
		enemies.append(_make_enemy("ボス", 58, 10, "guaranteed", []))
	else:
		var type_name := "はぐれ兵"
		var hp := 12 + encounter * 8
		var damage := 4 + encounter
		var attack_kind := "positional"
		var offsets: Array = [2]
		match encounter:
			1:
				offsets = [2]
			2:
				type_name = "斥候"
				offsets = [2, 4]
			3:
				type_name = "射手"
				attack_kind = "guaranteed"
				offsets = []
			4:
				type_name = "重装"
				offsets = [1, 3, 5]
			_:
				type_name = "隊長"
				offsets = [2, 4, 5]
		enemies.append(_make_enemy(type_name, hp, damage, attack_kind, offsets))

	for n in range(clamp(encounter - 1, 0, MAX_DEBUFFS - 1)):
		var p := _random_empty_cell()
		if p.x >= 0:
			temp_board[p.y][p.x] = "hazard"

	for enemy in enemies:
		_generate_telegraph(enemy)

func _make_enemy(type_name: String, hp: int, damage: int, attack_kind: String, offsets: Array) -> Dictionary:
	next_enemy_uid += 1
	return {
		"type": type_name,
		"uid": next_enemy_uid,
		"hp": hp,
		"max_hp": hp,
		"damage": damage,
		"attack_kind": attack_kind,
		"attack_offsets": offsets,
		"telegraph_cells": [],
	}

func _generate_telegraph(enemy: Dictionary) -> void:
	if str(enemy.get("attack_kind", "positional")) == "guaranteed":
		enemy["telegraph_cells"] = []
		return
	var cells: Array = []
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
	actions_left = ACTIONS_PER_TURN
	selected_die = {}
	selected_roll = 0
	steps_left = 0
	route_path = []
	combo = 0
	turn_visited = {}
	dice_rolled = false
	rerolls_left = REROLLS_PER_TURN
	_draw_to_hand()
	for die in hand:
		die["roll"] = 0
	if message != "":
		_set_log(message)
	_refresh_all()
	_set_banner("タップしてダイスを振る")

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
	var die: Dictionary = hand[index]
	var final_roll := int(die.get("roll", 0))
	if final_roll <= 0:
		return

	# Lock the state before the first await so a second tap during the move
	# cannot spend a second die.
	state = "moving"
	selected_die = die.duplicate(true)
	selected_roll = final_roll
	selected_tag = str(selected_die["tag"])
	steps_left = final_roll
	# Spending a die is what raises the combo.
	combo += 1
	route_path = [player_pos]
	discard_pile.append(selected_die)
	hand.remove_at(index)
	sfx.emit("hit")
	_set_log("%s：出目 %d" % [str(selected_die["name"]), final_roll])
	_refresh_all()
	await get_tree().create_timer(0.2).timeout
	await _advance_player()

func _advance_player() -> void:
	while steps_left > 0:
		player_step = _normalize_step(player_step + 1)
		player_pos = _pos_for_step(player_step)
		route_path.append(player_pos)
		turn_visited[player_pos] = true
		steps_left -= 1
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
	_set_log("敵を倒した。マスの毒も消えた。" if last_cleanse_count > 0 else "敵を倒した。")
	# Long enough to watch the enemy actually die before the reward card
	# covers the board.
	await get_tree().create_timer(1.2).timeout
	_show_reward()

func _resolve_pass_tile(pos: Vector2i) -> String:
	var messages := []
	if str(temp_board[pos.y][pos.x]) == "hazard":
		_take_damage(2)
		messages.append("毒のマス：HP-2")
	var tile_type: String = str(permanent_board[pos.y][pos.x])
	if str(tile_defs[tile_type]["trigger"]) == "pass":
		var effect := _apply_tile_effect(tile_type)
		if effect != "":
			messages.append(effect)
	return " ".join(messages)

func _resolve_stop_tile(pos: Vector2i) -> String:
	_flash_player_stop()
	var tile_type: String = str(permanent_board[pos.y][pos.x])
	var tile: Dictionary = tile_defs[tile_type]
	if str(tile["trigger"]) != "stop":
		# Landing on a pass tile is not a punishment, but it is a wasted
		# stop — say so plainly rather than leaving the player wondering
		# whether something fired.
		return "%sに停止。通過型なので効果なし" % str(tile["name"])
	return _apply_tile_effect(tile_type)

# One place where a tile's effect actually happens, driven by the table
# above — so a tile's rules, its board readout and its catalog entry can
# never drift apart.
func _apply_tile_effect(tile_type: String) -> String:
	var tile: Dictionary = tile_defs[tile_type]
	var name: String = str(tile["name"])
	var value := int(tile["value"])
	match str(tile["mode"]):
		"attack":
			var dmg := _combo_damage(value)
			if _strike(str(tile.get("target", "lowest")), dmg):
				return "%s：%dダメージ" % [name, dmg]
			return ""
		"shield":
			_gain_shield(value)
			return "%s：盾+%d" % [name, value]
		"heal":
			_heal(value)
			return "%s：HP+%d" % [name, value]
		"step":
			steps_left += value
			return "%s：%d歩追加" % [name, value]
		"shock":
			var shock_damage := _combo_damage(value)
			var landed := _strike(str(tile.get("target", "all")), shock_damage)
			_gain_shield(2)
			if landed:
				return "%s：%dダメージ、盾+2" % [name, shock_damage]
			return "%s：盾+2" % name
		"draw":
			_draw_to_hand()
			_refresh_hand()
			return "%s：ダイスを1枚補充" % name
		"combo":
			combo += value
			_spawn_floating_text(player_pos, "コンボ+%d" % value, COL_GOLD)
			return "%s：コンボ+%d（今 %d）" % [name, value, combo]
	return ""

func _strike(target: String, amount: int) -> bool:
	match target:
		"highest":
			return _strike_highest(amount)
		"all":
			return _strike_all(amount)
	return _strike_lowest(amount)

func _combo_damage(base: int) -> int:
	return base + combo

func _lowest_hp_enemy() -> Dictionary:
	var best := {}
	var best_hp := 2147483647
	for enemy in enemies:
		var hp := int(enemy["hp"])
		if hp > 0 and hp < best_hp:
			best = enemy
			best_hp = hp
	return best

func _highest_hp_enemy() -> Dictionary:
	var best := {}
	var best_hp := -1
	for enemy in enemies:
		var hp := int(enemy["hp"])
		if hp > 0 and hp > best_hp:
			best = enemy
			best_hp = hp
	return best

func _strike_lowest(amount: int) -> bool:
	var target := _lowest_hp_enemy()
	if target.is_empty():
		return false
	_damage_enemy(target, amount)
	return true

func _strike_highest(amount: int) -> bool:
	var target := _highest_hp_enemy()
	if target.is_empty():
		return false
	_damage_enemy(target, amount)
	return true

func _strike_all(amount: int) -> bool:
	var hit_any := false
	for enemy in enemies:
		if int(enemy["hp"]) > 0:
			_damage_enemy(enemy, amount)
			hit_any = true
	return hit_any

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
		_punch(hero_portrait, 1.18)
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

func _damage_enemy(enemy: Dictionary, amount: int) -> void:
	if amount <= 0:
		return
	enemy["hp"] = int(enemy["hp"]) - amount
	run_damage_dealt += amount
	_spawn_enemy_popup("-%d" % amount, Color("#FFE0CF"), amount >= 6)
	_flash_enemy()
	sfx.emit("hit")
	if amount >= 6:
		_shake(zone_enemy, 4.0)
	_refresh_enemy()

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
	_set_banner("敵のターン")
	await get_tree().create_timer(BEAT_PHASE).timeout
	var messages := []
	for enemy in enemies:
		if int(enemy["hp"]) <= 0:
			continue
		var hit := false
		if str(enemy.get("attack_kind", "positional")) == "guaranteed":
			hit = true
		else:
			for c in enemy.get("telegraph_cells", []):
				if turn_visited.has(c):
					hit = true
					break
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

	if encounter >= 3 and not enemies.is_empty() and _debuff_count() < MAX_DEBUFFS and rng.randi_range(0, 100) < 45:
		var p := _random_empty_cell()
		if p.x >= 0:
			temp_board[p.y][p.x] = "hazard"
			messages.append("マスに毒がかけられた")
			_set_log("マスに毒がかけられた")
			_refresh_board()
			_spawn_floating_text(p, "毒", Color("#5B7A0F"))
			sfx.emit("hurt")
			await get_tree().create_timer(BEAT_EFFECT).timeout

	_hide_banner()
	_cleanup_dead_enemies()
	if player_hp <= 0:
		_show_game_over("敵の攻撃で倒れました。")
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
	_set_log("行動を終えました。")
	_enemy_turn()

# --- rewards -----------------------------------------------------------

func _on_reward_selected(tile_type: String, tile_name: String) -> void:
	pending_reward_type = tile_type
	pending_reward_name = tile_name
	preview_place_pos = Vector2i(-1, -1)
	state = "reward_place"
	_close_overlay()
	_set_banner("%s を置くマスをタップ" % tile_name)
	_set_log("始点以外のどのマスにも置けます。置いたマスは次の戦いにも残ります。")
	_refresh_all()

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
			_set_banner("ここに置く？ もう一度タップで確定")
			_refresh_board()
			return
		permanent_board[pos.y][pos.x] = pending_reward_type
		preview_place_pos = Vector2i(-1, -1)
		_hide_banner()
		sfx.emit("reward")
		if encounter >= MAX_ENCOUNTERS:
			_show_victory()
		else:
			_start_encounter()
			_set_log("%s を配置しました。" % pending_reward_name)
	elif ring_index_map.has(pos):
		_show_cell_info(pos)

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
	parts.append("%s %s" % [str(tile["name"]), _trigger_label(str(tile["trigger"]))])
	parts.append(str(tile["effect"]))
	if temp_type == "hazard":
		parts.append("毒がかかっている（通過でHP-2）")
	if danger_cells.has(pos):
		parts.append("敵の攻撃予告あり")
	if log_label != null:
		log_label.text = " / ".join(parts)
	cell_info_timer = 3.5

func _cell_tooltip(pos: Vector2i, perm_type: String, temp_type: String) -> String:
	var lines := []
	var ahead := _steps_ahead(pos)
	if ahead > 0:
		lines.append("現在地から%dマス先" % ahead)
	if danger_cells.has(pos):
		lines.append("敵の攻撃予告")
	if temp_type != "none":
		lines.append(str(temp_defs[temp_type]["desc"]))
	var tile: Dictionary = tile_defs[perm_type]
	lines.append("%s %s: %s" % [str(tile["name"]), _trigger_label(str(tile["trigger"])), str(tile["effect"])])
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
	ring_cells = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
		Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 3),
		Vector2i(2, 3), Vector2i(1, 3), Vector2i(0, 3),
		Vector2i(0, 2), Vector2i(0, 1),
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

# Where a roll of this size actually finishes, following 跳躍路 the same
# way the move itself will.
func _landing_cell_for(roll: int) -> Vector2i:
	var step := player_step
	var remaining := roll
	var guard := 0
	while remaining > 0 and guard < 32:
		guard += 1
		step = _normalize_step(step + 1)
		remaining -= 1
		var p := _pos_for_step(step)
		var tile: Dictionary = tile_defs[str(permanent_board[p.y][p.x])]
		if str(tile["trigger"]) == "pass" and str(tile["mode"]) == "step":
			remaining += int(tile["value"])
	return _pos_for_step(step)

func _steps_ahead(pos: Vector2i) -> int:
	var idx := preview_path.find(pos)
	if idx == -1:
		return -1
	return idx + 1

func _start_pos() -> Vector2i:
	if ring_cells.is_empty():
		return Vector2i.ZERO
	return ring_cells[0]

func _rebuild_preview_path() -> void:
	preview_path = []
	if state != "player":
		return
	for i in range(1, 7):
		preview_path.append(_pos_for_step(player_step + i))

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

# Dice have no hidden bonuses: a die is the set of faces printed on it,
# and the label only describes how those faces lean.
func _tag_name(tag: String) -> String:
	match tag:
		"fire":
			return "均等"
		"steel":
			return "小さめ"
		"heavy":
			return "大きめ"
		"swift":
			return "小さめ"
		"trick":
			return "ばらつく"
		"lucky":
			return "偏り"
		"arcane":
			return "両極端"
		"focus":
			return "中くらい"
	return "均等"

func _tag_color(tag: String) -> Color:
	match tag:
		"fire":
			return Color("#F2762B")
		"steel":
			return Color("#2E7BD6")
		"heavy":
			return Color("#B5502A")
		"swift":
			return Color("#2AA1A8")
		"trick":
			return Color("#C2457E")
		"lucky":
			return Color("#C9971F")
		"arcane":
			return Color("#7C4DD6")
		"focus":
			return Color("#5B8C2A")
	return Color("#54687F")

func _enemy_icon_kind(type_name: String) -> String:
	match type_name:
		"射手":
			return "enemy_archer"
		"重装":
			return "enemy_heavy"
		"ボス":
			return "enemy_boss"
	return "enemy_grunt"

func _clear_children(node: Node) -> void:
	if node == null:
		return
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
