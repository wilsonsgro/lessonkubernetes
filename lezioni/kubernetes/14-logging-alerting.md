# 14 — Logging e alerting: Loki, Alloy, LogQL, Alertmanager, SLO burn rate

Spiegazione di `14-logging-alerting.yaml` (questa cartella). Lezione sul sito: http://127.0.0.1:3000/kubernetes/14

## In una frase

Nella lezione 13 lo stack lo montava l'operator; qui **ogni pezzo è scritto a mano**, in un solo namespace
`logalert`: un'app `pagamenti` che scrive **log JSON** ed espone una metrica, **Alloy** che raccoglie i log, **Loki** che
li conserva (con un ruler che fa alert sui log), **Prometheus** con alert di **burn rate** multiwindow,
**Alertmanager** con instradamento, **inibizione** e **silence**, e un **ricevitore webhook finto** al posto di
PagerDuty/Slack. Poi si alzano gli errori al 5% e si segue il percorso dell'alert fino al "pager".

## Due file con lo stesso nome: quale lanciare

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/lezioni/kubernetes/14-logging-alerting.yaml` | **questo**: tutti i manifest del laboratorio, con la teoria e i risultati misurati nei commenti | si legge; si applica con `kubectl apply -f 14-logging-alerting.yaml` (lo fa il guidato) |
| `~/kubernetesprj/kubernetes/14-logging-alerting.sh` | lo script **guidato**: applica il file, interroga Loki, alza gli errori, prova Alertmanager con amtool (Invio / s / q) | `bash kubernetes/14-logging-alerting.sh` |

Per imparare conviene lo **guidato**. Non serve kube-prometheus-stack: qui c'è tutto. Come dice il file: **mai sul
contesto di produzione** (`test "$(kubectl config current-context)" = lab || exit 1`).

## Com'è fatto il file

```
intestazione (commenti)       → schema dei flussi, Loki, LogQL, Alloy, Alertmanager, SLO e burn rate, LAB con risultati, NEL PROGETTO VERO
Namespace logalert
pagamenti   ConfigMap (app.py) + Deployment + Service      → l'app che scrive log e metriche
loki        ConfigMap (loki.yaml + regole-log.yaml) + Deployment + Service
alloy       ServiceAccount + Role + RoleBinding + ConfigMap (config.alloy) + Deployment
prometheus  ConfigMap (prometheus.yml + slo.yml) + Deployment + Service
alertmanager ConfigMap (alertmanager.yml) + Deployment + Service
ricevitore  ConfigMap (ricevitore.py) + Deployment + Service   → il finto pager
coda (commenti)               → domande da colloquio, riepilogo
```

Versioni: **Loki 3.7 · Alloy 1.21 · Prometheus 3.15 · Alertmanager 0.34**. Livello 5 "Produzione".

---

## 1. La teoria nell'intestazione

### I flussi

```
pod ──stdout──▶ Alloy ──push──▶ Loki ◀── LogQL (Grafana, ruler)
pod ──/metrics◀── Prometheus ──regole──▶ Alertmanager ──▶ pager / ticket
                                 Loki ruler ──┘
```

I **log** vanno in **push** (Alloy li spinge a Loki); le **metriche** in **pull** (Prometheus le va a prendere). Gli
alert arrivano ad Alertmanager da **due** sorgenti: Prometheus e il ruler di Loki.

### Loki indicizza solo le label

Loki indicizza **solo le label** (namespace, app, pod, level), **non il testo**: il contenuto si filtra al momento
della query. Conseguenze:

- label **poche e a bassa cardinalità**. `trace_id`, `user_id`, `path` come label = milioni di stream, ingester senza
  memoria. Restano nel testo e si estraggono con `| json` al momento della query;
- una query parte sempre da un **selettore stretto** `{app="x"}`: è quello che decide quanti chunk leggere.

### LogQL

| Query | Tipo |
|---|---|
| `{app="pagamenti"} \|= "ERROR"` | filtro di riga (veloce) |
| `{app="pagamenti"} \| json \| durata_ms > 800` | parser + filtro su un campo |
| `{app="pagamenti"} \| json \| line_format "{{.trace_id}} {{.msg}}"` | riformatta la riga |
| `sum by (level) (count_over_time({app="pagamenti"} \| json \| __error__="" [1m]))` | query **metrica**: righe per livello |
| `topk(3, sum by (msg) (rate({app="pagamenti"} \| json \| level="ERROR" [5m])))` | i 3 messaggi d'errore più frequenti |

`__error__=""` scarta le righe che il parser non capisce. Senza, **una** riga non JSON (per esempio troncata durante un
rollout) fa fallire tutta la query con `JSONParserErr`: nel file è segnato come **successo davvero**.

### Alloy

Successore di Promtail e Grafana Agent: una **pipeline di componenti**. Qui legge i log **dall'API di Kubernetes**
(`loki.source.kubernetes`), senza montare `/var/log` del nodo. In produzione si usa un **DaemonSet** con
`loki.source.file` su `/var/log/pods`, che non pesa sull'API server.

### Alertmanager: Prometheus valuta, Alertmanager decide CHI e QUANDO

| Concetto | Cosa fa |
|---|---|
| `route` | un albero: vince il **primo figlio** che fa match (`continue` per proseguire). `group_by` riunisce gli alert in **una** notifica |
| `group_wait` | quanto aspettare altri alert dello stesso gruppo (10-30 s) |
| `group_interval` | ogni quanto mandare le novità di un gruppo già notificato |
| `repeat_interval` | ogni quanto ripetere un alert ancora attivo (ore) |
| `inhibit_rules` | se c'è il page per un servizio, i ticket dello stesso servizio tacciono: **una causa, una sveglia** |
| `silences` | a tempo, da UI o amtool, per le manutenzioni |

### SLO e burn rate (Google SRE workbook)

- SLO 99,9% su 30 giorni → **budget d'errore 0,1%**.
- **Burn rate** = errori osservati / 0,001. A burn rate 1 il budget finisce in 30 giorni; a **14,4** se ne va il **2%
  del budget in un'ora**.
- Alert **multiwindow**: finestra lunga per la significatività, finestra corta per **smettere di suonare** appena il
  problema finisce.

| Severità | Condizione | Significato |
|---|---|---|
| **page** | burn > 14,4 su **1h E 5m** | 2% del budget in 1 ora |
| **ticket** | burn > 6 su **6h E 30m** | 5% del budget in 6 ore |

Allerta sui **sintomi** degli utenti, non sulle cause (CPU al 90%).

### Riquadro «NEL PROGETTO VERO»

In `~/biodistretto/kubernetes` HAProxy scrive i log su **stdout** in formato `tcplog`, e si leggono con
`docker logs biodistretto-haproxy`. nginx riceve il **PROXY protocol**, quindi nei suoi log c'è l'**IP vero del
client** e non quello del nodo: va saputo per gli alert sugli IP.

```bash
cd ~/biodistretto/kubernetes
grep -n -E 'log stdout|option tcplog' ansible/roles/haproxy/templates/haproxy.cfg.j2
grep -n 'real_ip_header' terraform/app/nginx/www.conf.tftpl
kubectl --context biodistretto -n biodistretto logs deploy/nginx --tail=5
```

Se Alloy/Loki leggessero questi log, il campo da usare è quello, non l'indirizzo sorgente del Pod.

---

## 2. I manifest, uno per uno

### `pagamenti` — l'app che produce i segnali

La **ConfigMap `pagamenti`** contiene `app.py`, uno script Python con due parti:

- un **thread** `traffico()` che ogni **0,1 s** (circa 10 righe al secondo) decide se la "richiesta" è un errore
  (`random.random() < ERRORI`) e stampa su stdout una riga JSON:

  | Campo | Normale | Errore |
  |---|---|---|
  | `level` | `INFO` | `ERROR` |
  | `msg` | `pagamento ok` | `gateway carte non risponde` |
  | `status` | 200 | 500 |
  | `durata_ms` | 20-200 | 900-1500 |
  | `trace_id` | 16 caratteri esadecimali casuali | idem |

  e incrementa il contatore `conteggi["200"]` o `conteggi["500"]`;
- un **server HTTP** sulla 8080 che a ogni GET risponde con il formato testuale di Prometheus:
  `# TYPE http_requests_total counter` e una riga `http_requests_total{code="200"}` / `{code="500"}`.

`flush=True` nella `print` è importante: senza, Python bufferizza lo stdout e i log arrivano a blocchi.

Il **Deployment `pagamenti`**: 1 replica, immagine `python:3.13-alpine`, `command: [python, /app/app.py]`, variabile
`ERRORI` a `"0"`, la ConfigMap montata in `/app`. Nessuna immagine da costruire: il codice arriva dalla ConfigMap. Il
**Service `pagamenti`** espone la 8080 (lo usa Prometheus).

### `loki` — binario unico su filesystem

`loki.yaml` (nella ConfigMap `loki`):

| Campo | Valore | Perché |
|---|---|---|
| `auth_enabled` | `false` | niente multi-tenant: Loki usa un tenant fisso, `fake` |
| `server.http_listen_port` | `3100` | |
| `common` | `path_prefix: /loki`, `replication_factor: 1`, ring `inmemory`, storage `filesystem` (`/loki/chunks`, `/loki/rules`) | tutto in un processo, niente object storage né ring distribuito |
| `schema_config` | dal `2024-01-01`, `store: tsdb`, `schema: v13`, indice ogni `24h` | lo schema attuale consigliato |
| `limits_config.retention_period` | `72h` | |
| `ruler` | `alertmanager_url: http://alertmanager:9093`, `enable_api: true`, `evaluation_interval: 30s`, storage `local` in `/etc/loki/rules` | il **ruler** valuta regole LogQL e manda gli alert ad Alertmanager |

`regole-log.yaml` contiene un alert **sui log**:

```yaml
- alert: ErroriNeiLog
  expr: sum by (app) (count_over_time({namespace="logalert"} | json | level="ERROR" [1m])) > 5
  for: 1m
  labels: {severity: ticket, servizio: pagamenti}
```

Più di 5 righe ERROR al minuto per un minuto → ticket. La label `servizio: pagamenti` serve all'**inibizione** (vedi
Alertmanager).

Il **Deployment `loki`**: immagine `grafana/loki:3.7.9`, `args: [-config.file=/etc/loki/loki.yaml, -target=all]`
(`all` = tutti i componenti in un processo), `securityContext.fsGroup: 10001` (così Loki, che non gira come root, può
scrivere nel volume). I volumi:

| Mount | Da dove |
|---|---|
| `/etc/loki/loki.yaml` (`subPath: loki.yaml`) | la ConfigMap |
| `/etc/loki/rules/fake/regole-log.yaml` (`subPath: regole-log.yaml`) | la ConfigMap: la cartella `fake` è quella del tenant |
| `/loki` | un `emptyDir`: i dati spariscono con il Pod (va bene per un lab) |

### `alloy` — la raccolta dei log

**RBAC**: ServiceAccount `alloy`, Role `alloy` con `get, list, watch` su `pods` e `pods/log` nel namespace `logalert`,
RoleBinding fra i due (lezione 07). Alloy legge i log **via API**, quindi gli serve proprio `pods/log`.

**`config.alloy`** è una catena di componenti; ognuno passa l'uscita al successivo:

| Componente | Cosa fa |
|---|---|
| `discovery.kubernetes "pod"` | trova i Pod (`role = "pod"`) del namespace `logalert` |
| `discovery.relabel "pod"` | tiene solo i Pod con label `app=pagamenti` (`action = "keep"`) e crea le label `namespace`, `pod`, `app`, `container` dai metadati `__meta_kubernetes_*` |
| `loki.source.kubernetes "pod"` | legge i log di quei Pod **dall'API** e li inoltra |
| `loki.process "json"` | `stage.json` estrae il campo `level` dalla riga; `stage.labels` lo promuove a **label** |
| `loki.write "loki"` | push verso `http://loki:3100/loki/api/v1/push` |

Solo `level` diventa label: ha **pochi valori** (INFO, ERROR). `trace_id` resta nel testo.

Il **Deployment `alloy`**: immagine `grafana/alloy:v1.21.3`, `serviceAccountName: alloy`,
`args: [run, /etc/alloy/config.alloy, --storage.path=/tmp/alloy]`, ConfigMap montata in `/etc/alloy`.

### `prometheus` — SLI, burn rate, alert

`prometheus.yml`:

| Campo | Valore | Perché |
|---|---|---|
| `scrape_interval` / `evaluation_interval` | `5s` | molto stretti, per vedere tutto in pochi minuti (in produzione si usa di più) |
| `alerting.alertmanagers` | `alertmanager:9093` | dove mandare gli alert |
| `rule_files` | `/etc/prometheus/slo.yml` | le regole |
| `scrape_configs` | job `pagamenti`, target statico `pagamenti:8080`, label `servizio: pagamenti` | niente operator, niente ServiceMonitor: config scritta a mano. La label `servizio` arriva su tutte le serie |

`slo.yml`, gruppo `slo-pagamenti`:

- **4 recording rule** `servizio:errori:ratio_rate5m`, `…30m`, `…1h`, `…6h`: per ogni finestra, la frazione di
  richieste `code=~"5.."` sul totale, per servizio. Qui gli errori sono **`5..`**, come va fatto in produzione (l'app di
  questa lezione risponde davvero 500, a differenza di quella della 13).
- **`BudgetErroriVeloce`**: `ratio_rate1h > 14.4 * 0.001` **and** `ratio_rate5m > 14.4 * 0.001`, `for: 1m`,
  `severity: page`, con `summary` e `runbook_url`.
- **`BudgetErroriLento`**: `ratio_rate6h > 6 * 0.001` **and** `ratio_rate30m > 6 * 0.001`, `for: 1m`,
  `severity: ticket`.

Il **Deployment `prometheus`**: immagine `prom/prometheus:v3.15.1`, `--config.file=/etc/prometheus/prometheus.yml`,
ConfigMap montata intera in `/etc/prometheus`; Service sulla 9090.

### `alertmanager` — chi riceve cosa

```yaml
route:
  receiver: ticket
  group_by: [alertname, servizio]
  group_wait: 10s
  group_interval: 1m
  repeat_interval: 4h
  routes:
    - matchers: [severity="page"]
      receiver: pager
      group_wait: 0s
inhibit_rules:
  - source_matchers: [severity="page"]
    target_matchers: [severity="ticket"]
    equal: [servizio]
receivers:
  - name: pager
    webhook_configs: [{url: "http://ricevitore:8080/pager", send_resolved: true}]
  - name: ticket
    webhook_configs: [{url: "http://ricevitore:8080/ticket", send_resolved: true}]
```

| Pezzo | Cosa fa |
|---|---|
| radice → `ticket` | tutto quello che non fa match con un figlio va ai ticket |
| figlio `severity="page"` → `pager`, `group_wait: 0s` | il page parte **subito**, senza aspettare altri alert |
| `group_by: [alertname, servizio]` | una notifica per ogni coppia alert + servizio |
| `inhibit_rules` | se c'è un alert `page` attivo, gli alert `ticket` **con lo stesso `servizio`** vengono soppressi |
| `send_resolved: true` | il ricevitore viene avvisato anche quando l'alert si risolve |

Il **Deployment `alertmanager`**: immagine `prom/alertmanager:v0.34.2`, config in
`/etc/alertmanager/alertmanager.yml`, Service sulla 9093. L'immagine contiene anche **`amtool`**, che il guidato usa con
`kubectl exec`.

### `ricevitore` — il finto pager

Un server Python (`python:3.13-alpine`, codice dalla ConfigMap) che a ogni POST legge il JSON di Alertmanager e stampa
una riga: **path, stato, nomi degli alert**, per esempio `/pager firing BudgetErroriVeloce`. Al posto di
PagerDuty/Slack: le notifiche si leggono con `kubectl logs`.

---

## 3. Il percorso del guidato, passo per passo

Il guidato definisce due funzioni:

```bash
Q()  { kubectl -n logalert run "q$RANDOM" --rm -i --restart=Never --quiet --image=curlimages/curl:8.23.0 \
         -- curl -s -G "http://loki:3100/loki/api/v1/$1" --data-urlencode "query=$2"; echo; }
AM() { kubectl -n logalert exec deploy/alertmanager -- amtool --alertmanager.url=http://localhost:9093 "$@"; }
```

`Q` interroga Loki **da dentro il cluster** con un Pod curl usa e getta (nome casuale `q$RANDOM`); `-G` +
`--data-urlencode` codificano `{ }` e `[ ]` della query nell'URL. `AM` esegue amtool dentro il Pod di Alertmanager.

| # | Comando | Cosa vedi |
|---|---|---|
| 1 | `kubectl apply -f $F` | tutto il laboratorio nel namespace `logalert` |
| 2 | `kubectl -n logalert rollout status deploy/loki deploy/alloy deploy/prometheus deploy/alertmanager deploy/ricevitore deploy/pagamenti --timeout=5m` | aspetta che tutti e sei i Deployment siano pronti |
| 3 | `kubectl -n logalert logs deploy/pagamenti --tail=3` | righe JSON con `level`, `msg`, `trace_id`. Alloy le legge dall'API e le manda a Loki |
| 4 | ciclo fino a 12 × 5 s su `Q labels ''`, poi `Q labels ''` | le label che Loki conosce (aspetta che Alloy abbia mandato i primi log). Misurato nel file: `app, container, instance, job, level, namespace, pod, service_name` (l'ultima la aggiunge Loki 3). **Niente `trace_id`** |
| 5 | `kubectl -n logalert set env deploy/pagamenti ERRORI=0.05 && … rollout status` | errori al **5%**, cioè **50 volte** il budget di uno SLO al 99,9%. Cambia l'env → nuovo Pod |
| 6 | `sleep 30; Q query_range '{app="pagamenti"} \| json \| level="ERROR" \| line_format "{{.trace_id}} {{.msg}}"' \| jq … \| head -5` | **filtro + parser**: solo le righe ERROR, riformattate. Si cerca **dentro la riga**, non nelle label. Misurato: `374659034d185343 gateway carte non risponde` |
| 7 | `Q query 'sum by (level) (count_over_time({app="pagamenti"} \| json \| __error__="" [1m]))' \| jq …` | **query metrica**: righe per livello nell'ultimo minuto. Misurato: `ERROR 31`, `INFO 563` (circa il 5%) |
| 8 | `kubectl -n logalert exec deploy/alertmanager -- amtool config routes test --config.file=/etc/alertmanager/alertmanager.yml severity=page` | instradamento **senza alert veri**: risponde `pager` |
| 9 | `sleep 120; AM alert query` | dopo ~2 minuti di errori: `BudgetErroriVeloce` (page) **active**; i ticket (`BudgetErroriLento` e `ErroriNeiLog` del ruler di Loki) **suppressed**, perché inibiti dal page |
| 10 | `kubectl -n logalert logs deploy/ricevitore --tail=5` | cosa ha ricevuto il webhook: `/pager firing …` |
| 11 | `AM silence add alertname=BudgetErroriVeloce --duration=15m --comment=manutenzione && AM silence query` | **silence** di 15 minuti per manutenzione: il page tace (diventa suppressed) |
| 12 | `AM alert query --silenced --inhibited` | i ticket **restano inibiti**: un alert silenziato **continua a inibire** gli altri |
| 13 | `kubectl -n logalert set env deploy/pagamenti ERRORI=0` | fine degli errori |

Nota finale del guidato: rilancia `kubectl -n logalert exec deploy/alertmanager -- amtool --alertmanager.url=http://localhost:9093 alert query`
fra qualche minuto. Misurato nel file: il page si **risolve dopo ~3,5 minuti** (la finestra da 5m si svuota), e
**subito dopo** `BudgetErroriLento` diventa **active** e arriva a `/ticket`. Tolta l'inibizione resta il "debito" della
finestra lunga (6h), che è giusto seguire di giorno, non di notte. Pulizia: `kubectl delete ns logalert`.

### La prova del rosso: cardinalità (solo nel file, non nel guidato)

Aggiungi `trace_id` a `stage.json` **e** a `stage.labels` in Alloy: ogni riga diventa uno **stream nuovo**. Misurato:
Loki risponde **429 `maximum active stream limit exceeded`** e rifiuta il **batch intero**, quindi non arriva più
nessuna riga, nemmeno quelle normali (serie negli ultimi 30 s: 0). Tolta la label, i log tornano.

---

## 4. Le trappole

- **Label ad alta cardinalità in Loki** (`trace_id`, `user_id`, `path`): non solo memoria, ma batch rifiutati interi
  (429) e log persi.
- **`| json` senza `__error__=""`** in una query metrica: una riga rotta fa fallire tutto.
- **Una sola finestra nel burn rate**: solo 1h = l'alert resta acceso un'ora dopo la fine; solo 5m = suona per ogni
  picco.
- **Silence non ferma l'inibizione**: un page silenziato continua a zittire i ticket dello stesso servizio.
- **`equal: [servizio]`** nell'inibizione: senza la stessa label su sorgente e bersaglio non inibisce niente. Per questo
  anche `ErroriNeiLog` del ruler porta `servizio: pagamenti`.
- **`loki.source.kubernetes` pesa sull'API server**: va bene per un lab, in produzione DaemonSet + `loki.source.file`.
- **File montati con `subPath`** (qui la config di Loki): se cambi la ConfigMap, il file nel Pod **non si aggiorna**;
  serve riavviare il Pod.
- **Dati in `emptyDir`**: un restart di Loki perde i log.

---

## 5. Comandi e domande da colloquio

### Comandi da sapere

| Comando | A cosa serve |
|---|---|
| `curl -s -G http://loki:3100/loki/api/v1/labels` | le label note a Loki |
| `curl -s -G …/query_range --data-urlencode 'query=…'` | righe di log in un intervallo |
| `curl -s -G …/query --data-urlencode 'query=…'` | query metrica istantanea |
| `amtool config routes test --config.file=… severity=page` | dove va un alert, senza alert veri |
| `amtool --alertmanager.url=http://localhost:9093 alert query [--silenced --inhibited]` | alert attivi, silenziati, inibiti |
| `amtool … silence add alertname=X --duration=15m --comment=…` / `silence query` | silence per manutenzione |
| `kubectl set env deploy/X VAR=valore` | cambia una variabile e fa partire un rollout |

### Domande

- **Loki o Elasticsearch?** Loki indicizza solo le label: costa poco in storage e RAM, le query sul testo scansionano
  i chunk (veloci se il selettore è stretto). Elasticsearch indicizza tutto il testo: ricerca libera rapida e
  aggregazioni ricche, ma costa molto di più. Log per il debug → Loki; analisi full-text, SIEM → Elastic/OpenSearch.
- **Arrivano 200 alert alle 3 di notte. Cosa sistemi?** `group_by` per servizio/cluster (una notifica, non 200),
  `inhibit_rules` (il servizio giù zittisce i suoi sintomi), alert sui sintomi via SLO invece che sulle cause, `for:`
  per i picchi brevi, severità diverse: solo il page sveglia, il ticket aspetta la mattina.
- **Perché due finestre nel burn rate?** Solo 1h: dopo che il problema è risolto l'alert resta acceso per un'ora.
  Solo 5m: suona per ogni picco. Le due insieme (AND): significativo **e** si spegne in pochi minuti quando gli errori
  finiscono.
- **Un alert che non suona mai: come sai che funziona?** Si prova: `promtool test rules` con serie sintetiche,
  `amtool config routes test` per l'instradamento, e un alert **Watchdog** sempre acceso che deve arrivare: se smette
  di arrivare è la pipeline di alert rotta.
- **Log in JSON: perché?** Campi estraibili (`| json`) senza regex fragili, livelli come label, `trace_id` per saltare
  dalla riga di log alla traccia.

---

## Riepilogo

- Loki: label poche e a bassa cardinalità, il resto nel testo (`| json`).
- LogQL: selettore stretto, filtri di riga, parser, query metriche (con `__error__=""`).
- Alloy: discovery → relabel → source → process → write.
- Alertmanager: route/`group_by`, `group_wait`/`group_interval`/`repeat_interval`, inhibit, silences.
- SLO: burn rate multiwindow (14,4 su 1h+5m → page; 6 su 6h+30m → ticket).

## Prova da solo

1. Con `ERRORI=0.05` attivo, scrivi con `Q query_range` la query del file
   `{app="pagamenti"} | json | durata_ms > 800`: che livello hanno le righe che escono, e perché (guarda come `app.py`
   sceglie `durata_ms`)?
2. Lancia `kubectl -n logalert exec deploy/alertmanager -- amtool config routes test --config.file=/etc/alertmanager/alertmanager.yml severity=ticket`
   e poi senza alcuna label: dove finiscono? Quale riga della `route` lo decide?
3. Con il page attivo, togli la silence (`AM silence expire <id>`, l'id lo dà `AM silence query`) e confronta
   `AM alert query --silenced --inhibited` prima e dopo: cambia qualcosa per i ticket? Poi rimetti `ERRORI=0` e
   misura quanto ci mette il page a risolversi rispetto ai ~3,5 minuti del file.
