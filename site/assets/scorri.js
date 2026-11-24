// Scroll-linked diagram and page index: the heading being read decides which nodes light up (in every copy of the diagram).
let staccaPrecedente = null;

export function attivaScorrimento(pannello) {
  const figure = [...document.querySelectorAll('.diagramma')];
  const indice = document.getElementById('indice-pagina');
  staccaPrecedente?.();
  const titoli = [...pannello.querySelectorAll('h2[id], h3[id]')];
  if (indice) {
    indice.innerHTML = titoli.map(h => `<li class="${h.tagName.toLowerCase()}"><a href="#${h.id}">${h.textContent.replace(/</g, '&lt;')}</a></li>`).join('');
  }
  const passi = figure.length ? JSON.parse(figure[0].dataset.passi).map(p => ({ ...p, re: new RegExp(p.re, p.f) })) : [];
  let ultimo = null;

  const accendi = h => {
    if (indice) indice.querySelectorAll('a').forEach(a => a.setAttribute('aria-current', String(a.getAttribute('href') === `#${h.id}`)));
    const p = passi.find(x => x.re.test(h.textContent));
    if (!p || p === ultimo) return;
    ultimo = p;
    const chiavi = p.k.split(' ');
    for (const fig of figure) {
      fig.querySelectorAll('[data-k]').forEach(el => el.classList.toggle('acceso', el.dataset.k.split(' ').some(k => chiavi.includes(k))));
      fig.querySelector('.diagramma-passo').textContent = p.didascalia;
    }
  };

  let attesa = false;
  const calcola = () => {
    attesa = false;
    const soglia = innerHeight * 0.35;
    let corrente = null;
    for (const h of titoli) { if (h.getBoundingClientRect().top <= soglia) corrente = h; else break; }
    if (corrente) accendi(corrente);
  };
  const suScroll = () => { if (!attesa) { attesa = true; requestAnimationFrame(calcola); } };
  addEventListener('scroll', suScroll, { passive: true });
  addEventListener('resize', suScroll);
  staccaPrecedente = () => { removeEventListener('scroll', suScroll); removeEventListener('resize', suScroll); };
  calcola();
}
