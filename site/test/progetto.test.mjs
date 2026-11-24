import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { caricaProgetto, maschera, FILE, SORGENTE, VIETATI } from '../src/progetto.mjs';

test('maschera: toglie gli IP della LAN, lascia ClusterIP e versioni', () => {
  assert.equal(maschera('192.168.1.79  biodistretto.lab'), 'IP-DEL-LAB  biodistretto.lab');
  assert.equal(maschera('http://192.168.1.79:8404/'), 'http://IP-DEL-LAB:8404/');
  assert.equal(maschera('default = "10.96.100.10"'), 'default = "10.96.100.10"');
  assert.equal(maschera('haproxy:3.2-alpine e 1.192.168.1'), 'haproxy:3.2-alpine e 1.192.168.1');
});

test('lezione 24: il README è la spiegazione, gli altri file sono sorgenti del progetto', () => {
  const l = caricaProgetto();
  assert.equal(l.id, '24');
  assert.equal(l.fonti[0].percorso, 'README.md');
  assert.equal(l.fonti[0].ruolo, 'lezione');
  assert.ok(l.fonti.slice(1).every(f => f.ruolo === 'progetto'));
  assert.equal(l.fonti.length, FILE.length);
  assert.ok(l.passi.testo.includes("'./deploy.sh'"));
  assert.ok(l.fonti.every(f => !/192\.168\.\d+\.\d+/.test(f.testo)), 'nessun IP della LAN');
  assert.ok(l.fonti[0].testo.includes('IP-DEL-LAB'));
});

test('nessun file con segreti finisce fra le sorgenti', () => {
  for (const f of FILE) for (const re of VIETATI) assert.ok(!re.test(f), f);
  assert.ok(VIETATI.some(re => re.test('terraform/app/terraform.tfstate')));
  assert.ok(VIETATI.some(re => re.test('.cache/haproxy-stats')));
  assert.ok(VIETATI.some(re => re.test('docker/.env')));
});

test('fedeltà: ogni file è identico a quello del progetto, salvo gli IP mascherati', t => {
  if (!existsSync(join(SORGENTE, 'README.md'))) return t.skip('progetto biodistretto assente');
  const l = caricaProgetto();
  for (const f of l.fonti) assert.equal(f.testo, maschera(readFileSync(join(SORGENTE, f.percorso), 'utf8')), f.percorso);
});
