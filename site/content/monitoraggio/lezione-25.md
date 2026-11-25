# Lezione — Prometheus, Grafana e monitoraggio delle metriche Kubernetes

> **Obiettivo formativo:** capire come Kubernetes espone metriche, installare una stack Prometheus + Grafana, raccogliere metriche applicative tramite `ServiceMonitor`, interrogare i dati con PromQL, creare dashboard e un primo alert, e prepararsi a monitorare HAProxy della Lezione 21.
>
> **Destinatari:** studenti che hanno già affrontato Deployment, Service, ConfigMap, Helm, HPA, RBAC e troubleshooting Kubernetes.
>
> **Ambiente:** profilo Minikube `lab`, namespace `monitoring` per la stack, namespace `lab-metrics` per l'app dimostrativa. Nessun comando in questo documento è stato eseguito sul cluster dell'utente: output, percentuali e grafici sono attesi o illustrativi.

## Indice

1. Observability: metriche, log e trace
2. Prometheus e Grafana: responsabilità diverse
3. Architettura della raccolta metriche in Kubernetes
4. Metrics-server vs Prometheus e integrazione HPA
5. Prometheus Operator e kube-prometheus-stack
6. Laboratorio Helm: installazione e accesso alle UI
7. PromQL: `up`, Counter, Gauge, `rate`, memoria e CPU
8. Applicazione dimostrativa e `ServiceMonitor`
9. Dashboard Grafana: RPS, totali e latenza media
10. Alerting con `PrometheusRule` e Alertmanager
11. Troubleshooting della stack
12. Metriche HAProxy e collegamento alla Lezione 21
13. Sicurezza, retention, persistenza e cardinalità
14. Esercizi, quiz e risposte

---

# 1. Observability: metriche, log e trace

Nelle lezioni precedenti abbiamo usato `kubectl get pods`, `kubectl top` e `kubectl logs` per capire lo stato delle applicazioni. Questi comandi sono necessari, ma non rispondono da soli a domande storiche e prestazionali: *quanta CPU usava il Pod due ore fa?*, *il tasso di errori sta crescendo?*, *quale nodo sta esaurendo memoria?*, *il tempo di risposta HTTP è peggiorato?*

**Le tre famiglie di segnali:**

| Segnale | Domanda | Esempio |
|---|---|---|
| Metriche | Quanto? Con quale frequenza? | CPU, RAM, richieste/s, P95 |
| Log | Che cosa è successo? | `database connection refused` |
| Trace | Dove è passata una richiesta? | API → DB → cache, tempo di ogni passaggio |

Uno stato `Running 1/1` dimostra che il container risulta pronto secondo le verifiche configurate, non che l'intera esperienza utente sia sana. Per esempio, due Pod possono essere `Running` pur impiegando secondi a rispondere. Le metriche rendono visibile il comportamento **nel tempo**.

# 2. Prometheus e Grafana: che cosa fanno?

**Prometheus** recupera periodicamente metriche da endpoint HTTP (modello *pull*), le conserva come **serie temporali**, permette interrogazioni **PromQL** e valuta regole di alert. **Grafana** interroga Prometheus (e altre sorgenti dati) e permette di creare dashboard, visualizzazioni e anche alert propri.

Immagina questi campioni di CPU (inventati):

| Ora | Consumo CPU |
|---|---:|
| 10:00 | 120m |
| 10:01 | 180m |
| 10:02 | 240m |
| 10:03 | 170m |

Prometheus memorizza e rende interrogabile la serie; Grafana la rappresenta in un grafico. Grafana **non sostituisce** il motore di raccolta e conservazione delle metriche di Prometheus.

Un endpoint di metriche può esporre testo come:

```text
# HELP demo_requests_total Total HTTP requests
# TYPE demo_requests_total counter
demo_requests_total{method="GET",status="200"} 1250
demo_requests_total{method="GET",status="500"} 12
```

- `demo_requests_total` è il nome della metrica.
- `method` e `status` sono **label**, dimensioni usate per distinguere serie.
- `1250` è un campione del contatore.
- Ogni combinazione metrica + label identifica una serie temporale.
- Il timestamp è quello della raccolta, se l'esposizione non ne specifica uno.

# 3. Architettura delle metriche Kubernetes

Le sorgenti delle metriche sono diverse, ciascuna con una responsabilità.

| Componente | Che cosa misura |
|---|---|
| kubelet / cAdvisor | Uso di CPU e memoria dei container |
| node-exporter | Risorse del sistema operativo e dei nodi: CPU, RAM, dischi, rete |
| kube-state-metrics | Stato degli oggetti Kubernetes: repliche, Pod, restart |
| Applicazione / exporter | Metriche di business o servizio: richieste HTTP, latenza, code |

**Percorso concettuale:**

```text
node-exporter ────────┐
kube-state-metrics ────┤
kubelet / cAdvisor ────┼──[HTTP scrape]──> Prometheus ──[PromQL]──> Grafana
app /metrics ─────────┘                       │
                                             └──[alert rules]──> Alertmanager
```

`node-exporter` osserva l'host; `kube-state-metrics` espone lo stato delle API Kubernetes. Non sono intercambiabili.

Esempi di metriche da kube-state-metrics:

```promql
kube_deployment_status_replicas_available
kube_pod_status_phase
kube_pod_container_status_restarts_total
```

**Modello pull:** Prometheus richiede periodicamente `/metrics`; non è l'applicazione che, nel caso standard, apre una connessione verso Prometheus per inviare ogni evento. Uno scrape riuscito non è prova che l'app sia utilizzabile da un utente finale.

# 4. Metrics-server e Prometheus NON sono equivalenti

Collegamento alla Lezione 06: l'HPA CPU/RAM utilizza la **Resource Metrics API**, fornita normalmente da `metrics-server`. Prometheus è progettato per raccolta storica, analisi e query.

| Funzione | metrics-server | Prometheus |
|---|---|---|
| `kubectl top` | Sì | Non direttamente |
| HPA standard su CPU/RAM | Sì | Non direttamente |
| Serie storiche e PromQL | Non è il suo scopo | Sì |
| Dashboard Grafana | Non è una sorgente Prometheus standard | Sì |
| Metriche applicative personalizzate | No | Sì |

**Attenzione:** installare Prometheus **non** fa migrare automaticamente l'HPA a Prometheus. Per autoscaling su metriche applicative sono necessarie integrazioni aggiuntive, come un adapter per le API Kubernetes o KEDA.

---

# 5. Prometheus Operator e kube-prometheus-stack

Per un laboratorio Kubernetes è comodo usare il Chart Helm `prometheus-community/kube-prometheus-stack`, che gestisce i componenti mediante **Prometheus Operator**.

Il Chart può includere Prometheus, Grafana, Alertmanager, node-exporter, kube-state-metrics, dashboard e regole già configurate.

Le risorse custom più importanti dell'Operator sono:

| Risorsa | Scopo |
|---|---|
| `Prometheus` | Specifica un'istanza Prometheus |
| `ServiceMonitor` | Definisce quali Service monitorare e su quale endpoint |
| `PodMonitor` | Definisce quali Pod monitorare direttamente |
| `PrometheusRule` | Regole di registrazione e alert |
| `Alertmanager` | Specifica l'istanza che gestisce e instrada gli alert |

Il controller osserva tali risorse e riconcilia la configurazione. È un'applicazione del modello dichiarativo studiato nella Lezione 01.

## 5.1 Prerequisiti

Usa preferibilmente il vecchio cluster `lab` (due nodi da 4 GiB), **non** il cluster `lab-haproxy` con soli 1 GiB per nodo. Prima di iniziare:

```bash
kubectl config current-context
kubectl get nodes
kubectl top nodes
```

Verifica che il contesto sia `lab`, che i nodi siano `Ready` e che ci siano CPU e memoria disponibili. Se il cluster è spento:

```bash
minikube -p lab start
```

Non avviare contemporaneamente diversi cluster pesanti se l'host ha poca memoria.

## 5.2 Aggiungi il repository Helm

```bash
helm repo add prometheus-community \
  https://prometheus-community.github.io/helm-charts
helm repo update prometheus-community
helm search repo prometheus-community/kube-prometheus-stack --versions
```

**Nota di riproducibilità:** scegli una versione Chart verificata compatibile con la versione Kubernetes del tuo cluster e fissala tramite `--version`. Gli esempi non inventano un numero di versione compatibile. Verifica i valori effettivi del Chart scelto con `helm show values`.

## 5.3 File `values-monitoring.yaml`

```yaml
# values-monitoring.yaml

grafana:
  enabled: true

prometheus:
  prometheusSpec:
    retention: 6h
    serviceMonitorSelectorNilUsesHelmValues: false
    serviceMonitorSelector:
      matchLabels:
        release: monitoring
    serviceMonitorNamespaceSelector: {}

alertmanager:
  enabled: true
```

Interpretazione:

- `retention: 6h`: breve finestra di conservazione adatta a un laboratorio; **non** è un limite rigido alla memoria.
- `serviceMonitorSelector.matchLabels.release: monitoring`: Prometheus seleziona i ServiceMonitor con quella label.
- `serviceMonitorNamespaceSelector: {}`: la discovery può interessare tutti i namespace secondo il contesto e i permessi effettivi.
- `serviceMonitorSelectorNilUsesHelmValues: false`: esplicita il controllo del selector anziché dipendere dal default del Chart.

Questa configurazione è **didattica**, non una configurazione di produzione da copiare senza rivedere RBAC, discovery, storage e sicurezza. Per le PrometheusRule va verificato separatamente il `ruleSelector` effettivo.

## 5.4 Installazione

```bash
helm upgrade --install monitoring \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values values-monitoring.yaml \
  --wait \
  --timeout 10m
```

Il nome della **Release** è `monitoring`, il Chart è `kube-prometheus-stack` e il namespace è `monitoring`. Collegamento alla Lezione 09: `helm upgrade --install` può installare la prima volta o aggiornare una Release esistente.

Verifiche:

```bash
kubectl -n monitoring get pods
kubectl -n monitoring get svc
kubectl -n monitoring get prometheus
kubectl -n monitoring get servicemonitors
```

Se trovi un Pod `Pending`, applica il metodo della Lezione 08: `get` → `describe` → eventi → risorse del nodo / PVC. Non presumere subito un problema con Prometheus.

---

# 6. Apriamo Grafana e Prometheus

## 6.1 Grafana

Individua il nome reale del Service:

```bash
kubectl -n monitoring get svc
```

Con il nome Release `monitoring`, il Service è comunemente `monitoring-grafana`:

```bash
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
```

Apri `http://localhost:3000`.

La password amministrativa è normalmente salvata in un Secret Kubernetes; verifica il nome e recuperala **solo** in un terminale sicuro:

```bash
kubectl -n monitoring get secret monitoring-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d
echo
```

Il nome o il metodo di autenticazione possono variare con i valori del Chart. Non pubblicare la password e non inserirla nel repository.

## 6.2 Prometheus

Verifica prima il Service effettivo:

```bash
kubectl -n monitoring get svc
```

Nome comune con questa Release:

```bash
kubectl -n monitoring port-forward \
  svc/monitoring-kube-prometheus-prometheus 9090:9090
```

Apri `http://localhost:9090`. Puoi consultare le query e la pagina **Targets**. I due `port-forward` richiedono terminali distinti, oppure processi gestiti consapevolmente.

---

# 7. PromQL: query da saper spiegare

## 7.1 `up`: la prima query

```promql
up
```

`up=1`: l'ultimo scrape è riuscito. `up=0`: lo scrape è fallito. **Non equivale** alla salute end-to-end dell'applicazione.

```promql
count(up == 0)
```

Conta i target che risultano non raggiungibili nel momento valutato.

## 7.2 Stato dei Deployment

```promql
kube_deployment_status_replicas_available{namespace="lab"}
```

Questa metrica richiede che kube-state-metrics sia disponibile e raccolto correttamente.

## 7.3 Memoria dei container

```promql
container_memory_working_set_bytes{
  namespace="lab",
  container!="",
  image!=""
} / 1024 / 1024
```

Converte il working set stimato da byte a MiB. Verifica quali label e metriche sono effettivamente disponibili nella tua installazione.

## 7.4 CPU dei container

```promql
rate(container_cpu_usage_seconds_total{
  namespace="lab",
  container!="",
  image!=""
}[5m])
```

È il tasso di incremento, negli ultimi cinque minuti, dei secondi CPU cumulativi. Il risultato corrisponde a una quantità equivalente di core CPU: `0.25` ≈ un quarto di CPU, `1.00` ≈ una CPU.

In millicore:

```promql
1000 * rate(container_cpu_usage_seconds_total{
  namespace="lab",
  container!="",
  image!=""
}[5m])
```

## 7.5 Counter e Gauge

- **Counter**: cumulativo che normalmente aumenta e può resettarsi quando il processo si riavvia. Esempi: `http_requests_total`, `container_cpu_usage_seconds_total`.
- **Gauge**: può salire e scendere. Esempi: `node_memory_MemAvailable_bytes`, `kube_deployment_status_replicas_available`.

Un Counter di `10000` richieste dice poco sul carico attuale. Per ottenere le richieste al secondo:

```promql
rate(http_requests_total[5m])
```

Non applicare indiscriminatamente `rate()` alle Gauge: il significato del risultato cambierebbe.

## 7.6 Altre query pratiche

Riavvii stimati nell'intervallo:

```promql
sum by (namespace, pod, container) (
  increase(kube_pod_container_status_restarts_total[30m])
)
```

Memoria non disponibile, stima percentuale per nodo:

```promql
100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)
```

CPU non idle per nodo:

```promql
100 * (
  1 - avg by (instance) (
    rate(node_cpu_seconds_total{mode="idle"}[5m])
  )
)
```

---

# 8. Laboratorio: un'app con `/metrics` e `ServiceMonitor`

Ora creiamo un'app dimostrativa con:

- `/work`: genera una richiesta applicativa e aumenta un Counter;
- `/health`: risponde `ok` alla readiness;
- `/metrics`: restituisce metriche testuali per Prometheus.

Usiamo una piccola applicazione Python con libreria standard. È **didattica**; per progetti reali è consigliabile usare le librerie client ufficiali Prometheus e gestire meglio errori, eccezioni e telemetria.

## 8.1 File completo `demo-metrics.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: lab-metrics
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: demo-metrics-code
  namespace: lab-metrics
data:
  app.py: |
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
    from threading import Lock
    import time

    requests = 0
    duration_sum = 0.0
    lock = Lock()

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            global requests, duration_sum

            if self.path == "/health":
                body = b"ok\n"
                content_type = "text/plain"

            elif self.path == "/work":
                start = time.monotonic()
                time.sleep(0.02)
                elapsed = time.monotonic() - start

                with lock:
                    requests += 1
                    duration_sum += elapsed

                body = b"lavoro completato\n"
                content_type = "text/plain"

            elif self.path == "/metrics":
                with lock:
                    count = requests
                    total = duration_sum

                metrics = (
                    "# HELP demo_requests_total Richieste di lavoro\n"
                    "# TYPE demo_requests_total counter\n"
                    f"demo_requests_total {count}\n"
                    "# HELP demo_request_duration_seconds Durata lavoro\n"
                    "# TYPE demo_request_duration_seconds summary\n"
                    f"demo_request_duration_seconds_sum {total}\n"
                    f"demo_request_duration_seconds_count {count}\n"
                )
                body = metrics.encode()
                content_type = "text/plain; version=0.0.4"

            else:
                body = b"not found\n"
                content_type = "text/plain"
                self.send_response(404)
                self.send_header("Content-Type", content_type)
                self.end_headers()
                self.wfile.write(body)
                return

            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    ThreadingHTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-metrics
  namespace: lab-metrics
spec:
  replicas: 1
  selector:
    matchLabels:
      app: demo-metrics
  template:
    metadata:
      labels:
        app: demo-metrics
    spec:
      automountServiceAccountToken: false
      containers:
        - name: app
          image: python:3.12-alpine
          command: ["python", "-u", "/app/app.py"]
          ports:
            - name: metrics
              containerPort: 8000
          volumeMounts:
            - name: code
              mountPath: /app
              readOnly: true
          readinessProbe:
            httpGet:
              path: /health
              port: metrics
          resources:
            requests:
              cpu: 20m
              memory: 32Mi
            limits:
              memory: 128Mi
      volumes:
        - name: code
          configMap:
            name: demo-metrics-code
---
apiVersion: v1
kind: Service
metadata:
  name: demo-metrics
  namespace: lab-metrics
  labels:
    app: demo-metrics
spec:
  selector:
    app: demo-metrics
  ports:
    - name: metrics
      port: 8000
      targetPort: metrics
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: demo-metrics
  namespace: lab-metrics
  labels:
    release: monitoring
spec:
  selector:
    matchLabels:
      app: demo-metrics
  namespaceSelector:
    matchNames:
      - lab-metrics
  endpoints:
    - port: metrics
      path: /metrics
      interval: 15s
```

**Nota:** `ServiceMonitor` è una CRD dell'Operator: l'apply fallisce se le CRD non sono ancora installate. Installa prima la stack.

## 8.2 Tre selector, tre passaggi

```text
Prometheus
  selector ServiceMonitor: release=monitoring
       ↓
ServiceMonitor demo-metrics
  selector Service: app=demo-metrics
       ↓
Service demo-metrics
  selector Pod: app=demo-metrics
       ↓
Pod :8000/metrics
```

Il campo `endpoints[].port: metrics` si riferisce al **nome della porta nel Service**, non al numero e non necessariamente al nome del container. Se manca una label, l'oggetto a valle non viene selezionato: collegamento alla Lezione 08 sul Service con selector errato.

## 8.3 Applica e testa

```bash
kubectl apply -f demo-metrics.yaml
kubectl -n lab-metrics rollout status deploy/demo-metrics
kubectl -n lab-metrics get pods,svc,servicemonitors
```

Apri il port-forward in un terminale:

```bash
kubectl -n lab-metrics port-forward svc/demo-metrics 8000:8000
```

Da un altro terminale:

```bash
for i in $(seq 100); do
  curl -fsS http://localhost:8000/work >/dev/null
done
curl -s http://localhost:8000/metrics
```

Output illustrativo:

```text
# HELP demo_requests_total Richieste di lavoro
# TYPE demo_requests_total counter
demo_requests_total 100
# HELP demo_request_duration_seconds Durata lavoro
# TYPE demo_request_duration_seconds summary
demo_request_duration_seconds_sum 2.01
demo_request_duration_seconds_count 100
```

Le cifre dipendono dall'esecuzione. Il Counter vive in memoria e riparte da zero quando il processo riparte.

## 8.4 Verifica in Prometheus

Nella UI Prometheus controlla che il target venga scoperto e sia `UP`; poi esegui:

```promql
demo_requests_total
```

E:

```promql
rate(demo_requests_total[1m])
```

Per ottenere un rate significativo servono almeno due scrape e traffico mentre vengono raccolti i campioni:

```bash
for i in $(seq 120); do
  curl -fsS http://localhost:8000/work >/dev/null
  sleep 0.2
done
```

**Non confondere scrape e richiesta applicativa:** Prometheus legge periodicamente i contatori cumulativi; non registra ogni singola richiesta in tempo reale.

---

# 9. Dashboard Grafana

La stack generalmente crea automaticamente una datasource Prometheus in Grafana. Verificala prima di crearne un'altra.

Crea una dashboard chiamata **Laboratorio Kubernetes — Metriche applicazione**.

## Pannello A: richieste al secondo

```promql
sum(rate(demo_requests_total[1m]))
```

Visualizzazione: Time series. Unità: richieste/secondo.

## Pannello B: valore cumulativo corrente

```promql
sum(demo_requests_total)
```

Visualizzazione: Stat. Attenzione: è la somma dei Counter correnti, **non** il totale storico affidabile lungo i riavvii dei processi.

## Pannello C: durata media in millisecondi

```promql
1000 *
sum(rate(demo_request_duration_seconds_sum[5m]))
/
sum(rate(demo_request_duration_seconds_count[5m]))
```

Il nostro exporter demo espone `sum` e `count` di una Summary, sufficienti per una media recente.

## Perché P95 e P99?

Una media può nascondere richieste molto lente. P95 indica circa il valore sotto il quale cade il 95% delle osservazioni; P99 è ancora più sensibile alla coda della distribuzione.

Con istogrammi classici, un esempio è:

```promql
histogram_quantile(
  0.95,
  sum by (le) (
    rate(http_request_duration_seconds_bucket[5m])
  )
)
```

Questa query è **illustrativa**: l'app demo non espone `http_request_duration_seconds_bucket`. Richiede un exporter con bucket di istogramma.

---

# 10. Alerting: PrometheusRule e Alertmanager

Una dashboard è utile quando la guardi; un alert rileva automaticamente una condizione.

- Prometheus valuta le regole.
- Alertmanager riceve, raggruppa, silenzia e instrada alert verso receiver configurati.
- Grafana possiede anche un sistema di alerting proprio: non va confuso automaticamente con PrometheusRule.

## 10.1 File `demo-alert.yaml`

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: demo-alert
  namespace: monitoring
  labels:
    release: monitoring
spec:
  groups:
    - name: laboratorio.rules
      rules:
        - alert: DemoMetricsNonDisponibile
          expr: |
            kube_deployment_status_replicas_available{
              namespace="lab-metrics",
              deployment="demo-metrics"
            } < 1
          for: 1m
          labels:
            severity: warning
          annotations:
            summary: "Applicazione demo-metrics non disponibile"
            description: "Il Deployment non ha repliche disponibili."
```

**Nota importante:** affinché Prometheus carichi questa `PrometheusRule`, il `ruleSelector` e il `ruleNamespaceSelector` della risorsa Prometheus devono includerla. La label `release: monitoring` è appropriata per molte installazioni, ma verifica i selector effettivi del Chart scelto.

## 10.2 Prova controllata

```bash
kubectl apply -f demo-alert.yaml
kubectl -n lab-metrics scale deploy/demo-metrics --replicas=0
```

Se la metrica viene raccolta e la regola è selezionata, l'alert attraversa:

```text
Inactive → Pending (condizione vera, meno di 1 minuto) → Firing
```

`for: 1m` richiede persistenza della condizione per un minuto. L'intervallo di valutazione e quello di scrape influiscono sui tempi effettivi.

Ripristina:

```bash
kubectl -n lab-metrics scale deploy/demo-metrics --replicas=1
```

**Firing non significa email inviata:** per ricevere notifiche va configurato un receiver/route in Alertmanager o in un altro sistema di alerting.

---

# 11. Troubleshooting di Prometheus

Applica il metodo della Lezione 08: **stato → eventi → log → dentro → intorno**.

| Sintomo | Possibile causa e verifica |
|---|---|
| Pod Prometheus `Pending` | CPU/RAM insufficienti, PVC, vincoli; usa `describe` |
| ServiceMonitor presente ma target assente | Selector Prometheus, label, namespace, Service, nome della porta |
| Target presente ma `DOWN` | Connettività, path, porta, TLS, NetworkPolicy, autenticazione |
| Grafana non mostra dati | Datasource, query, intervallo temporale |
| Alert non compare | `PrometheusRule` e relativi selector |
| Alert Firing ma niente messaggi | Configurazione receiver/route Alertmanager |
| Molte serie e memoria alta | Cardinalità, numero target e retention |

Comandi da usare:

```bash
kubectl -n monitoring get pods
kubectl -n lab-metrics get pods
kubectl -n lab-metrics get svc demo-metrics --show-labels
kubectl -n lab-metrics get endpointslices \
  -l kubernetes.io/service-name=demo-metrics
kubectl -n lab-metrics describe servicemonitor demo-metrics
kubectl -n monitoring get prometheus -o yaml
```

Verifica anche che l'endpoint risponda:

```bash
kubectl -n lab-metrics port-forward svc/demo-metrics 8000:8000
# in un altro terminale
curl -s http://localhost:8000/metrics
```

**Principio:** un oggetto `ServiceMonitor` creato con successo non garantisce che Prometheus lo abbia selezionato; un target selezionato non garantisce che lo scrape riesca; e `up=1` non garantisce che il servizio applicativo sia sano end-to-end.

---

# 12. Collegamento alla Lezione 21: monitorare HAProxy

La Lezione 21 usa due repliche HAProxy Ingress Controller, backend `blu` e `verde`, Runtime API e rate limiting. Questa lezione estende quel percorso: invece di osservare solo `haproxy.cfg`, socket e `/stats`, vogliamo **osservare l'andamento nel tempo**.

```text
Client → HAProxy Ingress (2 repliche) → Pod blu / verde
                 │
        metriche / exporter
                 ↓
             Prometheus
                 ↓
               Grafana
```

Per monitorare HAProxy bisogna che il controller, il processo HAProxy o un exporter dedicato esponga metriche in formato Prometheus e che quelle metriche siano raccolte da Prometheus. **La pagina CSV `/stats;csv` da sola non equivale automaticamente a un endpoint `/metrics`.** La configurazione dipende dalla distribuzione e dalla versione del controller/Chart usato.

**Pannelli interessanti da costruire:**

| Pannello | Domanda |
|---|---|
| Richieste HTTP al secondo | Quanto traffico passa dal proxy? |
| Connessioni attive | Quante connessioni gestisce ciascuna replica? |
| Stato dei backend e server | Quali server sono UP/DOWN? |
| Risposte 4xx/5xx | Quali errori HTTP crescono? |
| Richieste rate-limited | Quante richieste vengono respinte? |
| Reload/config updates | L'aggiunta di Pod richiede reload? |

**Collegamento cruciale:** nella Lezione 21 ogni replica HAProxy mantiene proprie connessioni, contatori e stick-table per il rate limiting. In Grafana bisogna capire se una metrica descrive una singola replica oppure se occorre aggregare i dati delle due repliche. Aggregare correttamente richiede di controllare le label e la semantica concreta delle metriche esportate.

### Esperimento aggiuntivo suggerito

1. Sul cluster `lab-haproxy`, abilita o verifica l'esposizione delle metriche del controller HAProxy, secondo il Chart in uso.
2. Crea un ServiceMonitor corrispondente ai reali Service e porte metriche.
3. Genera traffico verso `/blu` e `/verde`.
4. Scala il Deployment `blu` da 3 a 5 e torna a 3.
5. Osserva backend/server UP, richieste per secondo e contatori per replica.
6. Ripeti il rate limit su `limitato.lab.local` e spiega perché due repliche possono avere conteggi differenti.

Questo è un **approfondimento progettuale**, non un manifest pronto all'uso: i nomi degli endpoint e le metriche HAProxy vanno verificati sulla versione reale installata.

---

# 13. Sicurezza, storage e cardinalità

## Sicurezza

Nel laboratorio accediamo tramite `kubectl port-forward`, senza creare Ingress pubblici per Prometheus e Grafana. In produzione considera autenticazione, TLS, NetworkPolicy, RBAC e protezione delle credenziali.

## Persistenza

Il laboratorio non configura esplicitamente storage persistente per Prometheus. Le serie memorizzate in storage effimero possono andare perse quando il Pod viene sostituito. In produzione servono PVC/storage appropriati, retention e backup/strategie di recupero. Collegamento alla Lezione 05.

## Cardinalità

Evita label con valori praticamente illimitati, come `request_id`, `session_id`, `user_id` o URL che includono ID univoci. Ogni combinazione di label crea una serie distinta e può far crescere enormemente il costo di memoria e storage di Prometheus.

Preferisci dimensioni limitate e stabili: metodo HTTP, route normalizzata, categoria di status code, nome del servizio.

---

# 14. Esercizi e quiz

## Esercizio A — Leggere il cluster

Apri Prometheus ed esegui:

```promql
up
count(up == 0)
kube_deployment_status_replicas_available
```

Spiega la differenza tra **target raggiungibile** e **Deployment con repliche disponibili**.

## Esercizio B — Grafico del traffico

Genera richieste a `/work`, visualizza `demo_requests_total`, poi usa:

```promql
rate(demo_requests_total[1m])
```

Perché il valore di `demo_requests_total` aumenta ma il valore di `rate()` può scendere anche mentre il contatore totale sale?

## Esercizio C — Incident simulato

Porta il Deployment a zero repliche, osserva la metrica di disponibilità e l'alert. Poi ripristina una replica. Spiega `Inactive`, `Pending`, `Firing` e il significato di `for: 1m`.

## Esercizio D — Selezione dei target

Rimuovi temporaneamente la label `release: monitoring` dal `ServiceMonitor`, verifica se il target resta monitorato e ripristina la label. Esegui questa prova soltanto nel namespace di laboratorio.

## Quiz — Domande e risposte

**1. Prometheus e Grafana fanno lo stesso lavoro?**  
No. Prometheus raccoglie, conserva e interroga serie temporali; Grafana visualizza dati provenienti da Prometheus e da altre sorgenti.

**2. Chi espone i dati di stato dei Deployment?**  
`kube-state-metrics`.

**3. `up=1` garantisce che l'app funzioni?**  
No. Significa che lo scrape delle metriche è riuscito.

**4. Un ServiceMonitor seleziona direttamente un Deployment?**  
No. Seleziona Service tramite label e configura endpoint di scrape; il Service individua i Pod attraverso il proprio selector.

**5. Perché si usa `rate()` su un Counter?**  
Per stimare il suo tasso di incremento nell'intervallo, ad esempio richieste al secondo.

**6. L'HPA standard usa Prometheus automaticamente?**  
No. Il percorso standard usa la Resource Metrics API, normalmente attraverso `metrics-server`.

**7. Che cosa significa `for: 1m` in una PrometheusRule?**  
La condizione deve essere verificata continuativamente per almeno un minuto prima che l'alert diventi `firing`.

**8. Perché due HAProxy possono avere rate limit diversi?**  
Perché ogni replica può mantenere una stick-table e contatori locali, se lo stato non è sincronizzato.

---

# Riferimenti pubblici utili

- Prometheus documentation: https://prometheus.io/docs/introduction/overview/
- PromQL basics: https://prometheus.io/docs/prometheus/latest/querying/basics/
- Metric types: https://prometheus.io/docs/concepts/metric_types/
- Prometheus Operator: https://prometheus-operator.dev/docs/
- kube-prometheus-stack Chart: https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack
- Grafana + Prometheus datasource: https://grafana.com/docs/grafana/latest/datasources/prometheus/
- Alertmanager: https://prometheus.io/docs/alerting/latest/alertmanager/

---

**Messaggio finale della lezione:** Prometheus raccoglie, conserva e interroga metriche. Grafana le visualizza. Prometheus Operator integra la raccolta nel modello dichiarativo di Kubernetes. `ServiceMonitor` collega i Service applicativi agli scrape; `PrometheusRule` permette di rilevare condizioni problematiche; Alertmanager gestisce l'inoltro degli alert. Per HAProxy, due repliche richiedono attenzione speciale all'aggregazione e allo stato locale.
