# App icon source

## Current icon: gold X

`x-gold-icon.png` is the bundled icon artwork source for version 0.1.2. It was created on September 12, 2026 with the built-in image-generation tool, using `x-site-icon.png` as the edit target. The user requested the X logo over photoreal gold. The generated asset was visually reviewed and the packaged icon was checked in the running app's About panel.

The build invokes `scripts/render-icon.swift` to draw the unchanged local artwork into a rounded tile measuring 824 by 824 points on a transparent 1024 by 1024 canvas, scaled for each icon resolution. The 100-point outer margins correct the oversized Dock footprint of version 0.1.1. The corner radius is 22% of tile width. `iconutil` packages the resulting sizes as `AppIcon.icns`. The original website and generated gold assets are preserved separately. No regenerated artwork was adopted for the sizing fix.

### Exact final prompt

```text
Use case: precise-object-edit. Asset type: a production macOS app icon, 1024x1024 square. Edit target: the supplied official X website icon. Preserve the exact centered X mark's geometry, proportions, sharp edges, and placement. Replace the flat black background with photorealistic polished gold metal, with fine brushed microtexture and broad, realistic soft studio reflections. The gold fills the square edge to edge, with no surrounding scene, border, perspective tilt, text, or extra symbols. Change the X mark from white to rich near-black so it reads crisply on the bright gold; keep the original shape unchanged. Restrained premium product-photography material, warm natural gold rather than yellow paint, no glitter or ornamental pattern. Straight-on flat icon composition with strong legibility at Dock size. This is the final app icon asset, not a mockup of an icon on a desktop.
```

## Original reference

The original 1024 by 1024 PNG, `x-site-icon.png`, was retrieved from X's official website CDN:

https://abs.twimg.com/responsive-web/client-web/icon-ios.77d25eb62d3da71ba.png

This URL was discovered in the `apple-touch-icon` link in the HTML served by X on September 11, 2026.

The X name and branding belong to their respective owner. This is a personal, unofficial wrapper. This source attribution does not establish permission for public distribution.
