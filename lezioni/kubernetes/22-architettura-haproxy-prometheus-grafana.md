# 22 — HAProxy osservato con Prometheus e Grafana

Spiegazione di `22-architettura-haproxy-prometheus-grafana.yaml` (questa cartella) e dello script guidato
`kubernetes/22-architettura-haproxy-prometheus-grafana.sh`.

## In una frase

Lo script crea un **cluster minikube nuovo, `lab-monitoring`** (3 nodi da 3 GiB, Calico). Ci installa con Helm
**kube-prometheus-stack** (Prometheus, Alertmanager, Grafana) e lo **HAProxy della 21**, poi rimette le app della 21 e
ci aggiunge un'app che espone metriche sue. Alla fine ogni pezzo del traffico, dal frontend di HAProxy fino al
contatore dell'app, si vede **nel tempo**: query PromQL, una dashboard caricata da una ConfigMap e tre alert, uno dei
quali lo provochi tu spegnendo l'app.

## I file della lezione

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/kubernetes/22-architettura-haproxy-prometheus-grafana.sh` | lo script **guidato**: cluster, stack, HAProxy con PodMonitor, manifest della 21 e della 22, query, alert, Grafana, pulizia (Invio / s / q) | `bash kubernetes/22-architettura-haproxy-prometheus-grafana.sh` |
| `~/kubernetesprj/lezioni/kubernetes/22-architettura-haproxy-prometheus-grafana.yaml` | i **manifest** con la teoria nei commenti: app `demo-metrics`, ServiceMonitor, Ingress `demo`, PrometheusRule, dashboard | si **legge** mentre lo script gira; lo applica lo script |
| `~/kubernetesprj/lezioni/kubernetes/21-architettura-e-haproxy.yaml` | le app `blu` e `verde` e i due Ingress della 21, **senza modifiche** | lo applica lo script prima del 22 |
| `~/kubernetesprj/lezioni/kubernetes/22-architettura-haproxy-prometheus-grafana.md` | **questo**: la spiegazione | si legge |

**Prerequisiti**: la 21 (HAProxy come Ingress controller) e la 13 (che cos'è un ServiceMonitor). Il cluster è suo,
separato da `lab` e da `lab-haproxy`. **Tienine acceso uno alla volta**: `lab-monitoring` usa 9 GiB (3 × 3) e il PC
ne ha 15. Prima di cominciare: `minikube -p lab stop; minikube -p lab-haproxy stop`.

## Com'è fatto il manifest

```
intestazione (commenti)    → teoria: la catena delle metriche, i tre selettori, PodMonitor e non ServiceMonitor, il cluster, LAB
Namespace lab-metrics
ConfigMap demo-metrics-code → l'app Python del materiale: /work conta richieste e latenza, /metrics le espone
Deployment demo-metrics    → python:3.12-alpine, solo libreria standard, readiness su /health
Service demo-metrics       → porta chiamata "metrics": il ServiceMonitor la cerca per NOME
ServiceMonitor demo-metrics → label release: monitoring, ogni 15 s
Ingress demo               → classe haproxy, demo.lab.local → demo-metrics: l'app sta DIETRO HAProxy
PrometheusRule lezione-22  → namespace monitoring: DemoMetricsNonDisponibile, HAProxyBackendSenzaServer, HAProxyRateLimitAttivo
ConfigMap dashboard-lezione-22 → label grafana_dashboard: "1": il sidecar di Grafana la carica da solo
coda (commenti)            → domande da colloquio, riepilogo
```

---

## 1. L'architettura: la 21 più chi la guarda

```
 client ──▶ NodePort 30080 ──▶ Pod HAProxy (2, su m02 e m03) ──▶ Pod blu / verde / demo-metrics
                                   │ :1024/metrics                        │ :8000/metrics
                                   │ (PodMonitor)                         │ (ServiceMonitor)
                                   ▼                                      ▼
                          Prometheus (ogni 30 s / 15 s) ◀── kube-state-metrics, node-exporter, kubelet
                                   │ regole (PrometheusRule)   │ query PromQL
                                   ▼                           ▼
                             Alertmanager                    Grafana (dashboard da ConfigMap)
```

Prometheus **va a prendere** le metriche (pull): ogni target è un indirizzo `http://IP:porta/metrics` che risponde con
righe di testo. Nessuno gli dice gli indirizzi a mano: li ricava l'**Operator** dagli oggetti `ServiceMonitor` e
`PodMonitor`, che sono CRD installate dalla stack.

Le metriche arrivano da **tre livelli**, e servono tutti e tre:

| Livello | Chi le espone | Che cosa dice | Esempio |
|---|---|---|---|
| ingresso | HAProxy, porta 1024 | richieste, risposte per codice, 429, server attivi per backend | `haproxy_backend_active_servers` |
| app | demo-metrics, porta 8000 | quello che solo l'app sa: le sue richieste, la sua latenza | `demo_requests_total` |
| cluster | kube-state-metrics | lo stato degli oggetti Kubernetes | `kube_deployment_status_replicas_available` |

### I tre selettori: chi decide che cosa Prometheus legge

Un ServiceMonitor creato **non è ancora letto**. Devono combaciare tre selettori:

1. **Prometheus sceglie i ServiceMonitor** (`serviceMonitorSelector`): qui quelli con `release: monitoring`, da
   **ogni** namespace (`serviceMonitorNamespaceSelector: {}`). Il passo 08 fa vedere il default del chart:
   `*SelectorNilUsesHelmValues: true` vuol dire «solo quelli con la label della mia Release».
2. **Il ServiceMonitor sceglie i Service** (`selector.matchLabels: { app: demo-metrics }`) nel namespace dato.
3. **Il ServiceMonitor sceglie la porta per nome** (`port: metrics`): se nel Service la porta si chiama `http`, il
   target non nasce e **nessuno dà errore**.

Lo stesso vale per i PodMonitor (`podMonitorSelector`) e per le regole (`ruleSelector`): nessuno dei due è stato
toccato nei values, e il default della Release vuole `release: monitoring`. Per questo il PodMonitor di HAProxy e la
PrometheusRule portano quella label.

Nella 13 c'era la strada opposta: `serviceMonitorSelectorNilUsesHelmValues=false` **senza** selettore, cioè «leggi
tutti i ServiceMonitor del cluster». È comodo in laboratorio; con più team è meglio una label esplicita, come qui.

## 2. HAProxy: PodMonitor, non ServiceMonitor (la trappola misurata)

Il chart `haproxytech/kubernetes-ingress` 1.57.1 ha due interruttori:

- `controller.serviceMonitor.enabled` crea un Service `haproxy-kubernetes-ingress-metrics` e un ServiceMonitor;
- `controller.podMonitor.enabled` crea solo un PodMonitor, che punta direttamente ai Pod.

Il primo, con i NodePort della 21, **non si installa**:

```
Service "haproxy-kubernetes-ingress-metrics" is invalid:
spec.ports[0].nodePort: Forbidden: may not be used when type is 'ClusterIP'
```

Il template del Service delle metriche copia `controller.service.nodePorts.stat` (il 30024 della pagina statistiche)
in un Service di tipo `ClusterIP`, e l'apiserver lo rifiuta. Il passo 11 lo fa vedere con `helm template`, senza
applicarlo. Con il PodMonitor il problema non c'è, ed è anche il modello più giusto qui: si vuole **un target per
Pod**, perché le due repliche hanno contatori diversi.

Misurato: subito **2 target UP**, uno per replica, con
`scrapeUrl` = `http://<IP del Pod>:1024/metrics?scope=global&scope=frontend&scope=backend`, e **153** metriche
`haproxy_*`. Lo scope `server` non c'è: si vede il backend intero, non il singolo Pod blu.

### Che nomi hanno backend e frontend

La label `proxy` porta il nome che il controller ha scritto in `haproxy.cfg`:

| `proxy` | che cos'è |
|---|---|
| `lab-haproxy_svc_blu_http` | backend del Service `blu` (namespace `_svc_` nome `_` porta) |
| `lab-haproxy_svc_verde_http` | backend di `verde` |
| `lab-metrics_svc_demo-metrics_metrics` | backend della demo |
| `http`, `https`, `stats`, `healthz` | i frontend |

Per questo le query della dashboard filtrano `proxy=~"lab-.*"`: tengono i backend delle app e lasciano fuori quelli
interni del controller.

## 3. Che cosa si misura, e dove le repliche non sono d'accordo

Misurato nella corsa di prova:

- `haproxy_backend_active_servers`: blu **3**, verde **2**, demo **1**, uguale su tutte e due le repliche. È il numero di Pod
  pronti che HAProxy conosce, cioè la Runtime API della 21 vista da fuori.
- Richieste per backend: **diverse per replica** (44/34 su una, 26/26 sull'altra). kube-proxy sceglie la replica a
  caso, connessione per connessione.
- Rate limit: 12 richieste a `limitato.lab.local` danno **10 volte 200 e 2 volte 429** (nella seconda corsa 9 e 3), e
  i 429 cadono **tutti sulla stessa replica** (l'altra resta a 0). Si contano in `haproxy_frontend_requests_denied_total{proxy="http"}` e anche in
  `haproxy_frontend_http_responses_total{code="4xx"}`.

È la domanda della 21 («il rate limit è globale?») con la risposta in un grafico: due stick-table, due contatori.
In una dashboard bisogna scegliere e **scrivere** se si somma (`sum`) o si separa (`sum by (pod)`): la dashboard della
lezione separa.

### PromQL in quattro righe

```promql
sum(rate(demo_requests_total[1m]))                                          # richieste/s dell'app
sum by (pod) (rate(haproxy_backend_http_requests_total{proxy=~"lab-.*"}[1m])) # richieste/s per replica HAProxy
haproxy_backend_active_servers{proxy=~"lab-.*"}                             # server pronti per backend
1000 * sum(rate(demo_request_duration_seconds_sum[5m])) / sum(rate(demo_request_duration_seconds_count[5m]))  # latenza media in ms
```

`rate()` vuole un **Counter** e almeno due campioni nella finestra: con scrape ogni 15 s, `[1m]` ne contiene quattro.
Su un contatore appena nato la query torna vuota: lo script aspetta 30 s prima di chiedere.

## 4. Gli alert: dal lato del cluster e dal lato dell'utente

| Regola | Espressione | `for` | Che cosa dice |
|---|---|---|---|
| `DemoMetricsNonDisponibile` | `kube_deployment_status_replicas_available{…demo-metrics} < 1` | 1m | Kubernetes non ha repliche pronte |
| `HAProxyBackendSenzaServer` | `min by (proxy) (haproxy_backend_active_servers{proxy=~"lab-.*"}) == 0` | 1m | HAProxy non ha a chi mandare: l'utente vede 503 |
| `HAProxyRateLimitAttivo` | `sum by (pod) (rate(haproxy_frontend_requests_denied_total{proxy="http"}[2m])) > 0` | 0m | qualcuno sta prendendo 429 |

Il passo 24 spegne la demo (`--replicas=0`) e segue gli stati. Misurato in due corse:

| Quando | Stato |
|---|---|
| +16 s / +30 s | i due alert in `pending`: l'espressione è vera, il `for` sta contando |
| +76 s / +91 s | tutti e due `firing` |
| subito | `curl /work` attraverso HAProxy → **503** |

Il tempo è scrape (15–30 s) + valutazione (30 s) + `for` (1 min). `firing` vuol dire che Alertmanager li ha, **non**
che un messaggio è partito: nessun receiver è configurato (è la parte Alertmanager della 14).

Le due regole guardano lo stesso guasto da due lati. `HAProxyBackendSenzaServer` misura **quello che vede l'utente**:
se il problema fosse un Service che punta alla porta sbagliata, kube-state-metrics direbbe «tutto pronto» e solo
HAProxy si accorgerebbe che non c'è nessuno a cui mandare.

## 5. Grafana: la dashboard è un file, non un clic

La ConfigMap `dashboard-lezione-22` porta la label `grafana_dashboard: "1"`. Il **sidecar** del Pod di Grafana guarda
le ConfigMap con quella label in **tutti** i namespace e copia il JSON nella cartella che Grafana legge. Misurato:
dashboard `uid=lezione-22` caricata senza toccare l'interfaccia, datasource `Prometheus` con `uid=prometheus` (il
default della stack, citato nel JSON). Le 7 query dei pannelli tornano dati (3, 2, 6, 2, 1, 1, 1 serie).

Una dashboard fatta a mano in Grafana si perde con il Pod (qui non c'è un volume persistente); una dashboard in
ConfigMap sta in git, si rivede in una review e si rimette con un `kubectl apply`.

### Grafana e Prometheus dal Mac

Lo script apre i port-forward sul PC del lab (passi 17 e 27). Dal Mac serve un tunnel ssh:

```bash
ssh -N -L 3000:localhost:3000 -L 9090:localhost:9090 wilsonsgro@192.168.1.79
```

Poi `http://localhost:3000/d/lezione-22` (utente `admin`, password dal passo 28) e `http://localhost:9090/alerts`.
La password resta nel terminale: non va scritta in un file né in un repository.

## 6. Il cluster da 3 GiB per nodo

La 21 stava in 5 nodi da 1 GiB perché c'era solo HAProxy. La stack aggiunge Prometheus, Grafana (3 container),
Alertmanager, l'Operator, kube-state-metrics e un node-exporter per nodo: **non ci sta**. Qui: 3 nodi da 3 GiB, e
`minikube start` non chiede `--force`. Misurato a lezione in corso (memoria netta, senza la cache dei file):

| Nodo | Netto | Di 3072 Mi | oom_kill |
|---|---|---|---|
| lab-monitoring (control plane) | 1296 Mi | 42 % | 0 |
| lab-monitoring-m02 | 980 Mi | 31 % | 0 |
| lab-monitoring-m03 | 1044 Mi | 34 % | 0 |

L'installazione della stack ha richiesto **2 minuti e 48 secondi** (`--wait`). `hostRootFsMount.enabled=false` serve
perché il nodo minikube è un container: il node-exporter non può montare la radice dell'host.

## 7. Una cosa da non portare in produzione

L'Ingress `demo` manda **tutto** `demo.lab.local` all'app, quindi anche `/metrics` è raggiungibile da fuori:
chiunque arrivi a HAProxy legge i contatori dell'app. In laboratorio va bene; in produzione l'Ingress pubblica solo i
path dell'app (`/work`) e `/metrics` resta raggiungibile solo dentro il cluster, oppure sta su una porta che nessun
Ingress espone. Lo stesso vale per la porta 1024 di HAProxy: il PodMonitor la raggiunge dentro il cluster, nessun
Service la pubblica.

---

## I passi dello script

| Passo | Comando | Che cosa aspettarsi |
|---|---|---|
| 01 | versioni dei client | kubectl, minikube 1.37, helm 4 |
| 02 | `minikube start -p lab-monitoring … --nodes=3 --memory=3g --cni=calico` | qualche minuto, senza `--force` |
| 03 | `use-context lab-monitoring` | poi la guardia controlla il contesto |
| 04 | `rollout status daemonset/calico-node` | Calico pronto sui 3 nodi |
| 05 | `get nodes -L minikube.k8s.io/primary` | 1 control plane, 2 worker |
| 06 | addon metrics-server | per `kubectl top` |
| 07 | `helm repo add` e `search repo` | kube-prometheus-stack 93.10.1, kubernetes-ingress 1.57.1 |
| 08 | `helm show values … grep NilUsesHelmValues` | i `true` del default: rule, serviceMonitor, podMonitor (il quarto è di thanosRuler) |
| 09 | `helm upgrade --install monitoring …` | ~3 minuti |
| 10 | Pod, Service, oggetto Prometheus, CRD | `monitoring-grafana`, `monitoring-kube-prometheus-prometheus`, 10 CRD `monitoring.coreos.com` |
| 11 | `helm template … serviceMonitor.enabled=true` | un Service `ClusterIP` con dentro `nodePort: 30024`: la trappola |
| 12 | `helm upgrade --install haproxy …` con PodMonitor | 2 repliche su m02 e m03 |
| 13 | Pod e PodMonitor | `release=monitoring` nelle label |
| 14 | `kubectl apply -f 21-….yaml` | blu 3, verde 2 |
| 15 | `kubectl apply -f 22-….yaml` | demo-metrics pronta (il codice arriva dalla ConfigMap) |
| 16 | `curl` fino a 200 | `/blu`, `/verde`, `/work` → 200 dopo qualche tentativo |
| 17 | port-forward Prometheus in background | |
| 18 | target `up` | 2 Pod HAProxy + demo-metrics, con lo `scrapeUrl` |
| 19 | conta `haproxy_*` e server attivi | ~153 metriche; blu 3 e verde 2 per replica |
| 20 | 30 s di traffico | `fatto` |
| 21 | due query `rate` | richieste/s della demo e per replica HAProxy |
| 22 | 12 `curl` su `limitato.lab.local` | 200 e poi 429; i 429 per replica |
| 23 | regole caricate | i tre nomi; `HAProxyRateLimitAttivo` spesso già `firing` |
| 24 | `scale … --replicas=0` e attesa | `pending`, poi `firing` (76–91 s), poi `503` |
| 25 | `scale … --replicas=1` | ripristino |
| 26 | memoria netta per nodo | control plane ~41 %, worker ~30 %, `oom_kill 0` |
| 27 | port-forward Grafana e API | datasource `uid=prometheus`, dashboard `/d/lezione-22` |
| 28 | password di admin | solo a schermo |
| 29 | chiude i port-forward | **prima di dare Invio, guarda Grafana**: dopo questo passo non c'è più |
| 30 | `kubectl delete` e `helm uninstall` | pulizia |
| 31 | CRD rimaste | le CRD restano: `helm uninstall` non le toglie |

Per ripartire da un passo: `DA=17 bash kubernetes/22-architettura-haproxy-prometheus-grafana.sh` (dal 17 in poi il
cluster e le Release devono esserci già). Tutto senza fermarsi: `AUTO=1 bash kubernetes/22-…sh`.

---

## 8. Domande da colloquio

- **Ho creato un ServiceMonitor ma il target non c'è: dove guardo?** Nei tre selettori, in ordine: la label che
  Prometheus vuole (`kubectl get prometheus -o yaml`, `serviceMonitorSelector`), il `selector` del ServiceMonitor
  contro le label del Service, il **nome** della porta. Poi `/targets` e i log dell'Operator.
- **ServiceMonitor o PodMonitor?** ServiceMonitor quando esiste già un Service che vuoi comunque. PodMonitor quando
  ogni Pod va letto per conto suo e un Service esisterebbe solo per le metriche, come per le repliche di HAProxy.
- **Perché `rate()` e non il valore del Counter?** Il Counter cresce sempre e riparte da zero quando il Pod riparte;
  `rate()` dà la velocità e gestisce i reset.
- **Che differenza c'è fra `pending` e `firing`?** `pending`: l'espressione è vera ma non da quanto chiede `for`.
  `firing`: lo è da abbastanza, e l'alert va ad Alertmanager. `for` evita gli allarmi per un picco di un secondo.
- **L'alert è firing: è partita una mail?** Non è detto: decide Alertmanager, con route e receiver. Senza receiver
  l'alert resta nella sua interfaccia.
- **Dashboard in Grafana o in git?** In git, come ConfigMap letta dal sidecar: si rivede, si versiona, sopravvive al
  Pod.
- **metrics-server e Prometheus fanno la stessa cosa?** No. metrics-server dà CPU e memoria **di adesso** all'apiserver
  (per `kubectl top` e l'HPA); Prometheus tiene **la storia** di qualunque metrica e ci fa query e regole.

## Riepilogo

- kube-prometheus-stack porta Operator, Prometheus, Alertmanager e Grafana; le CRD `ServiceMonitor`, `PodMonitor` e
  `PrometheusRule` dicono che cosa leggere e quando allarmare.
- Tre selettori devono combaciare: Prometheus → monitor (label `release`), monitor → Service o Pod, porta per nome.
- HAProxy si legge con un **PodMonitor**: un target per replica. Il ServiceMonitor del chart 1.57.1 non si installa
  insieme ai NodePort.
- Le repliche di HAProxy hanno contatori diversi: `sum by (pod)` le separa, ed è così che si vede il rate limit
  per replica della 21.
- Gli alert guardano dai due lati: Kubernetes (repliche pronte) e utente (server attivi in HAProxy, 503).
- La dashboard è una ConfigMap con `grafana_dashboard: "1"`.
- `/metrics` non si pubblica con l'Ingress dell'app.

## Prova da solo

1. Rinomina la porta del Service `demo-metrics` da `metrics` a `http` (`kubectl edit`). Che cosa succede al target in
   `/targets`? Che errore vedi? (Spoiler: nessuno. Ritorna a `metrics`.)
2. Togli la label `release: monitoring` dalla PrometheusRule (`kubectl label prometheusrule … release-`): in quanto
   tempo le tre regole spariscono da `/rules`?
3. Scala HAProxy a 1 replica (`helm upgrade … --reuse-values --set controller.replicaCount=1`) e ripeti i 12 `curl`
   su `limitato.lab.local`: quanti 200 adesso? Il pannello «429/s per replica» come cambia?
4. Aggiungi alla dashboard un pannello con `sum by (code) (rate(haproxy_frontend_http_responses_total{proxy="http"}[1m]))`
   modificando la ConfigMap e rifacendo `kubectl apply`: quanto ci mette il sidecar a mostrarlo?
5. Scrivi una regola che scatta quando la latenza media della demo supera i 10 ms per 2 minuti. Il `/work` del
   materiale dorme 20 ms: scatta? Che cosa succede se porti la soglia a 50 ms?

## Collegamenti

- `06` — HPA e metrics-server, la strada «di adesso» delle metriche
- `08` e `09` — Helm: Release, values, `upgrade --install`
- `13` — la prima volta di kube-prometheus-stack, con i selettori aperti
- `14` — logging e Alertmanager, dove vanno gli alert dopo `firing`
- `21` — HAProxy come Ingress controller: questa lezione la osserva
- sul sito delle lezioni: la lezione **25** (Approfondimenti), lo stesso materiale su Prometheus e Grafana con le
  simulazioni di `rate()` e degli stati degli alert
