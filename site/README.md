# site/

The app's website, served at **x.banast.as**: one page about X for macOS with a Download button, the update feed installed copies check, and the current release. It's static, with no build step and nothing loaded from other servers: `index.html` with inline CSS and JS, `404.html`, `favicon.svg`, `_headers` and `robots.txt`. It follows Cue's site (`../Cue/site/`) in a plainer style.

- **Unlisted.** Every response says `noindex` (`_headers` and a meta tag), and `robots.txt` turns crawlers away. Nothing in the family's other sites links here.
- **Not X's brand.** The page says plainly that the app is independent of X Corp. It does not use X's logo, the app icon's artwork, or X's colors; the favicon is a plain refresh mark. Keep it that way.
- **Copy:** literal and short, a sentence or two a card.
- **Download:** the page reads `appcast.xml` for the version, date, notes and size, and turns the Download button on. Before the first release it stays off and says "No release yet".

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
