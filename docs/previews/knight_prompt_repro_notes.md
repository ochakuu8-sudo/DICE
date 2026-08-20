# Knight Prompt Reproduction Notes

Reference:

- `docs/previews/dice_knight_before_consistency_candidate_2.png`

Best direction:

- Use the short original prompt shape.
- Add only the stable identity markers visible in the reference.
- Do not add broad mood/style phrases like `soft friendly face` or `light parchment background`; they made the design softer but less like the reference.

Recommended prompt:

```text
cute female knight, full body standing pose, blonde high ponytail, blue scarf, white and blue plate armor with gold trim, round blue shield, short sword, fantasy anime character design, high quality illustration
```

Optional for game readability:

```text
sturdy boots
```

Negative prompt:

```text
low quality, bad anatomy, text, watermark
```

Ordinary Chroma settings used:

```text
Model: chroma-unlocked-v50.safetensors
Text encoder: t5xxl_fp8_e4m3fn.safetensors
VAE: ae.safetensors
Sampler: euler / simple
Steps: 24
CFG: 4.0
Size: 896x1280
```

Comparison files:

- `docs/previews/dice_knight_prompt_repro_search_contact.jpg`
- `docs/previews/dice_knight_prompt_repro_focus_contact.jpg`
- `docs/previews/dice_knight_prompt_repro_final_contact.jpg`
