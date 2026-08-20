# Rogue Design Transfer Experiments

Reference: original knight design candidate.

Goal: transfer the knight's design language to a cute female rogue without making her the same knight.

Methods:

## text_simple
Kind: txt2img

Positive:
```text
cute female rogue, full body standing pose, ash brown short hair, green cloak, light leather outfit, brown leather belt, sturdy boots, small dagger, fantasy anime character design, high quality illustration
```
Negative:
```text
low quality, bad anatomy, text, watermark
```

## text_design
Kind: txt2img

Positive:
```text
cute female rogue, full body standing pose, ash brown short hair, light leather rogue outfit with white and blue pieces and gold trim, blue waist cloth accent, brown leather belt, sturdy boots, small dagger, fantasy anime character design, high quality illustration
```
Negative:
```text
low quality, bad anatomy, text, watermark
```

## redux_low
Kind: redux
Redux strength: 0.35

Positive:
```text
cute female rogue, full body standing pose, ash brown short hair, nimble light leather outfit with white and blue pieces and gold trim, blue waist cloth accent, brown leather belt, sturdy boots, small dagger, fantasy anime character design, high quality illustration, use the reference image as style only: keep the cute face style, polished blue white gold material language, layered cloth and armor density, but change the role into a rogue
```
Negative:
```text
low quality, bad anatomy, text, watermark, round shield, heavy knight armor
```

## redux_mid
Kind: redux
Redux strength: 0.55

Positive:
```text
cute female rogue, full body standing pose, ash brown short hair, nimble light leather outfit with white and blue pieces and gold trim, blue waist cloth accent, brown leather belt, sturdy boots, small dagger, fantasy anime character design, high quality illustration, use the reference image as style only: keep the cute face style, polished blue white gold material language, layered cloth and armor density, but change the role into a rogue
```
Negative:
```text
low quality, bad anatomy, text, watermark, round shield, heavy knight armor
```

## img2img_convert
Kind: img2img
Denoise: 0.68

Positive:
```text
cute female rogue, full body standing pose, ash brown short hair, nimble light leather outfit with white and blue pieces and gold trim, blue waist cloth accent, brown leather belt, sturdy boots, small dagger, fantasy anime character design, high quality illustration, use the reference image as style only: keep the cute face style, polished blue white gold material language, layered cloth and armor density, but change the role into a rogue
```
Negative:
```text
low quality, bad anatomy, text, watermark, round shield, heavy knight armor
```

Pixelization: 2d_pixel_toolkit_i2i_depth, 800x1200, denoise 0.55.