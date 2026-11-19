# 01 — Architettura di Kubernetes e laboratorio su Ubuntu

Spiegazione di `01-architettura-e-lab.sh` (questa cartella). Lezione sul sito: http://127.0.0.1:3000/kubernetes/1

## In una frase

Lo script **crea il cluster minikube `lab`** (2 nodi, Calico, ingress, metrics-server), poi **lo esplora** e ti fa
vedere dal vivo l'idea su cui si regge tutto Kubernetes: **la riconciliazione**. Tu dichiari lo stato che vuoi,
i controller lo confrontano di continuo con quello reale e correggono la differenza.

## Due file con lo stesso nome: quale lanciare

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/lezioni/kubernetes/01-architettura-e-lab.sh` | **questo**: la lezione, con le spiegazioni nei commenti | `bash 01-architettura-e-lab.sh crea` · `esplora` · `spegni` |
| `~/kubernetesprj/kubernetes/01-architettura-e-lab.sh` | lo script **guidato**: fa gli stessi comandi, uno per volta, spiegando prima di eseguire (Invio / s / q) | `bash kubernetes/01-architettura-e-lab.sh` |

Per imparare conviene lo **guidato**. Questo file va **letto** mentre lo guidato gira: i commenti spiegano il perché.

## Com'è fatto il file

```
intestazione (commenti)  → la teoria: control plane, nodo, cosa succede con kubectl apply
set -euo pipefail        → lo script si ferma al primo errore
guardia_contesto()       → controlla che kubectl punti a "lab"
crea_cluster()           → minikube start + addon
esplora()                → giro guidato nel cluster + prova di auto-riparazione
spegni()                 → minikube stop
case "$1"                → sceglie la funzione dall'argomento: crea | esplora | spegni
coda (commenti)          → comandi kubectl da colloquio, domande da colloquio, riepilogo
```

`set -euo pipefail` vuol dire: `-e` esci se un comando fallisce, `-u` errore se usi una variabile non definita,
`-o pipefail` una pipe fallisce se fallisce uno qualunque dei suoi comandi (non solo l'ultimo).

---

## 1. La teoria nell'intestazione

### Control plane (il "cervello")

| Componente | Cosa fa |
|---|---|
| **kube-apiserver** | l'**unica porta d'ingresso**. Ogni richiesta (tua, dei controller, del kubelet) passa da qui: autenticazione → autorizzazione (RBAC) → admission controller → scrittura in etcd. Non ha stato, quindi se ne possono mettere più copie dietro un load balancer |
| **etcd** | il database chiave-valore dove vive **tutto** lo stato del cluster. Usa il consenso Raft: serve una maggioranza (quorum). Backup: `etcdctl snapshot save` |
| **kube-scheduler** | sceglie **su quale nodo** mettere un Pod che non ce l'ha: prima scarta i nodi che non vanno (risorse, taint, affinity), poi dà un punteggio agli altri, poi assegna (bind) |
| **controller-manager** | contiene i **loop di controllo**: Deployment → ReplicaSet → Pod, Node, Job, EndpointSlice, token dei ServiceAccount… |

### Il quorum di etcd

Quorum = `floor(N/2) + 1`.

| Membri etcd | Quorum | Guasti tollerati |
|---|---|---|
| 1 | 1 | 0 |
| 3 | 2 | 1 |
| 4 | 3 | 1 ← come con 3, ma le scritture sono più lente |
| 5 | 3 | 2 |

Per questo si usano **3 o 5** membri, mai un numero pari.

### Nodo (dove girano i container)

| Componente | Cosa fa |
|---|---|
| **kubelet** | l'agente su ogni nodo: legge i Pod assegnati **al suo nodo**, li fa partire tramite il runtime (containerd / CRI-O, attraverso l'interfaccia CRI), esegue le probe, riporta lo stato. Non si occupa dei Pod degli altri nodi |
| **kube-proxy** | traduce i Service in regole di rete (iptables / IPVS / nftables). Con Cilium può mancare: usa eBPF |
| **CNI** | il plugin di rete: dà un IP a ogni Pod. Modello "piatto": ogni Pod parla con ogni altro Pod senza NAT. **Le NetworkPolicy le applica il CNI** (Calico, Cilium), non Kubernetes |

### Cosa succede con `kubectl apply -f deploy.yaml`

1. `kubectl` manda la richiesta all'apiserver, che fa authn → authz → mutating admission → validazione dello schema →
   validating admission → scrittura in etcd.
2. Il **Deployment controller** vede l'oggetto nuovo e crea un **ReplicaSet**.
3. Il **ReplicaSet controller** crea N **Pod**, ancora senza nodo.
4. Lo **scheduler** assegna un nodo a ogni Pod.
5. Il **kubelet** di quel nodo vede il Pod e, tramite CRI, scarica l'immagine e avvia i container.
6. Il **CNI** dà l'IP. Quando la readiness probe passa, il Pod entra negli **EndpointSlice** e riceve traffico.

Il punto chiave: **nessuno chiama il componente successivo**. Ognuno osserva l'apiserver (watch) e reagisce. Per
questo, se qualcosa si rompe, il sistema si ripara da solo.

### Riquadro «NEL PROGETTO VERO»

Indica dove lo stesso concetto compare in `~/biodistretto/kubernetes`. Lì il cluster non nasce da `minikube start` ma
da una risorsa Terraform (`minikube_cluster`), con 2 nodi e CNI **kindnet** invece di Calico. Gli addon
(metrics-server, csi-hostpath-driver) sono una variabile Terraform. I `grep` del riquadro ti portano alle righe giuste.

---

## 2. `guardia_contesto()` — non sbagliare cluster

```bash
attuale="$(kubectl config current-context)"
if [[ "$attuale" != "lab" ]]; then echo "STOP…"; exit 1; fi
```

`kubectl` manda i comandi al **contesto** attivo. Sul tuo Ubuntu potrebbe essere un cluster GKE vero: un `apply` o un
`delete` nel posto sbagliato fa danni. Questa funzione blocca lo script se il contesto non è `lab`. Tutti gli script
delle lezioni successive fanno lo stesso controllo (`lib/passo.sh`).

Controllo a mano: `kubectl config current-context` → deve dire `lab`.

---

## 3. `crea` — `crea_cluster()`

```bash
minikube start -p lab --driver=docker --nodes=2 --cpus=2 --memory=4g --cni=calico
minikube -p lab addons enable ingress
minikube -p lab addons enable metrics-server
kubectl config use-context lab
```

| Opzione | Perché |
|---|---|
| `-p lab` | profilo dedicato: il cluster si chiama `lab` e anche il contesto kubectl si chiama `lab` |
| `--driver=docker` | ogni **nodo è un container Docker** (`lab`, `lab-m02`), non una VM |
| `--nodes=2` | servono due nodi per vedere affinity e distribuzione dei Pod (lezione 06) e il drain (lezione 05) |
| `--cpus=2 --memory=4g` | risorse per nodo (ma leggi la trappola sotto) |
| `--cni=calico` | il CNI di default di minikube **non applica le NetworkPolicy**: Calico sì (lezione 03) |
| addon `ingress` | installa il controller ingress-nginx (lezione 03) |
| addon `metrics-server` | abilita `kubectl top` e l'autoscaling HPA (lezione 06) |

Senza `--kubernetes-version`, minikube usa la versione che supporta meglio.

### La trappola delle risorse con il driver docker

- `--memory=4g` diventa un **limite reale** del cgroup del container-nodo: oltre i 4 GiB il kernel lo uccide.
- `--cpus=2` **non viene applicato**: `cpu.max` resta `max`.
- Il kubelet dichiara come Capacity **tutto il PC** (12 CPU, circa 16 GiB per nodo). Lo scheduler conta su risorse che
  il container non ha, e le percentuali di `kubectl top` sono calcolate su quella Capacity.

Comandi per vederlo:

```bash
kubectl get nodes -o custom-columns=NOME:.metadata.name,CPU:.status.capacity.cpu,MEM:.status.allocatable.memory
docker exec lab cat /sys/fs/cgroup/memory.max /sys/fs/cgroup/cpu.max
```

Per sapere quanto manca al limite **non basta `memory.current`**: comprende la cache dei file, che il kernel recupera.
Contano la memoria netta (totale meno `active_file` e `inactive_file`) e il contatore `oom_kill`:

```bash
docker exec lab grep -E '^(active|inactive)_file ' /sys/fs/cgroup/memory.stat
docker exec lab grep oom_kill /sys/fs/cgroup/memory.events
```

---

## 4. `esplora` — giro nel cluster

Prima chiama `guardia_contesto`, poi:

| Comando | Cosa vedi |
|---|---|
| `kubectl get nodes -o wide` | i due nodi, con IP, sistema operativo e runtime |
| `kubectl get pods -n kube-system -o wide` | il control plane: apiserver, etcd, scheduler, controller-manager, più CoreDNS, kube-proxy, Calico |
| `minikube -p lab ssh -- sudo ls /etc/kubernetes/manifests` | i file dei **Pod statici**: il kubelet avvia il control plane leggendo questa cartella **dentro il nodo**, non dall'apiserver. Sull'host Ubuntu la cartella non esiste: il nodo è un container |
| `kubectl api-resources \| head -30` | i tipi di oggetto che l'apiserver conosce: nome corto, gruppo API, se stanno in un namespace |
| `kubectl explain deployment.spec.strategy.rollingUpdate` | la documentazione di un campo, presa dallo schema del cluster |

### La riconciliazione dal vivo

```bash
kubectl create deployment eco --image=traefik/whoami:v1.12 --replicas=2
kubectl rollout status deployment/eco
kubectl get pods -l app=eco -w &          # osserva in background
kubectl delete pod -l app=eco --wait=false
sleep 10; kill "$osservatore"
kubectl get events --sort-by=.metadata.creationTimestamp | tail -12
```

1. Crea un Deployment `eco` con 2 repliche (in modo imperativo: in produzione si usa lo YAML).
2. Aspetta che le repliche siano pronte.
3. Avvia un `get -w` (watch) in background, poi **cancella i Pod**.
4. Nel watch vedi i Pod vecchi andare in `Terminating` e **due Pod nuovi** nascere: il ReplicaSet vuole 2 repliche,
   ne vede 0 e le ricrea. Nessuno gliel'ha chiesto.
5. Gli **eventi** raccontano il perché: `SuccessfulCreate` del ReplicaSet, `Scheduled`, `Pulled`, `Started`.

`kill "$osservatore"` ferma solo il watch, non i Pod.

Lo script guidato fa notare che i Pod cancellati passano da `Terminating` a `Error`: whoami esce con codice 2 quando
riceve il SIGTERM. Non è un guasto: conta che i due Pod nuovi arrivino a `Running`.

### I tre tipi di IP

```bash
kubectl expose deployment eco --port=80
kubectl get nodes,pods,svc -o wide
```

| IP | Rete | Di chi è |
|---|---|---|
| **del nodo** | 192.168.49.x (rete Docker di minikube) | del container-nodo |
| **del Pod** | 10.244.x (Calico) | del Pod, cambia quando il Pod viene ricreato |
| **del Service** (ClusterIP) | 10.96.0.0/12, cioè da 10.96 a 10.111 | **virtuale**: nessuna scheda di rete lo possiede, lo traducono le regole di kube-proxy. Resta stabile anche quando i Pod cambiano |

### Due trappole

- `kubectl get pods -A`: **senza `-n` guardi solo il namespace corrente** (`default`). «No resources found» non vuol
  dire che il cluster è vuoto.
- `kubectl -n kube-system get pod -l component=etcd`: c'è **un solo membro etcd**. Due nodi Kubernetes non vogliono
  dire due copie del database: qui il quorum tollera 0 guasti.

Alla fine `kubectl delete deployment,service eco` toglie tutto quello che la prova ha creato.

---

## 5. `spegni`

```bash
minikube -p lab stop       # ferma il cluster e conserva lo stato
# minikube delete -p lab   # (commentato) lo cancellerebbe del tutto
```

Per riaccenderlo: `minikube -p lab start`.

---

## 6. Lo script guidato `~/kubernetesprj/kubernetes/01-architettura-e-lab.sh`, passo per passo

Fa le stesse cose di `crea` + `esplora`, in 25 passi, con qualche misura in più che la lezione non ha: le risorse
vere del container-nodo, la memoria netta, `kubectl top`. Non fa `spegni`: alla fine stampa i comandi per farlo.

| Passo | Comando | Cosa vedi / perché |
|---|---|---|
| 1 | `kubectl version --client; minikube version` | le versioni dei due client: kubectl parla con l'apiserver, minikube crea il cluster |
| 2 | `kubectl config get-contexts` | i contesti noti a kubectl: il contesto dice **a quale cluster** arrivano i comandi |
| 3 | `minikube start -p lab --driver=docker --nodes=2 --cpus=2 --memory=4g --cni=calico` | crea il cluster (qualche minuto). Le opzioni sono spiegate nella sezione 3 |
| 4 | `minikube -p lab addons enable ingress` | il controller ingress-nginx (lezione 03) |
| 5 | `minikube -p lab addons enable metrics-server` | `kubectl top` e l'HPA (lezione 06) |
| 6 | `kubectl config use-context lab` | da qui in poi tutti gli script controllano che il contesto sia `lab` |
| 7 | `kubectl get nodes -o wide` | `lab` è il control plane, `lab-m02` il worker; IP, sistema operativo, runtime |
| 8 | `kubectl get pods -n kube-system -o wide` | il control plane come Pod: apiserver, etcd, scheduler, controller-manager, più CoreDNS, kube-proxy, Calico |
| 9 | `minikube -p lab ssh -- sudo ls /etc/kubernetes/manifests` | i file dei **Pod statici**, letti dal kubelet dentro il nodo |
| 10 | `ls /etc/kubernetes/manifests` | **fallisce apposta (uscita 2)**: sull'host Ubuntu la cartella non c'è, il nodo è un container con il suo filesystem |
| 11 | `kubectl -n kube-system get pod -l component=etcd -o wide` | un solo membro, `etcd-lab`, sul control plane |
| nota | — | quorum = floor(N/2)+1: 1 membro → 0 guasti tollerati · 3 → 1 · 4 → 1 · 5 → 2. Per questo 3 o 5, su macchine diverse |
| 12 | `kubectl get nodes -o custom-columns=…capacity…allocatable…` | quello che **Kubernetes crede** di avere: Capacity e Allocatable di ogni nodo |
| 13 | `docker exec lab cat /sys/fs/cgroup/memory.max /sys/fs/cgroup/cpu.max; docker exec lab nproc` | quello che il container-nodo **ha davvero**: `memory.max` = 4 GiB, `cpu.max` = `max` (il `--cpus=2` non è applicato), `nproc` vede tutte le CPU |
| 14 | ciclo su `lab` e `lab-m02` con `memory.current`, `memory.stat`, `memory.events` | per ogni nodo: totale, cache, **netto** e percentuale del limite, più il contatore `oom_kill`. La cache dei file il kernel la recupera: conta il netto |
| 15 | attesa del metrics-server (fino a 30 × 5 s), poi `kubectl top nodes` | il consumo osservato, in percentuale della Capacity del passo 12 (tutto il PC), **non** di 2 CPU / 4 GiB |
| nota | — | con il driver docker lo scheduler conta su ~16 GiB per nodo, ma il kernel uccide il container-nodo a 4 GiB. In un cluster vero Capacity = la macchina |
| 16 | `kubectl api-resources \| head -30` | i tipi di oggetto: nome corto, gruppo API, namespaced o no |
| 17 | `kubectl explain deployment.spec.strategy.rollingUpdate` | la documentazione di un campo, dallo schema del cluster |
| 18 | `kubectl create deployment eco --image=traefik/whoami:v1.12 --replicas=2` | un Deployment creato in modo imperativo, solo per vedere la riconciliazione |
| 19 | `kubectl rollout status deployment/eco` | aspetta che le 2 repliche siano pronte |
| 20 | `kubectl get pods -l app=eco -w &` + `kubectl delete pod -l app=eco --wait=false`, 15 secondi | l'**auto-riparazione**: i Pod vecchi se ne vanno, il ReplicaSet ne crea due nuovi |
| nota | — | i Pod cancellati passano da `Terminating` a `Error`: whoami esce con codice 2 al SIGTERM (misurato). Non è un guasto: conta che i nuovi arrivino a `Running` |
| 21 | `kubectl get events --sort-by=.metadata.creationTimestamp \| tail -12` | il perché: `SuccessfulCreate` del ReplicaSet, `Scheduled`, `Pulled`, `Started` |
| 22 | `kubectl expose deployment eco --port=80 && kubectl get svc eco` | un Service davanti a eco |
| 23 | tre `kubectl get … -o custom-columns` (nodi, Pod, Service) | i **tre IP** in colonna: nodo 192.168.49.x, Pod 10.244.x, Service nella 10.96.0.0/12 |
| 24 | `kubectl get pods` e il conteggio di `kubectl get pods -A` | la trappola del namespace: senza `-n` vedi solo `default` (c'è eco, il control plane no) |
| 25 | `kubectl delete deployment,service eco` | pulizia della prova |
| nota | — | spegnere: `minikube -p lab stop` · riaccendere: `minikube -p lab start` · cancellare: `minikube -p lab delete` |

Per ripartire da un passo: `DA=12 bash kubernetes/01-architettura-e-lab.sh`. Per eseguire tutto senza fermarsi:
`AUTO=1 bash kubernetes/01-architettura-e-lab.sh`. Se il cluster esiste già, il passo 3 lo riaccende invece di crearlo.

---

## 7. La coda: kubectl e domande da colloquio

### Comandi da sapere a memoria

| Comando | A cosa serve |
|---|---|
| `kubectl get pod -A -o wide --field-selector=status.phase!=Running` | tutti i Pod che **non** sono Running |
| `kubectl get events -A --sort-by=.lastTimestamp` | gli ultimi eventi del cluster, in ordine |
| `kubectl describe pod X` | eventi del Pod: scheduling, pull dell'immagine, probe |
| `kubectl logs X -c app --previous` | i log del container **prima** del crash |
| `kubectl get deploy X -o yaml \| less` | spec + status + managedFields |
| `kubectl diff -f file.yaml` | cosa cambierebbe un apply, senza farlo |
| `kubectl apply --server-side -f …` | server-side apply: il server traccia chi possiede ogni campo |
| `kubectl auth can-i create pods --as=system:serviceaccount:lab:app` | che cosa può fare un'identità (lezione 07) |
| `kubectl get --raw '/readyz?verbose'` | lo stato di salute dell'apiserver |

### Domande

- **Perché etcd con 3 o 5 nodi e non 4?** Con 4 il quorum è 3: tolleri 1 guasto come con 3, ma le scritture sono più
  lente. I numeri dispari massimizzano i guasti tollerati.
- **Se cade l'apiserver, i Pod si fermano?** No. I kubelet continuano a far girare ciò che hanno. Si ferma il resto:
  niente nuovi scheduling, niente auto-riparazione, niente aggiornamento degli endpoint. Il data plane va avanti, il
  control plane è congelato.
- **Apply client-side o server-side?** Il client-side calcola il merge con l'annotazione `last-applied`. Il
  server-side (SSA) registra in `managedFields` il "proprietario" di ogni campo: se due strumenti scrivono lo stesso
  campo, ottieni un conflitto esplicito invece di una sovrascrittura silenziosa. Helm 4 e Argo CD lo usano di default.
- **Cosa fa un admission controller?** Intercetta la richiesta dopo l'autorizzazione e prima di etcd. Quelli
  *mutating* la modificano (iniettano un sidecar, mettono dei default), quelli *validating* la accettano o la
  rifiutano (Pod Security Admission, Kyverno/Gatekeeper, ValidatingAdmissionPolicy in CEL, nativa dalla 1.30).

---

## Riepilogo

- Kubernetes = **stato desiderato** + **controller che riconciliano** osservando l'apiserver (watch).
- L'apiserver è l'unica porta, etcd l'unica fonte di verità (con un numero dispari di membri).
- Il kubelet esegue, lo scheduler sceglie il nodo, il CNI dà la rete.
- Il lab: minikube, profilo `lab`, 2 nodi, Calico, ingress, metrics-server.
- **Prima di ogni apply: `kubectl config current-context`.**

## Prova da solo

1. `kubectl get pods -n kube-system -o wide`: su quale nodo gira etcd? E i Pod di Calico?
2. Ricrea `eco` con 3 repliche, cancellane **una** sola e guarda gli eventi: chi la ricrea?
3. `kubectl explain pod.spec.containers.readinessProbe`: quali campi ha? Li userai nella lezione 02.
