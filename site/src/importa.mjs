// Deterministic import of content/corso.md into lesson data: fence-aware, source blocks copied byte for byte.
export const ORDINE = ['01', '02', '03', '04', '05', '06', '07', '08', '09', '21'];

const ANCORA = /^<a id="lezione-(\d\d)"><\/a>\s*$/;
const APRE = /^(`{3,}|~{3,})(.*)$/;

function blocchiDiPrimoLivello(righe, base = 0) {
  const sezioni = [];
  let corrente = { titolo: null, righe: [] };
  let fence = null;
  righe.forEach((r, i) => {
    if (fence) {
      const c = r.match(/^(`+|~+)\s*$/);
      if (c && c[1][0] === fence[0] && c[1].length >= fence.length) fence = null;
    } else {
      const m = r.match(APRE);
      if (m) fence = m[1];
      else if (r.startsWith('## ')) {
        sezioni.push(corrente);
        corrente = { titolo: r.slice(3).trim(), righe: [], riga: base + i + 1 };
        return;
      }
    }
    corrente.righe.push(r);
  });
  if (fence) throw new Error(`fence ${fence} non chiuso (dalla riga ${base + 1})`);
  sezioni.push(corrente);
  return sezioni;
}

function ruoloDi(nome, testo) {
  if (nome.endsWith('.md')) return 'lezione';
  if (nome.endsWith('.sh') && /^passo /m.test(testo)) return 'passi';
  return 'manifest';
}

function fonti(righe, id) {
  const out = [];
  for (let i = 0; i < righe.length; i++) {
    const m = righe[i].match(/^### Fonte originale: `(.+)`\s*$/);
    if (!m) continue;
    let j = i + 1;
    while (j < righe.length && !/^`{4,}/.test(righe[j])) {
      if (righe[j].startsWith('### ')) throw new Error(`lezione ${id}: ${m[1]} senza blocco sorgente`);
      j++;
    }
    if (j >= righe.length) throw new Error(`lezione ${id}: ${m[1]} senza blocco sorgente`);
    const fence = righe[j].match(/^`+/)[0];
    const lingua = righe[j].slice(fence.length).trim() || 'text';
    let k = j + 1;
    while (k < righe.length && righe[k] !== fence) {
      if (/^### Fonte originale: /.test(righe[k])) break;
      k++;
    }
    if (k >= righe.length || righe[k] !== fence) throw new Error(`lezione ${id}: fence di ${m[1]} non chiuso`);
    const testo = righe.slice(j + 1, k).join('\n') + '\n';
    const nome = m[1].replace(/\(\d+\)(?=\.\w+$)/, '');
    const ruolo = ruoloDi(nome, testo);
    const percorso = ruolo === 'passi' ? `kubernetes/${nome}` : `lezioni/kubernetes/${nome}`;
    out.push({ nome, percorso, lingua: lingua === 'sh' ? 'bash' : lingua, ruolo, testo, righe: k - j - 1 });
    i = k;
  }
  return out;
}

function mappa(righe) {
  const out = [];
  let dentro = false;
  for (const r of righe) {
    if (r.startsWith('## ')) dentro = /^## Mappa dei collegamenti/.test(r);
    if (!dentro || !r.startsWith('|') || /^\|\s*-|Concetto di origine/.test(r)) continue;
    const [concetto, verso, perche] = r.split('|').slice(1, -1).map(c => c.trim());
    const m = concetto.match(/^(.*?)\s*\((\d\d)\)$/);
    out.push({ concetto: m ? m[1] : concetto, da: m ? m[2] : null, verso: verso.split(/,\s*/), perche });
  }
  return out;
}

function indice(righe) {
  const out = {};
  for (const r of righe) {
    const m = r.match(/^\d+\.\s+\*\*(\d\d)\s*[—-]\s*(.+?):\*\*\s*(.+)$/);
    if (m) out[m[1]] = { breve: m[2].trim(), sommario: m[3].trim() };
  }
  return out;
}

export function sezioneMd(md, re) {
  const righe = md.split('\n');
  const out = [];
  let dentro = false, fence = null, livello = 0;
  for (const r of righe) {
    const f = r.match(/^(`{3,}|~{3,})/);
    if (fence) { if (f && f[1][0] === fence[0] && f[1].length >= fence.length && !r.slice(f[1].length).trim()) fence = null; if (dentro) out.push(r); continue; }
    if (f) { fence = f[1]; if (dentro) out.push(r); continue; }
    const h = r.match(/^(#{1,6}) (.*)$/);
    if (h) {
      if (dentro && h[1].length <= livello) break;
      if (!dentro && re.test(h[2])) { dentro = true; livello = h[1].length; continue; }
    }
    if (dentro) out.push(r);
  }
  return dentro ? out.join('\n').trim() : '';
}

function testo(righe) {
  return righe.join('\n').replace(/\n-{3,}\s*$/, '').trim() + '\n';
}

export function importa(md) {
  const righe = md.replace(/\r\n/g, '\n').split('\n');
  const inizi = [];
  righe.forEach((r, i) => { const m = r.match(ANCORA); if (m) inizi.push({ id: m[1], i }); });
  const testa = righe.slice(0, inizi.length ? inizi[0].i : righe.length);
  const lezioni = inizi.map(({ id, i }, n) => {
    const fine = n + 1 < inizi.length ? inizi[n + 1].i : righe.length;
    const corpo = righe.slice(i + 1, fine);
    const h1 = corpo.find(r => r.startsWith('# '));
    if (!h1) throw new Error(`lezione ${id} senza titolo`);
    const titolo = h1.replace(/^# Lezione \d\d\s*[—-]\s*/, '').trim();
    const sez = blocchiDiPrimoLivello(corpo, i + 1);
    const trova = re => sez.find(s => s.titolo && re.test(s.titolo));
    const spieg = trova(/^Spiegazione/);
    const mat = trova(/^Materiale originale/);
    const trac = trova(/^Traccia/);
    if (!spieg || !mat) throw new Error(`lezione ${id}: manca Spiegazione o Materiale originale`);
    return {
      id, titolo,
      spiegazione: testo(spieg.righe),
      fonti: fonti(mat.righe, id),
      traccia: trac ? testo(trac.righe) : '',
    };
  });
  const idx = indice(testa);
  lezioni.forEach(l => Object.assign(l, idx[l.id] || { breve: l.titolo, sommario: '' }));
  return { mappa: mappa(testa), lezioni };
}
