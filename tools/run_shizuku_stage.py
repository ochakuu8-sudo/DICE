"""Build シズク's battle stage sprite and install it into the Godot project.

Two stages, both already proven on this machine:

  1. Source illustration — chroma-unlocked-v50-fp8-scaled with the shizuku
     character LoRA alone at 1.0, euler / beta / 24 steps / CFG 3.8. The
     LoRA trained at 1024x1024 and DESIGN_DIRECTION.md §5 flags that its
     accuracy in a tall frame is unverified, so this renders several
     candidate seeds at 832x1216 rather than trusting one.
  2. Pixelization — the existing 2d_pixel_toolkit_i2i_depth path at
     800x1200, byte-identical settings to the ones that produced the
     roster already committed in art/stage/.

Then the same edge flood-fill cutout the roster script uses, and a
contact sheet at the real in-game size so the result is judged where it
will actually be seen rather than at authoring resolution.
"""

import json
import shutil
import time
import urllib.parse
import urllib.request
from collections import deque
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

COMFY = "http://127.0.0.1:8188"
ROOT = Path(r"C:\Users\yuuuu\Documents\Codex\2026-08-20\c-users-yuuuu-ai-comfyui-windows")
REPO = ROOT / "work" / "DICE"
PROJECT = REPO / "godot_project"
COMFY_ROOT = Path(
    r"C:\Users\yuuuu\AI\ComfyUI_windows_portable_nvidia\ComfyUI_windows_portable\ComfyUI"
)
COMFY_INPUT = COMFY_ROOT / "input"
COMFY_OUTPUT = COMFY_ROOT / "output"
OUT = ROOT / "outputs" / "shizuku_stage"

UNET = "chroma-unlocked-v50-fp8-scaled.safetensors"
LORA = "shizuku_charalora_v4_hair_ornament_chromav50-step00004000.safetensors"

# No face wording: the LoRA owns the face. Outfit enumerated one piece at
# a time, and a full-body standing pose asked for explicitly because this
# is a stage sprite, not a portrait.
POSITIVE = (
    "shizuku_charalora, shizuku, 1girl, front standing full body, standing straight, "
    "whole body visible from head to feet, "
    "pale blonde very long hair, blunt bangs, "
    "large black and white ribbon bow, antique gold flower hair ornament, "
    "black hanging tassel, black high collar, black corset bodice, "
    "white puffy sleeves, black and white noble dress, "
    "antique gold shoulder armor, "
    "rough painterly anime illustration, scratchy ink lines, "
    "plain flat white background"
)
NEGATIVE = (
    "low quality, worst quality, bad anatomy, bad hands, extra fingers, "
    "missing fingers, fused fingers, distorted face, color bleeding, "
    "gray skin, skin-colored clothing, text, watermark, "
    "cropped, close-up, portrait, bust shot, multiple characters, "
    "busy background, scenery"
)

PIXEL_POSITIVE = (
    "pixel art sprite of a noble girl in a black and white dress with gold shoulder armor, "
    "pale blonde very long hair, clean readable silhouette, "
    "transparent-friendly plain background, 2d pixel art, RPG battle stage character"
)
PIXEL_NEGATIVE = "lowres, worst quality, bad quality, blurry, text, watermark, multiple characters"

SEEDS = [91101, 91102, 91103, 91104]
# The size the sprite is actually drawn at inside the hero column.
INGAME = (274, 412)


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
            "inputs": {"width": 832, "height": 1216, "batch_size": 1},
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


def pixel_prompt(source_input_name, seed, prefix):
    return {
        "1": {
            "class_type": "CheckpointLoaderSimple",
            "inputs": {"ckpt_name": "2D_Pixel_Sprites.safetensors"},
        },
        "2": {
            "class_type": "LoraLoader",
            "inputs": {
                "model": ["1", 0],
                "clip": ["1", 1],
                "lora_name": "pixel sprites.safetensors",
                "strength_model": 0.45,
                "strength_clip": 0.45,
            },
        },
        "5": {"class_type": "LoadImage", "inputs": {"image": source_input_name}},
        "15": {
            "class_type": "ImageScale",
            "inputs": {
                "image": ["5", 0],
                "upscale_method": "nearest-exact",
                "width": 800,
                "height": 1200,
                "crop": "disabled",
            },
        },
        "6": {
            "class_type": "DepthAnythingV2Preprocessor",
            "inputs": {"image": ["15", 0], "ckpt_name": "depth_anything_v2_vitl.pth", "resolution": 512},
        },
        "8": {"class_type": "VAEEncode", "inputs": {"pixels": ["15", 0], "vae": ["1", 2]}},
        "9": {
            "class_type": "ControlNetLoader",
            "inputs": {"control_net_name": "control_v11f1p_sd15_depth_fp16.safetensors"},
        },
        "3": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["2", 1], "text": PIXEL_POSITIVE}},
        "4": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["2", 1], "text": PIXEL_NEGATIVE}},
        "10": {
            "class_type": "ControlNetApplyAdvanced",
            "inputs": {
                "positive": ["3", 0],
                "negative": ["4", 0],
                "control_net": ["9", 0],
                "image": ["6", 0],
                "strength": 0.5,
                "start_percent": 0.0,
                "end_percent": 0.9,
                "vae": ["1", 2],
            },
        },
        "11": {
            "class_type": "KSampler",
            "inputs": {
                "model": ["2", 0],
                "seed": seed,
                "steps": 24,
                "cfg": 7.0,
                "sampler_name": "dpmpp_2m",
                "scheduler": "karras",
                "positive": ["10", 0],
                "negative": ["10", 1],
                "latent_image": ["8", 0],
                "denoise": 0.55,
            },
        },
        "12": {"class_type": "VAEDecode", "inputs": {"samples": ["11", 0], "vae": ["1", 2]}},
        "13": {
            "class_type": "SaveImage",
            "inputs": {"images": ["12", 0], "filename_prefix": prefix},
        },
    }


def bg_like(pixel, ref):
    r, g, b = pixel[:3]
    rr, rg, rb = ref
    dist = ((r - rr) ** 2 + (g - rg) ** 2 + (b - rb) ** 2) ** 0.5
    bright = (r + g + b) / 3.0
    sat = max(r, g, b) - min(r, g, b)
    return dist < 42 or (bright > 232 and sat < 34)


def transparent_stage(pixel_path, tag):
    """Flood-fill the background in from the edges.

    Not a colour-key: keying the background colour globally also eats the
    whites inside the dress, which on this character is most of it.
    """
    im = Image.open(pixel_path).convert("RGBA")
    w, h = im.size
    pix = im.load()
    edge = []
    for x in range(0, w, max(1, w // 80)):
        edge.append(pix[x, 0][:3])
        edge.append(pix[x, h - 1][:3])
    for y in range(0, h, max(1, h // 80)):
        edge.append(pix[0, y][:3])
        edge.append(pix[w - 1, y][:3])
    ref = tuple(sorted(channel)[len(channel) // 2] for channel in zip(*edge))

    seen = set()
    q = deque()
    for x in range(w):
        q.append((x, 0))
        q.append((x, h - 1))
    for y in range(h):
        q.append((0, y))
        q.append((w - 1, y))
    while q:
        x, y = q.popleft()
        if x < 0 or y < 0 or x >= w or y >= h or (x, y) in seen:
            continue
        if not bg_like(pix[x, y], ref):
            continue
        seen.add((x, y))
        q.append((x + 1, y))
        q.append((x - 1, y))
        q.append((x, y + 1))
        q.append((x, y - 1))
    for x, y in seen:
        r, g, b, _ = pix[x, y]
        pix[x, y] = (r, g, b, 0)

    out = OUT / f"shizuku_idle_transparent_{tag}.png"
    im.save(out)
    return out


def make_contact(results):
    """Judged at the size it ships at, per DESIGN_DIRECTION.md §8."""
    # Tall enough to hold the in-game plate whole: it starts at y=316, so
    # anything shorter than that plus INGAME's height silently clips the
    # sprite's legs and makes a correct render look cropped.
    plate_y = 316
    cell_w, cell_h = 300, plate_y + INGAME[1] + 12
    sheet = Image.new("RGB", (cell_w * len(results), cell_h), (58, 44, 48))
    try:
        font = ImageFont.truetype("arial.ttf", 16)
    except OSError:
        font = ImageFont.load_default()
    for idx, r in enumerate(results):
        cell = Image.new("RGB", (cell_w, cell_h), (74, 58, 62))
        src = Image.open(r["source"]).convert("RGB")
        src.thumbnail((cell_w - 20, 300), Image.Resampling.LANCZOS)
        cell.paste(src, ((cell_w - src.width) // 2, 4))
        # The one that matters: the sprite at its real in-game footprint.
        cut = Image.open(r["transparent"]).convert("RGBA")
        shown = cut.copy()
        shown.thumbnail(INGAME, Image.Resampling.NEAREST)
        plate = Image.new("RGBA", INGAME, (96, 76, 80, 255))
        plate.paste(shown, ((INGAME[0] - shown.width) // 2, (INGAME[1] - shown.height) // 2), shown)
        cell.paste(plate.convert("RGB"), ((cell_w - INGAME[0]) // 2, plate_y))
        ImageDraw.Draw(cell).text((8, plate_y - 16), "seed %d  (下=実寸 %dx%d)" % (r["seed"], *INGAME),
                                  fill=(236, 226, 209), font=font)
        sheet.paste(cell, (idx * cell_w, 0))
    out = ROOT / "outputs" / "dice_shizuku_stage_contact.jpg"
    sheet.save(out, "JPEG", quality=92, optimize=True)
    return out


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    COMFY_INPUT.mkdir(parents=True, exist_ok=True)
    results = []
    for seed in SEEDS:
        print(f"SOURCE seed={seed}", flush=True)
        hist = wait_for_history(
            post_json("/prompt", {"prompt": source_prompt(seed, f"shizuku_stage_src_seed{seed}")})["prompt_id"]
        )
        src = copy_outputs(hist, f"src_seed{seed}")[0]

        input_name = f"codex_shizuku_stage_{seed}.png"
        shutil.copy2(src, COMFY_INPUT / input_name)
        pixel_seed = seed + 100
        print(f"PIXEL  seed={pixel_seed}", flush=True)
        hist = wait_for_history(
            post_json(
                "/prompt",
                {"prompt": pixel_prompt(input_name, pixel_seed, f"shizuku_stage_px_seed{pixel_seed}")},
            )["prompt_id"]
        )
        pixel = copy_outputs(hist, f"px_seed{pixel_seed}")[0]
        cut = transparent_stage(pixel, str(seed))
        results.append(
            {"seed": seed, "source": str(src), "pixel": str(pixel), "transparent": str(cut)}
        )
        print(f"DONE   seed={seed}", flush=True)

    (OUT / "run_results.json").write_text(
        json.dumps(
            {
                "unet": UNET,
                "lora": LORA,
                "lora_strength": 1.0,
                "source_sampler": "euler / beta / 24 steps / cfg 3.8 / 832x1216",
                "pixel_workflow": "2d_pixel_toolkit_i2i_depth (800x1200, denoise 0.55)",
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
