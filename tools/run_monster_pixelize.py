"""Put the whole roster through one renderer, without losing the designs.

Two failed attempts got us here, and both failures are worth keeping:

  1. Base Chroma, one prompt per creature. The designs were right but the
     styles were seven different idioms — a glossy mobile slime beside a
     flat vector octopus beside a painterly eye.
  2. The 2D_Pixel_Sprites checkpoint driving text-to-image. Style became
     perfectly uniform, and every creature came back humanoid: the mimic
     rendered as a muscular man. That model is trained on character
     sprites, so its prior overrides "human, humanoid" in the negative —
     which destroys the one thing §4 exists for.

So neither the design nor the style can come from the same stage. The
designs stay as the Chroma renders, and the pixel checkpoint is applied
over them through depth-guided img2img: DepthAnythingV2 holds the
geometry (a chest stays a chest) while the checkpoint supplies a single
rendering idiom to all seven. Settings are the 2d_pixel_toolkit_i2i_depth
workflow's, unchanged — the same path that produced the roster already
shipped in art/stage/.
"""

import importlib.util
import json
import shutil
from pathlib import Path

ROOT = Path(r"C:\Users\yuuuu\Documents\Codex\2026-08-20\c-users-yuuuu-ai-comfyui-windows")
BASE = ROOT / "work" / "run_monster_roster.py"
COMFY_INPUT = Path(
    r"C:\Users\yuuuu\AI\ComfyUI_windows_portable_nvidia\ComfyUI_windows_portable\ComfyUI\input"
)

spec = importlib.util.spec_from_file_location("roster", BASE)
R = importlib.util.module_from_spec(spec)
spec.loader.exec_module(R)

# The pop Chroma pass wrote _00002_; that is the set with the designs on it.
SOURCE_SUFFIX = "_00002_.png"

PIXEL_STYLE = (
    "pixel, pixel art, pixelart, game sprite, "
    "crisp outline, limited color palette, sharp pixel edges, "
    "bright saturated colours, clean readable silhouette"
)
PIXEL_NEGATIVE = (
    "lowres, worst quality, bad quality, blurry, fuzzy edges, smooth painting, "
    "realistic, 3d render, photo, text, watermark, logo, "
    "human, girl, woman, humanoid, human face, "
    "multiple characters, busy background, gradient background, shadow"
)


def pixel_prompt(mon, input_name, prefix):
    positive = f"{PIXEL_STYLE}, {mon['body']}"
    return {
        "1": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": R.CKPT}},
        "2": {
            "class_type": "LoraLoader",
            "inputs": {
                "model": ["1", 0],
                "clip": ["1", 1],
                "lora_name": R.PIXEL_LORA,
                "strength_model": 0.45,
                "strength_clip": 0.45,
            },
        },
        "5": {"class_type": "LoadImage", "inputs": {"image": input_name}},
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
        "3": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["2", 1], "text": positive}},
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
                "seed": mon["seed"] + 1000,
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


def main():
    R.OUT.mkdir(parents=True, exist_ok=True)
    COMFY_INPUT.mkdir(parents=True, exist_ok=True)
    results = []
    for mon in R.MONSTERS:
        actor = mon["actor"]
        src = R.OUT / f"{actor}_monster_{actor}{SOURCE_SUFFIX}"
        if not src.exists():
            raise SystemExit(f"missing pop source: {src}")
        input_name = f"codex_monster_{actor}.png"
        shutil.copy2(src, COMFY_INPUT / input_name)

        print(f"PIXELIZE {actor} ({mon['name']})", flush=True)
        hist = R.wait_for_history(
            R.post_json("/prompt", {"prompt": pixel_prompt(mon, input_name, f"monster_px_{actor}")})["prompt_id"]
        )
        px = R.copy_outputs(hist, f"px_{actor}")[0]
        stage = R.cutout(px, actor, mon.get("fill", 1.0))
        face = R.make_face(stage, actor)
        results.append(
            {
                "actor": actor, "name": mon["name"],
                "source": str(px), "stage": str(stage), "face": str(face),
            }
        )
        print(f"DONE {actor}", flush=True)

    (R.OUT / "pixelize_results.json").write_text(
        json.dumps(
            {
                "ckpt": R.CKPT,
                "lora": f"{R.PIXEL_LORA} 0.45/0.45",
                "workflow": "2d_pixel_toolkit_i2i_depth (800x1200, denoise 0.55, controlnet 0.5)",
                "design_source": "chroma pop pass" + SOURCE_SUFFIX,
                "results": results,
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    print(json.dumps({"contact": str(R.make_contact(results))}, indent=2), flush=True)


if __name__ == "__main__":
    main()
