# Rogue Design Transfer Summary

Goal:

- Transfer the original knight design language to one different cute female character.
- Test rogue as the first non-knight role.

Reference:

- `docs/previews/dice_knight_before_consistency_candidate_2.png`

Result:

- Best overall method: text-only design-language transfer.
- Redux reference conditioning was too strong even at low strength; it pushed the rogue back toward a knight.
- Direct img2img conversion preserved the knight design too much.
- The strongest usable final candidate is `final_2` in `dice_rogue_design_transfer_final_contact.jpg`.

Recommended prompt pattern for this rogue:

```text
cute female rogue, single character, full body standing pose, warm chestnut brown bob hair, light rogue outfit with white leather bodice, blue waist cloth accent, gold trim, brown leather belt, dark leggings, sturdy brown boots, small dagger, fantasy anime character design, high quality illustration
```

Recommended negative prompt:

```text
low quality, bad anatomy, text, watermark, blue hair, white hair, silver hair, multiple characters, character sheet, turnaround, back view, round shield, heavy knight armor
```

Takeaway for other characters:

- Use the knight as a design-language source, not as a visual reference at generation time.
- Keep shared design markers: cute female character, full-body standing pose, white/blue/gold outfit language, brown leather belt or straps, sturdy boots, one blue cloth accent.
- Change the blue cloth accent per role instead of copying the knight scarf.
- Avoid Redux unless the strength is extremely low and the prompt strongly blocks knight-specific items.
