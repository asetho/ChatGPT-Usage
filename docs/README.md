# App website

This static site is published from the `gh-pages` branch, `/docs` folder, at
https://asetho.github.io/ChatGPT-Usage/.

Edit this branch to update the website. No package installation or build is required.
Preview with `python3 -m http.server 8765 --directory docs`.

Keep the Google site-verification meta tag in `index.html` so Search Console ownership
remains verified. The sitemap contains the canonical homepage URL. Download links use
GitHub's latest-release page so they remain current without a website release.

The screenshots are illustrative 1.0.35 views with sample usage. Their editable
source is `Artwork/Screenshots/demo-source.html` on this branch; the rendered PNGs
are in `docs/assets`. Keep Mac signing and notarization status distinct from the
unsigned Windows installer.
