# KT Cold Signer identity

The offline app uses a platinum KT monogram enclosed by an emerald vault/shield,
on a graphite background. The online app retains its cyan/blue open-door mark.
The different silhouette and light lettering distinguish the apps beyond color.

Master: `kt-cold-signer-logo-1024.png` (opaque, square).
Repackage Flutter, Android density buckets, and iOS asset slots on macOS with
`bash tool/generate_cold_signer_icons.sh` from the repository root.
Launcher artwork has no pre-rounded outer corners; only in-app views clip it.
No new dependencies or remote assets are used by the offline application.

Generated with the built-in imagegen tool, using the online logo as a brand
reference. Resizing for platform slots does not alter the artwork.

## Generation prompt

Use case: logo-brand. Asset type: production square mobile app launcher icon, 1024x1024, for KT Cold Signer, an independent offline wallet signing app. Input image is reference ONLY: the online KT Wallet blue/cyan logo, preserve recognizable angular K and T letter identity but redesign for a clearly distinct offline product. Create ONE icon, no mockup or multiple options. Full-bleed near-black graphite background with an extremely subtle deep emerald tint. Center a bold unified monogram with precisely legible angular K and T, icy platinum/white lettering. Enclose the monogram inside one elegant emerald-green vault/shield silhouette with softly rounded top corners and a shallow pointed base, evoking protected offline custody. Keep symbol and enclosure within centered 66% of the square for safe launcher cropping. Refined restrained material: slightly luminous edges and very subtle glass/metal depth, almost flat high-contrast vector-like finish, thick clean geometry readable at 48px. No electric blue, no wireless/wifi/radio waves, no QR code, no extra words, no slogan, no small details, no padlock pasted onto the letters, no busy 3D bevels, no dramatic glow, no watermark. Background must fill the whole square with no pre-rounded outer app tile corners and no outside margin. Distinct silhouette AND palette from the online logo.
