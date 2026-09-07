# KT Wallet Website

Official responsive landing page for KT Wallet and KT Cold Signer, built with
[Astro](https://astro.build/).

## Local development

```sh
npm install
npm run dev -- --background
```

Use the URL returned by Astro; the current local preview is `http://localhost:4322`.

## Localized routes

- `/` — English (default)
- `/zh/` — Simplified Chinese
- `/ja/` — Japanese

## Production build

```sh
npm run build
```

The build creates static Astro pages and a Cloudflare Workers-compatible entry
point under `dist/server/index.js`.

Validate built routes, local assets, navigation anchors and source links with
`node scripts/validate-site.mjs` after building.

The root route is English. Chinese and Japanese remain available through the
language selector; all locales use the English Pixel 8 app screenshots, locally
retouched with Images to replace wallet details. No original wallet screenshots
are stored in the public assets. See [image provenance and editing prompts](docs/PRODUCT_IMAGE.md).
