# 18 — Namespace: quote, limiti e cosa non isolano

Spiegazione di `18-namespace-quote.yaml` (questa cartella). Lezione sul sito: http://127.0.0.1:3000/kubernetes/18

## In una frase

Il file crea due Namespace, `lab-team-a` (con **ResourceQuota**, **LimitRange**, un Deployment e un Service) e
`lab-team-b` (vuoto), per farti vedere a cosa serve davvero un Namespace — il **punto dove si attaccano le regole** — e
cosa **non** fa: non isola la rete. Il runner lo dimostra raggiungendo un Service dell'altro Namespace e poi
bloccandolo con una NetworkPolicy.

## Due file con lo stesso nome: quale lanciare

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/lezioni/kubernetes/18-namespace-quote.yaml` | **questo**: i manifest, con la teoria nei commenti | `kubectl apply -f 18-namespace-quote.yaml` (ma conviene il guidato) |
| `~/kubernetesprj/kubernetes/18-namespace-quote.sh` | lo script **guidato**: applica il file e fa le prove una per volta, spiegando prima di eseguire (Invio / s / q) | `bash kubernetes/18-namespace-quote.sh` |

Per imparare conviene lo **guidato**. Questo file va **letto** mentre lo guidato gira: i commenti spiegano il perché.

Versione dichiarata: **Kubernetes 1.34–1.35** (il lab minikube gira la **1.34.0**). Livello 3 — Sicurezza e operatività.

## Com'è fatto il file

```
intestazione (commenti)  → cosa è un Namespace, cosa sta dentro e cosa no, a cosa serve,
                            la trappola della quota, cosa NON isola, dettagli, LAB, NEL PROGETTO VERO
Namespace lab-team-a, lab-team-b
ResourceQuota tetto      → budget totale di lab-team-a
LimitRange default-container → default e massimo per container in lab-team-a
Deployment riempi        → 2 repliche whoami con requests/limits dichiarate
Service riempi           → ClusterIP sulla porta 80
coda (commenti)          → domande da colloquio, riepilogo
```

---

## 1. La teoria nell'intestazione

### Che cos'è un Namespace

Un Namespace Kubernetes divide i **nomi** e le **policy** di un cluster: dev, test e prod, o un team ciascuno, sullo
stesso control plane. **Non ha niente a che fare con i namespace del kernel Linux** (net, pid, mnt…) che fanno i
container: stesso nome, due cose diverse.

### Cosa sta dentro e cosa no

| Tipo | Esempi |
|---|---|
| **namespaced** | Pod, Deployment, Service, ConfigMap, Secret, PVC, ServiceAccount, Role, ResourceQuota, NetworkPolicy… |
| **cluster-scoped** | Node, PersistentVolume, StorageClass, ClusterRole, CRD, PriorityClass, e il Namespace stesso |

L'elenco del tuo cluster: `kubectl api-resources --namespaced=false`.

I nomi sono unici **solo dentro** il Namespace: `api` in dev e `api` in prod convivono, ed è proprio quello che permette
gli stessi manifest ovunque.

### A cosa serve davvero: è il punto dove si attaccano le regole

| Regola | Cosa fa |
|---|---|
| **ResourceQuota** | tetto **totale** del Namespace: CPU, memoria, numero di Pod, Service, PVC, storage… |
| **LimitRange** | regole **per container/Pod**: default di requests e limits, minimi e massimi |
| **RBAC (Role)** | chi può fare cosa, lì dentro (lezione 07) |
| **Pod Security** | label sul Namespace: privileged / baseline / restricted |
| **NetworkPolicy** | chi parla con chi (lezione 03) |

### La trappola della quota

Con una quota su `requests.cpu`/`requests.memory` o `limits.memory`, **ogni Pod nuovo deve dichiarare quei valori**,
altrimenti l'apiserver lo rifiuta. Misurato:

```
pods "senza" is forbidden: failed quota: q: must specify limits.memory…
```

Con un Deployment è peggio: il rifiuto colpisce il **ReplicaSet**, i Pod **non compaiono proprio** in `get pods`, e il
Deployment resta **0/N in silenzio**. Il motivo sta negli **eventi** (`FailedCreate … exceeded quota`). Il LimitRange
risolve la prima metà: dà i default a chi non li dichiara.

E soprattutto: **la quota conta le RICHIESTE dichiarate, non il consumo reale.**

### Cosa un Namespace NON isola

| Cosa | Perché |
|---|---|
| **rete** | di default ogni Pod raggiunge ogni Pod e Service di ogni Namespace (`web.altro-ns` funziona). Serve una NetworkPolicy, e un CNI che la applica (nel lab Calico) |
| **nodi** | Pod di Namespace diversi condividono nodo e kernel: un container che evade arriva sugli altri |
| **permessi** | un ClusterRoleBinding vale in tutti i Namespace |
| **oggetti cluster-scoped** | li vedono tutti per natura |
| **nodePort** | unico nel cluster, non nel Namespace |

Per isolare **tenant ostili** non basta: servono cluster separati, o almeno nodi dedicati (taint), PSA `restricted`,
NetworkPolicy deny e RBAC stretti.

### Dettagli utili

- Ogni Namespace riceve la label **`kubernetes.io/metadata.name=<nome>`**: è quella da usare nei `namespaceSelector`
  delle NetworkPolicy (il runner la usa).
- `kubectl config set-context --current --namespace=X` cambia il Namespace di default del contesto (e lo si dimentica:
  occhio).
- Cancellare un Namespace cancella **tutto** il suo contenuto, **PVC inclusi**.
- Un Namespace bloccato in **Terminating** ha quasi sempre un finalizer o un'API aggregata/CRD che non risponde.

### Riquadro «NEL PROGETTO VERO»

In `~/biodistretto/kubernetes` (branch `kubernetes`) tutto sta nel namespace `biodistretto`, creato da Terraform:

```bash
grep -n -A4 'resource "kubernetes_namespace_v1"' terraform/app/segreti.tf
```

Ogni container ha già le requests, quindi una ResourceQuota non romperebbe niente. Quanto chiede oggi il namespace:

```bash
kubectl --context biodistretto -n biodistretto get pods -o json | jq -r \
  '[.items[].spec.containers[].resources.requests.memory] | join(" ")'
```

**Esercizio** proposto dal file: una quota appena sopra quel totale, poi
`./deploy.sh --tags immagini,app -e repliche_web=3`: quale Pod resta fuori, e cosa dice l'evento?

---

## 2. I manifest

### I due Namespace

```yaml
kind: Namespace
metadata:
  name: lab-team-a
  labels:
    team: a
---
kind: Namespace
metadata:
  name: lab-team-b
  labels:
    team: b
```

La label `team` la metti tu; `kubernetes.io/metadata.name` la aggiunge Kubernetes da solo. `lab-team-b` resta **vuoto**:
niente quota, niente LimitRange. Serve da confronto.

### ResourceQuota `tetto`

```yaml
kind: ResourceQuota
metadata:
  name: tetto
  namespace: lab-team-a
spec:
  hard:
    pods: "4"
    requests.cpu: 200m
    requests.memory: 256Mi
    limits.memory: 512Mi
    services: "3"
    persistentvolumeclaims: "2"
```

| Voce | Tetto | Nota |
|---|---|---|
| `pods` | 4 | numero di Pod (non terminati) nel Namespace |
| `requests.cpu` | 200m | somma delle **richieste** di CPU |
| `requests.memory` | 256Mi | somma delle richieste di memoria |
| `limits.memory` | 512Mi | somma dei limiti di memoria |
| `services` | 3 | numero di Service |
| `persistentvolumeclaims` | 2 | numero di PVC |

Siccome ci sono voci su `requests.*` e `limits.memory`, **ogni Pod** di `lab-team-a` deve avere quei valori (o
riceverli dal LimitRange).

### LimitRange `default-container`

```yaml
kind: LimitRange
metadata:
  name: default-container
  namespace: lab-team-a
spec:
  limits:
    - type: Container
      defaultRequest: { cpu: 25m, memory: 32Mi }   # se il Pod non le dichiara
      default: { memory: 64Mi }                    # limit di default
      max: { memory: 256Mi }                       # oltre: rifiutato
```

| Campo | Effetto |
|---|---|
| `type: Container` | le regole valgono per ogni singolo container |
| `defaultRequest` | requests messe a chi non le dichiara: 25m CPU, 32Mi |
| `default` | **limit** messo a chi non lo dichiara: 64Mi di memoria |
| `max` | un container con limit di memoria oltre 256Mi viene **rifiutato** |

Il LimitRange agisce **all'ammissione** del Pod: scrive i valori nello spec. Per questo poi li leggi con
`get pod -o jsonpath='{.spec.containers[0].resources}'`.

### Deployment e Service `riempi`

```yaml
kind: Deployment
metadata: { name: riempi, namespace: lab-team-a }
spec:
  replicas: 2
  template:
    spec:
      containers:
        - name: app
          image: traefik/whoami:v1.12
          resources:
            requests: { cpu: 25m, memory: 32Mi }
            limits: { memory: 64Mi }
---
kind: Service
metadata: { name: riempi, namespace: lab-team-a }
spec:
  selector: { app: riempi }
  ports:
    - port: 80
```

Ogni replica dichiara gli stessi valori dei default del LimitRange (25m, 32Mi, 64Mi): così un Pod "nudo" e un Pod di
`riempi` pesano uguale sulla quota, e il conto è facile. Il Service è il bersaglio delle prove di rete.

### Il conto della quota

| | Pod | requests.cpu | requests.memory | limits.memory |
|---|---|---|---|---|
| tetto | 4 | 200m | 256Mi | 512Mi |
| 1 Pod (riempi o nudo) | 1 | 25m | 32Mi | 64Mi |
| 4 Pod | 4 | 100m | 128Mi | 256Mi |

Con 4 Pod CPU e memoria sono ancora a metà: **il primo tetto a scattare è `pods: 4`**. È quello che vedi al passo 8.

---

## 3. Il runner, passo per passo

| # | Passo | Cosa vedi |
|---|---|---|
| — | `guardia_lab` | lo script si ferma se il contesto non è `lab` |
| 1 | `kubectl api-resources --namespaced=false -o name \| head -20` | le risorse **cluster-scoped** di questo cluster |
| 2 | `kubectl get ns -L kubernetes.io/metadata.name` | i Namespace con la label automatica in colonna |
| 3 | `kubectl apply -f $F && rollout status deploy/riempi` | `lab-team-a` con quota, LimitRange e 2 Pod; `lab-team-b` vuoto |
| 4 | `kubectl describe ns lab-team-a` | quota (usato / tetto) e LimitRange **in una sola vista** |
| 5 | `run nudo` in `lab-team-a` + jsonpath delle resources | un Pod **senza** resources: il LimitRange gli dà i default (25m, 32Mi, limit 64Mi), e così la quota lo accetta |
| 6 | `run nudo` in `lab-team-b` + `qos={.status.qosClass}` | stesso Pod, niente LimitRange: resources **vuote**, classe QoS **BestEffort** |
| 7 | `run grosso --overrides=…` con `limits.memory: 300Mi` | **fallisce apposta (uscita 1)**: 300Mi supera il `max` di 256Mi del LimitRange |
| 8 | `scale deploy riempi --replicas=6 && sleep 8 && get deploy && get pods` | prima ci sono 3 Pod su 4 (2 riempi + nudo). Ne entra **uno solo**: il Deployment resta a **3/6**, e gli altri Pod **non compaiono** in `get pods` |
| 9 | `get events --field-selector reason=FailedCreate -o custom-columns=MESSAGGIO:.message` | il Deployment non dà errore: il motivo (`exceeded quota` sul tetto `tetto`) è negli **eventi del ReplicaSet** |
| 10 | `describe quota tetto \| tail -8`, poi `kubectl top pods` (riprova fino a 18 × 5 s) | la colonna **Used** conta le **richieste dichiarate**; `top` mostra il consumo vero, diverso. Il ciclo aspetta che metrics-server abbia dati |
| 11 | `create service clusterip riempi` in `lab-team-b` + `get svc -A --field-selector metadata.name=riempi` | due Service `riempi`, uno per Namespace: **nessun conflitto** |
| 12 | `exec nudo` in `lab-team-b` `-- wget -qO- -T 3 http://riempi.lab-team-a` | la rete **non è isolata**: da `lab-team-b` rispondi `riempi` di `lab-team-a` con il nome `riempi.lab-team-a` |
| 13 | applica la NetworkPolicy `solo-team-a` (vedi sotto) | da qui l'ingresso in `lab-team-a` è solo dallo stesso Namespace |
| 14 | stessa `wget` da `lab-team-b` | **fallisce apposta (uscita 1)**: timeout dopo 3 s. L'isolamento lo fa la **policy** (applicata da Calico), non il Namespace |
| 15 | `exec nudo` in `lab-team-a` `-- wget … http://riempi` | da dentro `lab-team-a` passa ancora, con il nome corto |
| 16 | `set-context --current --namespace=lab-team-a`, `get pods \| wc -l`, `config view --minify` | **trappola del contesto**: `kubectl get pods` senza `-n` ora guarda `lab-team-a` |
| 17 | `set-context --current --namespace=default` | lo rimette a posto, se no i comandi delle altre lezioni cercano nel posto sbagliato |
| 18 | `kubectl delete ns lab-team-a lab-team-b` | pulizia: cancellare un Namespace cancella tutto ciò che contiene |

### La NetworkPolicy del passo 13

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: solo-team-a, namespace: lab-team-a }
spec:
  podSelector: {}
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels: { kubernetes.io/metadata.name: lab-team-a }
```

| Campo | Perché |
|---|---|
| `podSelector: {}` | vale per **tutti** i Pod di `lab-team-a` |
| `policyTypes: [Ingress]` | regola solo il traffico in entrata; da quel momento entra solo ciò che è permesso |
| `namespaceSelector` sulla label automatica | permette solo i Pod del Namespace che si chiama `lab-team-a`. La label `kubernetes.io/metadata.name` non si può falsificare: la mette Kubernetes con il nome vero |

---

## 4. Trappole

- **Quota su requests/limits senza LimitRange**: ogni Pod senza valori è rifiutato (`must specify limits.memory`).
- **Deployment 0/N muto**: i Pod rifiutati dalla quota non esistono; il motivo è negli eventi `FailedCreate` del
  ReplicaSet, non in `get pods` né in `describe deploy` come errore.
- **La quota non misura il consumo**: un Pod che dichiara 32Mi e ne usa 200 conta 32.
- **Namespace ≠ isolamento di rete**: senza NetworkPolicy (e senza un CNI che la applica) ogni Pod raggiunge tutti.
- **Namespace di default del contesto cambiato e dimenticato**.
- **`delete ns`** porta via anche i PVC, cioè i dati.
- **Namespace in Terminating** per sempre: cerca finalizer o API aggregate/CRD che non rispondono.

---

## 5. Comandi e domande da colloquio

### Comandi (dalla sezione LAB del file)

| Comando | A cosa serve |
|---|---|
| `kubectl describe ns lab-team-a` | quota e limiti in una vista |
| `kubectl -n lab-team-a run nudo --image=busybox:1.37 -- sleep 3600` | un Pod senza resources |
| `kubectl -n lab-team-a get pod nudo -o jsonpath='{.spec.containers[0].resources}'` | i valori messi dal LimitRange |
| `kubectl -n lab-team-a scale deploy riempi --replicas=6` | sfondare il tetto dei Pod |
| `kubectl -n lab-team-a get events --field-selector reason=FailedCreate` | perché i Pod non ci sono |
| `kubectl api-resources --namespaced=false` | le risorse cluster-scoped |
| `kubectl config set-context --current --namespace=X` | cambia il Namespace di default (e rimettilo) |

### Domande

- **I Namespace isolano i team fra loro?** Isolano i nomi e sono il punto dove si applicano quote, RBAC, Pod Security e
  NetworkPolicy. Da soli non isolano rete, nodi né kernel: senza NetworkPolicy un Pod di un team raggiunge quelli
  dell'altro.
- **Ho messo una ResourceQuota e il Deployment non crea più Pod.** La quota su requests/limits obbliga ogni Pod a
  dichiararli, oppure il tetto è pieno. Il Deployment non dà errore: si guarda negli eventi del ReplicaSet
  (`FailedCreate`). Un LimitRange con i default evita il primo caso.
- **ResourceQuota o LimitRange?** La quota è il budget del Namespace intero; il LimitRange è la regola per il singolo
  container (default, minimi, massimi). Si usano insieme.
- **Quali risorse non stanno in un Namespace?** Node, PersistentVolume, StorageClass, ClusterRole/Binding, CRD,
  PriorityClass, Namespace. `kubectl api-resources --namespaced=false`.

---

## Riepilogo

- Namespace = confine di nomi e punto di aggancio delle policy, **non** di sicurezza.
- ResourceQuota = budget totale; LimitRange = default e massimi per container.
- Quota su requests/limits → Pod senza valori rifiutati; Deployment 0/N muto.
- Rete, nodi e permessi cluster-wide attraversano i Namespace.
- Label `kubernetes.io/metadata.name` per i `namespaceSelector`.

## Prova da solo

1. Togli il LimitRange (`kubectl -n lab-team-a delete limitrange default-container`) e rifai `run nudo2` senza
   resources: che errore dà l'apiserver? Confrontalo con il messaggio misurato nell'intestazione.
2. Porta `pods` della quota a `"10"` e scala `riempi` a 10: quale voce del tetto scatta adesso? Fai il conto con la
   tabella prima di guardare `describe quota tetto`.
3. Modifica la NetworkPolicy del passo 13 per ammettere anche `lab-team-b` usando la label `team: b` messa nel
   manifest, e verifica con la `wget` del passo 12. Perché è meno sicuro della label `kubernetes.io/metadata.name`?
