# FLUX2 Klein Rogue Design Transfer

No Chroma was used for source generation.
Source model: flux-2-klein-4b.safetensors
Text encoder: qwen_3_4b.safetensors / flux2
VAE: flux2-vae.safetensors
Sampler: custom Flux2 scheduler, euler, 6 steps, CFG 1.0, 768x1024.

## flux2_text_design
Kind: t2i

Positive:
```text
cute female rogue, single character, full body standing pose, warm chestnut brown bob hair, light rogue outfit with white leather bodice, blue waist cloth accent, gold trim, brown leather belt, dark leggings, sturdy brown boots, small dagger, fantasy anime character design, high quality illustration, plain light background
```
Negative:
```text
low quality, bad anatomy, text, watermark, blue hair, white hair, silver hair, multiple characters, character sheet, turnaround, back view, round shield, heavy knight armor, realistic photo, 3d render
```

## flux2_text_strict
Kind: t2i

Positive:
```text
cute female rogue, single character, full body standing pose, warm chestnut brown bob hair, soft cute face, bright eyes, compact readable silhouette, white leather bodice, blue waist cloth sash, small gold trim, brown leather belt and straps, dark fitted leggings, sturdy brown boots, one small dagger, fantasy RPG anime character design, high quality illustration, plain light background
```
Negative:
```text
low quality, bad anatomy, text, watermark, blue hair, white hair, silver hair, multiple characters, character sheet, turnaround, back view, round shield, heavy knight armor, realistic photo, 3d render
```

## flux2_reference_latent
Kind: reference_latent

Positive:
```text
cute female rogue, single character, full body standing pose, warm chestnut brown bob hair, light rogue outfit with white leather bodice, blue waist cloth accent, gold trim, brown leather belt, dark leggings, sturdy brown boots, small dagger, fantasy anime character design, high quality illustration, plain light background, use the reference image only as design-language guidance: polished anime rendering, white blue gold material language, leather belt density, layered cloth feel; change the role into a rogue and do not keep the knight armor or shield
```
Negative:
```text
low quality, bad anatomy, text, watermark, blue hair, white hair, silver hair, multiple characters, character sheet, turnaround, back view, round shield, heavy knight armor, realistic photo, 3d render
```

## flux2_refplus_clothes_late
Kind: refplus

Positive:
```text
cute female rogue, single character, full body standing pose, warm chestnut brown bob hair, light rogue outfit with white leather bodice, blue waist cloth accent, gold trim, brown leather belt, dark leggings, sturdy brown boots, small dagger, fantasy anime character design, high quality illustration, plain light background, use the reference image only as design-language guidance: polished anime rendering, white blue gold material language, leather belt density, layered cloth feel; change the role into a rogue and do not keep the knight armor or shield
```
Negative:
```text
low quality, bad anatomy, text, watermark, blue hair, white hair, silver hair, multiple characters, character sheet, turnaround, back view, round shield, heavy knight armor, realistic photo, 3d render
```

Pixelization used the existing 2d_pixel_toolkit_i2i_depth path after FLUX2 source generation.