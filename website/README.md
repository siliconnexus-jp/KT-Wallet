# KT Wallet Website

Official responsive landing page for KT Wallet and KT Cold Signer, built with
[Astro](https://astro.build/).

## Local development

```sh
npm install
npm run dev
```

The development server runs at `http://localhost:4321`.

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
