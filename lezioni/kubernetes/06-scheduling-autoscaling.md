# 06 — Scheduling e autoscaling: dove girano i Pod e quanti

Spiegazione di `06-scheduling-autoscaling.yaml` (questa cartella). Lezione sul sito: http://127.0.0.1:3000/kubernetes/6

## In una frase

Il file crea un Deployment **`api`** (whoami) che lo scheduler **distribuisce sui due nodi** (topology spread), con una
**priorità alta** (PriorityClass), una **toleration** per un taint e una nodeAffinity "morbida"; davanti un Service e una
NetworkPolicy; e un **HorizontalPodAutoscaler** che ne decide il numero (da 2 a 8) in base alla CPU. Il runner genera
carico, guarda l'HPA salire, poi prova un **taint** sul nodo `lab-m02`.

## Due file con lo stesso nome: quale lanciare

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/lezioni/kubernetes/06-scheduling-autoscaling.yaml` | **questo**: i manifest, con la teoria nei commenti | si **legge**; lo applica il runner (o a mano: `kubectl apply -f 06-scheduling-autoscaling.yaml`) |
| `~/kubernetesprj/kubernetes/06-scheduling-autoscaling.sh` | lo script **guidato**: applica, carica, osserva l'HPA, mette e toglie il taint, un passo per volta (Invio / s / q) | `bash kubernetes/06-scheduling-autoscaling.sh` |

Servono il namespace `lab` (lezione 02), l'addon **metrics-server** e i **2 nodi** (lezione 01).

## Com'è fatto il file

```
intestazione (commenti)        → teoria: DOVE (scheduling) e QUANTI (autoscaling), formula dell'HPA,
                                 comandi LAB, NEL PROGETTO VERO
PriorityClass lab-critico      → priorità 100000, può espellere Pod meno importanti
Service api                    → porta 80 → 8080
NetworkPolicy api-allow-client → api accetta solo da ruolo=client
Deployment api                 → senza replicas; spread, priorità, toleration, nodeAffinity, requests
HorizontalPodAutoscaler api    → 2-8 repliche al 60% della CPU, con behavior
coda (commenti)                → domande da colloquio, riepilogo
```

Versione: Kubernetes 1.34–1.35 (lab 1.34.0), `autoscaling/v2`, metrics-server.

---

## 1. La teoria nell'intestazione

### DOVE: come lo scheduler sceglie il nodo

Lo scheduler prima **filtra** i nodi (scarta quelli che non vanno), poi dà un **punteggio** agli altri. Gli strumenti,
dal più rigido al più morbido:

| Strumento | Cosa fa |
|---|---|
| `nodeSelector` | etichetta del nodo **obbligatoria** |
| `nodeAffinity` required / preferred | espressioni (`In`, `NotIn`, `Exists`…), obbligatorie o solo preferite |
| taints + tolerations | è il **nodo** che respinge chi non tollera: nodi GPU, nodi dedicati, control plane |
| `podAntiAffinity` | non accanto a un altro Pod (per label) — lezione 05 |
| `topologySpreadConstraints` | distribuzione uniforme su zone/nodi, con `maxSkew`: la scelta moderna per l'HA |
| `PriorityClass` | chi viene prima; se manca spazio, i Pod a priorità bassa vengono **espulsi** |

Differenza chiave: **affinity attrae** (il Pod sceglie il nodo), **taint respinge** (il nodo sceglie i Pod).

### QUANTI: tre autoscaler, tre domande diverse

| Autoscaler | Domanda | Note |
|---|---|---|
| **HPA** | quante **repliche** | CPU, memoria, metriche custom/esterne |
| **VPA** | quante **risorse** per replica (requests) | non mischiarlo con un HPA sulla stessa metrica CPU |
| **Cluster Autoscaler / Karpenter** | quanti **nodi** | aggiunge nodi quando ci sono Pod Pending per risorse, li toglie quando sono sottoutilizzati |
| **KEDA** | HPA guidato da **eventi** | lunghezza di una coda, lag Kafka, cron; anche fino a **zero** repliche |

### La formula dell'HPA

```
desiderate = ceil(attuali × valoreAttuale / target)
```

La percentuale di CPU è riferita alle **requests** del container: **senza requests** l'HPA mostra `<unknown>`, perché
manca il denominatore.

### I comandi LAB dell'intestazione

```bash
kubectl apply -f 06-scheduling-autoscaling.yaml
kubectl -n lab get pod -l app=api -o wide          # distribuiti sui nodi
kubectl -n lab get hpa api -w                      # TARGETS: x%/60%
kubectl -n lab run carico --rm -it --image=busybox:1.37 --labels=ruolo=client -- \
    sh -c 'while true; do wget -q -O- http://api/ >/dev/null; done'
(Ctrl+C ferma il carico; con --rm il Pod sparisce da solo)
kubectl -n lab describe hpa api                    # eventi di scala
kubectl top pod -n lab
kubectl taint nodes lab-m02 dedicato=batch:NoSchedule   # poi rimuovilo con "-"
```

Il runner fa lo stesso ma con un carico **in background e a tempo** (120 s), così non serve un secondo terminale.

### Riquadro «NEL PROGETTO VERO»

In `~/biodistretto/kubernetes`:

- backend, frontend e nginx usano **`topologySpreadConstraints` su hostname, con `maxSkew 1`**. Con 2 repliche e 2 nodi
  ne va una per nodo. Con `ScheduleAnyway`, se un nodo è giù il Pod parte comunque sull'altro.
  ```bash
  grep -n -A6 'topologySpreadConstraints' terraform/app/manifests/app.yaml.tftpl
  ```
- metrics-server è un addon del cluster, quindi un HPA funzionerebbe:
  ```bash
  grep -n 'metrics-server' terraform/cluster/variables.tf
  ```
- **TRAPPOLA**: le repliche le decide Terraform (`repliche_web`). Se aggiungi un HPA, **Terraform e HPA si contendono
  `spec.replicas`**, e ogni apply riporta il numero al valore del codice. Con l'HPA, toglilo dal template.

---

## 2. La PriorityClass `lab-critico`

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: lab-critico
value: 100000
preemptionPolicy: PreemptLowerPriority
globalDefault: false
description: "Servizi che devono restare su anche a cluster pieno"
```

| Campo | Perché |
|---|---|
| nessun `namespace` | la PriorityClass è un oggetto **di cluster**, vale per tutti i namespace |
| `value: 100000` | più alto = più importante. I Pod senza classe hanno priorità 0 |
| `preemptionPolicy: PreemptLowerPriority` | se un Pod `lab-critico` non trova posto, lo scheduler può **espellere** Pod a priorità più bassa per fargli spazio (l'altra scelta è `Never`) |
| `globalDefault: false` | non viene assegnata automaticamente ai Pod che non la chiedono |

---

## 3. Service e NetworkPolicy

```yaml
kind: Service
spec:
  selector: { app: api }
  ports:
    - port: 80
      targetPort: 8080
```

Service ClusterIP (il tipo di default) che porta `api:80` sulla 8080 dei Pod. Qui `targetPort` è un **numero**, non un
nome come nella lezione 03: funziona, ma se cambiasse la porta del container andrebbe cambiato anche qui.

```yaml
kind: NetworkPolicy
metadata:
  name: api-allow-client
spec:
  podSelector:
    matchLabels: { app: api }
  ingress:
    - from:
        - podSelector:
            matchLabels: { ruolo: client }
```

- Se la lezione 03 è applicata, nel namespace c'è già il **default deny** in ingresso: senza questa policy nessuno
  potrebbe chiamare `api`, nemmeno il generatore di carico.
- `policyTypes` è omesso: con una sezione `ingress` presente, Kubernetes la considera una policy di tipo `Ingress`.
- Nessuna `ports`: da `ruolo=client` si entra su **tutte** le porte.
- Per questo il Pod `carico` del runner ha `--labels=ruolo=client`.

---

## 4. Il Deployment `api` — campo per campo

### Niente `replicas`

```yaml
spec:
  # niente "replicas": con un HPA il numero lo decide lui
```

Se lasci `replicas` nel manifest, ogni `kubectl apply` lo riporta al valore del file e l'HPA lo rialza: **flapping**.
È la stessa trappola del riquadro Terraform. Senza il campo, il Deployment nasce con 1 replica e l'HPA la porta subito
al suo minimo (2).

### `priorityClassName: lab-critico`

Collega i Pod alla PriorityClass della sezione 2.

### `topologySpreadConstraints`

```yaml
- maxSkew: 1
  topologyKey: kubernetes.io/hostname    # in cloud: topology.kubernetes.io/zone
  whenUnsatisfiable: ScheduleAnyway      # DoNotSchedule = vincolo rigido
  labelSelector:
    matchLabels: { app: api }
```

| Campo | Significato |
|---|---|
| `topologyKey: kubernetes.io/hostname` | il "dominio" è il singolo nodo. In cloud si usa la **zona** |
| `labelSelector` | quali Pod contare: quelli `app: api` |
| `maxSkew: 1` | la differenza fra il dominio con più Pod e quello con meno non deve superare 1 (es. 4 e 4, o 5 e 4, mai 6 e 3) |
| `whenUnsatisfiable: ScheduleAnyway` | se non si riesce, il Pod parte lo stesso (lo spread diventa un punteggio). `DoNotSchedule` lo lascerebbe Pending |

A differenza della `podAntiAffinity` (lezione 05), lo spread funziona bene anche con **più repliche che nodi**: con 8
repliche e 2 nodi ne mette 4 e 4.

### `tolerations`

```yaml
- key: dedicato
  operator: Equal
  value: batch
  effect: NoSchedule
```

Il Pod **tollera** i nodi con taint `dedicato=batch:NoSchedule`, ma **non li richiede**. Il commento del file è il
punto: per **forzare** un Pod su un nodo dedicato servono **toleration + nodeAffinity insieme** (la toleration toglie il
divieto, l'affinity crea l'attrazione).

### `nodeAffinity` preferita

```yaml
nodeAffinity:
  preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 50
      preference:
        matchExpressions:
          - key: kubernetes.io/os
            operator: In
            values: [linux]
```

Una **preferenza** (peso 50) per i nodi con label `kubernetes.io/os=linux`. Nel lab tutti i nodi sono Linux, quindi non
cambia niente: è lì per mostrare la sintassi di `matchExpressions`.

### Container, risorse e probe

```yaml
image: traefik/whoami:v1.12
args: ["--port", "8080"]
resources:
  requests: { cpu: 20m, memory: 16Mi }    # base del calcolo HPA
  limits: { memory: 32Mi }
readinessProbe:
  httpGet: { path: /health, port: 8080 }
```

La **request di CPU di 20m** è il denominatore dell'HPA: il 60% di 20m = **12m** medi per Pod. Basta pochissimo carico
per superarla, ed è voluto: così nel lab l'HPA sale in fretta. La readiness fa entrare nel Service solo i Pod pronti.

---

## 5. L'HorizontalPodAutoscaler `api`

```yaml
scaleTargetRef:
  apiVersion: apps/v1
  kind: Deployment
  name: api
minReplicas: 2
maxReplicas: 8
metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 60
```

| Campo | Significato |
|---|---|
| `scaleTargetRef` | cosa scalare: il Deployment `api` (l'HPA scrive il suo `spec.replicas`) |
| `minReplicas` / `maxReplicas` | mai meno di 2, mai più di 8 |
| `type: Resource`, `cpu`, `Utilization 60` | obiettivo: CPU media **pari al 60% delle requests** |

### `behavior`: evitare le oscillazioni

```yaml
behavior:
  scaleUp:
    stabilizationWindowSeconds: 0
    policies:
      - { type: Percent, value: 100, periodSeconds: 15 }
  scaleDown:
    stabilizationWindowSeconds: 120
    policies:
      - { type: Pods, value: 1, periodSeconds: 60 }
```

| Direzione | Regola | Effetto |
|---|---|---|
| su | finestra 0, +100% ogni 15 s | sale **subito**, al massimo **raddoppiando** ogni 15 s |
| giù | finestra 120 s, 1 Pod ogni 60 s | scende solo se il calo dura **2 minuti**, e un Pod al minuto |

Salire in fretta e scendere piano: un picco breve non fa partire un ping-pong di Pod.

---

## 6. Il runner, passo per passo

`guardia_lab`, poi 10 passi e una `nota`:

| # | Comando | Cosa vedi |
|---|---|---|
| 1 | `kubectl apply -f …/06-scheduling-autoscaling.yaml` | `priorityclass…/lab-critico`, `service/api`, `networkpolicy…/api-allow-client`, `deployment.apps/api`, `horizontalpodautoscaler…/api` |
| 2 | `kubectl -n lab get pod -l app=api -o wide` | colonna NODE: i Pod distribuiti su `lab` e `lab-m02` |
| 3 | ciclo `for i in $(seq 30); do kubectl top pod … && break; sleep 5; done; kubectl top pod -n lab -l app=api` | attende fino a 150 s che metrics-server abbia le metriche (i Pod nuovi le hanno dopo **~1 minuto**; finché mancano l'HPA non decide), poi CPU e memoria per Pod |
| 4 | `kubectl -n lab run carico --restart=Never --image=busybox:1.37 --labels=ruolo=client -- sh -c '…120 s di wget su http://api/…'` | parte il Pod di carico, in background (niente `-i`): il runner va avanti |
| 5 | `timeout 90 kubectl -n lab get hpa api -w \|\| true` | per 90 s: TARGETS sale sopra `60%`, REPLICAS aumenta. `timeout` chiude il `-w`; `\|\| true` evita il rosso per l'uscita di timeout |
| 6 | `get deploy api -o jsonpath='{…requests}'; echo; top pod -l app=api` | `{"cpu":"20m","memory":"16Mi"}` e il consumo reale dei Pod |
| — | `nota` | il fatto **misurato sul lab** (sotto) |
| 7 | `kubectl -n lab describe hpa api \| tail -15` | gli eventi `SuccessfulRescale` con il motivo ("cpu resource utilization … above target") |
| 8 | `kubectl taint nodes lab-m02 dedicato=batch:NoSchedule; describe node lab-m02 \| grep -A2 Taints` | il taint sul nodo. `NoSchedule`: i Pod **già** lì restano (con `NoExecute` verrebbero espulsi) |
| 9 | `kubectl taint nodes lab-m02 dedicato=batch:NoSchedule-` | il **trattino finale** = rimuovi |
| 10 | `kubectl -n lab delete pod carico --ignore-not-found` | pulizia. L'HPA riscende da solo: dopo 120 s di calo, un Pod al minuto |

### Il fatto misurato (la `nota`)

> Esempio misurato sul lab: TARGETS **375%** = **75m per Pod** su 20m di request.
> desiderate = ceil(2 × 375 / 60) = **13** → tagliate a **maxReplicas 8**; la policy **+100% ogni 15 s** le fa salire
> **2 → 4 → 8**.

È la formula dell'intestazione applicata ai numeri veri: la formula chiederebbe 13, il `maxReplicas` taglia a 8, e il
`behavior.scaleUp` impone il ritmo (raddoppio ogni 15 s).

Nessun passo fallisce apposta. Da notare al passo 8: il Deployment `api` ha **proprio** la toleration
`dedicato=batch:NoSchedule`, quindi i **suoi** Pod nuovi possono ancora andare su `lab-m02`; il taint respinge gli
altri (per esempio i Pod di `web` della lezione 02).

---

## 7. Le trappole

| Trappola | Cosa succede | Rimedio |
|---|---|---|
| container senza requests di CPU | HPA `<unknown>/60%` | requests sempre, sono il denominatore |
| metrics-server assente o appena partito | HPA `<unknown>` | addon attivo; aspettare ~1 minuto |
| `replicas` nel manifest con un HPA | ogni apply lo riporta al valore del file (flapping) | toglierlo dal manifest (o dal template Terraform) |
| toleration pensata come "vai su quel nodo" | il Pod può andarci, non è obbligato | toleration + nodeAffinity |
| `DoNotSchedule` con un nodo giù | Pod Pending | `ScheduleAnyway` se la disponibilità conta più della simmetria |
| VPA e HPA sulla stessa metrica CPU | si combattono | VPA in modo "Off" come raccomandatore |
| default deny della lezione 03 senza policy per api | il carico non arriva, l'HPA non sale | `api-allow-client` + label `ruolo=client` |
| taint `NoSchedule` aspettandosi lo sgombero | i Pod già presenti restano | `NoExecute` o un drain |

---

## 8. La coda: domande da colloquio

- **Un Pod è Pending. Cause possibili?** `kubectl describe pod` → eventi `FailedScheduling`: "Insufficient cpu"
  (requests troppo alte o cluster pieno: lì entra l'autoscaler dei nodi), "didn't tolerate taint", "didn't match node
  affinity", "unbound PersistentVolumeClaim", vincolo di spread `DoNotSchedule`.
- **L'HPA mostra `<unknown>/60%`.** metrics-server assente o non pronto, oppure il container non ha requests di CPU (la
  percentuale non ha un denominatore).
- **Requests e limits: come le dimensioni?** Dai dati, non a occhio: p95 dell'uso reale (Prometheus, VPA in modo "Off"
  come raccomandatore) per le requests, margine per i picchi. Requests troppo basse = nodi sovraffollati e sfratti;
  troppo alte = cluster pagato e vuoto.
- **`topologySpreadConstraints` o `podAntiAffinity`?** L'anti-affinity dice "non insieme" (sì/no) e non scala bene oltre
  una replica per nodo. Lo spread dice "distribuiti con skew massimo N": funziona con più repliche che nodi ed è più
  leggero da calcolare.

### Comandi da sapere

| Comando | A cosa serve |
|---|---|
| `kubectl -n lab get hpa api -w` | TARGETS e REPLICAS in tempo reale |
| `kubectl -n lab describe hpa api` | gli eventi e il motivo di ogni scala |
| `kubectl top pod -n lab` | consumo reale (da metrics-server) |
| `kubectl taint nodes lab-m02 dedicato=batch:NoSchedule` / `…NoSchedule-` | mettere / togliere un taint |
| `kubectl describe node lab-m02 \| grep -A2 Taints` | i taint di un nodo |

---

## Riepilogo

- **Dove**: nodeSelector/affinity attraggono, taint respingono, spread distribuisce.
- **PriorityClass** decide chi resta quando manca spazio.
- **HPA** (repliche), **VPA** (risorse), **Cluster Autoscaler/Karpenter** (nodi), **KEDA** (eventi).
- HPA in **% delle requests**; `behavior` per evitare oscillazioni.
- Con un HPA, **niente `replicas`** nel manifest.

## Prova da solo

1. Rifai il conto della `nota` con i tuoi numeri: leggi TARGETS durante il carico e calcola
   `ceil(attuali × valore / 60)`. Torna con il numero di REPLICAS che l'HPA ha scelto? Se no, che cosa lo ha limitato?
2. Metti il taint `dedicato=batch:NoSchedule` su `lab-m02`, poi `kubectl -n lab rollout restart deploy/web` (lezione
   02): dove finiscono i Pod di `web`? E i Pod nuovi di `api` (`rollout restart deploy/api`)? Perché la differenza?
   Togli il taint alla fine.
3. Togli `requests.cpu` dal container `api`, riapplica e guarda `kubectl -n lab get hpa api`: che cosa mostra TARGETS?
   Rimetti la request.
