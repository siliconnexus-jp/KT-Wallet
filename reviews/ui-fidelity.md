# UI 1:1 Fidelity Review — ui.pen vs ui-m.md §17

Reviewed the Pencil design (`ui.pen`) screen-by-screen against the V1 page list
in ui-m.md §17.

## Inventory (verified via layout snapshot)

- **52 screens**: KT Wallet W1–W31 (31), Cold Signer C1–C21 (21).
- **7 reusable components**: Status Bar, W/C Button, W/C Detail Row, Network
  Chip, W Asset Row.

## Defects found & fixed during review

1. **QR screens rendered a "Script not found" error box** — the `qr.js` script
   was missing from the repo next to `ui.pen`, breaking 待签名二维码 (W6), 收款
   (W14), 签名结果 (C9), 地址导出 (C10). FIXED: restored `qr.js`; all four now
   render QR patterns.
2. **Stray empty 800×600 default frame** at the canvas root. FIXED: deleted.
3. **§17.17 手续费选择页 was not standalone** (folded into W4 as inline tiers).
   FIXED: added **W31 手续费选择** — three fee-tier cards + custom Gas/Fee-Limit
   fields + low-fee warning. KT Wallet is now 28/28 standalone vs §17.

## Remaining consolidations (intentional, documented)

Four Cold Signer pages in §17 are inline states of a parent screen rather than
standalone — these are defensible UX consolidations, kept as-is:

| §17 page | Realized as | Rationale |
|---|---|---|
| 离线 §4 创建或导入钱包页 | buttons on C1 欢迎 | choice is two buttons, not a page |
| 离线 §13 地址列表页 | part of C10 地址导出 | list + export QR on one screen |
| 离线 §16 扫描进度页 | inline state of C6 扫描交易 | progress is a scan state |
| 离线 §19 签名确认页 | part of C7 交易解析确认 | parse + confirm on one screen |

Recommendation: treat these as inline states in §17 (annotate the list) rather
than splitting — splitting adds navigation with no content gain.

## Beyond 1:1 (design exceeds the spec)

- §17.9 钱包首页 has two variants: W1 观察 + W20 普通.
- §17.18 交易确认 has two variants: W5 观察 + W29 普通.
- Extra W11 连接离线钱包 (pre-scan explainer).

## Verdict

All functional flows, states, and content are fully covered. After the fixes,
KT Wallet is page-for-page 1:1 with §17; Cold Signer covers all pages with 4
intentional inline consolidations. No missing flows or broken screens remain.
