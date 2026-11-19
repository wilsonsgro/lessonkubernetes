# 05 — Stato: StatefulSet, volumi persistenti e PodDisruptionBudget

Spiegazione di `05-statefulset-storage-pdb.yaml` (questa cartella). Lezione sul sito: http://127.0.0.1:3000/kubernetes/5

## In una frase

Il file crea un finto database a **3 repliche** come **StatefulSet `db`**: ogni Pod ha un **nome fisso** (`db-0`,
`db-1`, `db-2`), un **record DNS suo** grazie a un **Service headless** e un **disco suo** (PVC) che lo segue. Un
**PodDisruptionBudget** impedisce che un drain ne spenga più di uno alla volta. Il runner cancella un Pod e mostra che
ritrova il disco, scala giù e su, e fa il **drain** del nodo `lab-m02`.

## Due file con lo stesso nome: quale lanciare

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/lezioni/kubernetes/05-statefulset-storage-pdb.yaml` | **questo**: i manifest, con la teoria nei commenti | si **legge**; lo applica il runner (o a mano: `kubectl apply -f 05-statefulset-storage-pdb.yaml`) |
| `~/kubernetesprj/kubernetes/05-statefulset-storage-pdb.sh` | lo script **guidato**: applica, cancella, scala, fa drain e uncordon, un passo per volta (Invio / s / q) | `bash kubernetes/05-statefulset-storage-pdb.sh` |

Il namespace `lab` deve esistere (lezione 02). Il drain richiede i **2 nodi** del lab (`lab` e `lab-m02`, lezione 01).

## Com'è fatto il file

```
intestazione (commenti)  → teoria: bestiame vs identità, catena dello storage, comandi LAB, NEL PROGETTO VERO
Service db (headless)    → clusterIP: None, record DNS per ogni Pod
StatefulSet db           → 3 repliche ordinate, anti-affinity, volumeClaimTemplates, retention dei PVC
PodDisruptionBudget db   → maxUnavailable 1
coda (commenti)          → domande da colloquio, riepilogo
```

Versione: Kubernetes 1.34–1.35 (lab 1.34.0), storage class di default di minikube: `standard`.

---

## 1. La teoria nell'intestazione

### Bestiame contro identità

Un **Deployment** tratta i Pod come bestiame: nomi casuali, intercambiabili, tutti sullo stesso volume (se c'è).
Un database a 3 nodi ha bisogno di altro:

| Bisogno | Come lo dà lo StatefulSet |
|---|---|
| **identità stabile** | `db-0`, `db-1`, `db-2`: lo stesso nome dopo un restart |
| **DNS stabile** | `db-0.db.lab.svc.cluster.local`, grazie al Service headless |
| **disco per replica** | ogni Pod il suo PVC, che resta legato al nome del Pod (ma sul lab vedi la trappola dell'hostpath `standard` con 2 nodi, più sotto) |
| **ordine** | crea 0→1→2, cancella 2→1→0 (`podManagementPolicy: OrderedReady`); `Parallel` se l'ordine non serve |

### La catena dello storage

```
PVC (richiesta: 1Gi RWO) ──▶ StorageClass (provisioner: driver CSI) ──▶ PV (il disco vero: EBS, PD, local-path…)
```

- **PVC** (PersistentVolumeClaim): la **richiesta** ("voglio 1Gi in lettura-scrittura").
- **StorageClass**: **come** procurarlo (quale provisioner, quali parametri).
- **PV** (PersistentVolume): il **disco vero**, creato dal provisioner e legato al PVC.

| Impostazione | Cosa decide |
|---|---|
| `volumeBindingMode: WaitForFirstConsumer` | il PV si crea **nella zona del nodo** dove lo scheduler mette il Pod. Senza: disco in zona A, Pod costretto in zona B = **Pending per sempre** |
| `reclaimPolicy` | `Delete` (default del provisioning dinamico: cancelli il PVC, sparisce il disco) o `Retain` (dati di produzione) |
| `accessModes` | `RWO` (un nodo) · `RWOP` (un Pod) · `RWX` (più nodi: NFS/CephFS/EFS) |

### I comandi LAB dell'intestazione

```bash
kubectl apply -f 05-statefulset-storage-pdb.yaml
kubectl -n lab rollout status sts/db
kubectl -n lab get pod,pvc -l app=db
kubectl -n lab exec db-0 -- cat /data/identita        # db-0 avviato alle…
kubectl -n lab delete pod db-0 && kubectl -n lab wait --for=condition=Ready pod/db-0
kubectl -n lab exec db-0 -- cat /data/identita        # due righe: stesso disco
kubectl -n lab run dns --rm -i --quiet --restart=Never --image=busybox:1.37 -- \
    nslookup db-1.db.lab.svc.cluster.local
kubectl -n lab scale sts/db --replicas=1              # i PVC di db-1/db-2 RESTANO
kubectl drain <nodo> --ignore-daemonsets              # il PDB frena lo sfratto
```

Due fatti riportati nei commenti (il secondo è marcato «provato»):

- `kubectl run` con `-it` **senza un terminale** perde l'output: per questo si usa `-i --quiet`.
- Il `nslookup` di **busybox con il nome corto dà NXDOMAIN**: serve il nome completo
  `db-1.db.lab.svc.cluster.local`.

### Riquadro «NEL PROGETTO VERO»

In `~/biodistretto/kubernetes` **mariadb, redis, elasticsearch e minio** sono quattro StatefulSet con
`volumeClaimTemplates` sulla storage class **`csi-hostpath-sc`**:

```bash
grep -n 'storageClassName' terraform/app/manifests/dati.yaml.tftpl
grep -n -A3 'variable "storage_class"' terraform/app/variables.tf
```

- **Perché non lo `standard` di minikube**: con 2 nodi il suo hostpath crea il volume su **un nodo solo**, e il Pod
  schedulato sull'altro nodo non lo vede.
- **Elasticsearch scrive come uid 1000**: `fsGroup` rende il volume suo.
  ```bash
  grep -n -B1 'fsGroup' terraform/app/manifests/dati.yaml.tftpl
  ```
- **Differenza con questa lezione**: qui il Service è headless (`clusterIP: None`); nel progetto i Service dei dati sono
  **ClusterIP**: con 1 replica basta il nome del Service, il DNS per singolo Pod non serve.
- **Da colloquio**: lì **niente PDB**, perché con 1 replica e `minAvailable: 1` il PDB bloccherebbe ogni drain del nodo.

---

## 2. Il Service headless `db`

```yaml
spec:
  clusterIP: None
  publishNotReadyAddresses: true
  selector: { app: db }
  ports:
    - name: tcp
      port: 5432
```

| Campo | Perché |
|---|---|
| `clusterIP: None` | **headless**: niente IP virtuale né bilanciamento. Il DNS risponde con **gli IP dei Pod** e crea un record per ognuno (`db-0.db…`, `db-1.db…`) |
| `publishNotReadyAddresses: true` | i record DNS esistono **anche prima** che i Pod siano pronti: in un cluster di database i peer devono trovarsi durante l'avvio, prima di essere "pronti" |
| `port: 5432` | la porta di Postgres, solo indicativa: il container è un busybox che dorme |

---

## 3. Lo StatefulSet `db` — campo per campo

### Identità e ordine

| Campo | Valore | Cosa fa |
|---|---|---|
| `serviceName` | `db` | il Service headless che **governa i nomi DNS** dei Pod |
| `replicas` | `3` | `db-0`, `db-1`, `db-2` |
| `podManagementPolicy` | `OrderedReady` | crea uno alla volta, ognuno quando il precedente è Ready; cancella in ordine inverso |

### Aggiornamento: `partition`

```yaml
updateStrategy:
  type: RollingUpdate
  rollingUpdate:
    partition: 0
```

Il rolling update di uno StatefulSet va dall'ordinale **più alto al più basso**. Con `partition: N > 0` vengono
aggiornati **solo gli ordinali ≥ N**: è un **canary manuale**, per esempio su `db-2` prima di toccare `db-0` (spesso il
primario). Con `0`, come qui, si aggiornano tutti.

### Che fine fanno i dati: `persistentVolumeClaimRetentionPolicy`

```yaml
persistentVolumeClaimRetentionPolicy:
  whenDeleted: Retain
  whenScaled: Retain
```

| Evento | `Retain` vuol dire |
|---|---|
| `whenDeleted` | cancelli lo StatefulSet: **i PVC (e i dati) restano** |
| `whenScaled` | scali giù: i PVC delle repliche tolte restano, pronti per lo scale up |

L'alternativa è `Delete`. Il runner lo prova al passo 8.

### Il Pod

```yaml
terminationGracePeriodSeconds: 10
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          topologyKey: kubernetes.io/hostname
          labelSelector:
            matchLabels: { app: db }
```

- **podAntiAffinity**: "non mettermi su un nodo dove c'è già un Pod `app: db`". `topologyKey: kubernetes.io/hostname`
  = il dominio è il **singolo nodo**.
- **preferred** (non `required`): è una **preferenza** con peso 100. Con 3 repliche e 2 nodi una regola `required`
  lascerebbe un Pod **Pending**; con `preferred` lo scheduler li sparpaglia finché può e poi ne mette due insieme.
- `IgnoredDuringExecution`: la regola vale solo quando il Pod viene schedulato, non sposta Pod già in esecuzione.

### Il container

```yaml
image: busybox:1.37
command:
  - sh
  - -c
  - |
    echo "$(hostname) avviato alle $(date +%T)" >> /data/identita
    exec sleep 1000000
volumeMounts:
  - name: dati
    mountPath: /data
resources:
  requests: { cpu: 10m, memory: 16Mi }
  limits: { memory: 32Mi }
```

A ogni avvio il container **aggiunge** (`>>`) una riga al file `/data/identita` con il suo hostname (= il nome del Pod)
e l'ora. Il file sta sul disco persistente: se il Pod rinasce con lo stesso disco, le righe si accumulano. È la prova
visiva che "il disco segue il nome". `exec sleep` sostituisce la shell con `sleep`, che diventa il processo 1 del container. Il processo 1 non ha i
gestori di segnale di default: `sleep` ignora il SIGTERM, e il Pod muore solo con il SIGKILL dopo
`terminationGracePeriodSeconds: 10`. Per questo un `delete pod db-0` impiega circa 10 secondi.

### `volumeClaimTemplates`

```yaml
volumeClaimTemplates:
  - metadata:
      name: dati
    spec:
      accessModes: [ReadWriteOnce]
      resources:
        requests:
          storage: 1Gi
```

È uno **stampo di PVC**: lo StatefulSet crea un PVC per ogni Pod, con nome `<template>-<pod>`: **`dati-db-0`,
`dati-db-1`, `dati-db-2`**. `storageClassName` è omesso → si usa la **classe di default** del cluster (`standard` su
minikube). Un Deployment non può farlo: tutte le repliche condividerebbero lo stesso PVC.

---

## 4. Il PodDisruptionBudget `db`

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
spec:
  maxUnavailable: 1
  selector:
    matchLabels: { app: db }
  unhealthyPodEvictionPolicy: AlwaysAllow
```

Un PDB protegge dalle interruzioni **volontarie**: drain dei nodi (upgrade del cluster, autoscaler che spegne un nodo),
chiamate all'**eviction API**. **Non** protegge da un nodo che muore né da un `kubectl delete pod` (che non passa
dall'eviction).

| Campo | Perché |
|---|---|
| `maxUnavailable: 1` | con 3 repliche e quorum 2, al massimo **1 Pod giù per volta** (equivale a `minAvailable: 2`) |
| `unhealthyPodEvictionPolicy: AlwaysAllow` | un Pod **già rotto** (non Ready) si può sfrattare comunque: non blocca il drain |

---

## 5. Il runner, passo per passo

`guardia_lab`, poi 14 passi:

| # | Comando | Cosa vedi |
|---|---|---|
| 1 | `kubectl apply -f …/05-statefulset-storage-pdb.yaml` | `service/db`, `statefulset.apps/db`, `poddisruptionbudget.policy/db` creati |
| 2 | `kubectl -n lab rollout status sts/db` | i Pod nascono **in ordine**: db-0, poi db-1, poi db-2 |
| 3 | `kubectl -n lab get pod,pvc -l app=db` | 3 Pod e 3 PVC `dati-db-0/1/2`, `Bound` |
| 4 | `kubectl -n lab exec db-0 -- cat /data/identita` | una riga: `db-0 avviato alle HH:MM:SS` |
| 5 | `delete pod db-0 && wait --for=condition=Ready pod/db-0 --timeout=120s` | lo StatefulSet ricrea un Pod con **lo stesso nome** |
| 6 | `exec db-0 -- cat /data/identita` | **due righe**: il Pod nuovo ha ritrovato il disco del vecchio |
| 7 | `kubectl -n lab run dns --rm -i --quiet --restart=Never --image=busybox:1.37 -- nslookup db-1.db.lab.svc.cluster.local` | l'IP di **db-1** (il nome completo è necessario con busybox) |
| 8 | `scale sts/db --replicas=1; sleep 10; get pod,pvc -l app=db` | restano solo db-0, ma **i PVC sono ancora 3** (`whenScaled: Retain`) |
| 9 | `scale sts/db --replicas=3 && rollout status sts/db` | db-1 e db-2 tornano e **ritrovano i loro PVC** |
| 10 | `get pdb db; kubectl drain lab-m02 --ignore-daemonsets --delete-emptydir-data --timeout=90s` | il PDB (ALLOWED DISRUPTIONS 1) e lo sfratto dei Pod da `lab-m02`, uno db alla volta. Se il PDB non lo consente, il drain **aspetta e riprova** |
| 11 | `kubectl get nodes; get pods -A -o wide --field-selector spec.nodeName=lab-m02` | `lab-m02` è `Ready,SchedulingDisabled` (cordon); sopra restano solo i Pod dei DaemonSet (calico, kube-proxy) |
| 12 | `get pod -l app=db -o wide; get pdb db` | tutte le repliche db sono sul nodo `lab`; il PDB è tornato a 1 disruption permessa. **Attenzione**: con l'hostpath `standard` su 2 nodi, una replica spostata da `lab-m02` potrebbe non ritrovare i dati scritti là (vedi trappole) |
| 13 | `kubectl uncordon lab-m02 && kubectl get nodes` | il nodo torna schedulabile |
| 14 | `get pod -l app=db -o wide` | **uncordon non riporta indietro i Pod**: restano dove sono. Il nodo riceverà solo Pod **nuovi** |

Opzioni del drain:

- `--ignore-daemonsets`: i Pod dei DaemonSet non si possono spostare (ce n'è uno per nodo); senza l'opzione il drain si
  rifiuta di partire.
- `--delete-emptydir-data`: accetta di perdere i dati dei volumi `emptyDir` dei Pod sfrattati.
- `--timeout=90s`: non aspettare all'infinito se il PDB blocca.

Il drain sfratta **tutti** i Pod di `lab-m02`, non solo i db: anche le repliche di `web` (lezione 02) vengono spostate.

Nessun passo fallisce apposta. Il passo 10 è quello dove "aspettare" è normale: se due db stanno su `lab-m02`, il
secondo viene sfrattato solo quando il primo è rinato Ready altrove.

---

## 6. Le trappole

| Trappola | Cosa succede | Rimedio |
|---|---|---|
| storage class senza `WaitForFirstConsumer` in multi-zona | disco in una zona, Pod nell'altra: Pending per sempre | `volumeBindingMode: WaitForFirstConsumer` |
| hostpath `standard` di minikube con 2 nodi | il Pod sull'altro nodo non vede il volume | driver CSI (`csi-hostpath-sc` nel progetto) |
| `podAntiAffinity` **required** con più repliche che nodi | Pod Pending | `preferred`, o più nodi |
| `nslookup` di busybox col nome corto | NXDOMAIN | nome completo `…svc.cluster.local` |
| `kubectl run -it` senza terminale | output perso | `-i --quiet` |
| PDB con `minAvailable` = repliche | drain e upgrade bloccati per sempre | `maxUnavailable: 1` |
| credere che il PDB protegga dai guasti | un nodo morto non chiede permesso | repliche su nodi/zone diversi |
| aspettarsi che `uncordon` ribilanci | i Pod restano dove sono | rollout restart o descheduler |
| `reclaimPolicy: Delete` sui dati veri | cancelli il PVC, perdi il disco | `Retain` + `whenDeleted: Retain` |

---

## 7. La coda: domande da colloquio

- **Database su Kubernetes: sì o no?** Si può, con un **operator maturo** (CloudNativePG, Percona, Strimzi per Kafka)
  che gestisce failover, backup e upgrade: lo StatefulSet da solo dà identità e disco, **non la replica né il
  failover**. Se il cloud offre il gestito (RDS, Cloud SQL) e il team è piccolo, di solito si sceglie quello: il punto è
  il costo operativo, non la fattibilità.
- **Un nodo muore. Cosa succede al Pod db-1?** Il nodo va `NotReady`; dopo il timeout di eviction (default ~5 min,
  toleration not-ready/unreachable) il Pod è marcato per la cancellazione ma **resta Terminating**: lo StatefulSet **non**
  crea un nuovo db-1 finché non è sicuro che il vecchio sia morto (garanzia "**al più uno**"). Con RWO il volume è
  ancora attaccato al nodo morto. Serve cancellare il nodo, o il taint `node.kubernetes.io/out-of-service`.
- **PDB con `minAvailable` uguale alle repliche?** Il drain si blocca per sempre, e con lui l'upgrade del cluster. Su
  GKE/EKS è una causa frequente di upgrade bloccati.
- **Come allarghi un PVC?** Se la StorageClass ha `allowVolumeExpansion: true`, modifichi
  `resources.requests.storage` del PVC. Nello StatefulSet `volumeClaimTemplates` è **immutabile**: si edita ogni PVC,
  poi si ricrea lo StatefulSet con `--cascade=orphan` (i Pod restano) per allineare il template.

### Comandi da sapere

| Comando | A cosa serve |
|---|---|
| `kubectl -n lab get pod,pvc -l app=db` | Pod e dischi insieme |
| `kubectl -n lab scale sts/db --replicas=1` | scalare uno StatefulSet (in ordine inverso) |
| `kubectl -n lab get pdb db` | quante interruzioni sono permesse ora |
| `kubectl drain <nodo> --ignore-daemonsets --delete-emptydir-data` | svuotare un nodo rispettando i PDB |
| `kubectl uncordon <nodo>` | riaprirlo allo scheduling |

---

## Riepilogo

- StatefulSet = **nome, DNS e disco stabili** per ogni replica.
- **Service headless** per i record DNS di ogni Pod.
- **PVC → StorageClass → PV**; `WaitForFirstConsumer` per le zone.
- **partition** per il canary, **PVC retention** per non perdere i dati.
- Il **PDB** protegge dai drain, non dai guasti; mai `minAvailable` = repliche.

## Prova da solo

1. Cambia il PDB in `minAvailable: 3` (e togli `maxUnavailable`), riapplica e rifai il drain di `lab-m02` con
   `--timeout=60s`: cosa ripete il drain, e come finisce? Poi `kubectl uncordon lab-m02` e rimetti il PDB.
2. Imposta `partition: 2`, cambia l'immagine in `busybox:1.36` e riapplica: quali Pod vengono ricreati? Controlla con
   `kubectl -n lab get pod -l app=db -o custom-columns='NOME:.metadata.name,IMG:.spec.containers[0].image'` (le virgolette servono in zsh, per via delle `[ ]`).
3. Cancella lo StatefulSet (`kubectl -n lab delete sts db`) e guarda `get pvc`: i PVC ci sono ancora? Riapplica il file
   e leggi `/data/identita` di db-0: quante righe?
