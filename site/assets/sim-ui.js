// Interactive panels for the local simulations; all numbers come from sim-logica.mjs and the lesson examples.
import * as S from './sim-logica.mjs';

const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const NOTA = '<p class="nota-sim">Simulazione concettuale: un modello semplificato degli esempi della lezione, calcolato nel browser. Non è una misura del cluster.</p>';
const num = (box, n) => Number(box.querySelector(`[name="${n}"]`).value);
const val = (box, n) => box.querySelector(`[name="${n}"]:checked, select[name="${n}"]`)?.value;

const SIM = {
  hpa(box) {
    box.insertAdjacentHTML('beforeend', `<p>Il caso della lezione: Deployment <code>api</code>, requests 20m, target <code>averageUtilization: 60</code>, da 2 a 8 repliche. Sotto carico la CPU media arriva al 375% delle requests.</p>
      <div class="campi">
        <label>Repliche attuali<input type="number" name="attuali" value="2" min="1" max="50"></label>
        <label>Utilizzo attuale (%)<input type="number" name="valore" value="375" min="0" max="2000"></label>
        <label>Target (%)<input type="number" name="target" value="60" min="1" max="100"></label>
        <label>minReplicas<input type="number" name="min" value="2" min="1" max="50"></label>
        <label>maxReplicas<input type="number" name="max" value="8" min="1" max="100"></label>
      </div><div class="esito" aria-live="polite"></div>
      <p class="nota-sim"><span class="etichetta">precisazione editoriale</span> Il controller vero applica anche una tolleranza (di default 10%) e il <code>behavior</code> della lezione (+100% ogni 15 s in salita, 1 Pod ogni 60 s in discesa): la formula qui sotto è quella concettuale del corso.</p>${NOTA}`);
    const calcola = () => {
      const p = { attuali: num(box, 'attuali'), valore: num(box, 'valore'), target: num(box, 'target'), min: num(box, 'min'), max: num(box, 'max') };
      if (!(p.target > 0) || p.min > p.max) { box.querySelector('.esito').innerHTML = 'Controlla i valori: target > 0 e min ≤ max.'; return; }
      const r = S.hpa(p);
      box.querySelector('.esito').innerHTML = `<p class="formula">ceil(${p.attuali} × ${p.valore} / ${p.target}) = ceil(${r.grezzo.toFixed(2)}) = <b>${r.formula}</b></p>
        <p>Repliche desiderate: <b class="verdetto">${r.desiderate}</b>${r.limitatoDa ? ` — la formula chiede ${r.formula}, ma <code>${r.limitatoDa}</code> la limita a ${r.desiderate}.` : ' — dentro i limiti.'}</p>`;
    };
    box.addEventListener('input', calcola); calcola();
  },

  rbac(box) {
    const RIS = [['', 'pods'], ['', 'pods/log'], ['', 'services'], ['', 'configmaps'], ['', 'secrets'], ['apps', 'deployments'], ['apps', 'deployments/scale']];
    box.insertAdjacentHTML('beforeend', `<p>Il Role <code>deployer</code> e il RoleBinding della lezione 07, nel namespace <code>lab-sicuro</code>.</p>
      <div class="campi">
        <label>Soggetto<select name="soggetto"><option>system:serviceaccount:lab-sicuro:deployer</option><option>system:serviceaccount:lab-sicuro:default</option></select></label>
        <label>Verbo<select name="verbo">${['get', 'list', 'watch', 'create', 'update', 'patch', 'delete'].map(v => `<option>${v}</option>`).join('')}</select></label>
        <label>Risorsa<select name="risorsa">${RIS.map(([g, r], i) => `<option value="${i}">${g ? `${g}/` : ''}${r}</option>`).join('')}</select></label>
        <label>Namespace<select name="namespace"><option>lab-sicuro</option><option>default</option><option>lab</option></select></label>
      </div><div class="esito" aria-live="polite"></div>${NOTA}`);
    const calcola = () => {
      const [gruppo, risorsa] = RIS[Number(val(box, 'risorsa'))];
      const q = { soggetto: val(box, 'soggetto'), verbo: val(box, 'verbo'), risorsa, gruppo, namespace: val(box, 'namespace') };
      const r = S.rbac(S.RBAC_LEZIONE_07, q);
      const e = box.querySelector('.esito');
      e.className = `esito ${r.permesso ? 'si' : 'no'}`;
      e.innerHTML = `<p><b class="verdetto">${r.permesso ? 'yes' : 'no'}</b> — ${esc(r.motivo)}</p><p>Lo stesso controllo dal vero: <code>kubectl auth can-i ${q.verbo} ${risorsa.includes('/') ? risorsa : risorsa}${gruppo ? `.${gruppo}` : ''} -n ${q.namespace} --as=${q.soggetto}</code></p>`;
    };
    box.addEventListener('change', calcola); calcola();
  },

  netpol(box) {
    box.insertAdjacentHTML('beforeend', `<p>La <code>web-allow</code> della lezione 03 protegge i Pod <code>web</code> nel namespace <code>lab</code>, dietro una <code>default-deny-ingress</code>. Cambia la forma del <code>from</code> e il Pod che prova a entrare.</p>
      <div class="campi">
        <fieldset><legend>Forma</legend><label class="riga-check"><input type="radio" name="forma" value="OR" checked> due elementi (OR)</label><label class="riga-check"><input type="radio" name="forma" value="AND"> un elemento, due selettori (AND)</label></fieldset>
      </div>
      <div class="campi">
        <label>Namespace del Pod che chiama<select name="ns"><option>lab</option><option>ingress-nginx</option><option>default</option></select></label>
        <label class="riga-check"><input type="checkbox" name="client" checked> ha la label <code>ruolo: client</code></label>
      </div>
      <div class="repliche"><figure class="codice"><figcaption><span class="codice-nome">OR</span></figcaption><pre><code>ingress:
  - from:
      - podSelector:
          matchLabels: { ruolo: client }
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: ingress-nginx</code></pre></figure>
      <figure class="codice"><figcaption><span class="codice-nome">AND</span> <span class="etichetta">variante illustrativa</span></figcaption><pre><code>ingress:
  - from:
      - podSelector:
          matchLabels: { ruolo: client }
        namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: ingress-nginx</code></pre></figure></div>
      <div class="esito" aria-live="polite"></div>${NOTA}`);
    const calcola = () => {
      const r = S.netpol(val(box, 'forma'), { namespace: val(box, 'ns'), labels: box.querySelector('[name="client"]').checked ? { ruolo: 'client' } : {} });
      const e = box.querySelector('.esito');
      e.className = `esito ${r.ammesso ? 'si' : 'no'}`;
      e.innerHTML = `<p><b class="verdetto">${r.ammesso ? 'AMMESSO' : 'BLOCCATO'}</b> — ${esc(r.motivo)}</p>`;
    };
    box.addEventListener('change', calcola); calcola();
  },

  partition(box) {
    box.insertAdjacentHTML('beforeend', `<p>Lo StatefulSet <code>db</code> della lezione 05 con <code>updateStrategy.rollingUpdate.partition</code>: cambi l'immagine e guardi quali Pod si aggiornano.</p>
      <div class="campi"><label>replicas<input type="number" name="rep" value="3" min="1" max="6"></label><label>partition<input type="number" name="part" value="2" min="0" max="6"></label></div>
      <div class="esito" aria-live="polite"></div>${NOTA}`);
    const calcola = () => {
      const rep = num(box, 'rep'), part = num(box, 'part');
      const r = S.partition(rep, part);
      box.querySelector('.esito').innerHTML = `<div class="pods">${r.pod.map(p => `<span class="pod ${p.revisione}">${p.nome}<small>${p.revisione === 'nuova' ? 'immagine nuova' : 'resta com\'è'}</small></span>`).join('')}</div>
        <p>${r.ordine.length ? `Ordine dell'aggiornamento (dal più alto): <b>${r.ordine.join(' → ')}</b>.` : 'Nessun Pod si aggiorna: partition ≥ replicas.'} ${part > 0 && r.ordine.length ? 'È un canary: abbassa partition per estendere l\'aggiornamento.' : ''}</p>`;
    };
    box.addEventListener('input', calcola); calcola();
  },

  helm(box) {
    let ops = [];
    box.insertAdjacentHTML('beforeend', `<p>La sequenza della lezione 09 sulla release <code>eco</code>: prova i passi nell'ordine dello script o in un altro, e guarda <code>helm history</code>.</p>
      <div class="campi">
        <button type="button" class="btn" data-op="install">helm upgrade --install</button>
        <button type="button" class="btn" data-op="upgrade">upgrade messaggio</button>
        <button type="button" class="btn" data-op="fallito">upgrade image.tag=v9.9.9 --rollback-on-failure</button>
        <label>rollback a<select name="a"></select></label><button type="button" class="btn" data-op="rollback">helm rollback</button>
        <button type="button" class="btn piccolo" data-op="reset">azzera</button>
      </div><div class="esito" aria-live="polite"></div>${NOTA}`);
    const disegna = (err = '') => {
      let storia = [];
      try { storia = S.helm(ops); } catch (e) { ops.pop(); storia = S.helm(ops); err = e.message; }
      box.querySelector('select[name="a"]').innerHTML = storia.map(r => `<option>${r.revisione}</option>`).join('');
      box.querySelector('.esito').innerHTML = (err ? `<p><b>Errore:</b> ${esc(err)}</p>` : '') + (storia.length
        ? `<div class="tabella"><table><thead><tr><th>REVISION</th><th>STATUS</th><th>DESCRIPTION</th><th>valori</th></tr></thead><tbody>${storia.map(r => `<tr><td>${r.revisione}</td><td>${r.stato}</td><td>${esc(r.descrizione)}</td><td><code>${esc(r.valori)}</code></td></tr>`).join('')}</tbody></table></div>`
        : '<p>Nessuna release: parti da <code>helm upgrade --install</code>.</p>');
    };
    let msg = 0;
    box.addEventListener('click', e => {
      const b = e.target.closest('[data-op]');
      if (!b) return;
      const op = b.dataset.op;
      if (op === 'reset') { ops = []; msg = 0; }
      else if (op === 'install') ops.push({ op: 'install', valori: 'messaggio iniziale' });
      else if (op === 'upgrade') ops.push({ op: 'upgrade', valori: ++msg === 1 ? 'seconda versione' : `versione ${msg + 1}` });
      else if (op === 'fallito') ops.push({ op: 'upgrade-fallito', valori: 'image.tag=v9.9.9', rollbackOnFailure: true });
      else if (op === 'rollback') ops.push({ op: 'rollback', a: Number(val(box, 'a')) });
      disegna();
    });
    disegna();
  },

  failover(box) {
    const stato = { A: true, B: true };
    box.insertAdjacentHTML('beforeend', `<p>Due repliche del controller su worker diversi, dietro il Service NodePort. Metti giù A e manda connessioni nuove.</p>
      <div class="campi"><button type="button" class="btn" data-guasto="A" aria-pressed="false">Guasto HAProxy A</button><button type="button" class="btn" data-guasto="B" aria-pressed="false">Guasto HAProxy B</button><button type="button" class="btn primario" data-invia>Invia 6 connessioni nuove</button></div>
      <div class="esito" aria-live="polite"></div>${NOTA}`);
    const disegna = (inviate = null) => {
      const giu = Object.keys(stato).filter(k => !stato[k]);
      document.querySelectorAll('.diagramma .repA').forEach(n => n.classList.toggle('giu', !stato.A));
      document.querySelectorAll('.diagramma .repB').forEach(n => n.classList.toggle('giu', !stato.B));
      box.querySelector('.esito').innerHTML = `<p>Stato: ${['A', 'B'].map(k => `HAProxy ${k} <b>${stato[k] ? 'Ready' : 'non Ready'}</b>`).join(' · ')}</p>
        ${giu.length ? `<p>Quando la readiness di ${giu.join(' e ')} fallisce, il Pod esce dagli endpoint del Service NodePort: le connessioni <b>nuove</b> non ci arrivano più (dopo la propagazione, qualche secondo). Quelle già aperte su quella replica cadono.</p>` : ''}
        ${inviate ? `<div class="celle">${inviate.map((r, i) => `<span class="cella ${r ? 'ok' : 'ko'}">${i + 1}→${r || '✗'}</span>`).join('')}</div>${inviate.every(r => !r) ? '<p>Nessuna replica pronta: il NodePort non ha endpoint, la connessione fallisce.</p>' : ''}` : ''}`;
    };
    box.addEventListener('click', e => {
      const g = e.target.closest('[data-guasto]');
      if (g) { const k = g.dataset.guasto; stato[k] = !stato[k]; g.setAttribute('aria-pressed', String(!stato[k])); g.textContent = stato[k] ? `Guasto HAProxy ${k}` : `Ripristina HAProxy ${k}`; disegna(); }
      if (e.target.closest('[data-invia]')) disegna(S.failover(6, stato));
    });
    disegna();
  },

  ratelimit(box) {
    box.insertAdjacentHTML('beforeend', `<p>L'Ingress <code>limitato</code>: <code>rate-limit-requests: "5"</code>, <code>rate-limit-period: "10s"</code>, poi <code>429</code>. Il conteggio vive nella stick-table <b>di ogni replica</b>.</p>
      <div class="campi">
        <label>Richieste<input type="number" name="n" value="12" min="1" max="40"></label>
        <label>Limite per replica<input type="number" name="lim" value="5" min="1" max="20"></label>
        <label>Repliche HAProxy<input type="number" name="rep" value="2" min="1" max="4"></label>
        <button type="button" class="btn primario" data-vai>12 richieste con limit 5/10 s</button>
      </div><div class="esito" aria-live="polite"></div>
      <p class="nota-sim">Il modello alterna le richieste fra le repliche. Nel laboratorio di origine la distribuzione non era perfetta: su 12 richieste sono passate <b>10 e 9</b> nelle due corse.</p>${NOTA}`);
    const calcola = () => {
      const r = S.rateLimit({ richieste: num(box, 'n'), limite: num(box, 'lim'), repliche: num(box, 'rep') });
      box.querySelector('.esito').innerHTML = `<div class="repliche">${r.perReplica.map(p => `<div class="replica"><h4>HAProxy ${p.replica}</h4><div class="celle">${r.esiti.filter(e => e.replica === p.replica).map(e => `<span class="cella ${e.codice === 200 ? 'ok' : 'ko'}" title="richiesta ${e.richiesta}">${e.richiesta}:${e.codice}</span>`).join('')}</div><small>${p.passate} passate su ${p.viste}</small></div>`).join('')}</div>
        <p><b>${r.passate}</b> risposte 200 su ${num(box, 'n')}: il limite «${num(box, 'lim')} ogni 10 s» visto dal client vale fino a ${num(box, 'lim')} × ${num(box, 'rep')} = ${num(box, 'lim') * num(box, 'rep')}, perché le stick-table non sono condivise.</p>`;
    };
    box.addEventListener('click', e => { if (e.target.closest('[data-vai]')) { box.querySelector('[name="n"]').value = 12; box.querySelector('[name="lim"]').value = 5; calcola(); } });
    box.addEventListener('input', calcola); calcola();
  },

  bilancia(box) {
    box.insertAdjacentHTML('beforeend', `<p>Due server nel backend. Arriva prima una connessione <b>lunga</b> (durata 10), poi connessioni brevi (durata 1), una per istante.</p>
      <div class="campi"><fieldset><legend>Algoritmo</legend><label class="riga-check"><input type="radio" name="alg" value="roundrobin" checked> roundrobin (Service blu)</label><label class="riga-check"><input type="radio" name="alg" value="leastconn"> leastconn (Service verde)</label></fieldset></div>
      <div class="esito" aria-live="polite"></div>${NOTA}`);
    const RICH = [{ durata: 10 }, ...Array.from({ length: 7 }, () => ({ durata: 1 }))];
    const calcola = () => {
      const r = S.bilancia(val(box, 'alg'), RICH, 2);
      const mx = [0, 1].map(s => Math.max(...r.map(x => x.attive[s])));
      box.querySelector('.esito').innerHTML = `<div class="tabella"><table><thead><tr><th>richiesta</th><th>durata</th><th>va a</th><th>attive dopo (srv1 / srv2)</th></tr></thead><tbody>${r.map((x, i) => `<tr><td>${x.richiesta}</td><td>${RICH[i].durata}</td><td>srv${x.server + 1}</td><td>${x.attive.join(' / ')}</td></tr>`).join('')}</tbody></table></div>
        <p>Massimo di connessioni contemporanee: srv1 ${mx[0]}, srv2 ${mx[1]}. ${val(box, 'alg') === 'roundrobin' ? 'roundrobin manda a turno anche sul server ancora occupato dalla connessione lunga.' : 'leastconn guarda le connessioni aperte e lascia in pace il server occupato.'}</p>`;
    };
    box.addEventListener('change', calcola); calcola();
  },
  tls(box) {
    box.insertAdjacentHTML('beforeend', `<p>Il file <code>haproxy.cfg</code> del negozio dell'approfondimento: scegli il frontend in ascolto sulla 443 (<code>fe_https</code> oppure l'alternativa <code>fe_passthrough</code>) e la richiesta del client.</p>
      <div class="campi">
        <fieldset><legend>Frontend sulla 443</legend><label class="riga-check"><input type="radio" name="fe" value="fe_https" checked> fe_https (decifra)</label><label class="riga-check"><input type="radio" name="fe" value="fe_passthrough"> fe_passthrough (mode tcp)</label></fieldset>
        <label>Porta<select name="porta"><option>443</option><option>80</option></select></label>
        <label>SNI (handshake)<input type="text" name="sni" value="www.negozio.it" spellcheck="false"></label>
        <label>Host (header HTTP)<input type="text" name="host" value="www.negozio.it" spellcheck="false"></label>
        <label>Path<input type="text" name="path" value="/api/ordini" spellcheck="false"></label>
      </div><div class="esito" aria-live="polite"></div>${NOTA}`);
    const t = n => box.querySelector(`[name="${n}"]`).value.trim();
    const calcola = () => {
      const r = S.tlsInstrada({ frontend: val(box, 'fe'), porta: t('porta'), sni: t('sni'), host: t('host'), path: t('path') });
      const v = (k, etichetta) => `<li>${etichetta}: <b>${r.vede[k] ? 'leggibile' : 'cifrato, invisibile'}</b></li>`;
      box.querySelector('.esito').innerHTML = r.backend === null
        ? `<p><code>${r.frontend}</code> (<code>bind :80</code>): <b class="verdetto">${esc(r.esito)}</b>. Nessun backend: il client ripete la richiesta in HTTPS sulla 443.</p>`
        : `<p><code>${esc(r.frontend)}</code> → <b class="verdetto">${esc(r.backend)}</b> · modalità <b>${esc(r.modalita)}</b></p>
          <p>Regola che scatta: <code>${esc(r.regola)}</code></p>
          <ul>${v('sni', 'SNI')}${v('host', 'Host')}${v('path', 'Path')}${v('header', 'Header e cookie')}</ul>
          <p>Verso i server: ${esc(r.versoServer)} · chiave privata: ${esc(r.chiave)} · ${esc(r.esito)}.</p>`;
    };
    box.addEventListener('input', calcola); box.addEventListener('change', calcola); calcola();
  },

  'count-foreach'(box) {
    box.insertAdjacentHTML('beforeend', `<p>La domanda «quasi certa» della parte 02: tre servizi <code>a</code>, <code>b</code>, <code>c</code>. Scrivi l'elenco nuovo e confronta il plan con <code>count</code> e con <code>for_each</code>.</p>
      <div class="campi">
        <label>Prima<input type="text" name="prima" value="a, b, c" spellcheck="false"></label>
        <label>Dopo<input type="text" name="dopo" value="a, c" spellcheck="false"></label>
      </div><div class="esito" aria-live="polite"></div>${NOTA}`);
    const lista = n => [...new Set(box.querySelector(`[name="${n}"]`).value.split(/[\s,]+/).filter(Boolean))];
    const CLS = { nessuna: '', crea: 'si', distrugge: 'no', 'aggiorna/ricrea': 'no' };
    const tabella = modo => {
      const r = S.countForEach(modo, lista('prima'), lista('dopo'));
      const toccate = r.filter(x => x.azione !== 'nessuna').length;
      return `<div><h4><code>${modo}</code> · ${toccate} ${toccate === 1 ? 'risorsa toccata' : 'risorse toccate'}</h4><div class="tabella"><table><thead><tr><th>indirizzo</th><th>prima</th><th>dopo</th><th>plan</th></tr></thead><tbody>${r.map(x => `<tr class="${CLS[x.azione]}"><td><code>${esc(x.indirizzo)}</code></td><td>${esc(x.prima ?? '—')}</td><td>${esc(x.dopo ?? '—')}</td><td>${esc(x.azione)}</td></tr>`).join('')}</tbody></table></div></div>`;
    };
    const calcola = () => {
      box.querySelector('.esito').innerHTML = `${tabella('count')}${tabella('for_each')}<p>Con <code>count</code> l'indice è la posizione: togliere un elemento in mezzo fa scalare quelli dopo. Con <code>for_each</code> l'indice è la chiave: cambia solo ciò che hai tolto o aggiunto.</p>`;
    };
    box.addEventListener('input', calcola); calcola();
  },

  precedenza(box) {
    box.insertAdjacentHTML('beforeend', `<p>La variabile <code>ambiente</code> della parte 02 può arrivare da sei posti. Riempi quelli che vuoi: vince l'ultima fonte definita, nell'ordine dall'alto in basso.</p>
      <div class="campi">${S.FONTI_VARIABILI.map(([k, etichetta]) => `<label>${esc(etichetta)}<input type="text" name="${k}" value="${k === 'default' ? 'dev' : ''}" spellcheck="false"></label>`).join('')}</div>
      <div class="esito" aria-live="polite"></div>${NOTA}`);
    const calcola = () => {
      const valori = Object.fromEntries(S.FONTI_VARIABILI.map(([k]) => [k, box.querySelector(`[name="${k}"]`).value.trim()]));
      const r = S.precedenza(valori);
      const nome = Object.fromEntries(S.FONTI_VARIABILI)[r.fonte];
      box.querySelector('.esito').innerHTML = r.fonte
        ? `<p><code>var.ambiente</code> = <b class="verdetto">${esc(r.valore)}</b>, da <b>${esc(nome)}</b>.</p>`
        : '<p>Nessun valore: senza <code>default</code> Terraform lo chiede in modo interattivo, o fallisce in CI.</p>';
    };
    box.addEventListener('input', calcola); calcola();
  },

  rolling(box) {
    box.insertAdjacentHTML('beforeend', `<p>Il play della parte 09: <code>order: sorted</code>, versione da 1.0 a 2.0, il bilanciatore finto su <code>db1</code>. Scegli quanti server web, i lotti, la soglia e chi si rompe.</p>
      <div class="campi">
        <label>Server web<input type="number" name="n" value="2" min="2" max="8"></label>
        <label>serial<input type="text" name="serial" value="1" spellcheck="false"></label>
        <label>max_fail_percentage<input type="number" name="max" value="0" min="0" max="100"></label>
        <fieldset><legend>Si rompe (rompi)</legend><div class="rotti"></div></fieldset>
      </div><div class="esito" aria-live="polite"></div>
      <p class="nota-sim">Come nel playbook, ogni lotto riprepara il registro con tutti gli host del play: un host fallito in un lotto precedente ci rientra senza essere verificato (la trappola descritta nella parte 09).</p>${NOTA}`);
    const rotti = new Set(['web2']);
    const disegnaRotti = () => {
      box.querySelector('.rotti').innerHTML = Array.from({ length: num(box, 'n') }, (_, i) => `web${i + 1}`)
        .map(h => `<label class="riga-check"><input type="checkbox" name="rotto" value="${h}"${rotti.has(h) ? ' checked' : ''}> ${h}</label>`).join('');
    };
    const ETI = { ok: 'aggiornato e verificato', fallito: 'verifica fallita', 'non toccato': 'non toccato' };
    const calcola = () => {
      const host = Array.from({ length: num(box, 'n') }, (_, i) => `web${i + 1}`);
      const serial = box.querySelector('[name="serial"]').value.trim() || '1';
      const r = S.rolling({ host, serial, maxFail: num(box, 'max'), rotti: [...rotti].filter(h => host.includes(h)) });
      box.querySelector('.esito').innerHTML = `<div class="tabella"><table><thead><tr><th>lotto</th><th>host</th><th>esito</th></tr></thead><tbody>${r.lotti.flatMap(l => l.esiti.map((e, i) => `<tr class="${e.esito === 'ok' ? 'si' : e.esito === 'fallito' ? 'no' : ''}"><td>${i ? '' : l.n}</td><td>${esc(e.host)}</td><td>${ETI[e.esito]}</td></tr>`)).join('')}</tbody></table></div>
        <p>${r.fermato ? `<b class="verdetto">Play fermato al lotto ${r.fermato}</b>: i falliti hanno superato il ${num(box, 'max')}% del lotto, i lotti dopo non partono.` : '<b class="verdetto">Play arrivato in fondo.</b>'}</p>
        <p>In <code>/etc/lb/backends</code> su db1: <b>${r.bilanciatore.map(esc).join(', ') || 'nessuno'}</b>. Versioni: ${host.map(h => `${esc(h)} ${esc(r.versioni[h])}`).join(' · ')}.${r.rientrati.length ? ` Rientrati senza verifica: <b>${r.rientrati.map(esc).join(', ')}</b>.` : ''}</p>`;
    };
    box.addEventListener('change', e => {
      if (e.target.name === 'rotto') { e.target.checked ? rotti.add(e.target.value) : rotti.delete(e.target.value); }
      if (e.target.name === 'n') disegnaRotti();
      calcola();
    });
    box.addEventListener('input', e => { if (e.target.name !== 'rotto') { if (e.target.name === 'n') disegnaRotti(); calcola(); } });
    disegnaRotti(); calcola();
  },

  'precedenza-ansible'(box) {
    box.insertAdjacentHTML('beforeend', `<p>La porta <code>sito_porta</code> del ruolo della parte 08 può arrivare da otto posti (i più usati dei 22 livelli). Riempi quelli che vuoi: vince il più in basso.</p>
      <div class="campi">${S.FONTI_ANSIBLE.map(([k, etichetta]) => `<label>${esc(etichetta)}<input type="text" name="${k}" value="${k === 'defaults' ? '8080' : ''}" spellcheck="false"></label>`).join('')}</div>
      <div class="esito" aria-live="polite"></div>${NOTA}`);
    const calcola = () => {
      const valori = Object.fromEntries(S.FONTI_ANSIBLE.map(([k]) => [k, box.querySelector(`[name="${k}"]`).value.trim()]));
      const r = S.precedenza(valori, S.FONTI_ANSIBLE);
      const nome = Object.fromEntries(S.FONTI_ANSIBLE)[r.fonte];
      box.querySelector('.esito').innerHTML = r.fonte
        ? `<p><code>sito_porta</code> = <b class="verdetto">${esc(r.valore)}</b>, da <b>${esc(nome)}</b>.${r.fonte === 'roleVars' && valori.group ? ' Ecco perché un parametro non va in <code>vars/</code>: il group_vars non lo cambia più.' : ''}</p>`
        : `<p>Nessun valore: il template del ruolo fallirebbe con «'sito_porta' is undefined». Per questo i parametri hanno un default.</p>`;
    };
    box.addEventListener('input', calcola); calcola();
  },
};

export function avviaSimulazioni() {
  document.querySelectorAll('[data-sim]').forEach(box => {
    const f = SIM[box.dataset.sim];
    if (f) { box.querySelector('noscript')?.remove(); f(box); }
  });
}
