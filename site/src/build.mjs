// Builds the static site into dist/ from content/: same input, same output (no dates, no randomness).
import { readFileSync, writeFileSync, mkdirSync, rmSync, cpSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { importa, sezioneMd } from './importa.mjs';
import { creaMarkdown, bloccoCodice, esc, slug } from './markdown.mjs';
import { leggiPassi } from './passi.mjs';
import { diagramma } from './diagrammi.mjs';
import { caricaCapitolo } from './terraform.mjs';
import { caricaProgetto } from './progetto.mjs';
import { caricaMonitoraggio } from './monitoraggio.mjs';
import { paginaLezione, paginaHome, paginaGlossario, paginaFlashcard, paginaPreferiti } from './pagine.mjs';

const RADICE = join(dirname(fileURLToPath(import.meta.url)), '..');
const DIST = process.env.DIST || join(RADICE, 'dist');
const leggi = p => readFileSync(join(RADICE, p), 'utf8');
const json = p => JSON.parse(leggi(p));

const SIM = {
  '03': ['netpol'], '05': ['partition'], '06': ['hpa'], '07': ['rbac'], '09': ['helm'],
  '21': ['failover', 'ratelimit', 'bilancia', 'tls'], '22': ['count-foreach', 'precedenza'],
  '23': ['rolling', 'precedenza-ansible'], '25': ['rate', 'alert'],
};
const APPROFONDIMENTI = {
  '21': { id: 'approfondimento-tls', file: 'approfondimenti/21-haproxy-cfg-tls.md', quiz: '21-tls', titolo: 'HAProxy fuori da Kubernetes: haproxy.cfg e TLS' },
};
const TITOLI_SIM = {
  netpol: 'NetworkPolicy: OR contro AND', partition: 'StatefulSet: partition', hpa: 'Calcolo dell\'HPA',
  rbac: 'RBAC: chi può fare cosa', helm: 'Helm: storia della release', failover: 'Guasto di una replica HAProxy',
  ratelimit: 'Rate limit con più repliche', bilancia: 'roundrobin contro leastconn',
  tls: 'haproxy.cfg del negozio: ACL e modalità TLS',
  'count-foreach': 'count contro for_each: togliere un elemento', precedenza: 'Da dove arriva il valore di una variabile',
  rolling: 'Rolling update a lotti: chi resta nel bilanciatore', 'precedenza-ansible': 'Quale variabile vince in Ansible',
  rate: 'Counter e rate(): il contatore sale, il tasso no', alert: 'for: 1m — Inactive, Pending, Firing',
};

function testoPiano(html) {
  return html.replace(/<script[\s\S]*?<\/script>/g, ' ').replace(/<[^>]+>/g, ' ').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&amp;/g, '&').replace(/\s+/g, ' ').trim();
}

function sezioniDa(html, url, lezione, prefisso) {
  const out = [];
  const re = /<h([23]) id="([^"]+)">([\s\S]*?)<\/h\1>/g;
  const punti = [];
  let m;
  while ((m = re.exec(html))) punti.push({ i: m.index, fine: re.lastIndex, id: m[2], t: testoPiano(m[3]) });
  punti.forEach((p, n) => {
    const x = testoPiano(html.slice(p.fine, n + 1 < punti.length ? punti[n + 1].i : html.length));
    if (x) out.push({ u: `${url}#${p.id}`, l: lezione, t: `${prefisso}${p.t}`, x: x.slice(0, 4000) });
  });
  return out;
}

function htmlPassi(f, intro) {
  const voci = leggiPassi(f.testo);
  const li = voci.map(v => {
    if (v.tipo === 'passo') return `<li class="passo"><p class="passo-perche"><span class="passo-n">${String(v.n).padStart(2, '0')}</span> ${esc(v.perche)}</p>${bloccoCodice({ codice: v.comando, lingua: 'bash' })}</li>`;
    if (v.tipo === 'titolo') return `<li class="passo-titolo">${esc(v.testo)}</li>`;
    if (v.tipo === 'cartella') return `<li class="passo-cartella"><span class="etichetta">cartella di lavoro</span> <code>~/kubernetesprj/lavoro/${esc(v.testo)}</code></li>`;
    return `<li class="passo-nota"><span class="etichetta">nota</span> ${esc(v.testo).replace(/\n/g, ' ')}</li>`;
  }).join('');
  const testa = intro || `Da <code>~/kubernetesprj/${esc(f.percorso)}</code>: lo script stampa ogni passo e aspetta Invio (esegui), s (salta) o q (esci). Le variabili come <code>$F</code> o <code>$IP</code> le imposta lo script; il file completo è nella vista «Sorgenti originali».`;
  return `<p class="fonte-meta">${testa}</p><ol class="passi">${li}</ol>`;
}

export function costruisci() {
  const corso = importa(leggi('content/corso.md'));
  const glossario = json('content/glossario.json');
  const flashcard = json('content/flashcard.json');
  const lezioni = [...corso.lezioni, caricaCapitolo('22'), caricaCapitolo('23'), caricaProgetto(), caricaMonitoraggio()];
  const mappa = [...corso.mappa, ...json('content/terraform/mappa.json'), ...json('content/progetto/mappa.json'), ...json('content/monitoraggio/mappa.json')];
  const quiz = Object.fromEntries(lezioni.map(l => [l.id, json(`content/quiz/quiz-${l.id}.json`)]));

  mkdirSync(DIST, { recursive: true });
  for (const voce of readdirSync(DIST)) rmSync(join(DIST, voce), { recursive: true, force: true });
  mkdirSync(join(DIST, 'lezioni'), { recursive: true });
  mkdirSync(join(DIST, 'dati'), { recursive: true });
  cpSync(join(RADICE, 'assets'), join(DIST, 'assets'), { recursive: true });

  const indice = [];
  for (const l of lezioni) {
    const md = creaMarkdown();
    const fonteLez = l.fonti.find(f => f.ruolo === 'lezione');
    const passi = l.passi || l.fonti.find(f => f.ruolo === 'passi');
    const fraseMd = sezioneMd(l.parti || l.passi ? l.spiegazione : fonteLez.testo, /^In una frase/);
    const verificaMd = sezioneMd(l.spiegazione, /^Verifica rapida/);
    const html = {
      spiegazione: md.rendi(l.spiegazione),
      parti: (l.parti || []).map(p => md.rendi(p.spiegazione.testo, { spostaTitoli: 1 })),
      lezione: l.parti ? '' : md.rendi(fonteLez.testo, { spostaTitoli: 1 }),
      fonti: l.fonti.map((f, n) => bloccoCodice({ codice: f.testo, lingua: f.lingua, nome: f.nome, download: `/fonti/${f.scarica || f.percorso}`, id: `f${n + 1}` })),
      passi: l.parti ? l.parti.map(p => `<h3 id="passi-${p.n}">Parte ${p.n} · ${esc(p.titolo)}</h3>${htmlPassi(p.script)}`).join('') : htmlPassi(passi, l.introPassi),
      traccia: creaMarkdown().rendi(l.traccia),
    };
    const ap = APPROFONDIMENTI[l.id];
    const approfondimento = ap && {
      ...ap, html: md.rendi(leggi(`content/${ap.file}`), { spostaTitoli: 1 }), domande: json(`content/quiz/quiz-${ap.quiz}.json`),
    };
    const simulazioni = (SIM[l.id] || []).map(s => `<section class="sim" data-sim="${s}" aria-labelledby="sim-${s}"><h3 id="sim-${s}">${esc(TITOLI_SIM[s])}</h3><noscript>La simulazione richiede JavaScript.</noscript></section>`).join('');
    const pag = paginaLezione({
      l, lezioni, mappa, html, glossario,
      quiz: quiz[l.id], flashcard: flashcard.filter(f => f.lezione === l.id),
      simulazioni, diagramma: diagramma(l.id), approfondimento,
      frase: fraseMd ? creaMarkdown().rendi(fraseMd) : '',
      verifica: verificaMd ? creaMarkdown().rendi(verificaMd) : '',
    });
    writeFileSync(join(DIST, 'lezioni', `${l.id}.html`), pag);

    const url = `/lezioni/${l.id}.html`;
    indice.push(...sezioniDa(html.spiegazione, `${url}?vista=spiegazione`, l.id, 'Appunti · '));
    indice.push(...sezioniDa(html.lezione + html.parti.join(''), `${url}?vista=spiegazione`, l.id, ''));
    if (approfondimento) {
      indice.push(...sezioniDa(approfondimento.html, `${url}?vista=spiegazione`, l.id, 'Approfondimento · '));
      mkdirSync(join(DIST, 'fonti', dirname(approfondimento.file)), { recursive: true });
      writeFileSync(join(DIST, 'fonti', approfondimento.file), leggi(`content/${approfondimento.file}`));
      for (const q of approfondimento.domande) indice.push({ u: `${url}#quiz-${approfondimento.quiz}`, l: l.id, t: `Quiz · ${q.domanda.slice(0, 80)}`, x: `${q.domanda} ${q.spiegazione}` });
    }
    l.fonti.forEach((f, n) => {
      const righe = f.testo.replace(/\n$/, '').split('\n');
      for (let a = 0; a < righe.length; a += 25) {
        indice.push({ u: `${url}?vista=sorgenti#f${n + 1}-L${a + 1}`, l: l.id, t: `${f.nome} · righe ${a + 1}–${Math.min(a + 25, righe.length)}`, x: righe.slice(a, a + 25).join('\n'), s: 1 });
      }
      mkdirSync(join(DIST, 'fonti', dirname(f.scarica || f.percorso)), { recursive: true });
      writeFileSync(join(DIST, 'fonti', f.scarica || f.percorso), f.testo);
    });
    for (const q of quiz[l.id]) indice.push({ u: `${url}#quiz-titolo`, l: l.id, t: `Quiz · ${q.domanda.slice(0, 80)}`, x: `${q.domanda} ${q.spiegazione}` });
  }
  for (const g of glossario) indice.push({ u: `/glossario.html#${slug(g.termine)}`, l: 'G', t: `Glossario · ${g.termine}`, x: `${(g.alias || []).join(' ')} ${g.definizione}` });

  writeFileSync(join(DIST, 'index.html'), paginaHome({ lezioni, mappa }));
  writeFileSync(join(DIST, 'glossario.html'), paginaGlossario({ glossario, lezioni }));
  writeFileSync(join(DIST, 'flashcard.html'), paginaFlashcard({ flashcard, lezioni }));
  writeFileSync(join(DIST, 'preferiti.html'), paginaPreferiti());
  writeFileSync(join(DIST, 'dati', 'cerca.json'), JSON.stringify(indice));
  writeFileSync(join(DIST, 'dati', 'glossario.json'), JSON.stringify(glossario));
  writeFileSync(join(DIST, 'dati', 'lezioni.json'), JSON.stringify(lezioni.map(l => ({ id: l.id, titolo: l.titolo, breve: l.breve }))));
  writeFileSync(join(DIST, 'dati', 'corso.json'), JSON.stringify({ mappa, lezioni }, null, 1));
  return { lezioni: lezioni.length, voci: indice.length, file: readdirSync(join(DIST, 'lezioni')).length };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const r = costruisci();
  console.log(`dist: ${r.file} lezioni, ${r.voci} voci di ricerca`);
}
