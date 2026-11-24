// Server-side highlighting split into numbered lines, with a warning flag on commands that change or destroy cluster state.
import hljs from 'highlight.js/lib/core';
import yaml from 'highlight.js/lib/languages/yaml';
import bash from 'highlight.js/lib/languages/bash';
import json from 'highlight.js/lib/languages/json';
import markdown from 'highlight.js/lib/languages/markdown';
import plaintext from 'highlight.js/lib/languages/plaintext';
import ini from 'highlight.js/lib/languages/ini';
import nginx from 'highlight.js/lib/languages/nginx';
import dockerfile from 'highlight.js/lib/languages/dockerfile';

function haproxy(h) {
  return {
    name: 'HAProxy',
    aliases: ['haproxy.cfg', 'cfg'],
    case_insensitive: false,
    contains: [
      h.HASH_COMMENT_MODE,
      { className: 'section', begin: /^\s*(global|defaults|frontend|backend|listen|peers|resolvers|userlist|program|cache)\b/, relevance: 10 },
      { className: 'keyword', begin: /^\s*(bind|mode|balance|server|server-template|default_backend|use_backend|acl|http-request|http-response|tcp-request|tcp-response|option|timeout|stick-table|stick|maxconn|log|stats|retries|errorfile|http-check|default-server|filter|capture|redirect)\b/ },
      { className: 'built_in', begin: /\b(roundrobin|leastconn|source|uri|first|check|inter|fall|rise|backup|disabled|deny|allow|track-sc[0-2]|set-header|set-path|replace-path|if|unless)\b/ },
      { className: 'string', begin: /"/, end: /"/ },
      { className: 'number', begin: /\b\d+(\.\d+){3}(:\d+)?\b|\b\d+(ms|s|m|h|d|k)?\b/ },
      { className: 'variable', begin: /\{[^}]*\}/ },
    ],
  };
}

hljs.registerLanguage('yaml', yaml);
hljs.registerLanguage('bash', bash);
hljs.registerLanguage('json', json);
hljs.registerLanguage('markdown', markdown);
hljs.registerLanguage('plaintext', plaintext);
hljs.registerLanguage('ini', ini);
hljs.registerLanguage('nginx', nginx);
hljs.registerLanguage('dockerfile', dockerfile);
hljs.registerLanguage('haproxy', haproxy);
hljs.registerLanguage('hcl', hcl);

const ALIAS = { sh: 'bash', shell: 'bash', console: 'bash', zsh: 'bash', yml: 'yaml', md: 'markdown', text: 'plaintext', txt: 'plaintext', '': 'plaintext', cfg: 'haproxy', tf: 'hcl', terraform: 'hcl', tftest: 'hcl' };

export const PERICOLI = [
  [/\bkubectl\b[^\n#]*\bdelete\b/, 'delete'],
  [/\bkubectl\b[^\n#]*\bdrain\b/, 'drain'],
  [/\bkubectl\b[^\n#]*\btaint\b/, 'taint'],
  [/\bkubectl\b[^\n#]*\bcordon\b/, 'cordon'],
  [/--force\b/, '--force'],
  [/\brollout\s+restart\b/, 'rollout restart'],
  [/\bhelm\s+(uninstall|delete)\b/, 'helm uninstall'],
  [/\bminikube\b[^\n#]*\bdelete\b/, 'minikube delete'],
  [/\bterraform\s+destroy\b/, 'terraform destroy'],
  [/\bterraform\b[^\n#]*\s-replace=/, 'terraform -replace'],
  [/\bterraform\s+state\s+rm\b/, 'terraform state rm'],
  [/\bterraform\s+force-unlock\b/, 'terraform force-unlock'],
  [/\brm\s+-[a-z]*r[a-z]*f?\b/, 'rm -r'],
  [/\bdocker\s+(rm|rmi|system\s+prune|volume\s+rm)\b/, 'docker rm'],
  [/\bdeploy\.sh\s+distruggi\b/, 'deploy.sh distruggi'],
];

export function pericoliDi(riga) {
  if (/^\s*#/.test(riga)) return [];
  return PERICOLI.filter(([re]) => re.test(riga)).map(([, nome]) => nome);
}

function hcl(h) {
  const interpolazione = { className: 'subst', begin: /\$\{/, end: /\}/ };
  return {
    name: 'HCL',
    aliases: ['tf', 'terraform', 'tftest'],
    contains: [
      h.HASH_COMMENT_MODE,
      h.C_LINE_COMMENT_MODE,
      h.C_BLOCK_COMMENT_MODE,
      { className: 'keyword', begin: /^\s*(terraform|provider|resource|data|variable|output|locals|module|moved|import|removed|check|run|mock_provider|lifecycle|backend|required_providers|dynamic|precondition|postcondition|validation|assert|ephemeral)\b/ },
      { className: 'literal', begin: /\b(true|false|null)\b/ },
      { className: 'built_in', begin: /\b(for_each|count|depends_on|each|self|var|local|module|for|in|if)\b/ },
      { className: 'string', begin: /<<-?\s*([A-Z_]+)\s*$/, end: /^\s*[A-Z_]+\s*$/ },
      { className: 'string', begin: /"/, end: /"/, contains: [h.BACKSLASH_ESCAPE, interpolazione] },
      { className: 'number', begin: /\b\d+(\.\d+)?\b/ },
      { className: 'attr', begin: /\b[a-z_][a-z0-9_-]*(?=\s*=[^=>])/ },
    ],
  };
}

export function linguaggio(l) {
  const k = (l || '').toLowerCase().trim();
  const n = ALIAS[k] ?? k;
  return hljs.getLanguage(n) ? n : 'plaintext';
}

function dividiRighe(html) {
  const righe = [];
  const aperti = [];
  let cur = '';
  const re = /(<span[^>]*>)|(<\/span>)|(\n)|([^<\n]+|<)/g;
  let m;
  while ((m = re.exec(html))) {
    if (m[1]) { aperti.push(m[1]); cur += m[1]; }
    else if (m[2]) { aperti.pop(); cur += m[2]; }
    else if (m[3]) { righe.push(cur + '</span>'.repeat(aperti.length)); cur = aperti.join(''); }
    else cur += m[4];
  }
  righe.push(cur + '</span>'.repeat(aperti.length));
  return righe;
}

export function evidenzia(codice, lingua) {
  const testo = codice.replace(/\n$/, '');
  const lang = linguaggio(lingua);
  const html = hljs.highlight(testo, { language: lang, ignoreIllegals: true }).value;
  const grezze = testo.split('\n');
  const conteggio = {};
  const righe = dividiRighe(html).map((h, i) => {
    const p = lang === 'bash' || lang === 'plaintext' || lang === 'yaml' || lang === 'markdown' ? pericoliDi(grezze[i] ?? '') : [];
    p.forEach(n => { conteggio[n] = (conteggio[n] || 0) + 1; });
    const attr = p.length ? ` class="riga pericolo" title="Attenzione: ${p.join(', ')}"` : ' class="riga"';
    return `<span${attr} data-n="${i + 1}">${h || ' '}</span>`;
  });
  return { html: righe.join('\n'), lingua: lang, pericoli: conteggio, righe: grezze.length };
}
