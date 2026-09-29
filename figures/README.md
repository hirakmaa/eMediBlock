# figures/

`make_figures.py` regenerates Figures 4–9 from `results/` — nothing here is
drawn by hand, so a change to a measurement changes the figure.

Figures 1–3 are schematics of the architecture and are not generated from data;
keep their sources here in editable form (`.drawio`, `.svg` or similar) rather
than only as exported bitmaps.

## Known traps, learned the hard way

1. **`axhline` / `axvline` use a blended transform.** Forcing `transData` makes
   reference lines invisible to a collision detector. Use `line.get_transform()`.
2. **Source PNGs are RGBA.** A plain `convert("RGB")` maps transparency to
   black. Flatten onto white with `alpha_composite` first.
3. **Cap plate height at 6.3 in** — at 6.5 in the figures overran the page.
4. **Trim blank canvas before compositing.** Several schematics carry a wide
   band of empty space, which inflates plate height and shrinks the drawing.
5. **When replacing an image inside an existing `.docx`, strip `<a:srcRect>`.**
   Word stores cropping on the *blipFill*, independently of the image bytes, so
   a crop from the old image is silently re-applied to its replacement.
