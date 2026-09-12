# Repository social preview

Upload asset: `social-preview.jpg` (1280 × 640 pixels, JPEG under 1 MB). The generated artwork is exported at the template dimensions for GitHub.

Created with the built-in image-generation tool. The GitHub social-card template supplied the 2:1 canvas and safe margins; `x-gold-icon.png` supplied the app's visual identity. The card contains no personal attribution or live account content.

Upload the finished image under the repository's **Settings → Social preview → Edit → Upload an image**. Adding this asset to Git alone does not change GitHub's social preview. See [GitHub's requirements](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/customizing-your-repositorys-social-media-preview).

## Generation prompt

```text
Use case: ads-marketing.
Asset type: Finished GitHub repository social preview image, exactly 1280 x 640 pixels, 2:1 landscape.
Create a polished, restrained social card for the repository "X for macOS", an unofficial Swift desktop wrapper for X.
Input images: Image 1 is a LAYOUT TEMPLATE ONLY: use its 2:1 dimensions and inner safe area; do not reproduce its GitHub logo, template wording, pink areas, or red guide lines. Image 2 is the APP ICON REFERENCE: preserve the black X mark geometry and warm brushed-gold material.
Design: sophisticated near-black charcoal background with a very subtle soft warm glow behind the icon. Place a large front-facing rounded-square gold app icon on the left, about 290px square, with the reference black X mark, realistic fine brushed metal and restrained highlights. No perspective angle, no floating device, no web screenshot. On the right, generous negative space and strong typographic hierarchy in clean modern macOS-like sans serif.
Exact text:
Main headline: "X for macOS"
Secondary line: "Your timeline, in its own window."
Feature line: "Native controls · Auto-refresh · Pull-to-refresh"
Small understated footer: "Unofficial app · Swift + WebKit"
Main headline off-white, supporting text warm light gray, tiny separators muted gold. Headline is very large and dominant but fits on one line. Keep typography sharp, legible, and beautifully spaced.
All essential icon and text fully inside the template safe zone: at least 90px from every canvas edge. Horizontally balanced icon-and-copy composition, vertically centered with comfortable breathing room. Premium, simple, professional. No personal name, GitHub username, repository URL, official affiliation claim, GitHub logo, Apple logo, badges, additional words, template guides, or watermark. Export a complete ready-to-upload card, not a presentation mockup.
```

## Safe-margin refinement

```text
Use case: precise-object-edit. Edit the provided finished social card. Keep exactly the same artwork, gold icon, black background, wording, fonts, line breaks, and 2:1 landscape composition. Make only one layout correction: reduce the entire icon-and-text content group uniformly to 88% of its current size, centered on the same canvas, extending the existing near-black background seamlessly around it. This must create extra breathing room at all four edges, especially to the right of the subtitle. All essential content must be at least 90 pixels from the edges of a 1280 x 640 canvas. Keep the title and subtitle each on one line. Do not add anything or change the wording. Output at exactly 1280 x 640 pixels.
```
