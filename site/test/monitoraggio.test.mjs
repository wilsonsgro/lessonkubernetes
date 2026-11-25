import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { FILE, bloccoDellaSezione } from '../src/monitoraggio.mjs';

const leggi = p => readFileSync(new URL(`../content/monitoraggio/${p}`, import.meta.url), 'utf8');

test('lezione 25: ogni YAML scaricabile è identico al blocco della sua sezione nel testo', () => {
  const md = leggi('lezione-25.md');
  const yaml = FILE.filter(f => f.sezione);
  assert.equal(yaml.length, 3);
  for (const f of yaml) assert.equal(leggi(f.percorso), bloccoDellaSezione(md, f.sezione), f.percorso);
});

test('lezione 25: il testo tiene le sezioni 1–14 e i riferimenti, non la specifica per l\'agente', () => {
  const md = leggi('lezione-25.md');
  for (let n = 1; n <= 14; n++) assert.match(md, new RegExp(`^# ${n}\\. `, 'm'), `sezione ${n}`);
  assert.match(md, /^# Riferimenti pubblici utili$/m);
  assert.ok(!/^# 15\. /m.test(md) && !/^---\ntitle:/.test(md));
});
