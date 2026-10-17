# site/

The app's website, served at **x.banast.as**: one page about X for macOS with a Download button, the update feed installed copies check, and the current release. It's static, with no build step and nothing loaded from other servers: `index.html` with inline CSS and JS, `404.html`, the app icon (`icon.png` at 512 px, `icon-64.png` for the favicon and header), `_headers` and `robots.txt`. It follows Cue's site (`../Cue/site/`).

- **Out of search results, not hidden.** Every response says `noindex` (`_headers` and a meta tag), and `robots.txt` turns crawlers away. The page is linked from the public GitHub repository (its website field and the README's Install section, the user's choice, 2026-10-17), so anyone reading those can find it; the family's other sites still don't link here.
- **Design:** the family's greys with the app icon's gold. `--gold-hi`, `--gold` and `--gold-deep` are sampled from the rendered icon, and the icon's near-black mark is the ink on gold buttons. The hero draws the app's window in HTML and CSS: the toolbar, the For you and Following tabs, placeholder posts with no real content, and the status strip's countdown. It refreshes at zero and then every 60 seconds, and clicking the feed shows a pull. With Reduce Motion on, nothing slides or spins. Chips beside the window show on wide screens only.
- **The icon, not X's brand.** The app icon (the user's choice, 2026-10-17) is the only artwork. It contains X's mark, so the page says plainly, near the top and in the details, that the app is independent of X Corp. Don't add X's wordmark, its blue, or screenshots of real posts.
- **Icon files:** made from `Resources/x-gold-icon.png` by the app's own renderer, so the page and the Dock match. After changing the artwork, run:

  ```bash
  swift scripts/render-icon.swift Resources/x-gold-icon.png /tmp/x.iconset
  cp /tmp/x.iconset/icon_256x256@2x.png site/icon.png
  cp /tmp/x.iconset/icon_32x32@2x.png site/icon-64.png
  ```
- **Copy:** literal and short, a sentence or two a card.
- **Download:** the page reads `appcast.xml` for the version, date, notes and size, and turns on all three Download buttons (header, hero, closing). Before the first release it stays off and says "No release yet".

Preview locally:

```bash
python3 -m http.server 8765 --directory site
```

## Hosting (one-time, in your Cloudflare account)

1. Cloudflare dashboard › Workers & Pages › Create › Pages › Connect to Git, and choose `banastas/X`.
2. Project name `x` (or any free name), production branch `main`, no framework preset, no build command, build output directory `site`.
3. After the first deployment, the project's Custom domains › Set up a domain › `x.banast.as`. With banast.as on Cloudflare DNS, Pages adds the CNAME record itself.

Pages deploys on each push to `main`. A retry in Pages rebuilds that deployment's own commit, not the branch's newest: to deploy the newest, push or Create deployment. `404.html` matters: without it Pages answers any missing path, `appcast.xml` before the first release among them, with `index.html` and a 200.

## Downloads and updates

`PUBLISH=1 INSTALL=1 VERSION=… NOTES="…" scripts/release.sh` puts the notarized build here: `downloads/X-<version>-<build>.zip` (the one Sparkle updates fetch, a name of its own for each build) and `downloads/X.zip` (the Download button), and writes `appcast.xml`, the feed installed copies check once a day (`SUFeedURL`, which only release builds carry). Then it commits those and pushes `main`. Each zip is signed with Blit's EdDSA key, as Rune's and Cue's are (the release Mac's Keychain; the public half is `PUBLIC_KEY` in `scripts/release.sh`). Only the current release is kept here. `_headers` keeps the feed uncached.

Publishing makes the download public at that URL: run it with `PUBLISH=1` only when you mean to release.
