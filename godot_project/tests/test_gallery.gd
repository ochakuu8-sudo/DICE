extends SceneTree

# The CG catalog is fully browsable before art and achievement triggers are
# implemented. These checks keep its stable IDs, condition text and gallery
# fallback from regressing while the actual CG files are added later.

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

	var entries: Array = main._gallery_entries()
	check("catalog has twenty entries", entries.size(), 20)
	var ids := {}
	var valid_conditions := true
	var kinds := {"fatigue_end": 0, "climax_cutin": 0, "ending": 0}
	for raw in entries:
		var entry: Dictionary = raw
		var id := str(entry.get("id", ""))
		if id == "" or ids.has(id) or str(entry.get("condition", "")) == "" \
				or str(entry.get("condition_kind", "")) == "":
			valid_conditions = false
		ids[id] = true
		var kind := str(entry.get("kind", ""))
		kinds[kind] = int(kinds.get(kind, 0)) + 1
	check("every entry has a unique ID and condition", valid_conditions, true)
	check("catalog has seven fatigue ends", int(kinds["fatigue_end"]), 7)
	check("catalog has seven climax cutins", int(kinds["climax_cutin"]), 7)
	check("catalog has six final endings", int(kinds["ending"]), 6)

	main._show_gallery()
	check("gallery is open", main.state, "gallery")
	check("all cards are listed without unlocks", main.gallery_grid.get_child_count(), 20)
	var first: Dictionary = entries[0]
	main._replay_scene(first)
	check("missing CG opens the condition fallback", main.overlay.visible, true)
	check("fallback names the selected CG", main.overlay_title.text, str(first["title"]))

	print("\n%d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
