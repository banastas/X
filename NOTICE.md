# Notice

## What the MIT license covers

The [MIT license](LICENSE) covers this repository's source code, scripts, tests, test fixtures, and documentation.

## What it does not cover

The license grants no rights to the following, and they are not "the Software" for its purposes:

- **X's name, logo, and other marks.** They belong to X Corp. This app is independent: it is not made, endorsed, or supported by X Corp, and nothing here grants permission to use X's marks.
- **The app icon artwork and images made from it.** `Resources/x-gold-icon.png` is an edit of X's logo (see [ICON-SOURCE.md](Resources/ICON-SOURCE.md)). The same applies to everything made from it: the packaged `AppIcon.icns`, `Resources/social-preview.jpg`, and the site's `site/icon.png` and `site/icon-64.png`.

If you build, fork, or redistribute this project, replace that artwork with your own and don't present your copy as X's app or as this one. Your build can't use this project's update feed either: published builds are signed with the maintainer's Developer ID and Sparkle key, and copies built with `scripts/build-app.sh` carry no feed.

## Third-party software

Published builds include [Sparkle](https://sparkle-project.org) 2.10.0 under its own MIT-style license. The build copies Sparkle's license into the app's credits (X → About X).
