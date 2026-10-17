# App icon source

## Current icon: gold X

`x-gold-icon.png` is the bundled icon artwork source. It was generated with OpenAI image generation using X's official website icon as the edit target, placing the X logo over photoreal gold. The packaged icon was checked visually in the app's About panel.

The build invokes `scripts/render-icon.swift` to draw the unchanged local artwork into a rounded tile measuring 824 by 824 points on a transparent 1024 by 1024 canvas, scaled for each icon resolution. The 100-point outer margins correct the oversized Dock footprint of version 0.1.1. The corner radius is 22% of tile width. `iconutil` packages the resulting sizes as `AppIcon.icns`. The generated gold asset is preserved separately. No regenerated artwork was adopted for the sizing fix.

### Exact final prompt

```text
Use case: precise-object-edit. Asset type: a production macOS app icon, 1024x1024 square. Edit target: the supplied official X website icon. Preserve the exact centered X mark's geometry, proportions, sharp edges, and placement. Replace the flat black background with photorealistic polished gold metal, with fine brushed microtexture and broad, realistic soft studio reflections. The gold fills the square edge to edge, with no surrounding scene, border, perspective tilt, text, or extra symbols. Change the X mark from white to rich near-black so it reads crisply on the bright gold; keep the original shape unchanged. Restrained premium product-photography material, warm natural gold rather than yellow paint, no glitter or ornamental pattern. Straight-on flat icon composition with strong legibility at Dock size. This is the final app icon asset, not a mockup of an icon on a desktop.
```

## Original reference

The edit target was X's official 1024 by 1024 website icon, retrieved from X's CDN. It is X Corp's artwork, so it is not kept in this repository (removed 2026-10-17; earlier commits still contain it):

https://abs.twimg.com/responsive-web/client-web/icon-ios.77d25eb62d3da71ba.png

This URL was discovered in the `apple-touch-icon` link in the HTML served by X on September 11, 2026.

The X name and branding belong to their respective owner. This is an independent, unofficial wrapper. This source attribution does not establish permission for public distribution. The [MIT license](../LICENSE) does not cover `x-gold-icon.png` or images made from it; see [NOTICE.md](../NOTICE.md).
