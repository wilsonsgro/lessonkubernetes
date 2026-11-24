// HTML shells of the static site: shared header and sidebar, lesson page in three views, home, glossary, flashcards.
import { esc, slug } from './markdown.mjs';

const RUOLI = { lezione: 'Spiegazione della lezione', manifest: 'File della lezione', passi: 'Comandi passo passo', progetto: 'File del progetto' };
export const ruolo = r => RUOLI[r] || r;
const APPROFONDIMENTI = ['21', '22', '23', '24'];
const approf = l => APPROFONDIMENTI.includes(l.id);
const AVVISO_LAB = {
  '24': 'sono i comandi di un <b>progetto vero</b>, non di un esercizio: si lanciano solo a mano, sul PC del laboratorio, in <code>~/biodistretto/kubernetes</code>. <code>./deploy.sh</code> crea un cluster minikube a 2 nodi e un container HAProxy sulle porte 80 e 443 dell\'host; <code>./deploy.sh distruggi</code> toglie tutto, dati compresi.',
  '22': 'i comandi sono esempi da lanciare a mano: Terraform usa il <b>Docker locale</b> come se fosse un cloud, nessun cluster. <code>00-installa.sh</code> chiede sudo; ogni script lavora in <code>~/kubernetesprj/lavoro/iac/NN</code>.',
  '23': 'i comandi sono esempi da lanciare a mano. Prima serve la parte 00 della <a href="/lezioni/22.html">lezione 22</a> (ansible-core con pipx e le collection). I «server» sono container <b>privilegiati</b> con systemd (<code>web1</code>, <code>web2</code>, <code>db1</code>), solo per il laboratorio: le parti 06–09 lavorano in <code>~/kubernetesprj/lavoro/ansible</code> e li tolgono alla fine della 09, la 10 crea e distrugge i suoi in <code>~/kubernetesprj/lavoro/iac/10</code>. La parte 09 lascia <code>~/.vault_pass</code> nella tua home.',
};

export function testata() {
  return `<a class="salta" href="#contenuto">Vai al contenuto</a>
<header class="testata">
  <button type="button" class="apri-percorso" aria-controls="percorso" aria-expanded="false" aria-label="Apri l'elenco delle lezioni">☰</button>
  <a class="marchio" href="/">Kubernetes <span>· corso</span></a>
  <div class="cerca" role="search">
    <label class="vh" for="cerca-campo">Cerca nel corso</label>
    <input id="cerca-campo" type="search" autocomplete="off" placeholder="Cerca: EndpointSlice, stick-table, checksum…  ( / )" aria-controls="cerca-risultati" aria-expanded="false" aria-autocomplete="list">
    <ul id="cerca-risultati" class="cerca-risultati" role="listbox" aria-label="Risultati della ricerca" hidden></ul>
  </div>
  <a class="progresso-mini" href="/#percorso-corso" aria-label="Progresso del corso"><span class="barra" aria-hidden="true"><i data-progresso-barra></i></span><span data-progresso-testo>0/13</span></a>
  <nav class="testata-link" aria-label="Strumenti"><a href="/glossario.html">Glossario</a><a href="/flashcard.html">Flashcard</a></nav>
  <button type="button" class="tema" aria-label="Cambia tema chiaro/scuro" title="Tema chiaro/scuro">◐</button>
</header>`;
}

export function percorso(lezioni, corrente) {
  const voce = l => `<li><a href="/lezioni/${l.id}.html" data-id="${l.id}"${l.id === corrente ? ' aria-current="page"' : ''}><span class="num">${l.id}</span><span class="tit">${esc(l.breve)}</span><span class="stato" data-stato="${l.id}" aria-hidden="true"></span></a></li>`;
  const base = lezioni.filter(l => !approf(l)).map(voce).join('');
  const spec = lezioni.filter(approf).map(voce).join('');
  return `<nav class="percorso" id="percorso" aria-label="Lezioni del corso"><ol>${base}</ol><p class="percorso-sep">Approfondimenti</p><ol class="speciale">${spec}</ol></nav>`;
}

export function pagina({ titolo, descrizione = '', corpo, classe = '', lezione = '' }) {
  return `<!doctype html>
<html lang="it" data-tema="chiaro">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(titolo)}</title>
<meta name="description" content="${esc(descrizione)}">
<link rel="icon" href="/assets/icona.svg" type="image/svg+xml">
<script>try{const t=localStorage.getItem('k8s-lezioni:tema')||(matchMedia('(prefers-color-scheme: dark)').matches?'scuro':'chiaro');document.documentElement.dataset.tema=t}catch(e){}</script>
<link rel="stylesheet" href="/assets/app.css">
</head>
<body class="${classe}"${lezione ? ` data-lezione="${lezione}"` : ''}>
${corpo}
<div id="popover-termine" class="popover" role="dialog" aria-modal="false" aria-labelledby="popover-titolo" hidden></div>
<script type="module" src="/assets/app.js"></script>
</body>
</html>
`;
}

const linkLez = (id, lezioni) => {
  const l = lezioni.find(x => x.id === id);
  return l ? `<a href="/lezioni/${id}.html" class="chip" title="${esc(l.titolo)}">${id} ${esc(l.breve)}</a>` : `<span class="chip">${esc(id)}</span>`;
};

export function paginaLezione({ l, lezioni, mappa, html, glossario, quiz, flashcard, simulazioni, diagramma, frase, verifica, approfondimento }) {
  const i = lezioni.findIndex(x => x.id === l.id);
  const prima = lezioni[i - 1], dopo = lezioni[i + 1];
  const daQui = mappa.filter(m => m.da === l.id);
  const versoQui = mappa.filter(m => m.verso.includes(l.id));
  const termini = glossario.filter(g => g.lezioni.includes(l.id) && g.lezioni.length > 1);
  const collegamenti = `
    ${versoQui.length ? `<h3>Riprende</h3><ul class="colleg">${versoQui.map(m => `<li><b>${esc(m.concetto)}</b> ${linkLez(m.da, lezioni)}<br><small>${esc(m.perche)}</small></li>`).join('')}</ul>` : ''}
    ${daQui.length ? `<h3>Ritorna in</h3><ul class="colleg">${daQui.map(m => `<li><b>${esc(m.concetto)}</b> ${m.verso.map(v => linkLez(v, lezioni)).join(' ')}<br><small>${esc(m.perche)}</small></li>`).join('')}</ul>` : ''}
    ${termini.length ? `<h3>Termini condivisi</h3><ul class="colleg termini">${termini.map(g => `<li><a href="/glossario.html#${slug(g.termine)}">${esc(g.termine)}</a> ${g.lezioni.filter(x => x !== l.id).map(v => `<a class="chip piccolo" href="/lezioni/${v}.html">${v}</a>`).join('')}</li>`).join('')}</ul>` : ''}`;

  const fonti = l.fonti.map((f, n) => `
    <section class="fonte" aria-labelledby="fonte-${n + 1}">
      <h2 id="fonte-${n + 1}">${esc(f.nome)} <span class="etichetta">${esc(ruolo(f.ruolo))}</span></h2>
      <p class="fonte-meta"><code>${l.radice || '~/kubernetesprj/'}${esc(f.percorso)}</code> · ${f.righe} righe · trascrizione integrale, ${f.testo.includes('IP-DEL-LAB') ? 'identica al file salvo l\'indirizzo del laboratorio, mascherato come <code>IP-DEL-LAB</code>' : 'identica al file'}</p>
      ${html.fonti[n]}
    </section>`).join('');

  const corpo = `${testata()}
<div class="impianto">
${percorso(lezioni, l.id)}
<main id="contenuto" tabindex="-1">
  <header class="lezione-testa">
    <p class="occhiello">Lezione ${l.id}${approf(l) ? ' · Approfondimento' : ''}</p>
    <h1>${esc(l.titolo)}</h1>
    <div class="azioni">
      <button type="button" class="btn" data-azione="completa" aria-pressed="false">Segna come completata</button>
      <button type="button" class="btn icona" data-azione="preferita" aria-pressed="false" aria-label="Aggiungi ai preferiti">☆</button>
      <button type="button" class="btn icona" data-azione="stampa" aria-label="Stampa o salva in PDF">⎙</button>
    </div>
    ${frase ? `<div class="frase"><h2 class="vh">In una frase</h2>${frase}</div>` : ''}
    <div class="riassunto">
      ${versoQui.length ? `<div><h2>Prerequisiti</h2><p>${[...new Set(versoQui.map(m => m.da))].map(id => linkLez(id, lezioni)).join(' ')}</p></div>` : ''}
      ${verifica ? `<div><h2>Alla fine saprai rispondere</h2>${verifica}</div>` : ''}
    </div>
  </header>

  <div class="schede" role="tablist" aria-label="Livelli di lettura">
    <button type="button" role="tab" id="tab-spiegazione" aria-controls="vista-spiegazione" aria-selected="true">Spiegazione</button>
    <button type="button" role="tab" id="tab-sorgenti" aria-controls="vista-sorgenti" aria-selected="false" tabindex="-1">Sorgenti originali</button>
    <button type="button" role="tab" id="tab-laboratorio" aria-controls="vista-laboratorio" aria-selected="false" tabindex="-1">Laboratorio</button>
  </div>

  <section class="vista prosa" id="vista-spiegazione" role="tabpanel" aria-labelledby="tab-spiegazione">
    <div class="solo-mobile">${diagramma.replace('id="freccia"', 'id="freccia-m"').replace(/url\(#freccia\)/g, 'url(#freccia-m)')}</div>
    <p class="provenienza"><span class="etichetta">Appunti e riflessioni didattiche</span> sintesi riorganizzata dal percorso del corso.</p>
    <h2 id="appunti">Appunti e riflessioni</h2>
    ${html.spiegazione}
    ${l.parti ? l.parti.map((p, n) => `<section class="parte" id="parte-${p.n}" aria-label="Parte ${p.n}: ${esc(p.titolo)}">
      <p class="provenienza"><span class="etichetta">Fonte originale · parte ${p.n} di ${l.parti.length}</span> <code>~/kubernetesprj/${esc(p.spiegazione.percorso)}</code>, resa come pagina. Comandi: <a href="?vista=laboratorio#passi-${p.n}">laboratorio, parte ${p.n}</a>.</p>
      ${html.parti[n]}
    </section>`).join('') : `<p class="provenienza"><span class="etichetta">Fonte originale</span> <code>${l.radice || '~/kubernetesprj/'}${esc(l.fonti.find(f => f.ruolo === 'lezione').percorso)}</code>, resa come pagina.</p>
    ${html.lezione}`}
    ${approfondimento ? `<section class="approfondimento" id="${approfondimento.id}" aria-label="${esc(approfondimento.titolo)}">
      <p class="provenienza"><span class="etichetta">Approfondimento integrato</span> ${esc(approfondimento.titolo)}: materiale aggiunto al corso, non fa parte del repository del laboratorio. Esempio generico (<code>www.negozio.it</code>, IP di esempio), non il cluster della lezione. <a href="/fonti/${esc(approfondimento.file)}" download>Scarica il testo</a> · <a href="?vista=laboratorio#sim-tls">Prova la simulazione</a> · <a href="#quiz-${esc(approfondimento.quiz)}">Quiz dell'approfondimento</a></p>
      ${approfondimento.html}
    </section>` : ''}
  </section>

  <section class="vista" id="vista-sorgenti" role="tabpanel" aria-labelledby="tab-sorgenti" hidden>
    <p class="provenienza">${l.introFonti || `${l.parti ? `I ${l.fonti.length} file delle ${l.parti.length} parti (spiegazione, script guidato, file di lezione)` : 'I tre file della lezione'} così come sono nel repository. Copiali o scaricali per intero: nessun comando viene eseguito dal sito.`}</p>
    ${fonti}
  </section>

  <section class="vista prosa" id="vista-laboratorio" role="tabpanel" aria-labelledby="tab-laboratorio" hidden>
    <div class="avviso" role="note"><b>Laboratorio:</b> ${AVVISO_LAB[l.id] || `i comandi sono esempi da lanciare a mano sul tuo cluster di prova (contesto <code>lab</code>${l.id === '21' ? ' o <code>lab-haproxy</code>' : ''}).`} Le righe con ⚠ cancellano, svuotano o rompono qualcosa apposta. Le misure citate sono quelle del laboratorio di origine, non verifiche fatte da questo sito.</div>
    ${simulazioni ? `<h2 id="simulazioni">Simulazioni</h2><p class="provenienza"><span class="etichetta">Simulazione concettuale</span> modelli semplificati degli esempi della lezione, calcolati nel browser: non sono misure del cluster.</p>${simulazioni}` : ''}
    <h2 id="passi">${l.titoloPassi || (l.parti ? 'Gli script guidati, parte per parte' : 'Lo script guidato, passo per passo')}</h2>
    ${html.passi}
    ${l.traccia ? `<h2 id="traccia">Traccia per lo studio attivo</h2>${html.traccia}` : ''}
  </section>

  <section class="verifica" aria-labelledby="quiz-titolo">
    <h2 id="quiz-titolo">Autoverifica</h2>
    <div data-quiz="${l.id}"></div>
    <script type="application/json" id="dati-quiz">${JSON.stringify(quiz).replace(/</g, '\\u003c')}</script>
    ${approfondimento ? `<h3 id="quiz-${esc(approfondimento.quiz)}">Quiz dell'approfondimento: haproxy.cfg e TLS</h3>
    <div data-quiz="${esc(approfondimento.quiz)}"></div>
    <script type="application/json" id="dati-quiz-${esc(approfondimento.quiz)}">${JSON.stringify(approfondimento.domande).replace(/</g, '\\u003c')}</script>` : ''}
    ${flashcard.length ? `<h3>Flashcard</h3><div class="flashcard-griglia">${flashcard.map((f, n) => carta(f, `${l.id}-${n}`)).join('')}</div>` : ''}
    <h3><label for="note-${l.id}">Spiega con parole tue</label></h3>
    <textarea id="note-${l.id}" class="note" data-note="${l.id}" rows="5" placeholder="Rispiega la lezione come a un collega: resta salvato solo in questo browser."></textarea>
  </section>

  <nav class="vicine" aria-label="Lezione precedente e successiva">
    ${prima ? `<a href="/lezioni/${prima.id}.html" rel="prev">← ${prima.id} ${esc(prima.breve)}</a>` : '<span></span>'}
    ${dopo ? `<a href="/lezioni/${dopo.id}.html" rel="next">${dopo.id} ${esc(dopo.breve)} →</a>` : '<a href="/">Torna al percorso →</a>'}
  </nav>
</main>
<aside class="laterale" aria-label="Diagramma e indice">
  ${diagramma}
  <details class="indice" open><summary>In questa pagina</summary><ol id="indice-pagina"></ol></details>
  <section class="collegamenti"><h2>Collegamenti</h2>${collegamenti}</section>
</aside>
</div>`;
  return pagina({ titolo: `${l.id} · ${l.titolo} — Corso Kubernetes`, descrizione: l.sommario, corpo, classe: 'p-lezione', lezione: l.id });
}

export function carta(f, id) {
  return `<div class="carta" data-carta="${esc(id)}"><p class="fronte">${esc(f.fronte)}</p><button type="button" class="btn piccolo" aria-expanded="false" aria-controls="retro-${esc(id)}">Mostra risposta</button><p class="retro" id="retro-${esc(id)}" hidden>${esc(f.retro)}</p></div>`;
}

export function paginaHome({ lezioni, mappa }) {
  const voce = l => `<li class="tappa${approf(l) ? ' speciale' : ''}" data-tappa="${l.id}">
      <a href="/lezioni/${l.id}.html"><span class="tappa-num">${l.id}</span><span class="tappa-testo"><b>${esc(l.titolo)}</b><small>${esc(l.sommario)}</small></span><span class="tappa-stato" data-stato-esteso="${l.id}"></span></a></li>`;
  const righe = mappa.map(m => `<tr><th scope="row">${esc(m.concetto)}</th><td>${m.da ? linkLez(m.da, lezioni) : ''}</td><td>${m.verso.map(v => linkLez(v, lezioni)).join(' ')}</td><td>${esc(m.perche)}</td></tr>`).join('');
  const corpo = `${testata()}
<main id="contenuto" class="home" tabindex="-1">
  <section class="home-testa">
    <p class="occhiello">Lezioni 01–09 · approfondimenti 21–24</p>
    <h1>Corso Kubernetes</h1>
    <p>Dall'architettura del cluster a Helm, poi HAProxy come Ingress controller. Ogni lezione ha tre livelli di lettura: la spiegazione, i file originali completi e il laboratorio con le simulazioni.</p>
    <div class="home-progresso"><div class="barra grande" aria-hidden="true"><i data-progresso-barra></i></div><p><span data-progresso-testo>0/13</span> lezioni completate · <a data-riprendi href="/lezioni/01.html">Inizia dalla 01</a></p></div>
    <p class="nota-fonti">Le misure riportate nelle lezioni sono quelle del laboratorio di origine. Il sito non esegue comandi e funziona senza cluster.</p>
  </section>
  <section aria-labelledby="percorso-corso-tit" id="percorso-corso">
    <h2 id="percorso-corso-tit">Il percorso</h2>
    <ol class="metro">${lezioni.filter(l => !approf(l)).map(voce).join('')}</ol>
    <h2 class="approf">Approfondimenti</h2>
    <ol class="metro">${lezioni.filter(approf).map(voce).join('')}</ol>
  </section>
  <section aria-labelledby="mappa-tit">
    <h2 id="mappa-tit">Mappa dei collegamenti</h2>
    <p>I concetti che tornano: se una lezione ti è poco chiara, guarda da dove viene.</p>
    <div class="tabella" tabindex="0"><table><thead><tr><th scope="col">Concetto</th><th scope="col">Nasce in</th><th scope="col">Ritorna in</th><th scope="col">Perché conta</th></tr></thead><tbody>${righe}</tbody></table></div>
  </section>
  <section class="home-strumenti">
    <a href="/glossario.html"><b>Glossario</b><small>Pod, EndpointSlice, stick-table… con le lezioni dove tornano</small></a>
    <a href="/flashcard.html"><b>Flashcard</b><small>domande e risposte brevi per ripassare</small></a>
    <a href="/preferiti.html"><b>Preferiti e note</b><small>quello che hai segnato in questo browser</small></a>
  </section>
</main>`;
  return pagina({ titolo: 'Corso Kubernetes — lezioni 01–09, 21 HAProxy e 22 Terraform', descrizione: 'Corso Kubernetes in italiano: lezioni, sorgenti, laboratori e simulazioni.', corpo, classe: 'p-home' });
}

export function paginaGlossario({ glossario, lezioni }) {
  const voci = [...glossario].sort((a, b) => a.termine.localeCompare(b.termine, 'it')).map(g => `
    <div class="voce" id="${slug(g.termine)}" data-cerca="${esc([g.termine, ...(g.alias || []), g.definizione].join(' ').toLowerCase())}">
      <dt>${esc(g.termine)}${g.alias?.length ? ` <small>(${g.alias.map(esc).join(', ')})</small>` : ''}</dt>
      <dd><p>${esc(g.definizione)}</p><p class="voce-lez">${g.lezioni.map(v => linkLez(v, lezioni)).join(' ')}</p></dd>
    </div>`).join('');
  const corpo = `${testata()}
<main id="contenuto" class="semplice" tabindex="-1">
  <h1>Glossario</h1>
  <label class="filtro"><span>Filtra</span><input type="search" data-filtro=".voce" placeholder="es. readiness" aria-describedby="glossario-conta"></label>
  <p id="glossario-conta" class="conta" aria-live="polite">${glossario.length} voci</p>
  <dl class="glossario">${voci}</dl>
</main>`;
  return pagina({ titolo: 'Glossario — Corso Kubernetes', corpo, classe: 'p-semplice' });
}

export function paginaFlashcard({ flashcard, lezioni }) {
  const gruppi = lezioni.map(l => {
    const fs = flashcard.filter(f => f.lezione === l.id);
    return fs.length ? `<section><h2>${l.id} · ${esc(l.breve)}</h2><div class="flashcard-griglia">${fs.map((f, n) => carta(f, `${l.id}-${n}`)).join('')}</div></section>` : '';
  }).join('');
  const corpo = `${testata()}
<main id="contenuto" class="semplice" tabindex="-1"><h1>Flashcard</h1><p>Prova a rispondere prima di girare la carta. Le carte vengono dalle domande da colloquio e dalle verifiche rapide delle lezioni.</p>${gruppi}</main>`;
  return pagina({ titolo: 'Flashcard — Corso Kubernetes', corpo, classe: 'p-semplice' });
}

export function paginaPreferiti() {
  const corpo = `${testata()}
<main id="contenuto" class="semplice" tabindex="-1"><h1>Preferiti e note</h1>
<p>Tutto è salvato solo in questo browser (localStorage). Puoi esportarlo e reimportarlo su un altro browser.</p>
<div data-preferiti></div>
<div class="azioni"><button type="button" class="btn" data-azione="esporta">Esporta i progressi (JSON)</button>
<label class="btn">Importa<input type="file" accept="application/json" data-azione="importa" class="vh"></label>
<button type="button" class="btn pericolo" data-azione="azzera">Azzera tutto</button></div></main>`;
  return pagina({ titolo: 'Preferiti e note — Corso Kubernetes', corpo, classe: 'p-semplice' });
}
