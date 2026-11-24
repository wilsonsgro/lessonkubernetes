// Full-text search over lessons, notes, sources, quiz and glossary: every word must match, titles weigh more.
const norm = s => s.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
const esc = s => s.replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

export function cerca(indice, query, max = 20) {
  const parole = norm(query).split(/\s+/).filter(p => p.length > 1);
  if (!parole.length) return [];
  const out = [];
  for (const v of indice) {
    const t = v._t ??= norm(v.t), x = v._x ??= norm(v.x);
    let punti = 0;
    for (const p of parole) {
      const inT = t.includes(p), inX = x.includes(p);
      if (!inT && !inX) { punti = -1; break; }
      punti += (inT ? 10 : 0) + (inX ? 1 : 0);
    }
    if (punti > 0) out.push({ v, punti: punti - (v.s ? 2 : 0) });
  }
  return out.sort((a, b) => b.punti - a.punti).slice(0, max).map(r => ({ ...r.v, estratto: estratto(r.v.x, parole) }));
}

function estratto(testo, parole) {
  const n = norm(testo);
  const i = Math.max(0, Math.min(...parole.map(p => { const k = n.indexOf(p); return k < 0 ? Infinity : k; })) - 50);
  let s = esc(testo.slice(i, i + 170).replace(/\s+/g, ' '));
  for (const p of parole) s = s.replace(new RegExp(`(${p.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')})`, 'gi'), '<mark>$1</mark>');
  return (i ? '…' : '') + s + '…';
}

export function avviaRicerca() {
  const campo = document.getElementById('cerca-campo');
  const lista = document.getElementById('cerca-risultati');
  if (!campo) return;
  let indice = null, sel = -1, timer;
  const carica = async () => { indice ??= await fetch('/dati/cerca.json').then(r => r.json()); return indice; };
  const chiudi = () => { lista.hidden = true; campo.setAttribute('aria-expanded', 'false'); sel = -1; };
  const mostra = async () => {
    const q = campo.value.trim();
    if (q.length < 2) return chiudi();
    const ris = cerca(await carica(), q);
    lista.innerHTML = ris.length
      ? ris.map((r, i) => `<li role="option" id="ris-${i}" aria-selected="false"><a href="${r.u}"><span class="r-t"><span class="r-l">${r.l === 'G' ? 'GL' : r.l}</span>${esc(r.t)}</span><span class="r-x">${r.estratto}</span></a></li>`).join('')
      : `<li class="vuoto" role="option" aria-disabled="true">Nessun risultato per «${esc(q)}»: prova una parola sola.</li>`;
    lista.hidden = false; campo.setAttribute('aria-expanded', 'true'); sel = -1;
  };
  const evidenzia = i => {
    const voci = [...lista.querySelectorAll('li[id]')];
    if (!voci.length) return;
    sel = (i + voci.length) % voci.length;
    voci.forEach((v, k) => v.setAttribute('aria-selected', String(k === sel)));
    campo.setAttribute('aria-activedescendant', voci[sel].id);
    voci[sel].scrollIntoView({ block: 'nearest' });
  };
  campo.addEventListener('focus', carica, { once: true });
  campo.addEventListener('input', () => { clearTimeout(timer); timer = setTimeout(mostra, 120); });
  campo.addEventListener('keydown', e => {
    if (e.key === 'ArrowDown') { e.preventDefault(); evidenzia(sel + 1); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); evidenzia(sel - 1); }
    else if (e.key === 'Enter' && sel >= 0) { e.preventDefault(); lista.querySelectorAll('li[id] a')[sel].click(); }
    else if (e.key === 'Escape') { chiudi(); campo.blur(); }
  });
  document.addEventListener('click', e => { if (!e.target.closest('.cerca')) chiudi(); });
  document.addEventListener('keydown', e => {
    if (e.key === '/' && !e.target.closest('input, textarea, select')) { e.preventDefault(); campo.focus(); }
  });
}
