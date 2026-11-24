// Markdown to HTML for lesson prose: stable heading ids, highlighted code blocks, raw HTML escaped except a small allowlist.
import { Marked } from 'marked';
import { evidenzia } from './evidenzia.mjs';

export const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

export function slug(t) {
  return t.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .replace(/<[^>]+>/g, '').replace(/&[a-z]+;/g, '').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'sezione';
}

const HTML_OK = /^<\/?(a|br|kbd|sub|sup|details|summary)(\s[^>]*)?\/?>$/i;

export function bloccoCodice({ codice, lingua, nome, download, id, riga0 = '' }) {
  const e = evidenzia(codice, lingua);
  const nomi = Object.entries(e.pericoli);
  const avviso = nomi.length
    ? `<p class="avviso-codice" role="note"><span aria-hidden="true">⚠</span> Contiene comandi che modificano o cancellano risorse (${nomi.map(([n, c]) => `${esc(n)} ×${c}`).join(', ')}). Sono esempi da copiare a mano: il sito non esegue nulla.</p>`
    : '';
  const testa = `<figcaption>${nome ? `<span class="codice-nome">${esc(nome)}</span>` : ''}<span class="codice-lingua">${esc(e.lingua)}</span><span class="codice-azioni"><button type="button" class="copia" aria-label="Copia ${esc(nome || 'il blocco')} negli appunti">Copia</button>${download ? `<a class="scarica" href="${esc(download)}" download aria-label="Scarica ${esc(nome)}">Scarica</a>` : ''}</span></figcaption>`;
  return `<figure class="codice"${id ? ` id="${esc(id)}"` : ''} data-lingua="${e.lingua}"${riga0}>${testa}${avviso}<pre tabindex="0"><code class="hljs">${e.html}</code></pre></figure>`;
}

export function creaMarkdown() {
  const usati = new Map();
  const titoli = [];
  let sposta = 0;
  const m = new Marked({ gfm: true });
  m.use({
    walkTokens(t) { if (t.type === 'heading') t.depth = Math.min(6, t.depth + sposta); },
    renderer: {
      heading({ tokens, depth, text }) {
        const inner = this.parser.parseInline(tokens);
        let id = slug(text);
        const n = usati.get(id) || 0;
        usati.set(id, n + 1);
        if (n) id = `${id}-${n + 1}`;
        titoli.push({ livello: depth, id, testo: inner.replace(/<[^>]+>/g, '') });
        return `<h${depth} id="${id}">${inner}</h${depth}>\n`;
      },
      code({ text, lang }) {
        return bloccoCodice({ codice: text, lingua: (lang || '').split(/\s/)[0] });
      },
      html({ text }) {
        return HTML_OK.test(text.trim()) ? text : esc(text);
      },
    },
  });
  return {
    rendi(md, { spostaTitoli = 0 } = {}) {
      sposta = spostaTitoli;
      return m.parse(md).replace(/<table>/g, '<div class="tabella" tabindex="0"><table>').replace(/<\/table>/g, '</table></div>');
    },
    titoli,
  };
}
