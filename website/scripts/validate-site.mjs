import assert from 'node:assert/strict';
import { readFile, access } from 'node:fs/promises';
import { join, resolve } from 'node:path';

const dist = resolve(import.meta.dirname, '../dist');
const cases = [
  ['index.html', 'en', 'Frontend &amp; backend'],
  ['zh/index.html', 'zh-CN', '前后端'],
  ['ja/index.html', 'ja', 'バックエンド'],
];
for (const [file, lang, heading] of cases) {
  const html = await readFile(join(dist, file), 'utf8');
  assert.match(html, new RegExp(`<html lang="${lang}"`));
  assert.ok(html.includes(heading), `${file}: missing localized open-source message`);
  assert.ok(html.includes('100%'), `${file}: missing open-source percentage`);
  assert.equal((html.match(/<h1(?:\s|>)/g) ?? []).length, 1);
  for (const path of ['apps/kt_wallet', 'apps/cold_signer', 'backend/gateway']) {
    assert.ok(html.includes(`https://github.com/siliconnexus-jp/KT-Wallet/tree/main/${path}`));
  }
  for (const [, url] of html.matchAll(/(?:src|href)="(\/[^"#]*)"/g)) {
    const path = url.split('?')[0];
    await access(join(dist, path.endsWith('/') ? `${path}index.html` : path));
  }
  for (const [, anchor] of html.matchAll(/href="#([^"]+)"/g)) {
    assert.ok(html.includes(`id="${anchor}"`), `${file}: missing anchor ${anchor}`);
  }
  assert.ok(!html.includes('wallet-current-'), 'Do not publish rejected font captures');
  assert.ok(!html.includes('signer-current-'), 'Do not publish rejected font captures');
  assert.ok(!html.includes('<figcaption'), 'Product screenshots should have no disclaimer caption');
  assert.ok(!html.includes('<select'), 'Language picker should not use the rejected native select');
  assert.match(html, /<details[^>]*data-language-switch/);
  assert.equal((html.match(/aria-current="page"/g) ?? []).length, 1, 'Exactly one language is selected');
  assert.ok(html.includes('/assets/wallet-pixel8-en.png'));
  assert.ok(html.includes('/assets/signer-pixel8-en.png'));
  assert.ok(!html.includes('/assets/kt-wallet-product-en.png'), 'Do not use the superseded generated phones');
  console.log(`PASS ${lang}: localized copy, source links, images and navigation`);
}
console.log('PASS English is the default root route; all languages use English product art.');
