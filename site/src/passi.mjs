// Reads the guided runner scripts (`passo "why" 'cmd'`, `nota`, `titolo`, `cartella`) as data; shell quoting is undone exactly as bash would print it.
function parola(s, i) {
  let out = '';
  while (i < s.length) {
    const c = s[i];
    if (c === "'") {
      const j = s.indexOf("'", i + 1);
      if (j < 0) throw new Error('apice singolo non chiuso');
      out += s.slice(i + 1, j); i = j + 1;
    } else if (c === '"') {
      i++;
      while (i < s.length && s[i] !== '"') {
        if (s[i] === '\\' && '$`"\\\n'.includes(s[i + 1])) { if (s[i + 1] !== '\n') out += s[i + 1]; i += 2; }
        else out += s[i++];
      }
      if (i >= s.length) throw new Error('virgolette non chiuse');
      i++;
    } else if (c === '\\' && s[i + 1] === '\n') { return { out, i: i + 2 }; }
    else if (c === ' ' || c === '\t' || c === '\n' || c === ';') return { out, i };
    else { out += c; i++; }
  }
  return { out, i };
}

function argomenti(s, i) {
  const args = [];
  while (i < s.length) {
    while (s[i] === ' ' || s[i] === '\t') i++;
    if (s[i] === '\\' && s[i + 1] === '\n') { i += 2; continue; }
    if (s[i] === '\n' || s[i] === ';' || s[i] === '#' || i >= s.length) break;
    const p = parola(s, i);
    args.push(p.out); i = p.i;
  }
  return { args, i };
}

export function leggiPassi(script) {
  const voci = [];
  const re = /^(passo|nota|titolo|cartella)[ \t]/gm;
  let m;
  while ((m = re.exec(script))) {
    const { args, i } = argomenti(script, m.index + m[1].length);
    re.lastIndex = i;
    if (m[1] === 'passo') voci.push({ tipo: 'passo', n: voci.filter(v => v.tipo === 'passo').length + 1, perche: args[0] ?? '', comando: args[1] ?? '' });
    else voci.push({ tipo: m[1], testo: args.join('\n') });
  }
  return voci;
}
