# Pixel 8 screenshots for the website

- Captured from the user's connected Pixel 8 on 2026-09-07, then locally retouched with built-in Images (`image_gen`, edit mode).
- Online: `public/assets/wallet-pixel8-en.png` (841 × 1870).
- Offline: `public/assets/signer-pixel8-en.png` (841 × 1870).
- Wallet names, avatar initial, online address, and displayed financial values were replaced with English sample details; no mosaics or blurred redactions. System status icons and gesture bars were removed.
- These are edited device captures, not unmodified screenshots. The tool resampled the original 1080 × 2400 captures; app composition and visible warning states were retained.
- Images introduced minor background texture and icon-rendering differences; do not describe these as pixel-identical originals.
- Online incomplete-data warning and offline risk warning are deliberately preserved. No successful security state was fabricated.
- Raw captures remain outside the repository/public asset directory. No private keys or recovery phrases were viewed or captured.
- Default route and all screenshot UI are English. No visible AI/sample-data caption is displayed, as requested. Source provenance stays in this document.
- Social-preview image unchanged. Local preview only; no deployment performed.

# Real Pixel 8 screenshot local edits

Mode: built-in image_gen. One request per asset; no variants or retries.

## Results

- Online output: `/Users/github/.codex/generated_images/01a07983-41f8-7750-b36d-b0ee33c35cbb/exec-d00d8d17-3ed4-4750-af25-df98e601ff37.png`
- Offline output: `/Users/github/.codex/generated_images/01a07983-41f8-7750-b36d-b0ee33c35cbb/exec-20021632-5ef2-402f-817f-f2c3ff895c87.png`
- Both output dimensions verified with sips: 841 × 1870 pixels. The tool did not retain the requested source dimensions of 1080 × 2400 pixels. Portrait ratio is approximately preserved, but these outputs are not pixel-identical local retouches: the tool introduced subtle background texture and icon rendering differences. Layout and warning text are visually preserved.
- Online requested address, total, daily change, and token values are present. BNB lower text remains partly behind the original bottom app navigation; TRX zero USD remains visible. OS symbols and gesture bars removed in both.
- No site edits, resizing, variants, or retry requests performed.

## Online screenshot

Use case: text-localization
Asset type: real Pixel 8 app screenshot retouch for website
Input image: online-current.png is the sole edit target, an existing real 1080x2400 screenshot. This is a local retouch, never a new UI mockup.
Primary request: Preserve the screenshot exactly except these localized changes:
1. Erase only the OS time and status/notification symbols at the very top, and the OS gesture bar at the very bottom. Fill those tiny regions by matching their immediate surrounding background. Preserve all app navigation tabs and app icons.
2. Replace the Chinese wallet heading "钱包 1" with "Main Wallet", preserving its original font weight, size, alignment, and nearby dropdown chevron. Replace the Chinese character inside the blue avatar with "M".
3. Replace the abbreviated address with exact "0x7A2b...9D4e".
4. Change the large total from "$0.00" to "$862.40" and daily change to exact "+$12.06 (+1.4%) 1D", with the same original typography and placement.
5. Change the right-aligned token amounts and USD amounts to ETH "0.12 ETH" and "$360.00"; POL "250 POL" and "$100.00"; AVAX "10 AVAX" and "$240.00"; BNB "0.2 BNB" and "$162.40"; TRX remains zero and "$0.00". Preserve the original bottom navigation overlapping the lowest token rows; do not move rows or navigation to expose obscured text.
Invariants: Preserve exact real app geometry, spacing, card shapes, icon graphics, gradients, background colors, all button and tab labels, English labels and line wrapping. Preserve the original warning verbatim: "Some asset data could not be updated. Saved values are kept where available." Do not fabricate a successful/live state. Preserve "Local signing". Typography must be crisp, properly spelled, and match the original screenshot.
Composition: Same edge-to-edge portrait screenshot, same 1080x2400 dimensions and 9:20 aspect ratio; no crop, stretch, zoom, or rearrangement.
Avoid: Do not redesign; do not draw a phone or hardware/frame; do not add backdrop, captions, transparency, mosaic, blur, redaction blocks, or extra text. Edit only the requested pixels.

## Offline screenshot

Use case: text-localization
Asset type: real Pixel 8 offline signer screenshot retouch for website
Input image: signer-original.png is the sole edit target, an existing real 1080x2400 screenshot. This is a local retouch, never a new UI mockup.
Primary request: Make only these localized edits:
1. Replace the Chinese heading "主钱包" with exact "Main Wallet", preserving its original white font weight, size, and left alignment.
2. Erase only the OS time and status/notification symbols at the very top, and the OS gesture bar at the very bottom. Fill those small regions by exactly matching the surrounding dark background.
Invariants: Preserve the actual app geometry, every element's placement and spacing, rounded card shapes, borders, gradients, background, icons, and all other text unchanged. Preserve green "Network offline" exactly. Preserve the amber warning "Risks detected · Proceed with caution" exactly, with its warning icon, chevron and original amber panel. Do not replace any risk message with success. Preserve "Scan pending transaction", "Scan the dynamic QR from the online wallet", "Address QR", "Signing records", "Security check", and "Wallet management" with their original line wrapping. Crisp typography, no garbled text.
Composition: Same edge-to-edge portrait screenshot, same 1080x2400 dimensions and 9:20 aspect ratio; no crop, stretch, zoom, or rearrangement.
Avoid: Do not redesign; do not draw hardware or phone/frame; do not add backdrop, captions, transparency, mosaic, blur, redaction blocks, or extra text. Edit only the requested pixels.
