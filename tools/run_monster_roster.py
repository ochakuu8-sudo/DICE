"""Redraw the whole enemy roster as monsters, in シズク's finish.

Two problems solved by the same pass. DESIGN_DIRECTION.md §4 wants the
roster inhuman, and names the reason: the eight figures shipped so far
all had the same girl silhouette, so an enemy did not read as an enemy.
And since シズク stopped being a pixel sprite, the pixel enemies became
the one thing on screen speaking a different language.

So each monster is derived from what it already *does* rather than
invented and then assigned stats — its silhouette is its behaviour:

  stray   粘体      no debuff at all, the square where the rules are
                    learned. Formless, low, harmless-looking.
  scout   絡み蔦    spreads 茨. Briar is literally vines, and it strikes
                    at two separate distances: reaching tendrils.
  archer  灼眼      guaranteed hit, spreads 炎上. It never misses because
                    it is an eye, and it burns. Floating and round, so it
                    shares no contour with anything that stands.
  heavy   擬態箱    fixed squares, armour 3, spreads 凍結. It does not
                    move because it is furniture, it is armoured because
                    it is a box, and 凍結 holds you still: a mimic.
  plague  胞子塊    poison plus regeneration, strikes close. Fungus.
  captain 贄喰い    thorns (touching it costs) over a wide reach: arms.
  boss    深淵の主  guaranteed, armoured, regenerating. Inescapable.

§4 also asks for scale to come from composition rather than canvas,
since every figure is fitted into the same frame — so the framing tightens
as the roster climbs and the boss is drawn closest.

No character LoRA here: that one is シズク. Base Chroma only.
"""

import json
import shutil
import time
import urllib.parse
import urllib.request
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

COMFY = "http://127.0.0.1:8188"
ROOT = Path(r"C:\Users\yuuuu\Documents\Codex\2026-08-20\c-users-yuuuu-ai-comfyui-windows")
REPO = ROOT / "work" / "DICE"
PROJECT = REPO / "godot_project"
COMFY_OUTPUT = Path(
    r"C:\Users\yuuuu\AI\ComfyUI_windows_portable_nvidia\ComfyUI_windows_portable\ComfyUI\output"
)
OUT = ROOT / "outputs" / "monster_roster"

# Base Chroma renders whatever style each prompt suggests, which is why
# seven prompts came back in seven different idioms — a glossy mobile
# slime next to a flat vector octopus next to a painterly eye. The fix is
# not a better prompt, it is a model that owns the style: every sprite
# below is rendered by the same pixel checkpoint, so consistency is a
# property of the pipeline rather than of how carefully each line is
# worded. Settings taken from the 2d_pixel_toolkit_lora_asset workflow.
CKPT = "2D_Pixel_Sprites.safetensors"
PIXEL_LORA = "pixel sprites.safetensors"
PIXEL_LORA_STRENGTH = 0.7
# SD1.5 territory, and 512x768 is exactly 2:3 so it seats in the 800x1200
# sheet without distortion.
GEN_W, GEN_H = 512, 768
SHEET_W, SHEET_H = 800, 1200
FACE = 256
INGAME = (274, 412)
INK = (42, 35, 32)
OUTLINE_PX = 7

STYLE = (
    "pixel, pixel art, pixelart, xiangsu, xiang su, game asset, "
    "front view, full body, single character, standing idle pose, centered, "
    "solid white background, crisp outline, limited color palette, "
    "sharp pixel edges, bright saturated colours, friendly cartoon mascot"
)
NEGATIVE = (
    "lowres, worst quality, bad quality, blurry, fuzzy edges, smooth painting, "
    "realistic, 3d render, photo, text, watermark, logo, cropped, out of frame, "
    "duplicate, multiple objects, multiple characters, multiple views, "
    "busy background, gradient background, shadow, "
    "human, girl, woman, humanoid, human face, "
    "horror, creepy, scary, gore, gloomy, desaturated"
)

# Same seven identities, still each one derived from what it does in the
# fight — a face and a bright palette change the tone, not the design.
# "fill" is §4's scale: every sprite is fitted into the same panel, so the
# only way one creature can loom over another is to be given more of the
# shared frame. Prompting for close framing alone did nothing, because
# cropping to the alpha bbox normalised it straight back out.
MONSTERS = [
    {
        "actor": "stray", "fill": 0.62, "name": "粘体", "seed": 95101,
        "framing": "full body, small creature, plenty of space around it",
        "body": "a round bouncy slime blob with a big glossy highlight, "
                "bright mint green and translucent, two big simple round eyes "
                "and a small cheerful smile, soft jiggly shape, "
                "tiny sparkles floating inside it",
    },
    {
        "actor": "scout", "fill": 0.78, "name": "絡み蔦", "seed": 95102,
        "framing": "full body, medium distance",
        "body": "a friendly plant creature made of curling springy vines, "
                "fresh grass green, big round leaves and one bright pink flower "
                "on top, two big round eyes peeking out from the leaves, "
                "curly tendrils reaching out playfully",
    },
    {
        "actor": "archer", "fill": 0.76, "name": "灼眼", "seed": 95103,
        "framing": "full body, medium distance, floating in the air",
        "body": "a cheerful floating eyeball mascot wearing a crown of "
                "rounded cartoon flames, one big glossy eye with a bright "
                "orange iris, simple bold flame shapes in warm orange and "
                "yellow, little sparks bouncing around it",
    },
    {
        "actor": "heavy", "fill": 0.82, "name": "擬態箱", "seed": 95104,
        "framing": "full body, medium close, squat and chunky in frame",
        "body": "a chunky cartoon treasure chest monster, warm honey brown wood "
                "with bright gold trim, open lid grinning like a mouth with big "
                "blunt rounded teeth, a big pink tongue sticking out, two big "
                "round googly eyes on the lid, stubby little feet",
    },
    {
        "actor": "plague", "fill": 0.86, "name": "胞子塊", "seed": 95105,
        "framing": "full body, medium close",
        "body": "a round mushroom creature, big bright purple cap with cream "
                "polka dots, chubby rounded body, two big round eyes and a "
                "small smile, little puffs of sparkly spores floating around it",
    },
    {
        "actor": "captain", "fill": 0.92, "name": "贄喰い", "seed": 95106,
        "framing": "close framing, the creature fills much of the frame",
        "body": "a plump cartoon octopus creature with many curly arms, "
                "bright coral red and cream, big round friendly eyes, "
                "round suckers along springy playful tentacles",
    },
    {
        "actor": "boss", "fill": 1.00, "name": "深淵の主", "seed": 95107,
        "framing": "very close framing, looming large, filling most of the frame",
        "body": "a giant round cartoon maw creature, big bold rounded body with "
                "a wide open mouth and large blunt rounded teeth, bright teal "
                "and deep blue, two big round eyes above the mouth, "
                "chunky and bold and larger than everything else",
    },
]


def post_json(path, payload):
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        COMFY + path, data=data, headers={"Content-Type": "application/json"}, method="POST"
    )
    with urllib.request.urlopen(req, timeout=60) as res:
        return json.loads(res.read().decode("utf-8"))


def get_json(path):
    with urllib.request.urlopen(COMFY + path, timeout=60) as res:
        return json.loads(res.read().decode("utf-8"))


def wait_for_history(prompt_id):
    path = "/history/" + urllib.parse.quote(prompt_id)
    while True:
        hist = get_json(path)
        if prompt_id in hist:
            return hist[prompt_id]
        time.sleep(2)


def copy_outputs(history, dest_prefix):
    copied = []
    for node_out in history.get("outputs", {}).values():
        for image in node_out.get("images", []):
            src = COMFY_OUTPUT / image.get("subfolder", "") / image["filename"]
            dst = OUT / f"{dest_prefix}_{image['filename']}"
            shutil.copy2(src, dst)
            copied.append(dst)
    return copied


def source_prompt(mon, prefix):
    positive = f"{STYLE}, {mon['body']}, {mon['framing']}"
    return {
        "1": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": CKPT}},
        "2": {
            "class_type": "LoraLoader",
            "inputs": {
                "model": ["1", 0],
                "clip": ["1", 1],
                "lora_name": PIXEL_LORA,
                "strength_model": PIXEL_LORA_STRENGTH,
                "strength_clip": PIXEL_LORA_STRENGTH,
            },
        },
        "3": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["2", 1], "text": positive}},
        "4": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["2", 1], "text": NEGATIVE}},
        "5": {
            "class_type": "EmptyLatentImage",
            "inputs": {"width": GEN_W, "height": GEN_H, "batch_size": 1},
        },
        "6": {
            "class_type": "KSampler",
            "inputs": {
                "model": ["2", 0],
                "seed": mon["seed"],
                "steps": 28,
                "cfg": 7.0,
                "sampler_name": "dpmpp_2m",
                "scheduler": "karras",
                "positive": ["3", 0],
                "negative": ["4", 0],
                "latent_image": ["5", 0],
                "denoise": 1.0,
            },
        },
        "7": {"class_type": "VAEDecode", "inputs": {"samples": ["6", 0], "vae": ["1", 2]}},
        "8": {
            "class_type": "SaveImage",
            "inputs": {"images": ["7", 0], "filename_prefix": prefix},
        },
    }

# --- cutout: identical treatment to シズク's, so they sit together -------

FLOOD_T = 78.0
RAMP_LO = 26.0
RAMP_HI = 70.0


def cutout(src_path, actor, fill=1.0):
    im = Image.open(src_path).convert("RGB")
    rgb = np.asarray(im).astype(np.float32)
    h, w, _ = rgb.shape

    border = np.concatenate([rgb[0, :], rgb[-1, :], rgb[:, 0], rgb[:, -1]])
    bg = np.median(border, axis=0)
    dist = np.linalg.norm(rgb - bg[None, None, :], axis=2)

    floodable = dist < FLOOD_T
    outside = np.zeros((h, w), dtype=bool)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if floodable[y, x] and not outside[y, x]:
                outside[y, x] = True
                q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if floodable[y, x] and not outside[y, x]:
                outside[y, x] = True
                q.append((y, x))
    while q:
        y, x = q.popleft()
        for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
            if 0 <= ny < h and 0 <= nx < w and floodable[ny, nx] and not outside[ny, nx]:
                outside[ny, nx] = True
                q.append((ny, nx))

    alpha = np.ones((h, w), dtype=np.float32)
    ramp = np.clip((dist - RAMP_LO) / (RAMP_HI - RAMP_LO), 0.0, 1.0)
    alpha[outside] = ramp[outside]

    a3 = alpha[:, :, None]
    safe = np.maximum(a3, 1e-3)
    true_rgb = np.clip((rgb - (1.0 - a3) * bg[None, None, :]) / safe, 0, 255)
    cut = Image.fromarray(np.dstack([true_rgb, alpha * 255.0]).astype(np.uint8), "RGBA")

    bbox = cut.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    if bbox:
        cut = cut.crop(bbox)
    inner_w = SHEET_W - OUTLINE_PX * 4
    inner_h = int((SHEET_H - OUTLINE_PX * 4) * fill)
    # NEAREST, not LANCZOS: this art's whole character is in its hard
    # edges, and a smooth filter dissolves exactly that.
    cut.thumbnail((inner_w, inner_h), Image.Resampling.NEAREST)

    sheet = Image.new("RGBA", (SHEET_W, SHEET_H), (0, 0, 0, 0))
    sheet.paste(cut, ((SHEET_W - cut.width) // 2, SHEET_H - OUTLINE_PX * 2 - cut.height), cut)

    grown = sheet.getchannel("A").filter(ImageFilter.MaxFilter(OUTLINE_PX * 2 + 1))
    ink = Image.new("RGBA", sheet.size, INK + (0,))
    ink.putalpha(grown)
    final = Image.alpha_composite(ink, sheet)

    out_path = OUT / f"{actor}_idle.png"
    final.save(out_path)
    return out_path


def make_face(stage_path, actor):
    """The map node icon: the creature's own middle, not a shrunk full body.

    A whole figure scaled into 256px is a smudge; the node only has to say
    which creature is waiting there.
    """
    im = Image.open(stage_path).convert("RGBA")
    bbox = im.getchannel("A").getbbox()
    if bbox is None:
        bbox = (0, 0, im.width, im.height)
    left, top, right, bottom = bbox
    bw, bh = right - left, bottom - top
    side = min(bw, bh)
    cx = left + bw // 2
    # Upper-middle of the mass reads as the "head" end for most of these.
    cy = top + int(bh * 0.34) if bh > side else top + bh // 2
    x0 = max(0, min(im.width - side, cx - side // 2))
    y0 = max(0, min(im.height - side, cy - side // 2))
    crop = im.crop((x0, y0, x0 + side, y0 + side))
    crop.thumbnail((FACE - 20, FACE - 20), Image.Resampling.NEAREST)
    canvas = Image.new("RGBA", (FACE, FACE), (0, 0, 0, 0))
    canvas.paste(crop, ((FACE - crop.width) // 2, (FACE - crop.height) // 2), crop)
    out = OUT / f"{actor}_node.png"
    canvas.save(out)
    return out


def make_contact(results):
    plate_y = 300
    cell_w, cell_h = 300, plate_y + INGAME[1] + 16
    sheet = Image.new("RGB", (cell_w * len(results), cell_h), (58, 44, 48))
    try:
        font = ImageFont.truetype("arial.ttf", 15)
    except OSError:
        font = ImageFont.load_default()
    for idx, r in enumerate(results):
        cell = Image.new("RGB", (cell_w, cell_h), (74, 58, 62))
        src = Image.open(r["source"]).convert("RGB")
        src.thumbnail((cell_w - 20, 284), Image.Resampling.LANCZOS)
        cell.paste(src, ((cell_w - src.width) // 2, 4))
        cut = Image.open(r["stage"]).convert("RGBA")
        shown = cut.copy()
        shown.thumbnail(INGAME, Image.Resampling.NEAREST)
        plate = Image.new("RGBA", INGAME, (255, 247, 230, 255))
        plate.paste(shown, ((INGAME[0] - shown.width) // 2, (INGAME[1] - shown.height) // 2), shown)
        cell.paste(plate.convert("RGB"), ((cell_w - INGAME[0]) // 2, plate_y))
        ImageDraw.Draw(cell).text((8, plate_y - 16), "%s (%s)" % (r["name"], r["actor"]),
                                  fill=(236, 226, 209), font=font)
        sheet.paste(cell, (idx * cell_w, 0))
    out = ROOT / "outputs" / "dice_monster_roster_contact.jpg"
    sheet.save(out, "JPEG", quality=93, optimize=True)
    return out


def install(results):
    stage_dir = PROJECT / "art" / "stage"
    face_dir = PROJECT / "art" / "face"
    installed = []
    for r in results:
        for src, dest in (
            (r["stage"], stage_dir / f"{r['actor']}_idle.png"),
            (r["face"], face_dir / f"{r['actor']}_node.png"),
        ):
            shutil.copy2(src, dest)
            installed.append(str(dest))
    return installed


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    results = []
    for mon in MONSTERS:
        print(f"GEN {mon['actor']} ({mon['name']})", flush=True)
        hist = wait_for_history(
            post_json("/prompt", {"prompt": source_prompt(mon, f"monster_{mon['actor']}")})["prompt_id"]
        )
        src = copy_outputs(hist, mon["actor"])[0]
        stage = cutout(src, mon["actor"], mon.get("fill", 1.0))
        face = make_face(stage, mon["actor"])
        results.append(
            {
                "actor": mon["actor"], "name": mon["name"], "seed": mon["seed"],
                "source": str(src), "stage": str(stage), "face": str(face),
                "body": mon["body"], "framing": mon["framing"],
            }
        )
        print(f"DONE {mon['actor']}", flush=True)

    (OUT / "run_results.json").write_text(
        json.dumps(
            {
                "ckpt": CKPT,
                "lora": PIXEL_LORA,
                "sampler": f"dpmpp_2m / karras / 28 steps / cfg 7.0 / {GEN_W}x{GEN_H}",
                "style": STYLE,
                "negative": NEGATIVE,
                "results": results,
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    print(json.dumps({"contact": str(make_contact(results))}, indent=2), flush=True)


if __name__ == "__main__":
    main()
