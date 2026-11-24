// Contextual links: first mention of each glossary term in the visible prose opens a popover with the lessons where it returns.
const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const slug = t => t.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
const SALTA = 'code, pre, a, h1, h2, h3, h4, h5, h6, button, label, legend, .termine, figure, .etichetta, table thead';

export async function avviaTermini() {
  const zone = [...document.querySelectorAll('#vista-spiegazione, #vista-laboratorio')];
  if (!zone.length) return;
  const glossario = await fetch('/dati/glossario.json').then(r => r.json()).catch(() => []);
  const lezioni = await fetch('/dati/lezioni.json').then(r => r.json()).catch(() => []);
  const qui = document.body.dataset.lezione;
  const voci = glossario.filter(g => (!g.soloLezioni || g.lezioni.includes(qui)) && !(g.tranneLezioni || []).includes(qui)).flatMap(g => [g.termine, ...(g.alias || [])].filter(n => n.length > 2).map(n => ({ n, g })))
    .sort((a, b) => b.n.length - a.n.length);
  const re = new RegExp(`(?<![\\w/-])(${voci.map(v => v.n.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|')})(?![\\w/-])`, 'i');
  const perNome = new Map(voci.map(v => [v.n.toLowerCase(), v.g]));

  for (const zona of zone) {
    const visti = new Set();
    const w = document.createTreeWalker(zona, NodeFilter.SHOW_TEXT, { acceptNode: n => n.parentElement.closest(SALTA) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT });
    const nodi = [];
    while (w.nextNode()) nodi.push(w.currentNode);
    for (const nodo of nodi) {
      const m = nodo.nodeValue.match(re);
      if (!m) continue;
      const g = perNome.get(m[1].toLowerCase());
      if (!g || visti.has(g.termine)) continue;
      const corto = m[1].length <= 4 && m[1] !== m[1].toUpperCase() && m[1] !== g.termine;
      if (corto) continue;
      visti.add(g.termine);
      const dopo = nodo.splitText(m.index);
      dopo.nodeValue = dopo.nodeValue.slice(m[1].length);
      const b = document.createElement('button');
      b.type = 'button'; b.className = 'termine'; b.textContent = m[1]; b.dataset.termine = g.termine;
      b.setAttribute('aria-haspopup', 'dialog');
      dopo.parentNode.insertBefore(b, dopo);
    }
  }

  const pop = document.getElementById('popover-termine');
  let origine = null;
  const chiudi = () => { pop.hidden = true; origine?.focus(); origine = null; };
  document.addEventListener('click', e => {
    const b = e.target.closest('.termine');
    if (!b) { if (!e.target.closest('#popover-termine')) pop.hidden = true; return; }
    const g = glossario.find(x => x.termine === b.dataset.termine);
    const altre = g.lezioni.filter(l => l !== qui);
    const nome = id => lezioni.find(l => l.id === id)?.breve || '';
    pop.innerHTML = `<button type="button" class="chiudi" aria-label="Chiudi">×</button><h2 id="popover-titolo">${esc(g.termine)}</h2><p>${esc(g.definizione)}</p>
      ${altre.length ? `<p>${altre.map(l => `<a class="chip" href="/lezioni/${l}.html">${l} ${esc(nome(l))}</a>`).join(' ')}</p>` : ''}<p><a href="/glossario.html#${slug(g.termine)}">Nel glossario →</a></p>`;
    const r = b.getBoundingClientRect();
    pop.hidden = false;
    pop.style.top = `${window.scrollY + r.bottom + 6}px`;
    pop.style.left = `${Math.max(8, Math.min(window.scrollX + r.left, window.scrollX + document.documentElement.clientWidth - pop.offsetWidth - 8))}px`;
    origine = b;
    pop.querySelector('.chiudi').focus();
  });
  pop.addEventListener('click', e => { if (e.target.closest('.chiudi')) chiudi(); });
  document.addEventListener('keydown', e => { if (e.key === 'Escape' && !pop.hidden) chiudi(); });
}
