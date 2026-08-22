"""シズク's stage sprite as a finished illustration — no pixelization.

The screen's actual design language is not pixel art. Every board tile,
panel, chip and dice card is a clean shape with a COL_INK (#2A2320)
outline; IconGlyph even documents the technique ("painted twice: once
grown into the outline color, once at true size"). The pixel sprites
were the one thing on screen that did not speak it.

So: render the illustration, key it cleanly, and give it the same ink
outline the rest of the frame wears. Three things have to be right for
this to look made rather than exported —

  1. no white fringe. A hard binary key on an anti-aliased illustration
     leaves one, so alpha ramps across the boundary band and the
     background colour is un-mixed back out of the semi-transparent
     pixels.
  2. interior whites survive. Her dress is mostly white, so the key is a
     flood fill inwards from the border, never a global colour match.
  3. the outline lands at the same visual weight as the board's. The
     board draws 3px at display size and she is shown at ~0.4x, so the
     rim is authored at 7px.
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
COMFY_ROOT = Path(
    r"C:\Users\yuuuu\AI\ComfyUI_windows_portable_nvidia\ComfyUI_windows_portable\ComfyUI"
)
COMFY_OUTPUT = COMFY_ROOT / "output"
OUT = ROOT / "outputs" / "shizuku_stage_clean"

UNET = "chroma-unlocked-v50-fp8-scaled.safetensors"
LORA = "shizuku_charalora_v4_hair_ornament_chromav50-step00004000.safetensors"

# 832x1248 is exactly 2:3, so fitting to the manifest's 800x1200 is a
# clean scale with no aspect distortion.
GEN_W, GEN_H = 832, 1248
SHEET_W, SHEET_H = 800, 1200
INGAME = (274, 412)
INK = (42, 35, 32)
OUTLINE_PX = 7

POSITIVE = (
    "shizuku_charalora, shizuku, 1girl, front standing full body, standing straight, "
    "whole body visible from head to feet, feet visible, "
    "pale blonde very long hair, blunt bangs, "
    "large black and white ribbon bow, antique gold flower hair ornament, "
    "black hanging tassel, black high collar, black corset bodice, "
    "white puffy sleeves, black and white noble dress, "
    "antique gold shoulder armor, "
    "crisp clean ink linework, confident outlines, flat cel shading, "
    "high quality character illustration, game character art, "
    "plain flat white background, no shadow on the ground"
)
NEGATIVE = (
    "low quality, worst quality, bad anatomy, bad hands, extra fingers, "
    "missing fingers, fused fingers, distorted face, color bleeding, "
    "gray skin, skin-colored clothing, text, watermark, signature, "
    "cropped, close-up, portrait, bust shot, multiple characters, "
    "busy background, scenery, gradient background, cast shadow, "
    "blurry edges, soft focus, sketch, unfinished"
)

SEEDS = [92101, 92102, 92103, 92104, 92105, 92106]


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


def source_prompt(seed, prefix):
    return {
        "1": {"class_type": "UNETLoader", "inputs": {"unet_name": UNET, "weight_dtype": "default"}},
        "2": {
            "class_type": "LoraLoaderModelOnly",
            "inputs": {"model": ["1", 0], "lora_name": LORA, "strength_model": 1.0},
        },
        "3": {
            "class_type": "CLIPLoader",
            "inputs": {
                "clip_name": "t5xxl_fp8_e4m3fn.safetensors",
                "type": "chroma",
                "device": "default",
            },
        },
        "4": {
            "class_type": "T5TokenizerOptions",
            "inputs": {"clip": ["3", 0], "min_padding": 0, "min_length": 3},
        },
        "5": {"class_type": "VAELoader", "inputs": {"vae_name": "ae.safetensors"}},
        "6": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["4", 0], "text": POSITIVE}},
        "7": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["4", 0], "text": NEGATIVE}},
        "8": {
            "class_type": "EmptySD3LatentImage",
            "inputs": {"width": GEN_W, "height": GEN_H, "batch_size": 1},
        },
        "9": {
            "class_type": "KSampler",
            "inputs": {
                "model": ["2", 0],
                "seed": seed,
                "steps": 24,
                "cfg": 3.8,
                "sampler_name": "euler",
                "scheduler": "beta",
                "positive": ["6", 0],
                "negative": ["7", 0],
                "latent_image": ["8", 0],
                "denoise": 1.0,
            },
        },
        "10": {"class_type": "VAEDecode", "inputs": {"samples": ["9", 0], "vae": ["5", 0]}},
        "11": {
            "class_type": "SaveImage",
            "inputs": {"images": ["10", 0], "filename_prefix": prefix},
        },
    }


# --- cutout -------------------------------------------------------------

FLOOD_T = 78.0     # what counts as "still background" while flooding inward
RAMP_LO = 26.0     # fully transparent at or below this distance from bg
RAMP_HI = 70.0     # fully opaque at or above it
# The model draws a soft grey contact shadow whatever the negative prompt
# says. Removing it by colour was tried and reverted: "achromatic and
# bright" also describes her dress, and because her linework is scratchy
# rather than closed, adding that rule to the flood opened a path from
# the shadow through the hem and ate the skirt. The shadow stays. It is
# small, and DESIGN_DIRECTION.md §6 asks for a contact shadow anyway —
# so the seed to ship is the one whose shadow is least pronounced, not
# whichever one a filter can be talked into cleaning.


def cutout(src_path, tag):
    im = Image.open(src_path).convert("RGB")
    rgb = np.asarray(im).astype(np.float32)
    h, w, _ = rgb.shape

    border = np.concatenate([rgb[0, :], rgb[-1, :], rgb[:, 0], rgb[:, -1]])
    bg = np.median(border, axis=0)
    dist = np.linalg.norm(rgb - bg[None, None, :], axis=2)

    # Flood inward from the frame. Connectivity is the whole point: a
    # global colour match would also erase the white of her dress.
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

    # Opaque everywhere the flood never reached; inside the flooded region
    # alpha ramps with distance from the background, which is what keeps
    # the anti-aliased boundary soft instead of stair-stepped.
    alpha = np.ones((h, w), dtype=np.float32)
    ramp = np.clip((dist - RAMP_LO) / (RAMP_HI - RAMP_LO), 0.0, 1.0)
    alpha[outside] = ramp[outside]

    # Un-mix the background out of the partly transparent pixels. Without
    # this every soft edge keeps a pale rim of the old backdrop and the
    # figure reads as a cutout pasted on.
    a3 = alpha[:, :, None]
    safe = np.maximum(a3, 1e-3)
    true_rgb = np.clip((rgb - (1.0 - a3) * bg[None, None, :]) / safe, 0, 255)

    out = np.dstack([true_rgb, alpha * 255.0]).astype(np.uint8)
    cut = Image.fromarray(out, "RGBA")

    # Trim to the figure, then seat it in the sheet with a little air, so
    # every seed lands at the same scale regardless of how much margin the
    # model happened to leave.
    bbox = cut.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    if bbox:
        cut = cut.crop(bbox)
    inner_w, inner_h = SHEET_W - OUTLINE_PX * 4, SHEET_H - OUTLINE_PX * 4
    cut.thumbnail((inner_w, inner_h), Image.Resampling.LANCZOS)

    sheet = Image.new("RGBA", (SHEET_W, SHEET_H), (0, 0, 0, 0))
    # Bottom-aligned: she stands on the floor of her frame rather than
    # floating in the middle of it.
    pos = ((SHEET_W - cut.width) // 2, SHEET_H - OUTLINE_PX * 2 - cut.height)
    sheet.paste(cut, pos, cut)

    # The same trick IconGlyph uses: grow the silhouette into the ink
    # colour, then lay the true-size figure over it.
    grown = sheet.getchannel("A").filter(ImageFilter.MaxFilter(OUTLINE_PX * 2 + 1))
    ink = Image.new("RGBA", sheet.size, INK + (0,))
    ink.putalpha(grown)
    final = Image.alpha_composite(ink, sheet)

    out_path = OUT / f"shizuku_clean_{tag}.png"
    final.save(out_path)
    return out_path


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
        cut = Image.open(r["clean"]).convert("RGBA")
        shown = cut.copy()
        shown.thumbnail(INGAME, Image.Resampling.LANCZOS)
        # On the panel colour she will actually sit on, not on a neutral
        # grey — a fringe only shows against the real ground.
        plate = Image.new("RGBA", INGAME, (255, 247, 230, 255))
        plate.paste(shown, ((INGAME[0] - shown.width) // 2, (INGAME[1] - shown.height) // 2), shown)
        cell.paste(plate.convert("RGB"), ((cell_w - INGAME[0]) // 2, plate_y))
        ImageDraw.Draw(cell).text((8, plate_y - 16), "seed %d  (下=実寸 %dx%d)" % (r["seed"], *INGAME),
                                  fill=(236, 226, 209), font=font)
        sheet.paste(cell, (idx * cell_w, 0))
    out = ROOT / "outputs" / "dice_shizuku_stage_clean_contact.jpg"
    sheet.save(out, "JPEG", quality=93, optimize=True)
    return out


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    results = []
    for seed in SEEDS:
        print(f"SOURCE seed={seed}", flush=True)
        hist = wait_for_history(
            post_json("/prompt", {"prompt": source_prompt(seed, f"shizuku_clean_seed{seed}")})["prompt_id"]
        )
        src = copy_outputs(hist, f"src_seed{seed}")[0]
        clean = cutout(src, str(seed))
        results.append({"seed": seed, "source": str(src), "clean": str(clean)})
        print(f"DONE   seed={seed}", flush=True)

    (OUT / "run_results.json").write_text(
        json.dumps(
            {
                "unet": UNET,
                "lora": LORA,
                "lora_strength": 1.0,
                "sampler": f"euler / beta / 24 steps / cfg 3.8 / {GEN_W}x{GEN_H}",
                "pixelization": "none - finished illustration",
                "cutout": f"inward flood (T={FLOOD_T}), alpha ramp {RAMP_LO}-{RAMP_HI}, background un-mixed",
                "outline": f"{OUTLINE_PX}px ink {INK}",
                "positive": POSITIVE,
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
