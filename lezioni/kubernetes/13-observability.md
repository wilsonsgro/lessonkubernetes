# 13 — Observability: metriche, log e alert con Prometheus su Kubernetes

Spiegazione di `13-observability.yaml` (questa cartella). Lezione sul sito: http://127.0.0.1:3000/kubernetes/13

## In una frase

Il guidato installa **kube-prometheus-stack** (Prometheus Operator, Prometheus, Alertmanager, Grafana, node-exporter,
kube-state-metrics); questo file aggiunge un'**app d'esempio che espone metriche**, un **ServiceMonitor** che dice a
Prometheus di raccoglierle e una **PrometheusRule** con recording rule e alert. Poi si generano errori apposta e si
guardano gli alert passare da **pending** a **firing**.

## Due file con lo stesso nome: quale lanciare

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/lezioni/kubernetes/13-observability.yaml` | **questo**: i manifest (Namespace, Deployment, Service, ServiceMonitor, PrometheusRule) con la teoria nei commenti | si legge; lo applica il guidato con `kubectl apply -f`. Da solo funziona **solo dopo** aver installato kube-prometheus-stack (servono le CRD `monitoring.coreos.com`) |
| `~/kubernetesprj/kubernetes/13-observability.sh` | lo script **guidato**: installa lo stack, applica questo file, interroga Prometheus, genera carico, apre Grafana (Invio / s / q) | `bash kubernetes/13-observability.sh` |

Per imparare conviene lo **guidato**. Attenzione alla RAM: lo stack chiede **circa 1,5 GB in più** al cluster `lab`
(ricorda la trappola del `--memory=4g` della lezione 01).

## Com'è fatto il file

```
intestazione (commenti)  → monitoraggio vs observability, RED/USE, Prometheus in 6 righe, CRD dell'operator, LAB, NEL PROGETTO VERO
Namespace lab-oss
Deployment app           → prometheus-example-app, espone /metrics
Service app              → con label app: app (le guarda il ServiceMonitor)
ServiceMonitor app       → cosa raccogliere
PrometheusRule app-slo   → 2 recording rule + 3 alert
coda (commenti)          → PromQL da colloquio, log su Kubernetes, domande, riepilogo
```

---

## 1. La teoria nell'intestazione

Versioni: **kube-prometheus-stack (Prometheus Operator) · Grafana · Loki · OpenTelemetry**. Livello 5 "Produzione".

### Monitoraggio o observability?

- **Monitoraggio** = sapere **se** qualcosa è rotto (domande note in anticipo).
- **Observability** = capire **perché**, anche per guasti mai visti, a partire dai segnali:

| Segnale | Cos'è | Strumento |
|---|---|---|
| **Metriche** | numeri nel tempo, economici, per gli alert | Prometheus |
| **Log** | eventi con contesto, costosi, per il dettaglio | Loki / ELK |
| **Tracce** | il percorso di **una** richiesta fra i servizi | Tempo / Jaeger |

**OpenTelemetry** è lo standard per produrli tutti e tre (SDK + Collector). Il ponte fra i tre: un `trace_id` nei log e
negli **exemplar** delle metriche.

### Cosa misurare

| Metodo | Per | Cosa |
|---|---|---|
| **RED** | i servizi | Rate, Errors, Duration |
| **USE** | le risorse | Utilization, Saturation, Errors |
| **Golden signals** (Google SRE) | | latenza, traffico, errori, saturazione |

### Prometheus in 6 righe

- **PULL**: Prometheus fa scrape di `/metrics` ogni N secondi (è lui che va a prendere i numeri).
- Tipi: **counter** (sale soltanto: si usa con `rate()`), **gauge**, **histogram**, **summary**.
- Ogni combinazione di label = **una serie**. `user_id` come label = esplosione di **cardinalità** e Prometheus che
  finisce la memoria.
- Alert = regola PromQL vera per `for:` minuti → **Alertmanager**.
- Alertmanager: raggruppa, deduplica, silenzia, inibisce, instrada.
- Lungo periodo / alta affidabilità: Thanos, Mimir, VictoriaMetrics (`remote_write`).

### Con l'Operator non si edita `prometheus.yml`: si creano CRD

| CRD | A cosa serve |
|---|---|
| `ServiceMonitor` / `PodMonitor` | **cosa** fare scrape (per label del Service / del Pod) |
| `PrometheusRule` | regole di registrazione e di alert |
| `AlertmanagerConfig` | instradamento delle notifiche per namespace |

L'operator legge questi oggetti e **riscrive lui** la configurazione di Prometheus, poi lo ricarica. È di nuovo la
riconciliazione della lezione 01.

### Il laboratorio

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install mon prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=false \
  --set prometheus-node-exporter.hostRootFsMount.enabled=false \
  --wait --timeout 10m
kubectl apply -f 13-observability.yaml
kubectl -n monitoring port-forward svc/mon-kube-prometheus-stack-prometheus 9090   # /targets, /alerts
kubectl -n monitoring port-forward svc/mon-grafana 3001:80
```

| Opzione | Perché |
|---|---|
| `serviceMonitorSelectorNilUsesHelmValues=false` | di default Prometheus legge solo i ServiceMonitor con la label `release=<nome della release>`. Con `false` li legge **tutti**, in tutti i namespace: il nostro in `lab-oss` non ha quella label |
| `ruleSelectorNilUsesHelmValues=false` | lo stesso per le PrometheusRule |
| `prometheus-node-exporter.hostRootFsMount.enabled=false` | serve quando il "nodo" è un container (minikube con driver docker, kind, k3s in Docker). Senza, node-exporter resta in `CreateContainerError` con `path "/" is mounted on "/" but it is not a shared mount` |

Grafana si apre sulla porta locale **3001** (il file non dice perché; la 3000 è quella del sito delle lezioni).

### Riquadro «NEL PROGETTO VERO»

In `~/biodistretto/kubernetes` il segnale di salute usato davvero è il **CSV delle statistiche di HAProxy**: Ansible
riprova finché ogni nodo è UP.

```bash
cd ~/biodistretto/kubernetes
grep -n -A10 'Attende che HAProxy' ansible/roles/verifica/tasks/main.yml
grep -n 'stats auth' ansible/roles/haproxy/templates/haproxy.cfg.j2
```

Le statistiche hanno una password (in `.cache/haproxy-stats`, mai in git). Esercizio proposto: HAProxy 3.2 ha già un
exporter Prometheus; un frontend con `http-request use-service prometheus-exporter if { path /metrics }` e uno scrape
da Prometheus danno lo stato dei nodi come **metrica**, non più come CSV.

---

## 2. I manifest, uno per uno

### Namespace `lab-oss`

Tutto quello che segue vive qui; la pulizia è un `kubectl delete ns lab-oss`.

### Deployment `app`

| Campo | Valore | Perché |
|---|---|---|
| `replicas` | `2` | due target di scrape, due Pod nelle metriche |
| `image` | `quay.io/brancz/prometheus-example-app:v0.5.0` | espone `/metrics` con `http_requests_total{code,method}` e un istogramma |
| `ports` | `name: web`, `containerPort: 8080` | il nome `web` è quello che userà tutta la catena |
| `resources` | requests `cpu: 10m`, `memory: 16Mi`; limit `memory: 32Mi` | piccola: è un'app di prova |

Nota del file, **misurata**: questa app sa rispondere solo **200 e 404**. `/err` dà **404**.

### Service `app`

```yaml
metadata:
  labels: { app: app }              # il ServiceMonitor seleziona QUESTE label
spec:
  selector: { app: app }
  ports:
    - { name: web, port: 8080, targetPort: web }
```

Due cose diverse con la stessa label: `spec.selector` sceglie i **Pod** a cui mandare il traffico;
`metadata.labels` sono le label **del Service stesso**, e sono quelle che guarda il ServiceMonitor. Senza
`metadata.labels`, il ServiceMonitor non troverebbe niente.

### ServiceMonitor `app`

```yaml
spec:
  selector:
    matchLabels: { app: app }
  endpoints:
    - port: web          # il NOME della porta del Service
      path: /metrics
      interval: 15s
```

- `selector`: i **Service** con label `app: app` (nello stesso namespace del ServiceMonitor).
- `port: web`: il **nome** della porta del Service, non il numero.
- `interval: 15s`: uno scrape ogni 15 secondi.

L'operator trasforma questo oggetto in un job di scrape; ogni Pod dietro al Service diventa un target. La label `job`
delle serie raccolte prende il nome del Service: `app` (è il `job="app"` delle regole sotto).

### PrometheusRule `app-slo`

Il commento più importante del file: **in produzione gli errori sono `code=~"5.."`**, perché i 4xx sono quasi sempre
colpa del client e non consumano lo SLO. In questo lab l'app sa dare solo 200 e 404, quindi le regole contano
`[45]..`: così vedi l'alert scattare. **Su un servizio vero rimetti `5..`.**

#### Gruppo `app.registrazioni` — recording rule

| Record | Espressione | Perché |
|---|---|---|
| `job:http_requests:rate5m` | `sum by (job) (rate(http_requests_total[5m]))` | richieste al secondo per job |
| `job:http_errori:ratio_rate5m` | errori `[45]..` / totale, per job, su 5 minuti | la frazione di risposte in errore |

Una **recording rule** viene calcolata a ogni intervallo e salvata come serie nuova: interrogarla costa zero. Il nome
segue la convenzione `livello:metrica:operazioni`.

#### Gruppo `app.alert` — gli alert

| Alert | Condizione | `for` | Severità |
|---|---|---|---|
| `AppErroriAlti` | `job:http_errori:ratio_rate5m{job="app"} > 0.05` (più del 5% di errori) | `2m` | critical |
| `AppErrorBudgetBruciaVeloce` | tasso d'errore > `14.4 * 0.001` **sia** su 1 h **sia** su 5 min | — | critical |
| `AppPodInRestart` | `increase(kube_pod_container_status_restarts_total{namespace="lab-oss"}[15m]) > 3` | — | warning |

- **`AppErroriAlti`** è un alert **sul sintomo** (gli utenti vedono errori), non sulla causa. `for: 2m`: niente pagine
  per un picco di 30 secondi; prima l'alert è **pending**, se dura 2 minuti diventa **firing**. Le annotazioni danno
  il riassunto (`{{ $value | humanizePercentage }}`) e un `runbook_url`.
- **`AppErrorBudgetBruciaVeloce`**: SLO 99,9% → error budget 0,1%. **Burn rate 14,4** su 1 ora = il budget mensile
  consumato in circa 2 giorni: si pagina (dal Google SRE workbook). Le due finestre (1 h **e** 5 min) servono a non
  suonare per un problema già finito: la finestra lunga dice "è grave", quella corta "sta succedendo adesso".
- **`AppPodInRestart`** usa una metrica di **kube-state-metrics** (installato dallo stack), non dell'app.

Le `{{ $labels.job }}` nelle annotazioni sono template di Prometheus, non di Helm: questo file si applica con kubectl,
quindi nessuno le tocca prima di Prometheus.

---

## 3. Il percorso del guidato, passo per passo

| # | Comando | Cosa vedi |
|---|---|---|
| 1 | `helm repo add prometheus-community …; helm repo update prometheus-community` | il repository dei chart della comunità Prometheus |
| 2 | `helm upgrade --install mon prometheus-community/kube-prometheus-stack -n monitoring --create-namespace --set … --wait --timeout 10m` | installa lo stack con le tre opzioni spiegate sopra. Qualche minuto |
| 3 | `kubectl -n monitoring get pods` | operator, Prometheus, Alertmanager, Grafana, node-exporter (uno per nodo), kube-state-metrics |
| 4 | `kubectl get crd \| grep monitoring.coreos.com` | le CRD dell'operator: ServiceMonitor e PrometheusRule sono oggetti Kubernetes come gli altri |
| 5 | `kubectl apply -f $F` | questo file: app, ServiceMonitor, PrometheusRule |
| 6 | `kubectl -n monitoring port-forward svc/mon-kube-prometheus-stack-prometheus 9090 >/dev/null 2>&1 & echo $! > /tmp/pf-prom.pid; sleep 5` | Prometheus su `localhost:9090` **in background**; il PID finisce in `/tmp/pf-prom.pid` per chiuderlo dopo |
| 7 | ciclo `for i in $(seq 24)` con `curl …/api/v1/targets \| jq -e …` | aspetta fino a **2 minuti** (24 × 5 s) che un target di `lab-oss` sia `up`: l'operator deve prima leggere il ServiceMonitor e ricaricare Prometheus. Poi stampa `job health` per ogni target, per esempio `app up` |
| 8 | `kubectl -n lab-oss run carico --restart=Never --image=busybox:1.37 -- sh -c '…'` | un Pod che per **240 secondi** chiama `/err` e `/` in alternanza: circa metà delle risposte sono 404 |
| 9 | `sleep 40; curl … --data-urlencode 'query=sum by (code) (rate(http_requests_total{namespace="lab-oss"}[2m]))' \| jq '.data.result'` | **RED, la R**: richieste al secondo per codice (`200` e `404`). `rate()` vuole almeno **due campioni**: per questo aspetta 40 s |
| 10 | `sleep 120; curl …/api/v1/alerts \| jq -r '… alertname state'` | dopo circa 2 minuti gli alert `App…` passano da `pending` a `firing` (il `for` della regola). **Normale** vedere anche `TargetDown`, `etcd…` ecc. in firing: su minikube etcd, scheduler e controller-manager ascoltano solo su `127.0.0.1` del nodo e Prometheus non li raggiunge |
| 11 | `kubectl -n monitoring get secret mon-grafana -o jsonpath='{.data.admin-password}' \| base64 -d; echo` | la password di Grafana (utente `admin`) |
| 12 | `kubectl -n monitoring port-forward svc/mon-grafana 3001:80` | Grafana **in primo piano** su `http://localhost:3001`, con dashboard già pronte (Kubernetes / Compute Resources). Ctrl+C per chiudere. Con `AUTO=1` viene saltato (port-forward senza `&`) |
| 13 | `kill $(cat /tmp/pf-prom.pid) 2>/dev/null; kubectl -n lab-oss delete pod carico --ignore-not-found` | chiude il port-forward di Prometheus e cancella il Pod di carico |

Nota finale: l'interfaccia di Prometheus si riapre con il port-forward sulla 9090 (`/targets`, `/alerts`). Pulizia:
`helm uninstall mon -n monitoring; kubectl delete ns monitoring lab-oss`.

Differenza col LAB dell'intestazione: lì il carico è un `run carico --rm -it` che gira **all'infinito** finché non
premi Ctrl+C; il guidato usa un Pod `--restart=Never` che si ferma da solo dopo 240 s.

---

## 4. Le trappole

- **Il ServiceMonitor guarda le label del Service, non del Pod.** E `port` è il **nome** della porta.
- **kube-prometheus-stack di default** legge solo i ServiceMonitor con `release=<nome>`: per questo i due
  `*NilUsesHelmValues=false`.
- **node-exporter su nodi-container**: senza `hostRootFsMount.enabled=false` resta in `CreateContainerError`.
- **`rate()` su un gauge** dà numeri senza senso: per i gauge `deriv` / `delta`.
- **Cardinalità**: una label con valori illimitati (user_id, URL completi) moltiplica le serie.
- **Alert falsi su minikube**: etcd, scheduler e controller-manager risultano giù perché ascoltano solo in locale.
- **4xx come errori**: vale solo nel lab. In produzione `5..`.

---

## 5. La coda: PromQL e log

### PromQL che ti chiedono

| Query | Cosa dà |
|---|---|
| `rate(http_requests_total[5m])` | richieste al secondo (è un counter!) |
| `sum by (code) (rate(http_requests_total[5m]))` | per codice di risposta |
| `histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))` | p95 della latenza |
| `sum by (pod) (container_memory_working_set_bytes{namespace="lab-oss"})` | la memoria che conta per l'OOM |
| `sum(rate(container_cpu_cfs_throttled_periods_total[5m])) by (pod) / sum(rate(container_cpu_cfs_periods_total[5m])) by (pod)` | throttling dovuto al limit CPU |
| `kube_deployment_status_replicas_available / kube_deployment_spec_replicas` | frazione di repliche disponibili |

### Log su Kubernetes

L'app scrive su **stdout/stderr** in JSON; il runtime salva i file sul nodo; un **DaemonSet** (Promtail/Alloy, Fluent
Bit, Vector) li legge, aggiunge le label del Pod e li manda a Loki o Elasticsearch. **Loki indicizza solo le label,
non il testo**: economico, ma le label vanno tenute poche (come in Prometheus). Query LogQL d'esempio:
`{namespace="lab-oss"} |= "error" | json`. Lo stack di log completo è nella lezione 14.

---

## 6. Domande da colloquio

- **Alert sulla CPU all'80%: buono o cattivo?** Cattivo come pagina: la CPU alta non è un problema finché latenza ed
  errori sono buoni (forse è efficienza). Si pagina sui **sintomi** (SLO); le cause (CPU, disco) diventano ticket o
  dashboard. Eccezione: la saturazione che porta a un guasto certo (disco pieno fra 4 ore → `predict_linear`).
- **`rate` o `irate`? E perché mai `rate` su un gauge?** `rate` media sulla finestra ed è giusto per gli alert;
  `irate` usa gli ultimi due punti, utile per grafici molto reattivi. `rate` gestisce i reset dei counter (restart):
  su un gauge darebbe numeri senza senso; per i gauge `deriv` / `delta`.
- **Prometheus non vede il mio ServiceMonitor.** 1) le label del ServiceMonitor combaciano con il
  `serviceMonitorSelector` del Prometheus (con kube-prometheus-stack di default serve `release=<nome>`, per questo nel
  lab lo si apre a tutti); 2) il namespace è fra quelli osservati; 3) il selector del ServiceMonitor combacia con le
  label del **Service** (non del Pod); 4) `port` è il **nome** della porta. Poi `/targets` mostra l'errore di scrape.
- **Come eviti 200 notifiche quando cade un nodo?** Alertmanager: `group_by (cluster, alertname)`, `inhibit_rules`
  (se c'è NodeDown, silenzia gli alert dei Pod su quel nodo), e alert sul sintomo a livello di servizio invece che di
  singolo Pod.
- **Che cos'è una recording rule?** Una query calcolata periodicamente e salvata come serie: le dashboard e gli alert
  la leggono a costo zero.

---

## Riepilogo

- Metriche (Prometheus), log (Loki), tracce (Tempo) + OpenTelemetry.
- RED per i servizi, USE per le risorse; cardinalità sotto controllo.
- Operator: ServiceMonitor (cosa raccogliere) + PrometheusRule (regole).
- Alert sui **sintomi** e sugli SLO (burn rate), con `for:` e runbook.
- Alertmanager: raggruppa, inibisce, instrada.

## Prova da solo

1. Con il port-forward sulla 9090 attivo, interroga la recording rule
   `job:http_errori:ratio_rate5m` (`curl -s localhost:9090/api/v1/query --data-urlencode 'query=job:http_errori:ratio_rate5m' | jq '.data.result'`)
   mentre gira il Pod `carico`: che valore vedi, e come si confronta con la soglia `0.05`?
2. Togli `labels: { app: app }` dai **metadata** del Service, riapplica e guarda `/api/v1/targets` dopo un paio di
   minuti: il target `app` c'è ancora? Rimettila.
3. Scrivi la query p95 della sezione 5 per l'app di `lab-oss` (`namespace="lab-oss"`) e prova a eseguirla: esiste la
   metrica `http_request_duration_seconds_bucket` in questa app? Cerca il nome vero dell'istogramma in
   `curl -s localhost:9090/api/v1/label/__name__/values | jq -r '.data[]' | grep http_`.
