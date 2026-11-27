import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const DIST = mkdtempSync(join(tmpdir(), 'k8s-site-test-'));
process.env.DIST = DIST;
const { costruisci } = await import('../src/build.mjs');
const ORDINE = ['01', '02', '03', '04', '05', '06', '07', '08', '09', '21', '22', '23', '24', '25'];
const pag = p => readFileSync(join(DIST, p), 'utf8');
const unesc = s => s.replace(/&#x27;|&#39;/g, "'").replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');

before(() => costruisci());
process.on('exit', () => rmSync(DIST, { recursive: true, force: true }));

test('la home elenca le lezioni nell\'ordine 01…09, poi gli approfondimenti 21, 22, 23, 24 e 25', () => {
  const ids = [...pag('index.html').matchAll(/data-tappa="(\d\d)"/g)].map(m => m[1]);
  assert.deepEqual(ids, ORDINE);
});

test('ogni lezione: tre viste, almeno cinque domande, tre sorgenti integrali scaricabili', () => {
  for (const id of ORDINE) {
    const h = pag(`lezioni/${id}.html`);
    for (const v of ['spiegazione', 'sorgenti', 'laboratorio']) assert.match(h, new RegExp(`id="vista-${v}"`), id);
    const quiz = JSON.parse(h.match(/<script type="application\/json" id="dati-quiz">([\s\S]*?)<\/script>/)[1]);
    assert.ok(quiz.length >= 5, id);
    for (const q of quiz) assert.ok(q.corretta >= 0 && q.corretta < q.opzioni.length, q.id);
    const scarica = [...h.matchAll(/class="scarica" href="([^"]+)"/g)].map(m => m[1]);
    assert.equal(scarica.length, { '22': 17, '23': 18, '24': 37, '25': 4 }[id] ?? 3, id);
    for (const s of scarica) assert.ok(existsSync(join(DIST, s)), s);
  }
});

test('i passi del diagramma sono JSON leggibile e le regex compilano', () => {
  for (const id of ORDINE) {
    const m = pag(`lezioni/${id}.html`).match(/data-passi="([^"]*)"/);
    assert.ok(m, `${id}: data-passi assente o non fra virgolette doppie`);
    const passi = JSON.parse(unesc(m[1]));
    assert.ok(passi.length >= 3, id);
    for (const p of passi) assert.doesNotThrow(() => new RegExp(p.re, p.f));
  }
});

test('i link interni puntano a file che esistono', () => {
  const pagine = ['index.html', 'glossario.html', 'flashcard.html', 'preferiti.html', ...ORDINE.map(id => `lezioni/${id}.html`)];
  for (const p of pagine) {
    for (const [, href] of pag(p).matchAll(/(?:href|src)="(\/[^"#?]*)/g)) {
      const f = href.endsWith('/') ? `${href}index.html` : href;
      assert.ok(existsSync(join(DIST, f)), `${p} → ${href}`);
    }
  }
});

test('collegamenti obbligatori: checksum/config → 04, 09; EndpointSlice → 03, 08, 21', () => {
  const g = JSON.parse(pag('dati/glossario.json'));
  const voce = t => g.find(x => x.termine === t);
  for (const l of ['04', '09']) assert.ok(voce('checksum/config').lezioni.includes(l), `checksum/config ${l}`);
  for (const l of ['03', '08', '21']) assert.ok(voce('EndpointSlice').lezioni.includes(l), `EndpointSlice ${l}`);
  for (const t of ['Pod', 'ReplicaSet', 'readiness', 'EndpointSlice', 'PVC', 'RoleBinding', 'taint', 'Chart', 'frontend', 'backend', 'NodePort', 'Runtime API', 'stick-table']) assert.ok(voce(t), t);
});

test('lezione 21: distingue replica HAProxy, NodePort, Ingress, Service applicativo e Pod IP', () => {
  const h = pag('lezioni/21.html');
  for (const s of ['HAProxy A', 'HAProxy B', 'controller.service.nodePorts', 'Ingress', 'Pod IP blu', 'Pod IP verde', 'data-sim="failover"', 'data-sim="ratelimit"', 'data-sim="bilancia"']) assert.ok(h.includes(s), s);
  const lab = h.slice(h.indexOf('id="vista-laboratorio"'));
  assert.equal((lab.match(/<li class="passo">/g) || []).length, 34);
  for (const s of ['headlamp.lab.local', 'headlamp-lettore']) assert.ok(lab.includes(s), s);
  assert.match(h, /system:anonymous/);
});

test('la ricerca indicizza spiegazioni, sorgenti, quiz e glossario', () => {
  const idx = JSON.parse(pag('dati/cerca.json'));
  assert.ok(idx.some(v => v.u.includes('vista=sorgenti') && /stick-table/i.test(v.x)));
  assert.ok(idx.some(v => v.t.startsWith('Glossario · EndpointSlice')));
  assert.ok(idx.some(v => v.t.startsWith('Quiz · ')));
  for (const id of ORDINE) assert.ok(idx.some(v => v.l === id && v.u.includes('vista=spiegazione')), id);
});

test('gli script del browser compilano: un errore di sintassi spegne simulazioni, glossario e quiz insieme', async () => {
  const { execFileSync } = await import('node:child_process');
  const { readdirSync } = await import('node:fs');
  const cartella = new URL('../assets/', import.meta.url);
  const file = readdirSync(cartella).filter(f => /\.m?js$/.test(f));
  assert.ok(file.length >= 5, `file ${file.length}`);
  for (const f of file) assert.doesNotThrow(() => execFileSync(process.execPath, ['--check', new URL(f, cartella).pathname], { stdio: 'pipe' }), f);
});

test('il build è deterministico', () => {
  const prima = pag('lezioni/21.html') + pag('dati/cerca.json');
  costruisci();
  assert.equal(pag('lezioni/21.html') + pag('dati/cerca.json'), prima);
});

test('lezione 21: approfondimento haproxy.cfg e TLS integrato, fedele e con un suo quiz', () => {
  const h = pag('lezioni/21.html');
  assert.match(h, /id="approfondimento-tls"/);
  const md = readFileSync(new URL('../content/approfondimenti/21-haproxy-cfg-tls.md', import.meta.url), 'utf8');
  const blocchi = [...md.matchAll(/^```[a-z]*\n([\s\S]*?)^```$/gm)].map(m => m[1]);
  assert.ok(blocchi.length >= 8, `blocchi ${blocchi.length}`);
  const testo = unesc(h.replace(/<[^>]+>/g, ''));
  for (const b of blocchi) for (const r of b.split('\n').filter(Boolean)) assert.ok(testo.includes(r), `riga persa: ${r}`);
  const q = JSON.parse(h.match(/<script type="application\/json" id="dati-quiz-21-tls">([\s\S]*?)<\/script>/)[1]);
  assert.ok(q.length >= 5 && q.length <= 8, `quiz ${q.length}`);
  for (const d of q) assert.ok(d.corretta >= 0 && d.corretta < d.opzioni.length, d.id);
  assert.ok(h.includes('data-sim="tls"'));
  assert.equal([...h.matchAll(/class="scarica" href=/g)].length, 3, 'le sorgenti del laboratorio restano tre');
  assert.ok(existsSync(join(DIST, 'fonti/approfondimenti/21-haproxy-cfg-tls.md')));
  const g = JSON.parse(pag('dati/glossario.json'));
  for (const t of ['SNI', 'terminazione TLS', 'ri-cifratura TLS', 'TLS passthrough', 'ACL', 'health check', 'PEM', 'HSTS', 'X-Forwarded-For']) assert.ok(g.find(x => x.termine === t)?.lezioni.includes('21'), t);
  const idx = JSON.parse(pag('dati/cerca.json'));
  assert.ok(idx.some(v => v.l === '21' && /passthrough/i.test(v.x) && v.u.includes('vista=spiegazione')));
});

test('lezione 22 Terraform: approfondimento dopo la 21, parti, passi, simulazioni, glossario', () => {
  const h = pag('lezioni/22.html');
  assert.match(h, /class="occhiello">Lezione 22 · Approfondimento/);
  const nav = h.match(/<nav class="percorso"[\s\S]*?<\/nav>/)[0];
  assert.match(nav.split('percorso-sep')[1], /data-id="21"[\s\S]*data-id="22"/);
  for (const n of ['00', '01', '02', '03', '04', '05']) assert.match(h, new RegExp(`id="passi-${n}"`), n);
  assert.equal((h.match(/<li class="passo">/g) || []).length, 62);
  assert.equal((h.match(/class="passo-cartella"/g) || []).length, 5);
  assert.match(h, /~\/kubernetesprj\/lavoro\/iac\/01/);
  for (const s of ['count-foreach', 'precedenza']) assert.ok(h.includes(`data-sim="${s}"`), s);
  assert.ok(h.includes('hljs-keyword">resource<'), 'HCL colorato');
  const g = JSON.parse(pag('dati/glossario.json'));
  for (const t of ['state', 'provider', 'plan', 'drift', 'lock file', 'backend remoto', 'for_each', 'modulo', 'moved', 'import', 'sensitive', 'check']) assert.ok(g.find(x => x.termine === t)?.lezioni.includes('22'), t);
  const idx = JSON.parse(pag('dati/cerca.json'));
  assert.ok(idx.some(v => v.l === '22' && v.u.includes('vista=sorgenti') && /docker_container/.test(v.x)));
  assert.ok(pag('index.html').includes('data-tappa="22"'));
});

test('lezione 23 Ansible: approfondimento dopo la 22, parti 06–11, passi, simulazioni, glossario', () => {
  const h = pag('lezioni/23.html');
  assert.match(h, /class="occhiello">Lezione 23 · Approfondimento/);
  const nav = h.match(/<nav class="percorso"[\s\S]*?<\/nav>/)[0];
  assert.match(nav.split('percorso-sep')[1], /data-id="21"[\s\S]*data-id="22"[\s\S]*data-id="23"/);
  for (const n of ['06', '07', '08', '09', '10', '11']) assert.match(h, new RegExp(`id="passi-${n}"`), n);
  assert.equal((h.match(/<li class="passo">/g) || []).length, 61);
  assert.match(h, /id="parte-11"[\s\S]*lezioni\/kubernetes\/23-architettura-e-haproxy-ansible\.md/);
  assert.ok(h.includes('href="/fonti/kubernetes/23-architettura-e-haproxy-ansible.sh"'));
  assert.equal((h.match(/class="passo-cartella"/g) || []).length, 5);
  assert.match(h, /~\/kubernetesprj\/lavoro\/ansible/);
  assert.match(h, /~\/kubernetesprj\/lavoro\/iac\/10/);
  for (const s of ['rolling', 'precedenza-ansible']) assert.ok(h.includes(`data-sim="${s}"`), s);
  assert.ok(!/id="passi-0[0-5]"/.test(h), 'le parti Terraform restano nella 22');
  const g = JSON.parse(pag('dati/glossario.json'));
  for (const t of ['idempotenza', 'inventario', 'playbook', 'handler', 'ruolo', 'argument_specs', 'collection', 'Ansible Vault', 'no_log', 'serial', 'delegate_to', 'drain dal bilanciatore']) assert.ok(g.find(x => x.termine === t)?.lezioni.includes('23'), t);
  for (const t of ['drain', 'Role', 'Service', 'Deployment', 'Secret']) assert.deepEqual(g.find(x => x.termine === t).tranneLezioni, ['23'], t);
  const idx = JSON.parse(pag('dati/cerca.json'));
  assert.ok(idx.some(v => v.l === '23' && v.u.includes('vista=sorgenti') && /delegate_to/.test(v.x)));
  assert.ok(idx.some(v => v.l === '23' && v.u.includes('vista=sorgenti') && /kubernetes\.core\.k8s_scale/.test(v.x)));
  for (const t of ['Headlamp', 'kubernetes.core']) assert.ok(g.find(x => x.termine === t)?.lezioni.includes('23'), t);
  assert.ok(g.find(x => x.termine === 'Headlamp').lezioni.includes('21'));
  assert.ok(idx.some(v => v.l === '23' && v.t.startsWith('Appunti · ')));
  assert.ok(pag('index.html').includes('data-tappa="23"'));
  assert.ok(pag('lezioni/22.html').includes('href="/lezioni/23.html"'));
});

test('lezione 24 progetto reale: dopo la 23, README come lezione, 37 file, comandi del README, nessun IP del laboratorio', () => {
  const h = pag('lezioni/24.html');
  assert.match(h, /class="occhiello">Lezione 24 · Approfondimento/);
  const nav = h.match(/<nav class="percorso"[\s\S]*?<\/nav>/)[0];
  assert.match(nav.split('percorso-sep')[1], /data-id="21"[\s\S]*data-id="22"[\s\S]*data-id="23"[\s\S]*data-id="24"/);
  const lab = h.slice(h.indexOf('id="vista-laboratorio"'));
  assert.equal((lab.match(/<li class="passo">/g) || []).length, 8);
  assert.deepEqual(lab.match(/class="riga pericolo" title="[^"]*"/g), ['class="riga pericolo" title="Attenzione: deploy.sh distruggi"']);
  assert.match(h, /<h2 id="passi">I comandi del README<\/h2>/);
  assert.match(h, /Raccolti dal README del progetto/);
  assert.ok(!h.includes('lo script stampa ogni passo'), 'niente testo dello script guidato');
  assert.match(h, /<code>~\/biodistretto\/kubernetes\/ansible\/site\.yml<\/code>/);
  assert.match(h, /Fonte originale<\/span> <code>~\/biodistretto\/kubernetes\/README\.md<\/code>/);
  assert.match(h, /I 37 file del progetto/);
  assert.ok(h.includes('IP-DEL-LAB'));
  assert.ok(!/192\.168\./.test(h), 'IP del laboratorio nella pagina');
  const voci24 = JSON.parse(pag('dati/cerca.json')).filter(v => v.l === '24');
  assert.ok(voci24.length > 37);
  assert.ok(!voci24.some(v => /192\.168\./.test(v.t + v.x)), 'IP del laboratorio nella ricerca');
  assert.ok(!existsSync(join(DIST, 'fonti', 'terraform', 'app', 'terraform.tfstate')));
  const scarica = [...h.matchAll(/class="scarica" href="([^"]+)"/g)].map(m => m[1]);
  assert.equal(scarica.length, 37);
  for (const u of scarica) assert.ok(u.startsWith('/fonti/biodistretto/') && existsSync(join(DIST, u)), u);
  assert.equal(pag('fonti/biodistretto/ansible/site.yml'), readFileSync(new URL('../content/progetto/file/ansible/site.yml', import.meta.url), 'utf8'));
  for (const lg of ['nginx', 'dockerfile', 'hcl', 'haproxy', 'yaml']) assert.match(h, new RegExp(`data-lingua="${lg}"`), lg);
  const g = JSON.parse(pag('dati/glossario.json'));
  for (const t of ['HAProxy', 'NodePort', 'for_each', 'no_log', 'PROXY protocol', 'externalTrafficPolicy']) assert.ok(g.find(x => x.termine === t)?.lezioni.includes('24'), t);
  assert.equal(JSON.parse(pag('dati/corso.json')).mappa.filter(m => m.verso.includes('24')).length, 4);
  assert.ok(pag('index.html').includes('data-tappa="24"'));
  assert.ok(pag('lezioni/23.html').includes('href="/lezioni/24.html"'));
});

test('lezione 25 Prometheus e Grafana: dopo la 24, testo integrale, tre YAML, laboratorio con pulizia, simulazioni, quiz', () => {
  const h = pag('lezioni/25.html');
  assert.match(h, /class="occhiello">Lezione 25 · Approfondimento/);
  const nav = h.match(/<nav class="percorso"[\s\S]*?<\/nav>/)[0];
  assert.match(nav.split('percorso-sep')[1], /data-id="24"[\s\S]*data-id="25"/);
  const home = pag('index.html');
  assert.ok(home.indexOf('data-tappa="24"') < home.indexOf('data-tappa="25"'));
  assert.ok(home.split('class="approf"')[1].includes('data-tappa="25"'), '25 fra gli approfondimenti');
  assert.ok(pag('lezioni/24.html').includes('href="/lezioni/25.html"'));
  const md = readFileSync(new URL('../content/monitoraggio/lezione-25.md', import.meta.url), 'utf8');
  const blocchi = [...md.matchAll(/^```[a-z]*\n([\s\S]*?)^```$/gm)].map(m => m[1]);
  assert.ok(blocchi.length >= 40, `blocchi ${blocchi.length}`);
  const spieg = h.slice(h.indexOf('id="vista-spiegazione"'), h.indexOf('id="vista-sorgenti"'));
  const testo = unesc(spieg.replace(/<[^>]+>/g, ''));
  for (const b of blocchi) for (const r of b.split('\n').filter(Boolean)) assert.ok(testo.includes(r), `riga persa: ${r}`);
  assert.ok(!/Codex|OpenClaw|Prompt breve/.test(h), 'la specifica per l\'agente resta fuori');
  assert.match(spieg, /data-lingua="promql"/);
  assert.match(spieg, /hljs-built_in">rate</);
  const scarica = [...h.matchAll(/class="scarica" href="([^"]+)"/g)].map(m => m[1]);
  assert.deepEqual(scarica, ['/fonti/monitoraggio/lezione-25.md', '/fonti/monitoraggio/values-monitoring.yaml', '/fonti/monitoraggio/demo-metrics.yaml', '/fonti/monitoraggio/demo-alert.yaml']);
  assert.equal(pag('fonti/monitoraggio/demo-metrics.yaml'), readFileSync(new URL('../content/monitoraggio/file/demo-metrics.yaml', import.meta.url), 'utf8'));
  const lab = h.slice(h.indexOf('id="vista-laboratorio"'), h.indexOf('class="verifica"'));
  assert.equal((lab.match(/<li class="passo">/g) || []).length, 18);
  for (const s of ['helm upgrade --install monitoring', 'kubectl apply -f demo-metrics.yaml', '--replicas=0', '--replicas=1', 'helm uninstall monitoring']) assert.ok(unesc(lab).includes(s), s);
  const pericoli = (lab.match(/class="riga pericolo" title="[^"]*"/g) || []).map(x => x.match(/Attenzione: ([^"]*)/)[1]);
  assert.deepEqual(pericoli, ['delete', 'delete', 'helm uninstall', 'delete']);
  for (const s of ['rate', 'alert']) assert.ok(lab.includes(`data-sim="${s}"`), s);
  const q = JSON.parse(h.match(/<script type="application\/json" id="dati-quiz">([\s\S]*?)<\/script>/)[1]);
  assert.equal(q.length, 8);
  assert.match(h, /id="vista-spiegazione"[\s\S]*class="frase"|class="frase"[\s\S]*id="vista-spiegazione"/);
  const g = JSON.parse(pag('dati/glossario.json'));
  for (const t of ['Prometheus', 'Grafana', 'PromQL', 'ServiceMonitor', 'PrometheusRule', 'Alertmanager', 'kube-state-metrics', 'node-exporter', 'Counter', 'Gauge', 'rate()', 'cardinalità']) assert.ok(g.find(x => x.termine === t)?.lezioni.includes('25'), t);
  for (const t of ['metrics-server', 'HPA', 'Chart', 'HAProxy', 'stick-table']) assert.ok(g.find(x => x.termine === t).lezioni.includes('25'), t);
  assert.deepEqual(JSON.parse(pag('dati/corso.json')).mappa.filter(m => m.verso.includes('25')).map(m => m.da).sort(), ['01', '05', '06', '08', '09', '21']);
  const idx = JSON.parse(pag('dati/cerca.json'));
  assert.ok(idx.some(v => v.l === '25' && v.u.includes('vista=spiegazione') && /ServiceMonitor/.test(v.x)));
  assert.ok(idx.some(v => v.l === '25' && v.u.includes('vista=sorgenti') && /PrometheusRule/.test(v.x)));
  assert.match(home, /0\/14/);
});
