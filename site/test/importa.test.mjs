import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { importa, ORDINE, sezioneMd } from '../src/importa.mjs';

const MINI = [
  '# Corso', '', '## Mappa dei collegamenti che il sito deve rendere evidenti', '',
  '| Concetto di origine | Ritorna in | Perché è importante |', '|---|---|---|',
  '| Readiness (02) | 03, 21 | Running non vuol dire pronto |', '',
  '<a id="lezione-02"></a>', '', '# Lezione 02 — Deployment', '',
  '## Spiegazione e riflessioni ragionate', '', '### Modello', 'Testo **forte**.', '',
  '## Materiale originale della lezione', '',
  '### Fonte originale: `02-x.md`', '', '> nota', '', '````markdown', '# 02 titolo', '```bash', 'echo ciao', '```', '````', '',
  '### Fonte originale: `02-x.sh`', '', '````bash', 'passo "uno" \\', "  'kubectl get pod'", '````', '',
  '## Traccia per lo studio attivo', '', 'Rileggi.', '', '---', '',
  '<a id="lezione-21"></a>', '', '# Lezione 21 — HAProxy', '', '## Spiegazione e riflessioni ragionate', '', 'x', '',
  '## Materiale originale della lezione', '', '### Fonte originale: `21-y.yaml`', '', '````yaml', 'kind: Service', '````', '',
  '## Traccia per lo studio attivo', '', 'y', '',
].join('\n');

test('divide le lezioni sulle ancore e tiene il titolo', () => {
  const c = importa(MINI);
  assert.deepEqual(c.lezioni.map(l => l.id), ['02', '21']);
  assert.equal(c.lezioni[0].titolo, 'Deployment');
  assert.equal(c.lezioni[1].titolo, 'HAProxy');
});

test('le fonti sono copiate senza toccare i fence interni', () => {
  const [l02] = importa(MINI).lezioni;
  assert.equal(l02.fonti.length, 2);
  assert.equal(l02.fonti[0].testo, '# 02 titolo\n```bash\necho ciao\n```\n');
  assert.equal(l02.fonti[0].lingua, 'markdown');
  assert.equal(l02.fonti[0].ruolo, 'lezione');
  assert.equal(l02.fonti[1].ruolo, 'passi');
});

test('spiegazione e traccia restano separate dalle fonti', () => {
  const [l02] = importa(MINI).lezioni;
  assert.match(l02.spiegazione, /### Modello/);
  assert.doesNotMatch(l02.spiegazione, /Fonte originale/);
  assert.equal(l02.traccia.trim(), 'Rileggi.');
});

test('la mappa dei collegamenti diventa dati', () => {
  const { mappa } = importa(MINI);
  assert.deepEqual(mappa, [{ concetto: 'Readiness', da: '02', verso: ['03', '21'], perche: 'Running non vuol dire pronto' }]);
});

test('un fence non chiuso è un errore, non una lezione troncata', () => {
  assert.throws(() => importa(MINI.replace(/````\n\n### Fonte originale: `02-x.sh`/, '\n### Fonte originale: `02-x.sh`')), /non chiuso/);
});

const CORSO = new URL('../content/corso.md', import.meta.url);

test('il corso vero ha le dieci lezioni nell\'ordine giusto, tre fonti ciascuna', () => {
  const c = importa(readFileSync(CORSO, 'utf8'));
  assert.deepEqual(c.lezioni.map(l => l.id), ORDINE);
  for (const l of c.lezioni) {
    assert.equal(l.fonti.length, 3, l.id);
    assert.equal(l.fonti.filter(f => f.ruolo === 'lezione').length, 1, l.id);
    assert.equal(l.fonti.filter(f => f.ruolo === 'passi').length, 1, l.id);
    assert.ok(l.spiegazione.length > 500, l.id);
  }
  assert.equal(c.mappa.length, 10);
  assert.equal(c.lezioni[9].breve, 'HAProxy');
  assert.match(c.lezioni[0].sommario, /etcd/);
});

test('sezioneMd prende una sezione fino al titolo dello stesso livello, ignorando i # nei fence', () => {
  const md = '# T\n## In una frase\nUno.\n```bash\n## non titolo\n```\n### sotto\nDue.\n## Altro\nNo.';
  assert.equal(sezioneMd(md, /^In una frase/), 'Uno.\n```bash\n## non titolo\n```\n### sotto\nDue.');
  assert.equal(sezioneMd(md, /^Manca/), '');
});

test('ogni fonte è identica al file vero del repo (se il repo c\'è)', (t) => {
  const radice = new URL('../../', import.meta.url);
  if (!existsSync(new URL('lezioni/kubernetes', radice))) return t.skip('repo kubernetesprj assente');
  const c = importa(readFileSync(CORSO, 'utf8'));
  for (const l of c.lezioni) for (const f of l.fonti) {
    const vero = readFileSync(new URL(f.percorso, radice));
    const h = s => createHash('sha256').update(s).digest('hex');
    assert.equal(h(f.testo), h(vero), `${l.id} ${f.percorso}`);
  }
});
