// Pure logic of the local simulations: concept models of the course examples, not cluster measurements.
export function hpa({ attuali, valore, target, min, max }) {
  const grezzo = (attuali * valore) / target;
  const formula = Math.ceil(grezzo);
  const desiderate = Math.min(max, Math.max(min, formula));
  const limitatoDa = formula > max ? 'maxReplicas' : formula < min ? 'minReplicas' : null;
  return { grezzo, formula, desiderate, limitatoDa };
}

export const RBAC_LEZIONE_07 = {
  role: {
    nome: 'deployer', namespace: 'lab-sicuro',
    regole: [
      { gruppi: [''], risorse: ['pods', 'pods/log', 'services', 'configmaps'], verbi: ['get', 'list', 'watch'] },
      { gruppi: ['apps'], risorse: ['deployments'], verbi: ['get', 'list', 'watch', 'create', 'update', 'patch'] },
      { gruppi: ['apps'], risorse: ['deployments/scale'], verbi: ['patch'] },
    ],
  },
  binding: { nome: 'deployer', namespace: 'lab-sicuro', soggetti: ['system:serviceaccount:lab-sicuro:deployer'] },
};

export function rbac({ role, binding }, { soggetto, verbo, risorsa, gruppo, namespace }) {
  if (!binding.soggetti.includes(soggetto)) return { permesso: false, motivo: `Nessun binding lega ${soggetto} al Role ${role.nome}: RBAC nega per default.` };
  if (namespace !== binding.namespace) return { permesso: false, motivo: `Il RoleBinding vive in ${binding.namespace}: in ${namespace} non dà niente.` };
  const i = role.regole.findIndex(r => r.gruppi.includes(gruppo) && r.risorse.includes(risorsa) && r.verbi.includes(verbo));
  if (i < 0) return { permesso: false, motivo: `Nessuna regola del Role ${role.nome} copre ${verbo} su ${gruppo || 'core'}/${risorsa}: RBAC è solo additivo, non esiste un «deny».` };
  return { permesso: true, regola: i, motivo: `Regola ${i + 1} del Role ${role.nome}: ${verbo} su ${gruppo || 'core'}/${risorsa}.` };
}

const NS_POLICY = 'lab';
const haLabel = (l, k, v) => l && l[k] === v;

export function netpol(forma, { namespace, labels }) {
  const pod = haLabel(labels, 'ruolo', 'client');
  const ns = namespace === 'ingress-nginx';
  if (forma === 'OR') {
    const daPod = pod && namespace === NS_POLICY;
    const ammesso = daPod || ns;
    const motivo = daPod ? 'Elemento 1: Pod ruolo=client nello stesso namespace della policy.'
      : ns ? 'Elemento 2: qualunque Pod del namespace ingress-nginx.'
      : pod ? 'ruolo=client, ma un podSelector da solo guarda solo il namespace della policy (lab).'
      : 'Nessun elemento combacia: vince la default-deny-ingress.';
    return { ammesso, motivo };
  }
  const ammesso = pod && ns;
  return { ammesso, motivo: ammesso ? 'Unico elemento, due condizioni vere: Pod ruolo=client DENTRO ingress-nginx.' : 'Unico elemento: servono entrambe le condizioni insieme (AND).' };
}

export function partition(repliche, soglia) {
  const pod = Array.from({ length: repliche }, (_, i) => ({ nome: `db-${i}`, revisione: i >= soglia ? 'nuova' : 'vecchia' }));
  const ordine = pod.filter(p => p.revisione === 'nuova').map(p => p.nome).reverse();
  return { pod, ordine };
}

export function helm(operazioni) {
  const storia = [];
  const aggiungi = (valori, stato, descrizione) => {
    storia.forEach(r => { if (r.stato === 'deployed') r.stato = 'superseded'; });
    storia.push({ revisione: storia.length + 1, valori, stato, descrizione });
  };
  for (const o of operazioni) {
    if (o.op !== 'install' && !storia.length) throw new Error('serve prima un install');
    if (o.op === 'install' && storia.length) throw new Error('release già installata: usa upgrade');
    if (o.op === 'install') aggiungi(o.valori, 'deployed', 'Install complete');
    else if (o.op === 'upgrade') aggiungi(o.valori, 'deployed', 'Upgrade complete');
    else if (o.op === 'upgrade-fallito') {
      const buona = [...storia].reverse().find(r => r.stato === 'deployed');
      storia.push({ revisione: storia.length + 1, valori: o.valori, stato: 'failed', descrizione: 'Upgrade failed' });
      if (o.rollbackOnFailure && buona) aggiungi(buona.valori, 'deployed', `Rollback to ${buona.revisione}`);
    } else if (o.op === 'rollback') {
      const r = storia.find(x => x.revisione === o.a);
      if (!r) throw new Error(`revisione ${o.a} inesistente`);
      aggiungi(r.valori, 'deployed', `Rollback to ${o.a}`);
    } else throw new Error(`operazione sconosciuta ${o.op}`);
  }
  return storia;
}

export function bilancia(algoritmo, richieste, nServer) {
  const fine = Array.from({ length: nServer }, () => []);
  let turno = 0;
  return richieste.map((r, t) => {
    fine.forEach((f, s) => { fine[s] = f.filter(x => x > t); });
    let s;
    if (algoritmo === 'leastconn') {
      const attive = fine.map(f => f.length);
      s = attive.indexOf(Math.min(...attive));
    } else {
      s = turno % nServer; turno++;
    }
    fine[s].push(t + r.durata);
    return { richiesta: t + 1, server: s, attive: fine.map(f => f.length) };
  });
}

export function rateLimit({ richieste, limite, repliche }) {
  const perReplica = Array.from({ length: repliche }, (_, i) => ({ replica: String.fromCharCode(65 + i), viste: 0, passate: 0 }));
  const esiti = [];
  for (let i = 0; i < richieste; i++) {
    const r = perReplica[i % repliche];
    r.viste++;
    const ok = r.viste <= limite;
    if (ok) r.passate++;
    esiti.push({ richiesta: i + 1, replica: r.replica, codice: ok ? 200 : 429 });
  }
  return { passate: esiti.filter(e => e.codice === 200).length, perReplica, esiti };
}

export function failover(n, pronte) {
  const vive = Object.keys(pronte).filter(k => pronte[k]);
  return Array.from({ length: n }, (_, i) => (vive.length ? vive[i % vive.length] : null));
}

export function tlsInstrada({ frontend, porta, sni, host, path }) {
  if (Number(porta) === 80) return { frontend: 'fe_http', backend: null, decifra: false, vede: { sni: false, host: true, path: true, header: true }, esito: 'http-request redirect scheme https code 301', regola: 'fe_http' };
  const ugualeI = (a, b) => String(a || '').toLowerCase() === b;
  if (frontend === 'fe_passthrough') {
    const pay = ugualeI(sni, 'pagamenti.negozio.it');
    return {
      frontend, backend: pay ? 'be_pagamenti' : 'be_web_tls', modalita: 'passthrough', decifra: false,
      vede: { sni: true, host: false, path: false, header: false },
      regola: pay ? 'use_backend be_pagamenti if { req_ssl_sni -i pagamenti.negozio.it }' : 'default_backend be_web_tls',
      versoServer: 'HTTPS originale, non toccato', chiave: 'solo sui server',
      esito: 'byte cifrati inoltrati così come sono: host, path e header non sono leggibili',
    };
  }
  const hostNegozio = ugualeI(host, 'www.negozio.it');
  const percorsoApi = String(path || '').startsWith('/api/');
  const api = hostNegozio && percorsoApi;
  return {
    frontend: 'fe_https', backend: api ? 'be_api' : 'be_web', modalita: api ? 'ri-cifratura' : 'terminazione', decifra: true,
    vede: { sni: true, host: true, path: true, header: true },
    regola: api ? 'use_backend be_api if host_negozio percorso_api' : hostNegozio ? 'use_backend be_web if host_negozio' : 'default_backend',
    versoServer: api ? 'HTTPS ri-cifrato, ssl verify required con ca-file interna' : 'HTTP in chiaro sulla rete interna',
    chiave: api ? 'HAProxy (+ certificati sui server)' : 'HAProxy',
    esito: api ? 'leastconn fra api1 e api2' : 'roundrobin fra web1 e web2',
  };
}

export function countForEach(modo, prima, dopo) {
  if (modo === 'for_each') {
    const chiavi = [...new Set([...prima, ...dopo])].sort();
    return chiavi.map(k => ({
      indirizzo: `web["${k}"]`,
      azione: prima.includes(k) && dopo.includes(k) ? 'nessuna' : prima.includes(k) ? 'distrugge' : 'crea',
      prima: prima.includes(k) ? k : null, dopo: dopo.includes(k) ? k : null,
    }));
  }
  return Array.from({ length: Math.max(prima.length, dopo.length) }, (_, i) => ({
    indirizzo: `web[${i}]`,
    azione: i >= dopo.length ? 'distrugge' : i >= prima.length ? 'crea' : prima[i] === dopo[i] ? 'nessuna' : 'aggiorna/ricrea',
    prima: prima[i] ?? null, dopo: dopo[i] ?? null,
  }));
}

export const FONTI_VARIABILI = [
  ['default', 'default nel blocco variable'],
  ['env', 'TF_VAR_nome (ambiente)'],
  ['tfvars', 'terraform.tfvars'],
  ['auto', '*.auto.tfvars'],
  ['varFile', '-var-file=…'],
  ['cli', '-var nome=…'],
];

export const FONTI_ANSIBLE = [
  ['defaults', 'defaults del ruolo'],
  ['groupAll', 'group_vars/all'],
  ['group', 'group_vars/web'],
  ['hostVars', 'host_vars/web1'],
  ['playVars', 'vars del play'],
  ['roleVars', 'vars del ruolo'],
  ['setFact', 'set_fact / register'],
  ['extra', '-e (extra vars)'],
];

export function precedenza(valori, fonti = FONTI_VARIABILI) {
  let esito = { valore: null, fonte: null };
  for (const [fonte] of fonti) if (valori[fonte] !== undefined && valori[fonte] !== '') esito = { valore: valori[fonte], fonte };
  return esito;
}

export function lottiSerial(host, serial) {
  const misure = String(serial).split(/[\s,]+/).filter(Boolean)
    .map(s => s.endsWith('%') ? Math.max(1, Math.floor(host.length * parseFloat(s) / 100)) : Math.max(1, parseInt(s, 10) || 1));
  const lotti = [];
  for (let i = 0, n = 0; i < host.length; n++) {
    const m = misure[Math.min(n, misure.length - 1)];
    lotti.push(host.slice(i, i + m));
    i += m;
  }
  return lotti;
}

export function rolling({ host, serial, maxFail, rotti = [], nuova = '2.0', vecchia = '1.0' }) {
  const ordinati = [...host].sort((a, b) => a.localeCompare(b, 'it', { numeric: true }));
  const lb = new Set();
  const versioni = Object.fromEntries(ordinati.map(h => [h, vecchia]));
  const falliti = new Set();
  const rientrati = new Set();
  let fermato = null;
  const lotti = lottiSerial(ordinati, serial).map((lotto, n) => {
    if (fermato !== null) return { n: n + 1, esiti: lotto.map(h => ({ host: h, esito: 'non toccato' })) };
    for (const h of ordinati) { if (falliti.has(h) && !lb.has(h)) rientrati.add(h); lb.add(h); }
    const esiti = lotto.map(h => {
      lb.delete(h);
      const rotto = rotti.includes(h);
      versioni[h] = rotto ? 'rotto' : nuova;
      if (rotto) { falliti.add(h); return { host: h, esito: 'fallito' }; }
      lb.add(h);
      return { host: h, esito: 'ok' };
    });
    const ko = esiti.filter(e => e.esito === 'fallito').length;
    if (ko / lotto.length * 100 > maxFail) fermato = n + 1;
    return { n: n + 1, esiti };
  });
  return { lotti, fermato, bilanciatore: ordinati.filter(h => lb.has(h)), versioni, rientrati: [...rientrati] };
}

export function serieContatore({ rps1, rps2, cambio, riavvio, n = 13, passo = 15 }) {
  const v = [0];
  for (let i = 1; i < n; i++) {
    const nuove = (i <= cambio ? rps1 : rps2) * passo;
    v.push(i === riavvio ? nuove : v[i - 1] + nuove);
  }
  return v;
}

export function rateContatore({ campioni, passo, finestra }) {
  return campioni.map((valore, i) => {
    const primo = Math.max(0, i - Math.floor(finestra / passo) + 1);
    const dentro = campioni.slice(primo, i + 1);
    if (dentro.length < 2) return { t: i * passo, valore, aumento: null, rate: null, differenza: null };
    let aumento = 0;
    for (let k = 1; k < dentro.length; k++) aumento += dentro[k] >= dentro[k - 1] ? dentro[k] - dentro[k - 1] : dentro[k];
    const durata = (dentro.length - 1) * passo;
    return { t: i * passo, valore, aumento, rate: Math.round(aumento / durata * 1000) / 1000, differenza: dentro.at(-1) - dentro[0] };
  });
}

export function statiAlert({ inizio, fine, intervallo, per, durata }) {
  const out = [];
  let attivoDa = null;
  for (let t = 0; t <= durata; t += intervallo) {
    const vera = t >= inizio && t < fine;
    if (!vera) attivoDa = null;
    else if (attivoDa === null) attivoDa = t;
    out.push({ t, vera, stato: !vera ? 'inactive' : t - attivoDa >= per ? 'firing' : 'pending' });
  }
  return out;
}
