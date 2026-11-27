# 21 — Architettura con HAProxy come Ingress controller

Spiegazione di `21-architettura-e-haproxy.yaml` (questa cartella) e dello script guidato
`kubernetes/21-architettura-e-haproxy.sh`.

## In una frase

Lo script crea un **cluster minikube nuovo, `lab-haproxy`** (5 nodi da 1 GiB, Calico), ci installa **HAProxy come
Ingress controller** al posto di ingress-nginx, e ti fa vedere che HAProxy **parla direttamente con i Pod**: legge gli
Ingress e gli EndpointSlice dall'apiserver, scrive da sé la propria configurazione e aggiunge o toglie i server **senza
ricaricarsi**. Alla fine ci mette davanti **Headlamp**, una UI web del cluster servita dallo stesso HAProxy, con
il pod senza permessi e un token in sola lettura che scade.

## I file della lezione

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/kubernetes/21-architettura-e-haproxy.sh` | lo script **guidato**: crea il cluster, installa HAProxy con Helm, applica il manifest e lo prova, installa Headlamp dietro HAProxy, un passo per volta (Invio / s / q) | `bash kubernetes/21-architettura-e-haproxy.sh` |
| `~/kubernetesprj/lezioni/kubernetes/21-architettura-e-haproxy.yaml` | i **manifest** con la teoria nei commenti: namespace, app `blu` e `verde`, Service e Ingress con le annotazioni `haproxy.org/*` | si **legge** mentre lo script gira; lo applica lo script (o a mano: `kubectl apply -f …`) |
| `~/kubernetesprj/lezioni/kubernetes/21-architettura-e-haproxy.md` | **questo**: la spiegazione | si legge |

Il file della lezione è uno `.yaml` (come la 03), non uno `.sh` (come la 01): qui c'è qualcosa da **applicare**, i
manifest, e i comandi stanno già nello script guidato.

**Prerequisito**: nessuno. Il cluster è suo, separato da `lab`. **Non tenerli accesi insieme**: `lab` usa 8 GiB
(2 × 4), `lab-haproxy` 5 GiB, il PC ne ha 15. Prima di cominciare: `minikube -p lab stop`.

## Com'è fatto il manifest

```
intestazione (commenti)  → teoria: il percorso del traffico, Runtime API, il cluster da 1 GiB, LAB, HEADLAMP, NEL PROGETTO VERO
Namespace lab-haproxy
Deployment blu (3)       → whoami, sparsi sui nodi, request piccole
Deployment verde (2)     → uguale
Service blu              → haproxy.org/load-balance: roundrobin
Service verde            → haproxy.org/load-balance: leastconn
Ingress app              → classe haproxy, host app.lab.local, /blu e /verde, path-rewrite
Ingress limitato         → host limitato.lab.local, rate limit 5 ogni 10 s, poi 429
coda (commenti)          → domande da colloquio, riepilogo
```

Versioni misurate: Kubernetes 1.34.0, minikube 1.37.0, chart `haproxytech/kubernetes-ingress` **1.57.1**
(HAProxy 3.4), Calico, chart `headlamp/headlamp` **0.46.0**.

Headlamp **non** sta nel manifest: lo installa lo script con Helm. La lezione 22 applica tutto il manifest della 21
nel suo cluster, e Headlamp non deve finirci.

---

## 1. L'architettura: cosa cambia rispetto alla 01 e alla 03

| | Lezione 01/03 (`lab`) | Lezione 21 (`lab-haproxy`) |
|---|---|---|
| Nodi | 2 da 4 GiB | **5 da 1 GiB** |
| Ingress controller | ingress-nginx, `minikube addons enable ingress` | **HAProxy**, `helm upgrade --install` |
| `ingressClassName` | `nginx` | `haproxy` |
| Come si entra dall'host | porta 80 dell'IP di minikube | **NodePort 30080** (http), 30443 (https), 30024 (stats) |
| Namespace delle prove | `lab` | `lab-haproxy` |
| Namespace del controller | `ingress-nginx` | `haproxy-controller` |

### Perché non `minikube addons enable ingress`

L'addon `ingress` di minikube installa **sempre ingress-nginx**. minikube 1.37 non ha un addon HAProxy (lo script lo
mostra con `minikube addons list`: ci sono solo `ingress`, `ingress-dns` e `kong`). HAProxy si installa con il **chart
ufficiale di HAProxy Technologies**:

```bash
helm repo add haproxytech https://haproxytech.github.io/helm-charts
helm upgrade --install haproxy haproxytech/kubernetes-ingress --version 1.57.1 \
  -n haproxy-controller --create-namespace -f valori.yaml
```

Il chart crea anche l'**IngressClass `haproxy`**: un Ingress con un'altra classe viene ignorato.

### Il percorso di una richiesta

```
curl -H 'Host: app.lab.local' http://192.168.49.2:30080/blu/ciao
  │
  ▼ NodePort 30080 su un nodo qualunque (anche il control plane)
  │ kube-proxy fa DNAT verso UNO dei 2 Pod HAProxy
  ▼
Pod HAProxy ── frontend: Host app.lab.local + path /blu → backend lab-haproxy_svc_blu_http
  │            path-rewrite: /blu/ciao → /ciao
  ▼ roundrobin fra le righe "server" del backend = gli IP dei Pod blu pronti
Pod blu (10.244.x.x:80) → risponde "Hostname: blu-…", "GET /ciao"
```

Il punto chiave: **HAProxy non usa il ClusterIP del Service**. Il Service serve da *indice*: il controller guarda i
suoi EndpointSlice e mette ogni IP di Pod pronto in una riga `server`. Per questo l'algoritmo di bilanciamento, gli
health check e le sticky session sono di HAProxy, non il DNAT casuale di kube-proxy.

### Configurazione scritta da un controller

Il Pod HAProxy contiene due cose: il **controller** (un programma Go che fa watch sull'apiserver) e **HAProxy**. Il
controller traduce Ingress, Service ed EndpointSlice in `/etc/haproxy/haproxy.cfg`:

```
backend lab-haproxy_svc_blu_http from haproxytech
  mode http
  balance roundrobin
  default-server check
  server s8b6ace539ea1bc2ba7edfc18 10.244.121.3:80 enabled
  server sd091f11bb8ebabf2e073452b 10.244.69.132:80 enabled
  server sd757b298bf4fc36cf98b1eda 10.244.205.66:80 enabled
```

Un backend per porta di Service (`<namespace>_svc_<service>_<porta>`), una riga per Pod.

### Senza reload: la Runtime API

Quando i Pod cambiano, il controller **non ricarica HAProxy**: gli manda `add server` / `del server` sul socket
`/run/haproxy-runtime-api.sock`. Misurato sul lab: `blu` da 3 a 5 repliche → nei log due `add server … New server
registered`, e il contatore `reloads` del processo master (`show proc` sul socket master) **resta uguale**. Un reload
lo provoca solo un cambio di struttura: un backend nuovo, un'annotazione nuova.

Le versioni vecchie del controller facevano diversamente: pre-allocavano degli «slot» `server` spenti (in `maint`) da
accendere. In HAProxy 3.x i server sono dinamici e gli slot non ci sono più: se leggi una guida che li nomina, è vecchia.

### Le annotazioni: Service = backend, Ingress = frontend

| Dove | Annotazione | Cosa fa |
|---|---|---|
| Service `blu` | `haproxy.org/load-balance: roundrobin` | a turno (è anche il default) |
| Service `verde` | `haproxy.org/load-balance: leastconn` | al Pod con meno connessioni aperte: per connessioni lunghe |
| Ingress `app` | `haproxy.org/path-rewrite: /(blu\|verde)/?(.*) /\2` | toglie il prefisso prima di passare al Pod |
| Ingress `limitato` | `haproxy.org/rate-limit-requests: "5"`, `rate-limit-period: "10s"`, `rate-limit-status-code: "429"` | 5 richieste ogni 10 s per IP, poi 429 (il default è 403) |

Le annotazioni di un Ingress valgono per **tutte** le sue regole: per questo il rate limit sta in un Ingress a parte,
su un host a parte.

---

## 2. Il cluster da 1 GiB per nodo: tre trappole misurate

### minikube rifiuta 1 GiB

```
X Exiting due to RSRC_INSUFFICIENT_REQ_MEMORY: Requested memory allocation 1024MiB is less than the usable minimum of 1800MB
```

Il passo 2 dello script lo fa vedere apposta (uscita 23). Il passo 3 aggiunge `--force`, che scavalca il controllo.

### `minikube start` finisce prima di Calico

Con 5 nodi, `minikube start` dice «Done!» quando i nodi sono `Ready`, ma `calico-node` sui worker può essere ancora in
avvio. Un Pod schedulato in quel momento fallisce la creazione della rete:

```
plugin type="calico" failed (add): stat /var/lib/calico/nodename: no such file or directory
```

Il kubelet ricrea il sandbox (`SandboxChanged`) e il container riparte: `RESTARTS 1` su entrambi i Pod HAProxy, senza
nessun guasto vero. Il passo 5 aspetta `kubectl -n kube-system rollout status daemonset/calico-node` prima di installare
qualunque cosa. Regola generale: dopo aver creato un cluster, aspetta il CNI, non solo i nodi.

### Il control plane sta al limite

Memoria netta (senza la cache dei file, come nella lezione 01) misurata dopo l'installazione di HAProxy:

| Nodo | Netto | Su | OOM kill |
|---|---|---|---|
| `lab-haproxy` (control plane) | 840–860 Mi (82–84%) | 1024 Mi | 0 |
| `lab-haproxy-m02` … `m05` | 320–375 Mi | 1024 Mi | 0 |

Apiserver, etcd, scheduler, controller-manager e Calico stanno tutti sul control plane: con 1 GiB resta poco. Per
questo i valori Helm hanno una **nodeAffinity** che tiene HAProxy fuori dal nodo con label
`minikube.k8s.io/primary=true`, e una **podAntiAffinity** che mette le 2 repliche su worker diversi. Se vedi
`oom_kill` maggiore di 0 sul control plane, il cluster è troppo stretto: rifallo con `--memory=2g`.

### Il chart chiede 2 GiB e lo scheduler dice sì

Di default il chart mette `requests.memory: 2048Mi` per replica. Su nodi da 1 GiB **lo scheduler le accetta lo stesso**:
con il driver docker il kubelet dichiara come Capacity **tutta la RAM del PC** (~16 GiB per nodo, la trappola della
lezione 01). Lo script la abbassa a 64 Mi, con un limite di 256 Mi. Le app `blu` e `verde` hanno request da 16 Mi.

---

## 3. Headlamp: il cluster visto da una UI, dietro HAProxy

Headlamp è una UI web per Kubernetes (progetto `kubernetes-sigs`, estendibile con plugin). Qui serve a **guardare**
quello che lo script fa: i 5 nodi, i Pod `blu` che passano da 3 a 5 e tornano a 3, gli Ingress, gli EndpointSlice.
La lezione 15 l'aveva già installato su MicroK8s con un NodePort; qui entra **dallo stesso HAProxy** della lezione.

```
browser ──▶ NodePort 30080 ──▶ Pod HAProxy ── Host headlamp.lab.local ──▶ backend headlamp_svc_headlamp_http
                                                                             │ IP del Pod Headlamp, porta 4466
                                                                             ▼
                                                     Pod Headlamp ── con il token del login ──▶ apiserver
```

### I valori Helm, e perché

```yaml
clusterRoleBinding:
  create: false                 # il pod NON è cluster-admin
resources:
  requests: { cpu: 10m, memory: 32Mi }
  limits: { memory: 128Mi }
affinity:                       # come HAProxy: lontano dal control plane
  nodeAffinity: … minikube.k8s.io/primary NotIn ['true']
ingress:
  enabled: true
  ingressClassName: haproxy     # lo serve il controller di questa lezione
  hosts:
    - host: headlamp.lab.local
      paths: [ { path: /, type: Prefix } ]
```

| Valore | Perché |
|---|---|
| `clusterRoleBinding.create: false` | **la riga che conta**. Di default il chart lega il ServiceAccount **del pod** a `cluster-admin` (il passo 22 lo mostra). Chi entra nel pod, o sfrutta una falla di Headlamp, ha il cluster. Con `false` il pod non può niente: `auth can-i list pods -A --as=…:headlamp:headlamp` → `no` |
| `resources` | misurato: **30–31 Mi** in uso. Il chart non mette request: sul cluster da 1 GiB meglio dichiararle |
| `affinity` | il control plane sta all'82–84%: Headlamp va su un worker (misurato: `lab-haproxy-m05`) |
| `ingress` | il chart crea l'Ingress `headlamp` di classe `haproxy`. Ha un **host suo**: una regola senza host prenderebbe tutto, e il `curl` senza `Host` del passo 19 non darebbe più 404 |

### Un Ingress nuovo è un cambio di struttura

Scalare `blu` non ricarica HAProxy; un Ingress nuovo sì: il controller scrive un backend in più, e il `curl` su
`headlamp.lab.local` risponde 200 dopo 2–5 tentativi (tre corse):

```
backend headlamp_svc_headlamp_http from haproxytech
  mode http
  balance roundrobin
  …
  server s906bf01b7137b87d2bccee32 10.244.121.3:4466 enabled
```

Stessa regola delle app: l'IP del **Pod** e la sua porta (4466), non il ClusterIP del Service (porta 80).

### Dove stanno i permessi: nel token

Headlamp non decide niente: passa all'apiserver il token che riceve. Misurato sull'API di Headlamp
(`/clusters/main/api/v1/namespaces/lab-haproxy/…`, attraverso HAProxy):

| Chi | `pods` | `secrets` |
|---|---|---|
| nessun token | **403**, l'apiserver vede `system:anonymous` | 403 |
| token di `headlamp-lettore` (ClusterRole `view`) | **200** | **403**: `view` non legge i Secret |

Senza token è **403, non 401**: Headlamp non ripiega sul ServiceAccount del pod, gira la richiesta così com'è, e
l'apiserver (con l'autenticazione anonima accesa) la tratta come `system:anonymous`. Misurato anche con il chart di
default (pod legato a `cluster-admin`): senza token resta 403. Il rischio del default quindi non è il visitatore
anonimo, è **chi entra nel pod**: il token montato in `/var/run/secrets/kubernetes.io/serviceaccount/` è `cluster-admin`.

Il token del login: `kubectl -n headlamp create token headlamp-lettore --duration=8h`. Scade, e non finisce in nessun
Secret (lezione 15).

### La UI dal Mac

I nodi minikube si vedono solo dall'Ubuntu, e HAProxy sceglie il backend dall'header `Host`: servono un tunnel e una
riga in `/etc/hosts` del Mac.

```bash
ssh -N -L 30080:192.168.49.2:30080 wilsonsgro@192.168.1.79
# /etc/hosts del Mac:   127.0.0.1 headlamp.lab.local
# browser:              http://headlamp.lab.local:30080  → incolla il token
```

Senza la riga in `/etc/hosts`, `http://localhost:30080` arriva con `Host: localhost:30080` e HAProxy risponde 404.
Verificato dal Mac: la pagina di login di Headlamp arriva attraverso tunnel e HAProxy. Le viste si aggiornano da
sole: il watch dell'apiserver passa da HAProxy (scalando `blu` 3 → 4 → 3 arrivano gli eventi `ADDED`, `MODIFIED`,
`DELETED`) e il websocket di Headlamp (`/wsMultiplexer`) risponde `101`.

Cosa guardare mentre lo script va avanti dal passo 28: **Workloads → Pods**, namespace `lab-haproxy`, i Pod `blu`
salgono a 5 e tornano a 3; **Network → Ingresses**, i tre Ingress di classe `haproxy` (`app`, `limitato`, `headlamp`);
**Cluster → Nodes**, i 5 nodi.

---

## 4. Lo script guidato, passo per passo

| # | Comando | Cosa vedi |
|---|---|---|
| 1 | `kubectl version --client; minikube version; helm version` | le versioni dei client |
| 2 | `minikube start -p lab-haproxy … --memory=1g` | **rifiutato** (uscita 23 voluta): sotto i 1800 MB |
| 3 | lo stesso con `--force` | 5 nodi `lab-haproxy`, `-m02` … `-m05`. Qualche minuto |
| 4 | `kubectl config use-context lab-haproxy` | da qui la guardia controlla il contesto `lab-haproxy` |
| 5 | `kubectl -n kube-system rollout status daemonset/calico-node` | Calico pronto sui 5 nodi. Senza questa attesa i Pod HAProxy fallivano il sandbox (`/var/lib/calico/nodename: no such file`) e ripartivano una volta |
| 6 | `kubectl get nodes -L minikube.k8s.io/primary -o wide` | il control plane ha `primary=true` |
| 7 | `minikube … addons enable metrics-server` | `kubectl top`; **non** si abilita `ingress` |
| 8 | `minikube … addons list \| grep …` | nessun addon HAProxy |
| 9 | `helm repo add haproxytech …; helm search repo …` | il chart 1.57.1, HAProxy 3.4 |
| 10 | `helm show values … \| sed -n '/resources/…'` | le request da 2 GiB del chart |
| 11 | `helm upgrade --install haproxy … -f - <<VALORI` | i valori sono nel comando stesso: repliche, risorse, NodePort, affinity |
| 12 | `kubectl -n haproxy-controller get pods,svc; get ingressclass` | 2 Pod su worker diversi, NodePort 30080/30443/30024, classe `haproxy` |
| 13 | memoria netta e `oom_kill` di ogni nodo | il control plane vicino al limite |
| 14 | `kubectl apply -f 21-…yaml` + `rollout status` | namespace, app, Service, Ingress |
| 15 | un `curl` ripetuto fino a 200 su `/blu` e `/verde` | Pod pronti non vuol dire HAProxy pronto: il controller deve ancora scrivere i backend (alla prima corsa `/verde` rispondeva vuoto) |
| 16 | `kubectl -n lab-haproxy get pods -o wide` | blu e verde sparsi sui worker |
| 17 | `curl -H 'Host: app.lab.local' …/blu/ciao` e `…/verde` | `GET /ciao`: il prefisso è stato tolto |
| 18 | sei `curl` a `/blu` | roundrobin; la sequenza non è perfetta perché le 2 repliche di HAProxy girano ognuna per conto suo |
| 19 | `curl` senza `Host` | 404: nessuna regola combacia |
| 20 | `sed` su `/etc/haproxy/haproxy.cfg` + `get endpointslices` | una riga `server` per IP di Pod, gli stessi IP dell'EndpointSlice |
| 21 | `helm repo add headlamp …; helm search repo …` | il chart `headlamp/headlamp` 0.46.0 |
| 22 | `helm show values … \| sed -n '/^clusterRoleBinding:/…'` | la trappola: di default `create: true` con `cluster-admin`, cioè il **pod** ha tutto il cluster |
| 23 | `helm upgrade --install headlamp … -f - <<VALORI` | pod su un worker, request 32 Mi, Ingress `headlamp` di classe `haproxy` su `headlamp.lab.local` |
| 24 | `auth can-i … --as=…:headlamp:headlamp` + SA `headlamp-lettore` con `view` | `no`: il ServiceAccount del pod non può niente |
| 25 | `curl` ripetuto fino a 200 su `headlamp.lab.local` + `sed` su `haproxy.cfg` | 200 dopo qualche tentativo; il backend nuovo `headlamp_svc_headlamp_http`, una riga `server` con l'IP del Pod e la porta 4466 |
| 26 | tre `curl` all'API di Headlamp (`/clusters/main/api/v1/…`) | senza token `403 system:anonymous`; col lettore `pods` 200, `secrets` 403 |
| 27 | `kubectl -n headlamp create token headlamp-lettore --duration=8h` | il token da incollare nel browser; la nota dice come aprirlo dal Mac |
| 28 | `show proc` sul socket master | il numero di reload, prima |
| 29 | `scale deploy/blu --replicas=5` + log | `add server … New server registered` |
| 30 | `show proc` e `show servers state` | reload invariati, 5 server (stato 2 = UP) |
| 31 | 12 `curl` su `limitato.lab.local` | 200 e poi 429; misurato in due corse **10 e 9 volte 200** su 12: fino a 5 per replica |
| 32 | `curl …:30024/stats;csv` | la pagina statistiche in CSV: backend, server, `UP` |
| 33 | `scale deploy/blu --replicas=3` + log | `Server deleted.` due volte: i server in più escono a caldo |
| 34 | `helm uninstall headlamp …; kubectl delete -f …; helm uninstall haproxy …` | pulizia: prima Headlamp e il suo utente, poi app e controller |

`kubectl exec deploy/haproxy-kubernetes-ingress` sceglie **uno** dei due Pod: l'altro ha la sua configurazione e i suoi
contatori.

Per ripartire da un passo: `DA=14 bash kubernetes/21-architettura-e-haproxy.sh`. Tutto senza fermarsi:
`AUTO=1 bash kubernetes/21-architettura-e-haproxy.sh`.

### La pagina statistiche dal Mac

I nodi minikube (`192.168.49.x`) si vedono solo dall'Ubuntu. Dal Mac, un tunnel ssh:

```bash
ssh -N -L 30024:192.168.49.2:30024 wilsonsgro@192.168.1.79
# nel browser del Mac: http://localhost:30024/stats
```

`192.168.49.2` è `minikube -p lab-haproxy ip`: se è diverso, usa quello.

---

## 5. Dentro o fuori dal cluster

Nel Biodistretto (`~/biodistretto/kubernetes`) HAProxy sta **fuori**, sull'host, ed entra dai NodePort di nginx:

| | HAProxy fuori (Biodistretto) | HAProxy dentro (questa lezione) |
|---|---|---|
| Vede | i **nodi** | i **Pod** |
| Si configura | a mano, `haproxy.cfg` sull'host | da sé, dagli Ingress |
| Health check | per nodo; serve `externalTrafficPolicy: Local` perché non menta | per Pod |
| Davanti serve ancora | niente | qualcosa che arrivi ai nodi: NodePort, un LB, o l'HAProxy esterno |

Le due cose si sommano: in produzione spesso c'è un bilanciatore esterno (HAProxy, un LB del cloud) che manda ai nodi,
e un Ingress controller dentro che manda ai Pod.

---

## 6. Domande da colloquio

- **Un Ingress controller manda il traffico al ClusterIP?** Di solito no: HAProxy e ingress-nginx leggono gli
  EndpointSlice e parlano con gli IP dei Pod.
- **Scalo da 3 a 6 repliche: HAProxy si ricarica?** No: `add server` sulla Runtime API. Si ricarica solo per un
  cambio di struttura.
- **Rate limit con più repliche del controller: è esatto?** No: ogni replica ha la sua stick-table, il limite si
  moltiplica per le repliche raggiunte. Per un limite globale servono i `peers` fra le repliche, o un limite a monte.
- **roundrobin o leastconn?** roundrobin per richieste brevi e simili; leastconn per connessioni lunghe o di durata
  diversa (websocket, upload, query lente).
- **Perché due IngressClass nello stesso cluster?** Per avere due controller (uno pubblico e uno interno, o nginx e
  HAProxy durante una migrazione): ogni Ingress sceglie il suo con `ingressClassName`.
- **Headlamp (o Dashboard, Lens): dove stanno i permessi?** Nel token con cui si entra, non nel pod della UI. Il chart
  di default lega il pod a `cluster-admin`: si spegne con `clusterRoleBinding.create=false`, e a ogni utente un token
  a tempo con il ruolo minimo (`view`, o un Role in un solo namespace per scrivere).
- **Senza token l'API risponde 403, non 401: perché?** L'apiserver ha l'autenticazione anonima accesa: una richiesta
  senza credenziali diventa `system:anonymous`, che è autenticato ma senza permessi.

---

## Riepilogo

- minikube non ha l'addon HAProxy: si installa con Helm, e porta l'IngressClass `haproxy`.
- HAProxy legge Ingress ed EndpointSlice e scrive `haproxy.cfg` da sé; il traffico va ai **Pod**, non al ClusterIP.
- I Pod nuovi entrano con la Runtime API, **senza reload**.
- Annotazioni: sul Service il backend, sull'Ingress il frontend.
- Il rate limit è **per replica**.
- 5 nodi da 1 GiB: serve `--force`, le request vanno abbassate, il controller sta lontano dal control plane.
- Headlamp entra dallo stesso HAProxy (Ingress su `headlamp.lab.local`): il pod senza permessi, il token `view` a tempo.

## Prova da solo

1. Cancella un Pod `blu` e guarda i log del controller: quale comando della Runtime API vedi? Il numero di reload cambia?
2. Aggiungi a `Service blu` l'annotazione `haproxy.org/load-balance: leastconn` con `kubectl annotate --overwrite`:
   cambia il `balance` in `haproxy.cfg`? Questa volta il reload c'è?
3. Porta `rate-limit-requests` a `"2"` e ripeti i 12 `curl`: quanti 200 ti aspetti con 2 repliche? E se scali il
   controller a 1 (`helm upgrade … --reuse-values --set controller.replicaCount=1`)?
4. Spegni un worker con un Pod HAProxy (`docker stop lab-haproxy-m02`, poi `docker start`): i `curl` continuano a
   passare? Quanto ci mette Kubernetes ad accorgersene?
5. Crea un ServiceAccount `headlamp-scrittore` con un Role nel **solo** namespace `lab-haproxy` che permette `get`,
   `list`, `watch`, `patch` e `update` su `deployments` e `deployments/scale`. Entra in Headlamp con il suo token e
   scala `verde` dalla UI: nei log del controller vedi `add server`? E con il token di `headlamp-lettore`?
