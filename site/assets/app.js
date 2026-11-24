// Entry point: theme, navigation, tabs, copy buttons, progress, notes, then the feature modules.
import { leggi, aggiorna, esporta, importa, azzera, ORDINE } from './stato.js';
import { avviaRicerca } from './cerca.js';
import { avviaQuiz, avviaCarte } from './quiz.js';
import { avviaTermini } from './termini.js';
import { attivaScorrimento } from './scorri.js';
import { avviaSimulazioni } from './sim-ui.js';

const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const LEZ = document.body.dataset.lezione;

function tema() {
  $('.tema')?.addEventListener('click', () => {
    const t = document.documentElement.dataset.tema === 'scuro' ? 'chiaro' : 'scuro';
    document.documentElement.dataset.tema = t;
    try { localStorage.setItem('k8s-lezioni:tema', t); } catch {}
  });
}

function menu() {
  const b = $('.apri-percorso'), nav = $('#percorso');
  if (!b || !nav) { if (b) b.hidden = true; return; }
  const imposta = aperto => { nav.classList.toggle('aperto', aperto); b.setAttribute('aria-expanded', String(aperto)); };
  b.addEventListener('click', () => imposta(!nav.classList.contains('aperto')));
  document.addEventListener('keydown', e => { if (e.key === 'Escape') imposta(false); });
  nav.addEventListener('click', e => { if (e.target.closest('a')) imposta(false); });
}

function schede() {
  const tabs = $$('[role="tab"]');
  if (!tabs.length) return;
  const mostra = (tab, aggiornaUrl = true) => {
    tabs.forEach(t => {
      const on = t === tab;
      t.setAttribute('aria-selected', String(on));
      t.tabIndex = on ? 0 : -1;
      document.getElementById(t.getAttribute('aria-controls')).hidden = !on;
    });
    const pannello = document.getElementById(tab.getAttribute('aria-controls'));
    attivaScorrimento(pannello);
    if (aggiornaUrl) {
      const u = new URL(location.href);
      u.searchParams.set('vista', tab.id.replace('tab-', ''));
      history.replaceState(null, '', u.pathname + u.search);
    }
  };
  tabs.forEach((t, i) => {
    t.addEventListener('click', () => mostra(t));
    t.addEventListener('keydown', e => {
      const k = { ArrowRight: 1, ArrowLeft: -1 }[e.key];
      if (k) { const n = tabs[(i + k + tabs.length) % tabs.length]; n.focus(); mostra(n); }
      if (e.key === 'Home') { tabs[0].focus(); mostra(tabs[0]); }
      if (e.key === 'End') { tabs.at(-1).focus(); mostra(tabs.at(-1)); }
    });
  });
  const vista = new URLSearchParams(location.search).get('vista');
  mostra(tabs.find(t => t.id === `tab-${vista}`) || tabs[0], false);

  const vaiARiga = () => {
    const m = location.hash.match(/^#f(\d)-L(\d+)$/);
    if (m) {
      mostra(document.getElementById('tab-sorgenti'), false);
      const r = $(`#f${m[1]} .riga[data-n="${m[2]}"]`);
      if (r) { r.classList.add('lampeggia'); r.scrollIntoView({ block: 'center' }); setTimeout(() => r.classList.remove('lampeggia'), 2500); }
      return;
    }
    const bersaglio = location.hash.length > 1 ? document.getElementById(decodeURIComponent(location.hash.slice(1))) : null;
    const pannello = bersaglio?.closest('[role="tabpanel"]');
    if (pannello?.hidden) { mostra(document.getElementById(pannello.getAttribute('aria-labelledby')), false); bersaglio.scrollIntoView(); }
  };
  window.addEventListener('hashchange', vaiARiga);
  vaiARiga();
}

function copia() {
  document.addEventListener('click', async e => {
    const b = e.target.closest('button.copia');
    if (!b) return;
    const testo = b.closest('figure').querySelector('code').textContent;
    try { await navigator.clipboard.writeText(testo); }
    catch {
      const t = Object.assign(document.createElement('textarea'), { value: testo });
      document.body.append(t); t.select(); document.execCommand('copy'); t.remove();
    }
    const prima = b.textContent;
    b.textContent = 'Copiato'; b.classList.add('copiato');
    setTimeout(() => { b.textContent = prima; b.classList.remove('copiato'); }, 1600);
  });
}

function progresso() {
  const disegna = () => {
    const s = leggi();
    const fatte = ORDINE.filter(id => s.completate[id]).length;
    $$('[data-progresso-barra]').forEach(i => { i.style.width = `${(fatte / ORDINE.length) * 100}%`; });
    $$('[data-progresso-testo]').forEach(t => { t.textContent = `${fatte}/${ORDINE.length}`; });
    $$('[data-stato]').forEach(el => { el.toggleAttribute('data-fatto', !!s.completate[el.dataset.stato]); });
    $$('[data-stato-esteso]').forEach(el => {
      const id = el.dataset.statoEsteso, q = s.quiz[id];
      el.textContent = [s.completate[id] ? 'completata' : '', q?.migliore !== undefined ? `quiz ${q.migliore}/8` : '', s.preferite[id] ? '★' : ''].filter(Boolean).join(' · ');
      el.closest('.tappa')?.classList.toggle('fatta', !!s.completate[id]);
    });
    const r = $('[data-riprendi]');
    if (r) {
      const prossima = ORDINE.find(id => !s.completate[id]);
      r.href = `/lezioni/${prossima || '21'}.html`;
      r.textContent = fatte === 0 ? 'Inizia dalla 01' : prossima ? `Riprendi dalla ${prossima}` : 'Corso completato: ripassa la 21';
    }
    if (LEZ) {
      const c = $('[data-azione="completa"]'), p = $('[data-azione="preferita"]');
      if (c) { c.setAttribute('aria-pressed', String(!!s.completate[LEZ])); c.textContent = s.completate[LEZ] ? 'Completata ✓' : 'Segna come completata'; }
      if (p) { p.setAttribute('aria-pressed', String(!!s.preferite[LEZ])); p.textContent = s.preferite[LEZ] ? '★' : '☆'; p.setAttribute('aria-label', s.preferite[LEZ] ? 'Togli dai preferiti' : 'Aggiungi ai preferiti'); }
    }
  };
  document.addEventListener('click', e => {
    const a = e.target.closest('[data-azione]')?.dataset.azione;
    if (a === 'completa') aggiorna(s => { s.completate[LEZ] = !s.completate[LEZ]; if (!s.completate[LEZ]) delete s.completate[LEZ]; });
    if (a === 'preferita') aggiorna(s => { s.preferite[LEZ] = !s.preferite[LEZ]; if (!s.preferite[LEZ]) delete s.preferite[LEZ]; });
    if (a === 'stampa') window.print();
  });
  document.addEventListener('stato:cambiato', disegna);
  window.addEventListener('storage', disegna);
  disegna();
}

function note() {
  $$('[data-note]').forEach(t => {
    const id = t.dataset.note;
    t.value = leggi().note[id] || '';
    let timer;
    t.addEventListener('input', () => { clearTimeout(timer); timer = setTimeout(() => aggiorna(s => { if (t.value.trim()) s.note[id] = t.value; else delete s.note[id]; }), 300); });
  });
}

async function preferiti() {
  const box = $('[data-preferiti]');
  if (!box) return;
  const lezioni = await fetch('/dati/lezioni.json').then(r => r.json());
  const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const disegna = () => {
    const s = leggi();
    const voci = lezioni.filter(l => s.preferite[l.id] || s.note[l.id]);
    box.innerHTML = voci.length
      ? `<ul class="pref-lista">${voci.map(l => `<li><a href="/lezioni/${l.id}.html">${s.preferite[l.id] ? '★ ' : ''}${l.id} · ${esc(l.titolo)}</a>${s.note[l.id] ? `<blockquote>${esc(s.note[l.id])}</blockquote>` : ''}</li>`).join('')}</ul>`
      : '<p>Ancora niente: usa ☆ in una lezione o scrivi nel riquadro «Spiega con parole tue».</p>';
  };
  document.addEventListener('click', e => {
    const a = e.target.closest('[data-azione]')?.dataset.azione;
    if (a === 'esporta') {
      const u = URL.createObjectURL(new Blob([esporta()], { type: 'application/json' }));
      Object.assign(document.createElement('a'), { href: u, download: 'progressi-corso-kubernetes.json' }).click();
      URL.revokeObjectURL(u);
    }
    if (a === 'azzera' && confirm('Cancellare progressi, note, preferiti e quiz salvati in questo browser?')) azzera();
  });
  $('[data-azione="importa"]')?.addEventListener('change', async e => {
    try { importa(await e.target.files[0].text()); alert('Progressi importati.'); } catch (err) { alert(`Import non riuscito: ${err.message}`); }
  });
  document.addEventListener('stato:cambiato', disegna);
  disegna();
}

function filtri() {
  $$('[data-filtro]').forEach(inp => {
    const voci = $$(inp.dataset.filtro);
    const conta = document.getElementById(inp.getAttribute('aria-describedby'));
    const applica = () => {
      const q = inp.value.trim().toLowerCase();
      let n = 0;
      voci.forEach(v => { const ok = !q || v.dataset.cerca.includes(q); v.hidden = !ok; n += ok; });
      if (conta) conta.textContent = `${n} voci`;
    };
    inp.addEventListener('input', applica);
  });
}

tema(); menu(); copia(); progresso(); note(); filtri(); avviaCarte(); avviaRicerca(); avviaQuiz();
schede(); avviaSimulazioni(); preferiti(); avviaTermini();
