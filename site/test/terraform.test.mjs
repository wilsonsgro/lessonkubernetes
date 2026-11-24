import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { caricaCapitolo, PARTI } from '../src/terraform.mjs';

const radice = new URL('../../', import.meta.url);

for (const [id, parti, conFile, fonti] of [
  ['22', ['00', '01', '02', '03', '04', '05'], 5, 17],
  ['23', ['06', '07', '08', '09', '10'], 5, 15],
]) {
  test(`lezione ${id}: parti ${parti[0]}–${parti.at(-1)}, ognuna con spiegazione e script guidato`, () => {
    const l = caricaCapitolo(id);
    assert.equal(l.id, id);
    assert.deepEqual(l.parti.map(p => p.n), parti);
    for (const p of l.parti) {
      assert.equal(p.spiegazione.ruolo, 'lezione', p.n);
      assert.equal(p.script.ruolo, 'passi', p.n);
      assert.match(p.script.testo, /^titolo "/m, p.n);
      assert.ok(p.titolo.length > 5, p.n);
      assert.ok(p.spiegazione.percorso.startsWith(`terraform/${p.n}-`), p.n);
    }
    assert.equal(l.parti.filter(p => p.file).length, conFile);
    assert.equal(l.fonti.length, fonti);
  });
}

test('le due lezioni si dividono le parti 00–10 senza sovrapporsi', () => {
  assert.deepEqual(PARTI, ['00', '01', '02', '03', '04', '05', '06', '07', '08', '09', '10']);
  const a = caricaCapitolo('22').fonti.map(f => f.percorso);
  const b = caricaCapitolo('23').fonti.map(f => f.percorso);
  assert.equal(a.filter(p => b.includes(p)).length, 0);
});

test('fedeltà: i file Terraform e Ansible del sito sono identici a quelli del laboratorio', t => {
  if (!existsSync(new URL('terraform', radice))) return t.skip('repo kubernetesprj assente');
  const h = s => createHash('sha256').update(s).digest('hex');
  for (const id of ['22', '23']) for (const f of caricaCapitolo(id).fonti) assert.equal(h(f.testo), h(readFileSync(new URL(f.percorso, radice))), f.percorso);
});
