# Knight Repro i2i_depth Pixelization

Positive: cute female knight, pixel art sprite, blue and white armor, blue scarf, round shield, short sword, clean readable silhouette
Negative: lowres, worst quality, bad quality, blurry

Model: 2D_Pixel_Sprites.safetensors
LoRA: pixel sprites.safetensors, 0.45 / 0.45
Depth: depth_anything_v2_vitl.pth, resolution 512
ControlNet: control_v11f1p_sd15_depth_fp16.safetensors, strength 0.5, 0.0-0.9
Sampler: dpmpp_2m / karras, 24 steps, cfg 7.0, denoise 0.55
ImageScale: nearest-exact, 800x1200, crop disabled