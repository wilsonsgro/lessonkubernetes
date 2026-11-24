// Multiple-choice self check: explanation after each answer, score kept locally, retry resets the lesson.
import { leggi, aggiorna } from './stato.js';

const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

export function avviaQuiz() {
  document.querySelectorAll('[data-quiz]').forEach((box, n) => {
    const dati = document.getElementById(n === 0 ? 'dati-quiz' : `dati-quiz-${box.dataset.quiz}`);
    if (dati) avviaUno(box, dati);
  });
}

function avviaUno(box, dati) {
  const id = box.dataset.quiz;
  const domande = JSON.parse(dati.textContent);

  const disegna = () => {
    const salvato = leggi().quiz[id] || { risposte: {} };
    box.innerHTML = `<div class="quiz-testa"><p class="punteggio" aria-live="polite"></p><button type="button" class="btn piccolo" data-riprova>Riprova da capo</button></div>` +
      domande.map((q, n) => `<fieldset class="domanda" data-q="${n}">
        <legend>${n + 1}. ${esc(q.domanda)}</legend>
        <p class="tipo"><span class="etichetta ${q.tipo === 'esito-lab' ? 'lab' : ''}">${q.tipo === 'esito-lab' ? 'Esito riportato dal laboratorio di origine · non verificato su questo cluster' : 'Domanda didattica'}</span></p>
        ${q.opzioni.map((o, k) => `<label class="opzione"><input type="radio" name="q-${id}-${n}" value="${k}"> <span>${esc(o)}</span></label>`).join('')}
        <div class="spiega" hidden></div>
      </fieldset>`).join('');
    Object.entries(salvato.risposte).forEach(([n, k]) => rispondi(Number(n), Number(k), false));
    punteggio();
  };

  const rispondi = (n, k, salva = true) => {
    const q = domande[n];
    const fs = box.querySelector(`[data-q="${n}"]`);
    fs.querySelectorAll('input').forEach((inp, i) => {
      inp.disabled = true;
      if (i === k) inp.checked = true;
      const l = inp.closest('.opzione');
      if (i === q.corretta) l.classList.add('giusta');
      else if (i === k) l.classList.add('sbagliata');
    });
    const sp = fs.querySelector('.spiega');
    sp.innerHTML = `<b>${k === q.corretta ? 'Giusto.' : 'Non è questa.'}</b> ${esc(q.spiegazione)}${q.fonte ? `<small>Fonte: ${esc(q.fonte)}</small>` : ''}`;
    sp.hidden = false;
    if (salva) aggiorna(s => { (s.quiz[id] ??= { risposte: {} }).risposte[n] = k; });
    punteggio();
  };

  const punteggio = () => {
    const r = leggi().quiz[id]?.risposte || {};
    const date = Object.keys(r).length;
    const giuste = Object.entries(r).filter(([n, k]) => domande[n]?.corretta === Number(k)).length;
    box.querySelector('.punteggio').textContent = date ? `${giuste}/${domande.length} corrette · ${date}/${domande.length} risposte` : `${domande.length} domande`;
    if (date === domande.length) aggiorna(s => { s.quiz[id].ultimo = giuste; s.quiz[id].migliore = Math.max(giuste, s.quiz[id].migliore || 0); });
  };

  box.addEventListener('change', e => {
    const inp = e.target.closest('input[type="radio"]');
    if (inp) rispondi(Number(inp.closest('[data-q]').dataset.q), Number(inp.value));
  });
  box.addEventListener('click', e => {
    if (!e.target.closest('[data-riprova]')) return;
    aggiorna(s => { if (s.quiz[id]) s.quiz[id].risposte = {}; });
    disegna();
    box.querySelector('input')?.focus();
  });
  disegna();
}

export function avviaCarte() {
  document.addEventListener('click', e => {
    const b = e.target.closest('.carta .btn');
    if (!b) return;
    const retro = document.getElementById(b.getAttribute('aria-controls'));
    const aperta = b.getAttribute('aria-expanded') === 'true';
    retro.hidden = aperta;
    b.setAttribute('aria-expanded', String(!aperta));
    b.textContent = aperta ? 'Mostra risposta' : 'Nascondi risposta';
  });
}
