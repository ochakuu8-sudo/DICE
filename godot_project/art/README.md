# art/

Drop image files here and the game picks them up. Nothing in `Main.gd` has
to be edited to accept a new file — the code asks for a *slot*, and a slot
is a path.

## The naming rule

```
art/<category>/<actor>_<state>.png          a still
art/<category>/<actor>_<state>_0.png        frame 0 of an animation
art/<category>/<actor>_<state>_1.png        frame 1
...                                          (probed up to _23)
```

If `<actor>_<state>.png` exists it wins and the slot is a single still.
Otherwise the loader collects `_0`, `_1`, … until a number is missing, and
plays them as a loop. So an animation is a numbered run with no gaps — a
gap silently truncates the clip.

Any slot with no file draws a magenta placeholder with the slot id written
across it. That is deliberate: a missing picture should be impossible to
miss in a screenshot, and a prettier fallback would hide how much art is
still outstanding.

## Categories

### `stage/` — the standing figures in a fight

Shown in the left column (the player) and the right column (the enemy).
Authored tall: the frames they land in are roughly **300×450** and
**250×430** at the 1024×576 design size, and art is fitted inside, never
cropped, so anything from 2:3 to 3:5 sits well. A transparent background is
expected — the panel behind it is part of the UI.

| state  | when it plays |
| ------ | ------------- |
| `idle` | the default. **The only required file.** |
| `hit`  | plays once when that character takes damage, then returns to idle |
| `down` | swapped in below 35% HP (falls back to `idle` if absent) |
| `win`  | reserved; not yet shown by any screen |

`hit` is the in-battle animation slot. It must read in well under a second
— a fight is twenty-odd turns long and this plays on every one of them, so
it is a flinch, not a scene.

### `cg/` — full-frame scene art

Covers the whole window when a fight is decided, and again in the gallery.
Authored at **16:9**, 1920×1080 or larger.

| state   | when it plays |
| ------- | ------------- |
| `win`   | the enemy is defeated, before the reward card |
| `lose`  | the enemy kills the player |
| `scene` | an event node's illustration (actor = the event id) |

A fight shows at most one scene, so `win` and `lose` are mutually exclusive
within a single encounter.

## Actor ids

An actor id is the `art` field on a row in `Main.gd`, never a display name
— renaming a character in Japanese must not orphan its files.

| actor     | who                          |
| --------- | ---------------------------- |
| `knight`  | the player character (剣士)   |
| `stray`   | はぐれ兵                      |
| `scout`   | 斥候                          |
| `archer`  | 射手                          |
| `heavy`   | 重装                          |
| `plague`  | 疫病持ち                      |
| `captain` | 隊長                          |
| `boss`    | ボス                          |

Event ids double as actors for `cg/<id>_scene.png`: `shrine`, and the rest
of the keys in `event_defs`.

## Adding a character

1. Give its row in `enemy_defs` an `art` id.
2. Drop `stage/<id>_idle.png`.
3. Everything else is optional and degrades quietly — except `cg/`, which
   shows a placeholder, because a fight that resolves to nothing is a bug
   in the content, not a style choice.

## Importing

Godot generates a `.import` sidecar for every image the first time the
project is opened in the editor. Files copied in while the editor is closed
are invisible to an export until the editor has been opened once — the
loader tests for the *imported* resource, not for the file on disk. Commit
the `.import` files alongside the art.
