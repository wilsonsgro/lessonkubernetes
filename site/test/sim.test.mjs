import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as S from '../assets/sim-logica.mjs';

test('HPA: il caso della lezione 06 chiede 13 e il max taglia a 8', () => {
  const r = S.hpa({ attuali: 2, valore: 375, target: 60, min: 2, max: 8 });
  assert.equal(r.formula, 13);
  assert.equal(r.desiderate, 8);
  assert.equal(r.limitatoDa, 'maxReplicas');
});

test('HPA: sotto target scende ma non sotto minReplicas', () => {
  const r = S.hpa({ attuali: 4, valore: 10, target: 60, min: 2, max: 8 });
  assert.equal(r.formula, 1);
  assert.equal(r.desiderate, 2);
  assert.equal(r.limitatoDa, 'minReplicas');
  assert.equal(S.hpa({ attuali: 3, valore: 60, target: 60, min: 2, max: 8 }).limitatoDa, null);
});

test('RBAC: il Role deployer vale solo nel suo namespace e solo per i verbi elencati', () => {
  const chiedi = (verbo, risorsa, gruppo, namespace) => S.rbac(S.RBAC_LEZIONE_07, { soggetto: 'system:serviceaccount:lab-sicuro:deployer', verbo, risorsa, gruppo, namespace }).permesso;
  assert.equal(chiedi('get', 'pods', '', 'lab-sicuro'), true);
  assert.equal(chiedi('delete', 'pods', '', 'lab-sicuro'), false);
  assert.equal(chiedi('create', 'deployments', 'apps', 'lab-sicuro'), true);
  assert.equal(chiedi('patch', 'deployments/scale', 'apps', 'lab-sicuro'), true);
  assert.equal(chiedi('get', 'secrets', '', 'lab-sicuro'), false);
  assert.equal(chiedi('get', 'pods', '', 'default'), false);
  assert.equal(chiedi('get', 'deployments', '', 'lab-sicuro'), false);
});

test('RBAC: un altro soggetto non eredita il binding', () => {
  const r = S.rbac(S.RBAC_LEZIONE_07, { soggetto: 'system:serviceaccount:lab-sicuro:default', verbo: 'get', risorsa: 'pods', gruppo: '', namespace: 'lab-sicuro' });
  assert.equal(r.permesso, false);
  assert.match(r.motivo, /binding/i);
});

test('NetworkPolicy: due elementi = OR, un elemento con due selettori = AND', () => {
  const client = { namespace: 'lab', labels: { ruolo: 'client' } };
  const altro = { namespace: 'lab', labels: {} };
  const ingress = { namespace: 'ingress-nginx', labels: {} };
  const clientInIngress = { namespace: 'ingress-nginx', labels: { ruolo: 'client' } };
  const or = s => S.netpol('OR', s).ammesso, and = s => S.netpol('AND', s).ammesso;
  assert.deepEqual([client, altro, ingress, clientInIngress].map(or), [true, false, true, true]);
  assert.deepEqual([client, altro, ingress, clientInIngress].map(and), [false, false, false, true]);
});

test('partition: aggiorna solo gli ordinali >= soglia, dal più alto', () => {
  const r = S.partition(3, 2);
  assert.deepEqual(r.pod.map(p => p.revisione), ['vecchia', 'vecchia', 'nuova']);
  assert.deepEqual(S.partition(3, 0).ordine, ['db-2', 'db-1', 'db-0']);
  assert.deepEqual(S.partition(3, 3).ordine, []);
});

test('Helm: la sequenza della lezione 09 arriva a 5 revisioni senza cancellare la storia', () => {
  const h = S.helm([
    { op: 'install', valori: 'v1' }, { op: 'upgrade', valori: 'seconda versione' },
    { op: 'upgrade-fallito', valori: 'v9.9.9', rollbackOnFailure: true }, { op: 'rollback', a: 1 },
  ]);
  assert.deepEqual(h.map(r => r.revisione), [1, 2, 3, 4, 5]);
  assert.deepEqual(h.map(r => r.stato), ['superseded', 'superseded', 'failed', 'superseded', 'deployed']);
  assert.equal(h[3].valori, 'seconda versione');
  assert.match(h[3].descrizione, /Rollback to 2/);
  assert.equal(h[4].valori, 'v1');
  assert.throws(() => S.helm([{ op: 'upgrade', valori: 'x' }]), /install/);
  assert.equal(S.helm([{ op: 'install', valori: 'a' }, { op: 'upgrade-fallito', valori: 'b' }]).at(-1).stato, 'failed');
});

test('bilanciamento: leastconn evita il server occupato da una connessione lunga', () => {
  const richieste = [{ durata: 10 }, { durata: 1 }, { durata: 1 }, { durata: 1 }];
  const rr = S.bilancia('roundrobin', richieste, 2).map(a => a.server);
  const lc = S.bilancia('leastconn', richieste, 2).map(a => a.server);
  assert.deepEqual(rr, [0, 1, 0, 1]);
  assert.deepEqual(lc, [0, 1, 1, 1]);
});

test('rate limit: due repliche con contatori locali lasciano passare il doppio', () => {
  assert.equal(S.rateLimit({ richieste: 12, limite: 5, repliche: 1 }).passate, 5);
  const due = S.rateLimit({ richieste: 12, limite: 5, repliche: 2 });
  assert.equal(due.passate, 10);
  assert.deepEqual(due.perReplica.map(r => r.passate), [5, 5]);
  assert.equal(S.rateLimit({ richieste: 12, limite: 2, repliche: 2 }).passate, 4);
});

test('failover: con A non Ready le connessioni nuove vanno tutte a B', () => {
  assert.deepEqual(S.failover(4, { A: true, B: true }), ['A', 'B', 'A', 'B']);
  assert.deepEqual(S.failover(3, { A: false, B: true }), ['B', 'B', 'B']);
  assert.deepEqual(S.failover(2, { A: false, B: false }), [null, null]);
});

test('TLS/ACL del negozio: fe_https decifra e instrada per host E path', () => {
  const api = S.tlsInstrada({ frontend: 'fe_https', porta: 443, sni: 'www.negozio.it', host: 'WWW.negozio.it', path: '/api/ordini' });
  assert.equal(api.backend, 'be_api');
  assert.equal(api.modalita, 'ri-cifratura');
  assert.equal(api.decifra, true);
  assert.deepEqual(api.vede, { sni: true, host: true, path: true, header: true });
  const web = S.tlsInstrada({ frontend: 'fe_https', porta: 443, sni: 'www.negozio.it', host: 'www.negozio.it', path: '/catalogo' });
  assert.equal(web.backend, 'be_web');
  assert.equal(web.modalita, 'terminazione');
  assert.equal(S.tlsInstrada({ frontend: 'fe_https', porta: 443, sni: 'altro.it', host: 'altro.it', path: '/api/x' }).regola, 'default_backend');
  assert.equal(S.tlsInstrada({ frontend: 'fe_https', porta: 443, sni: 'www.negozio.it', host: 'www.negozio.it', path: '/API/x' }).backend, 'be_web');
});

test('TLS: la porta 80 risponde solo con il redirect 301', () => {
  const r = S.tlsInstrada({ frontend: 'fe_https', porta: 80, sni: '', host: 'www.negozio.it', path: '/api/x' });
  assert.equal(r.frontend, 'fe_http');
  assert.equal(r.backend, null);
  assert.match(r.esito, /301/);
});

test('TLS passthrough: non decifra, sceglie solo per SNI e ignora il path', () => {
  const pay = S.tlsInstrada({ frontend: 'fe_passthrough', porta: 443, sni: 'PAGAMENTI.negozio.it', host: 'www.negozio.it', path: '/api/x' });
  assert.equal(pay.backend, 'be_pagamenti');
  assert.equal(pay.decifra, false);
  assert.deepEqual(pay.vede, { sni: true, host: false, path: false, header: false });
  assert.match(pay.chiave, /server/);
  const web = S.tlsInstrada({ frontend: 'fe_passthrough', porta: 443, sni: 'www.negozio.it', host: 'www.negozio.it', path: '/api/x' });
  assert.equal(web.backend, 'be_web_tls');
  assert.equal(web.modalita, 'passthrough');
});

test('count contro for_each: togliere "b" da a,b,c', () => {
  const c = S.countForEach('count', ['a', 'b', 'c'], ['a', 'c']);
  assert.deepEqual(c.map(x => `${x.azione} ${x.indirizzo}`), ['nessuna web[0]', 'aggiorna/ricrea web[1]', 'distrugge web[2]']);
  const f = S.countForEach('for_each', ['a', 'b', 'c'], ['a', 'c']);
  assert.deepEqual(f.map(x => `${x.azione} ${x.indirizzo}`), ['nessuna web["a"]', 'distrugge web["b"]', 'nessuna web["c"]']);
  const agg = S.countForEach('count', ['a', 'b'], ['a', 'b', 'c']);
  assert.deepEqual(agg.map(x => x.azione), ['nessuna', 'nessuna', 'crea']);
});

test('precedenza delle variabili: vince l\'ultima fonte definita', () => {
  assert.deepEqual(S.precedenza({ default: 'dev' }), { valore: 'dev', fonte: 'default' });
  assert.deepEqual(S.precedenza({ default: 'dev', env: 'collaudo', tfvars: 'staging' }), { valore: 'staging', fonte: 'tfvars' });
  assert.deepEqual(S.precedenza({ default: 'dev', cli: 'prod', varFile: 'x', auto: 'y' }), { valore: 'prod', fonte: 'cli' });
  assert.deepEqual(S.precedenza({}), { valore: null, fonte: null });
});

test('rolling: lotti di serial, anche in percentuale e a lista (canary); minimo 1 host', () => {
  const h = ['web1', 'web2', 'web3', 'web4', 'web5', 'web6', 'web7', 'web8', 'web9', 'web10'];
  assert.deepEqual(S.lottiSerial(h.slice(0, 2), '1'), [['web1'], ['web2']]);
  assert.deepEqual(S.lottiSerial(h, '30%').map(l => l.length), [3, 3, 3, 1]);
  assert.deepEqual(S.lottiSerial(h, '1, 50%').map(l => l.length), [1, 5, 4]);
  assert.deepEqual(S.lottiSerial(h.slice(0, 3), '10%').map(l => l.length), [1, 1, 1]);
});

test('rolling della parte 09: web2 rotto resta fuori dal bilanciatore, web1 serve la 2.0', () => {
  const r = S.rolling({ host: ['web1', 'web2'], serial: '1', maxFail: 0, rotti: ['web2'] });
  assert.deepEqual(r.lotti.map(l => l.esiti.map(e => `${e.host}:${e.esito}`)), [['web1:ok'], ['web2:fallito']]);
  assert.deepEqual(r.bilanciatore, ['web1']);
  assert.deepEqual(r.versioni, { web1: '2.0', web2: 'rotto' });
});

test('rolling: con max_fail_percentage 0 un lotto fallito ferma i successivi, che restano alla 1.0 e in servizio', () => {
  const r = S.rolling({ host: ['web1', 'web2', 'web3'], serial: '1', maxFail: 0, rotti: ['web1'] });
  assert.equal(r.fermato, 1);
  assert.deepEqual(r.lotti.map(l => l.esiti.map(e => e.esito)), [['fallito'], ['non toccato'], ['non toccato']]);
  assert.deepEqual(r.bilanciatore, ['web2', 'web3']);
  assert.deepEqual(r.versioni, { web1: 'rotto', web2: '1.0', web3: '1.0' });
});

test('rolling: la soglia va superata, non eguagliata; il registro ripreparato rimette dentro chi era fallito', () => {
  const pari = S.rolling({ host: ['web1', 'web2', 'web3', 'web4'], serial: '2', maxFail: 50, rotti: ['web1'] });
  assert.equal(pari.fermato, null);
  assert.ok(pari.bilanciatore.includes('web1'));
  assert.deepEqual(pari.rientrati, ['web1']);
  const sotto = S.rolling({ host: ['web1', 'web2', 'web3', 'web4'], serial: '2', maxFail: 49, rotti: ['web1'] });
  assert.equal(sotto.fermato, 1);
  assert.deepEqual(sotto.bilanciatore, ['web2', 'web3', 'web4']);
});

test('precedenza delle variabili di Ansible: -e vince su tutto, i defaults del ruolo su niente', () => {
  const F = S.FONTI_ANSIBLE;
  assert.equal(F[0][0], 'defaults');
  assert.equal(F.at(-1)[0], 'extra');
  assert.deepEqual(S.precedenza({ defaults: '8080', hostVars: '9090' }, F), { valore: '9090', fonte: 'hostVars' });
  assert.deepEqual(S.precedenza({ groupAll: '1', group: '2', roleVars: '3' }, F), { valore: '3', fonte: 'roleVars' });
  assert.deepEqual(S.precedenza({ defaults: 'a', extra: 'z', setFact: 'y' }, F), { valore: 'z', fonte: 'extra' });
});

test('rate(): con traffico costante il tasso è quello vero, e un riavvio non lo fa crollare', () => {
  const v = S.serieContatore({ rps1: 2, rps2: 2, cambio: 6, riavvio: 0, n: 13, passo: 15 });
  assert.deepEqual(v.slice(0, 5), [0, 30, 60, 90, 120]);
  const r = S.rateContatore({ campioni: v, passo: 15, finestra: 60 });
  assert.equal(r[0].rate, null);
  for (const x of r.slice(4)) assert.equal(x.rate, 2);
  const conRiavvio = S.serieContatore({ rps1: 2, rps2: 2, cambio: 6, riavvio: 8, n: 13, passo: 15 });
  assert.equal(conRiavvio[8], 30);
  const rr = S.rateContatore({ campioni: conRiavvio, passo: 15, finestra: 60 });
  assert.equal(rr[9].rate, 2);
  assert.ok(rr[9].differenza < 0, 'la differenza ingenua va sotto zero');
});

test('rate(): il contatore sale sempre, il tasso scende quando il traffico rallenta', () => {
  const v = S.serieContatore({ rps1: 5, rps2: 1, cambio: 6, riavvio: 0, n: 13, passo: 15 });
  for (let i = 1; i < v.length; i++) assert.ok(v[i] > v[i - 1]);
  const r = S.rateContatore({ campioni: v, passo: 15, finestra: 60 });
  assert.equal(r[6].rate, 5);
  assert.equal(r[12].rate, 1);
  assert.ok(r[8].rate < 5 && r[8].rate > 1);
});

test('alert: for 1m, Pending prima e Firing dopo un minuto; una condizione breve non parte mai', () => {
  const t = S.statiAlert({ inizio: 30, fine: 180, intervallo: 15, per: 60, durata: 240 });
  const a = Object.fromEntries(t.map(x => [x.t, x.stato]));
  assert.equal(a[15], 'inactive');
  assert.equal(a[30], 'pending');
  assert.equal(a[75], 'pending');
  assert.equal(a[90], 'firing');
  assert.equal(a[180], 'inactive');
  const breve = S.statiAlert({ inizio: 30, fine: 60, intervallo: 15, per: 60, durata: 240 });
  assert.ok(!breve.some(x => x.stato === 'firing'));
  assert.ok(breve.some(x => x.stato === 'pending'));
  const subito = S.statiAlert({ inizio: 30, fine: 60, intervallo: 15, per: 0, durata: 120 });
  assert.equal(subito.find(x => x.t === 30).stato, 'firing');
});
