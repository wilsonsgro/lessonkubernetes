# Diario di studio Kubernetes — 2 novembre 2026

> Appunti ricostruiti dalla nostra conversazione e dai manifest delle lezioni 03–06 condivisi. Distinguo gli **output effettivamente osservati** dagli **esempi** e dai **comandi proposti ma non confermati**. Ambiente: PC Ubuntu, Minikube con driver Docker, profilo `lab`, Kubernetes v1.34.0, due Node.

## Indice

1. [Architettura: cluster, Node, Pod e container](#1-architettura-cluster-node-pod-e-container)
2. [Control Plane: API Server, etcd, scheduler, controller e kubelet](#2-control-plane-api-server-etcd-scheduler-controller-e-kubelet)
3. [etcd, Raft e quorum](#3-etcd-raft-e-quorum)
4. [Il cluster Minikube lab](#4-il-cluster-minikube-lab)
5. [Calico, Service, DNS e Ingress](#5-calico-service-dns-e-ingress)
6. [Metrics Server e misura delle risorse](#6-metrics-server-e-misura-delle-risorse)
7. [Lezione 02: Deployment, rollout, probe e QoS](#7-lezione-02-deployment-rollout-probe-e-qos)
8. [Lezione 03: Service, Ingress, NetworkPolicy](#8-lezione-03-service-ingress-networkpolicy)
9. [Lezione 04: ConfigMap e Secret; Laravel e AWS](#9-lezione-04-configmap-e-secret-laravel-e-aws)
10. [Lezione 05: StatefulSet, storage e PDB](#10-lezione-05-statefulset-storage-e-pdb)
11. [Lezione 06: scheduling e autoscaling](#11-lezione-06-scheduling-e-autoscaling)
12. [Comandi rapidi e prossimi controlli](#12-comandi-rapidi-e-prossimi-controlli)

---

## 1. Architettura: cluster, Node, Pod e container

- **Cluster**: insieme dei Node gestiti da Kubernetes.
- **Node**: macchina fisica o virtuale, oppure — nel caso di Minikube con driver Docker — un container Docker che rappresenta un Node Kubernetes. Fornisce CPU, RAM e capacità di eseguire Pod.
- **Pod**: unità minima distribuibile di Kubernetes; contiene uno o più container che condividono rete e possono condividere volumi. Un Pod gira su un solo Node alla volta.
- **Container**: ambiente in cui gira il processo applicativo, per esempio NGINX, PHP/Laravel o `whoami`.

Schema mentale: `cluster → Node → Pod → container`.

Un solo PC Ubuntu **può ospitare più Node Kubernetes**: con il driver Docker, Minikube esegue più container-Node. Non sono però macchine fisiche indipendenti: se si spegne Ubuntu si fermano entrambi.

### Differenza tra accessi

```bash
minikube -p lab ssh                         # entra nel Node principale lab
minikube -p lab ssh -n lab-m02              # entra nel Node worker
kubectl -n ingress-nginx exec -it <pod> -- sh  # shell di un container del Pod, se presente
```

Il percorso `/etc/kubernetes/manifests` esisteva **nel filesystem del Node `lab`**, ma non sull'host Ubuntu:

```bash
minikube -p lab ssh -- sudo ls /etc/kubernetes/manifests
# etcd.yaml  kube-apiserver.yaml  kube-controller-manager.yaml  kube-scheduler.yaml

ls /etc/kubernetes/manifests
# File o directory non esistente (sull'host Ubuntu)
```

Il kubelet sorveglia quei manifest di **Static Pod** e può avviare i componenti fondamentali anche prima che l'API Server sia disponibile.

## 2. Control Plane: API Server, etcd, scheduler, controller e kubelet

| Componente | Ruolo |
|---|---|
| `kube-apiserver` | Porta di ingresso per API e `kubectl`: autentica, autorizza, valida e gestisce risorse Kubernetes. |
| `etcd` | Database key-value distribuito che conserva lo stato del cluster. |
| `kube-scheduler` | Sceglie il Node su cui assegnare un Pod non ancora schedulato. |
| `kube-controller-manager` | Esegue controller che riconciliano stato desiderato e reale. |
| `kubelet` | Agente sul Node: fa avviare e monitorare Pod tramite Container Runtime. |
| Container Runtime (`containerd`, Docker tramite integrazione del runtime) | Esegue concretamente i container. |
| `kube-proxy` | Quando utilizzato, configura la connettività dei Service sui Node. |
| CNI/Calico | Configura rete dei Pod e applica NetworkPolicy. |

### RBAC

**Authentication**: chi sei? **Authorization/RBAC**: che operazioni puoi fare? Un `Role` può consentire `get`, `list`, `watch` sui Pod; un `RoleBinding` assegna il Role a utente, gruppo o ServiceAccount. Il controllo avviene nell'API Server. RBAC non autentica autonomamente gli utenti.

### Esempio di flusso

`kubectl create deployment` → API Server → stato memorizzato in etcd → controller crea ReplicaSet e Pod → scheduler assegna i Node → kubelet e runtime avviano container → API Server riceve aggiornamenti di stato.

## 3. etcd, Raft e quorum

etcd **non è un Pod applicativo/database PostgreSQL**: è il database interno di Kubernetes che memorizza oggetti come Pod, Deployment, Service, ConfigMap, Secret, ruoli e stato del cluster.

Una installazione può avere più **membri etcd** che mantengono copie coerenti mediante l'algoritmo di consenso **Raft**. I membri etcd non coincidono necessariamente con tutti i Node Kubernetes.

Quorum = maggioranza stretta:

```text
quorum = floor(N / 2) + 1
max guasti tollerati = N - quorum
```

La funzione `floor` arrotonda verso il basso: `floor(2,5) = 2`.

| Membri etcd | Quorum | Guasti tollerati |
|---:|---:|---:|
| 1 | 1 | 0 |
| 3 | 2 | 1 |
| 4 | 3 | 1 |
| 5 | 3 | 2 |
| 6 | 4 | 2 |

**Perché 3 o 5, non 4?** Passare da 3 a 4 non aumenta i guasti tollerati; passare da 3 a 5 li porta da 1 a 2. Cinque membri forniscono resilienza a due guasti **di membri** solo se la loro collocazione evita guasti correlati. Cinque istanze distribuite su tre sole macchine non assicurano tolleranza a due guasti di macchina.

- **Stacked etcd**: membro etcd sui Node Control Plane; cinque membri normalmente su cinque macchine/Node indipendenti.
- **External etcd**: membri su server dedicati anche non registrati come Node Kubernetes. Esempio possibile: tre Control Plane Kubernetes più cinque server esterni etcd e altri Worker.
- **Il nostro cluster**: due Node Kubernetes, ma un solo membro `etcd-lab` sul Control Plane `lab`.

## 4. Il cluster Minikube lab

### Comando iniziale di creazione

```bash
minikube start -p lab --driver=docker --nodes=2 --cpus=2 --memory=4g --cni=calico
```

- Profilo `lab`.
- Due Node creati tramite Docker.
- Plugin di networking Calico.
- `--cpus` e `--memory` configurano le risorse richieste per i Node (l'effettiva capacità vista in Kubernetes si verifica con `kubectl describe node`).

### Problema iniziale con kubectl

```text
The connection to the server localhost:8080 was refused
```

`kubectl config get-contexts` inizialmente mostrava solo le intestazioni: **nessun context configurato**. Questo non prova da solo l'assenza di Kubernetes; significa che `kubectl` non sapeva a quale API Server connettersi. Dopo l'avvio del profilo, Minikube ha configurato il context `lab`.

### Avvio successivo osservato

```bash
minikube -p lab start
```

Minikube v1.37.0 su Ubuntu 24.04 ha riavviato/aggiornato i container Docker `lab` e `lab-m02`, con Kubernetes v1.34.0; ha verificato gli addon **ingress** e **metrics-server**.

### Node osservati

```text
NAME      STATUS   ROLES           INTERNAL-IP     VERSION
lab       Ready    control-plane   192.168.49.2    v1.34.0
lab-m02   Ready    <none>          192.168.49.3    v1.34.0
```

`192.168.49.2` e `192.168.49.3` sono IP dei container-Node sulla rete Docker di Minikube, **non IP dei Pod** e non l'IP LAN dell'host Ubuntu.

Altri esempi effettivamente osservati:

- Pod `web`: `10.244.77.77`, `10.244.104.70`, `10.244.104.73`.
- Pod NGINX Ingress: `10.244.77.69`.
- I **ClusterIP** dei Service sono un terzo tipo di IP virtuale.

### Namespace e visibilità dei Pod

```bash
kubectl get pods                  # solo namespace default
kubectl get pods -n lab           # solo namespace lab
kubectl get pods -A -o wide       # tutti i namespace, IP e Node
kubectl get nodes -o wide
kubectl config current-context
```

Dopo un riavvio Minikube, `kubectl get pods` restituiva `No resources found in default namespace`: non significa che il cluster fosse vuoto. Per verificare i componenti di sistema si usa `-A` o `-n kube-system`.

## 5. Calico, Service, DNS e Ingress

### CNI e Calico

CNI significa *Container Network Interface*: specifica/interfaccia per configurare networking dei container. **Calico** è una implementazione che gestisce connettività dei Pod e NetworkPolicy; nel nostro cluster sono stati osservati due Pod `calico-node`, uno per Node, più `calico-kube-controllers`.

### Addon NGINX Ingress

```bash
minikube -p lab addons enable ingress
```

Output osservato:

```text
Using image registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.6.2
Using image registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.6.2
Using image registry.k8s.io/ingress-nginx/controller:v1.13.2
The 'ingress' addon is enabled
```

Le immagini vengono reperite dal container registry quando necessarie; NGINX Ingress Controller gira in un **Pod Kubernetes**, non come installazione NGINX sull'host Ubuntu. I due Job di admission certificate `create`/`patch` risultavano `Completed`, mentre il controller era `Running` sul Node `lab`.

Differenze:

- **Service**: nome e punto d'accesso stabile ai Pod selezionati per label.
- **Ingress**: regole HTTP/HTTPS per host e path verso Service; serve un controller come ingress-nginx.
- **NetworkPolicy**: policy di traffico in ingresso/uscita applicate dal CNI.
- **CoreDNS**: risoluzione dei nomi Kubernetes.

## 6. Metrics Server e misura delle risorse

```bash
minikube -p lab addons enable metrics-server
kubectl top nodes
kubectl top pods -A
```

Il Pod `metrics-server` era `1/1 Running`. Misure effettivamente osservate:

```text
NAME      CPU(cores) CPU(%) MEMORY(bytes) MEMORY(%)
lab       412m       3%     1058Mi        6%
lab-m02   148m       1%      381Mi        2%
```

Alcuni consumi Pod osservati: kube-apiserver `82m` / `283Mi`, etcd `46m` / `60Mi`, ingress-nginx `5m` / `139Mi`, metrics-server `7m` / `18Mi`.

- `1000m` di CPU = 1 core; `412m` = 0,412 core.
- `kubectl top` mostra utilizzo osservato, **non** `requests` o `limits`.
- Metrics Server fornisce metriche di CPU/memoria a `kubectl top` e al controllo HPA; non è uno storico completo come Prometheus.
- Le percentuali CPU/memoria riportate inizialmente sembravano riferirsi a capacità più grandi di quelle attese dalle flag di avvio: per una spiegazione precisa bisogna ispezionare `Capacity` e `Allocatable` con `kubectl describe node`.

## 7. Lezione 02: Deployment, rollout, probe e QoS

File eseguito:

```bash
kubectl apply -f /home/wilsonsgro/kubernetesprj/lezioni/kubernetes/02-deployment-rollout-probe.yaml
```

### Primo esercizio con `eco`

```bash
kubectl create deployment eco --image=traefik/whoami:v1.12 --replicas=2
kubectl get deployments
kubectl get replicasets
kubectl get pods -o wide
```

Output osservato: Deployment `eco` `READY 2/2`, ReplicaSet `eco-55d948c646` con due Pod pronti, distribuiti su `lab` e `lab-m02`.

- **Deployment** gestisce revisioni e ReplicaSet.
- **ReplicaSet** mantiene il numero desiderato di Pod.
- I Pod hanno nomi generati; se uno viene eliminato, il ReplicaSet lo sostituisce.

Il comando seguente osservava le eliminazioni e ricreazioni:

```bash
kubectl get pods -l app=eco -w & W=$!; sleep 2; kubectl delete pod -l app=eco --wait=false; sleep 13; kill $W
```

`&` manda `kubectl get` in background, `W=$!` salva il suo PID, `kill $W` ferma **solo il monitoraggio**, non i Pod; `delete` elimina i Pod selezionati, **non il Deployment**. È un esercizio di *reconciliation* / self-healing.

### Deployment `web` nel namespace `lab`

Il manifest richiede 3 repliche di `traefik/whoami:v1.12` con porta `8080`.

Output osservato:

```text
NAME   READY   UP-TO-DATE   AVAILABLE
web    3/3     3            3
```

Tre Pod `web-6bdcf59778-...` osservati: uno su `lab`, due su `lab-m02`. Due erano più recenti del Deployment, ma il motivo della loro ricreazione non è stato verificato (utile `kubectl get events -n lab`).

### Rolling update

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1
    maxUnavailable: 0
```

Durante un aggiornamento da tre repliche: fino a quattro Pod previsti; obiettivo di non scendere sotto tre disponibili. `minReadySeconds: 5`, `progressDeadlineSeconds: 120`, `revisionHistoryLimit: 5` gestiscono disponibilità, monitoraggio e storia delle revisioni.

```bash
kubectl -n lab rollout status deployment/web
kubectl -n lab set image deployment/web web=traefik/whoami:v1.11
kubectl -n lab rollout history deployment/web
kubectl -n lab rollout undo deployment/web --to-revision=1
```

**Nota:** la conversazione non conferma che l'update o l'undo siano stati eseguiti; erano esercizi suggeriti nel file/nei messaggi. Un rollout completato non prova da solo la correttezza applicativa end-to-end.

### Probe

- **startupProbe**: controlla l'avvio, tiene sospese le altre probe finché non passa.
- **readinessProbe**: determina quando il Pod è pronto a ricevere traffico; il fallimento non lo riavvia.
- **livenessProbe**: se fallisce ripetutamente, causa il riavvio del container.
- Nel manifest tutte interrogano `/health` sulla porta HTTP nominata `http` (`8080`).

`preStop.sleep.seconds: 5` e `terminationGracePeriodSeconds: 30` servono a rendere meno brusca la chiusura, ma non garantiscono automaticamente zero downtime.

### Requests, limits, QoS

Per il container `web`:

```yaml
resources:
  requests:
    cpu: 50m
    memory: 32Mi
  limits:
    memory: 64Mi
```

- `requests`: capacità considerata dallo scheduler.
- `limits`: restrizioni a runtime (CPU può subire throttling, memoria può causare OOM).
- Classi QoS: **Guaranteed**, **Burstable**, **BestEffort**. Qui è **Burstable**: le request e i limit non sono tutti uguali e manca un CPU limit.

```bash
kubectl -n lab get pod -o 'custom-columns=NOME:.metadata.name,QOS:.status.qosClass'
```

## 8. Lezione 03: Service, Ingress, NetworkPolicy

File:

```bash
kubectl apply -f /home/wilsonsgro/kubernetesprj/lezioni/kubernetes/03-service-ingress-networkpolicy.yaml
```

Quattro risorse nel namespace `lab`:

1. Service `web`, tipo `ClusterIP`, porta `80` → porta denominata `http` dei Pod (`8080`), selettore `app.kubernetes.io/name=web`.
2. Ingress `web`, classe `nginx`, host `web.lab.local`, path `/` Prefix → Service `web`.
3. NetworkPolicy `default-deny-ingress`, seleziona tutti i Pod di `lab` e blocca di default il loro traffico **in ingresso**.
4. NetworkPolicy `web-allow`, consente traffico in ingresso verso `web` sulla porta nominata `http` da Pod `ruolo=client` nello stesso namespace oppure da Pod nel namespace `ingress-nginx`.

Le policy sono additive: più policy possono concedere accesso. Il file usa Calico affinché siano effettivamente applicate.

### Test Service + NetworkPolicy riuscito

```bash
kubectl -n lab run curl --rm -it \
  --image=curlimages/curl:8.23.0 \
  --labels=ruolo=client \
  -- sh -c 'sleep 8; curl -s web/api'
```

Output effettivo riportato dall'app `whoami` (estratto):

```json
{
  "hostname": "web-6bdcf59778-fthbl",
  "ip": ["127.0.0.1", "::1", "10.244.104.76", "fe80::5029:61ff:fe73:b529"],
  "url": "/api",
  "host": "web",
  "method": "GET",
  "remoteAddr": "10.244.104.78:50372"
}
```

Questo **conferma** che un Pod con `ruolo=client` ha raggiunto con successo un Pod `web` attraverso il Service. Il Pod temporaneo `curl` è stato poi eliminato grazie a `--rm`.

Test di blocco proposto, **senza output finale condiviso**:

```bash
kubectl -n lab run intruso --rm -it --image=curlimages/curl:8.23.0 \
  -- sh -c 'sleep 8; curl -v -m 3 web/api'
```

### Test Ingress dall'host Ubuntu

```bash
curl -s -H 'Host: web.lab.local' http://$(minikube -p lab ip)/api
```

`$(minikube -p lab ip)` viene sostituito dalla shell con l'IP del Node principale, che nell'output era `192.168.49.2`. L'header `Host` permette a NGINX di scegliere la regola per `web.lab.local`. In condizioni corrette il percorso previsto è `Ubuntu → ingresso NGINX → Service web → Pod web`.

**Non abbiamo ricevuto il risultato effettivo di questo curl dall'host**; la raggiungibilità dipende anche dalla rete Docker/Minikube e dalla configurazione Ingress.

Comandi di verifica:

```bash
kubectl -n lab get svc,ingress,networkpolicy
kubectl -n lab get endpointslices -l kubernetes.io/service-name=web
kubectl -n ingress-nginx get pods -o wide
```

## 9. Lezione 04: ConfigMap e Secret; Laravel e AWS

File:

```bash
kubectl apply -f /home/wilsonsgro/kubernetesprj/lezioni/kubernetes/04-configmap-secret.yaml
```

Tre risorse nel namespace `lab`:

- ConfigMap `app-config`: `LOG_LEVEL=info`, `app.properties` con `feature.x=false`.
- Secret `db`: username `app`, password **didattica** presente nel manifest (non usare valori reali in repository).
- Deployment `conf`: un Pod `busybox:1.37` che importa `LOG_LEVEL` dalla ConfigMap e `DB_PASSWORD` dal Secret come variabili d'ambiente; monta anche ConfigMap in `/etc/app` e Secret in `/run/secrets/db` come file.

### Esperimento di aggiornamento

```bash
kubectl -n lab rollout status deploy/conf
P=$(kubectl -n lab get pod -l app=conf -o name | head -1)
kubectl -n lab exec "$P" -- sh -c 'echo "$LOG_LEVEL"; cat /etc/app/app.properties'
kubectl -n lab patch cm app-config --type merge \
  -p '{"data":{"LOG_LEVEL":"debug","app.properties":"feature.x=true\n"}}'
# Attendere la propagazione del volume, poi:
kubectl -n lab exec "$P" -- sh -c 'echo "$LOG_LEVEL"; cat /etc/app/app.properties'
```

Risultato didattico atteso: il valore della **variabile d'ambiente** resta `info` nel container esistente, mentre il **file montato** si aggiorna a `feature.x=true`. Il file aggiornato non implica che l'applicazione lo rilegga automaticamente; può essere necessario un reload/rollout. Montaggi con `subPath` non ricevono aggiornamenti automatici nello stesso modo.

### Esempio Laravel/PHP

- ConfigMap per `APP_ENV`, `APP_DEBUG`, `APP_URL`, `LOG_CHANNEL`, `DB_HOST`, `DB_DATABASE` e simili se non sensibili.
- Secret per `APP_KEY`, `DB_PASSWORD`, token API e credenziali; `DB_USERNAME` può stare nel Secret per prudenza.
- Il Pod può importare entrambi con `envFrom`; non è obbligatorio avere un `.env` fisico nell'immagine.
- Se si usa `php artisan config:cache`, la cache deve riflettere i valori dell'ambiente corretto; cambi a ConfigMap/Secret iniettati come env richiedono normalmente nuovi container e rigenerazione della cache.

Esempio Deployment (estratto):

```yaml
envFrom:
  - configMapRef:
      name: laravel-config
  - secretRef:
      name: laravel-secret
```

### Git e Secret

- Committare manifest `Deployment`, `Service`, `Ingress` e `ConfigMap` **solo se senza segreti**.
- Non committare `Secret` con password reali neppure in Base64: Base64 **non cifra**.
- Per laboratori: file `secret.yaml` ignorato in `.gitignore`, più eventuale `secret.example.yaml` con valori fittizi.
- Se una credenziale reale è stata committata, sostituirla/ruotarla: `.gitignore` non cancella la storia Git.

### Su AWS/EKS

Approccio spiegato: conservare le credenziali in **AWS Secrets Manager** e concedere ai workload EKS l'accesso appropriato via IAM/Pod Identity. Due integrazioni possibili:

- **Secrets Store CSI Driver + provider AWS**: monta segreti come file nel Pod.
- **External Secrets Operator**: sincronizza da Secrets Manager a Kubernetes Secret, riutilizzabile con `envFrom`.

Nel repo Git rimangono i riferimenti e le configurazioni, non i valori segreti. La rotazione AWS non modifica automaticamente le variabili d'ambiente di container già avviati.

## 10. Lezione 05: StatefulSet, storage e PDB

File:

```bash
kubectl apply -f /home/wilsonsgro/kubernetesprj/lezioni/kubernetes/05-statefulset-storage-pdb.yaml
```

Tre risorse principali nel namespace `lab`:

1. **Service headless** `db`, `clusterIP: None`, con `publishNotReadyAddresses: true` e porta `5432`.
2. **StatefulSet** `db`, tre repliche `db-0`, `db-1`, `db-2` con `podManagementPolicy: OrderedReady`.
3. **PodDisruptionBudget** `db`, `maxUnavailable: 1`, che limita le eviction volontarie delle repliche.

Lo StatefulSet crea tre claim persistenti `dati-db-0`, `dati-db-1`, `dati-db-2`, ciascuno da **1 GiB** con `ReadWriteOnce`. Minikube usa normalmente la propria StorageClass predefinita.

**Importante:** il container di questa lezione è **BusyBox**, non un vero PostgreSQL. Esso aggiunge la stringa `db-N avviato alle ...` al file persistente `/data/identita`, poi dorme. La porta `5432` e il nome `db` sono didattici: StatefulSet da solo non configura replica database, backup o failover.

### Esperimento identità e persistenza

```bash
kubectl -n lab rollout status sts/db
kubectl -n lab get pod,pvc -l app=db
kubectl -n lab exec db-0 -- cat /data/identita
kubectl -n lab delete pod db-0
kubectl -n lab wait --for=condition=Ready pod/db-0 --timeout=180s
kubectl -n lab exec db-0 -- cat /data/identita
```

Risultato previsto: il Pod sostitutivo mantiene nome `db-0`, riutilizza il suo PVC e nel file si trovano più righe di avvio.

### Test DNS dello StatefulSet

```bash
kubectl -n lab run dns --rm -i --quiet --restart=Never \
  --image=busybox:1.37 -- nslookup db-1.db.lab.svc.cluster.local
```

Scomposto: `db-1` = nome del Pod, `db` = Service headless, `lab` = namespace, `svc.cluster.local` = dominio standard dei Service nel cluster. CoreDNS dovrebbe risolverlo nell'IP attuale di `db-1`; il nome rimane stabile anche se l'IP cambia. Il risultato effettivo del comando non è stato condiviso.

### Drain di un Node e PodDisruptionBudget

```bash
kubectl drain lab-m02 --ignore-daemonsets --delete-emptydir-data --timeout=90s
```

- Esegue **cordon** (rende il Node unschedulable), poi tenta le eviction dei Pod idonei.
- `--ignore-daemonsets` lascia i Pod gestiti dai DaemonSet.
- `--delete-emptydir-data` permette la rimozione di Pod con dati temporanei `emptyDir`, che si perdono.
- `--timeout=90s` limita la durata; il drain può non completarsi per PDB o problemi di scheduling/storage.

Output **effettivamente osservato** dopo il comando:

```text
lab       Ready
lab-m02   Ready,SchedulingDisabled
```

Questo conferma il **cordon**, non necessariamente il completamento di tutte le eviction. `Ready` indica che il kubelet del Node risponde, `SchedulingDisabled` che non accetta normali nuovi Pod.

```bash
kubectl get pods -A -o wide --field-selector spec.nodeName=lab-m02
kubectl -n lab get pdb db
kubectl -n lab describe pdb db
kubectl uncordon lab-m02
```

`uncordon` riabilita lo scheduling ma non riporta automaticamente sul Node i Pod ricreati altrove. Non è stato condiviso l'output finale di `uncordon`.

## 11. Lezione 06: scheduling e autoscaling

File:

```bash
kubectl apply -f /home/wilsonsgro/kubernetesprj/lezioni/kubernetes/06-scheduling-autoscaling.yaml
```

Il manifest definisce cinque risorse:

| Risorsa | Nome | Dettaglio |
|---|---|---|
| PriorityClass (cluster-scoped) | `lab-critico` | `value: 100000`, `PreemptLowerPriority` |
| Service (`lab`) | `api` | Porta 80 → 8080, selector `app=api` |
| NetworkPolicy (`lab`) | `api-allow-client` | Ingresso ai Pod `api` da Pod con label `ruolo=client` nello stesso namespace |
| Deployment (`lab`) | `api` | Immagine `traefik/whoami:v1.12`, requests CPU `20m`, RAM `16Mi`, limit RAM `32Mi` |
| HPA (`lab`) | `api` | Min 2, max 8 repliche, target CPU medio 60% delle requests |

### Dove lo scheduler mette i Pod

- `nodeSelector`: vincolo diretto per label.
- `nodeAffinity`: requisiti o preferenze più flessibili.
- `taints` e `tolerations`: il Node può rifiutare Pod non compatibili; una toleration **non obbliga** il Pod a usare quel Node.
- `podAntiAffinity`: preferisce/se richesto impone separazione tra Pod.
- `topologySpreadConstraints`: in questo manifest preferisce bilanciare tra host con `maxSkew: 1`, ma `whenUnsatisfiable: ScheduleAnyway` è **soft**.
- `PriorityClass`: priorità di scheduling e possibile preemption a seconda delle condizioni.

### Quanti Pod: HPA

```text
repliche desiderate ≈ ceil(repliche attuali × CPU osservata % / CPU target %)
```

Nel manifest CPU request per Pod `20m`; il 60% corrisponde a **12m medi per Pod**. Si tratta della percentuale rispetto alle **requests**, non rispetto alla capacità totale del Node.

Comportamento HPA configurato:

- `minReplicas: 2`, `maxReplicas: 8`.
- `scaleUp`: finestra stabilizzazione zero, al più +100% per 15 s secondo la policy.
- `scaleDown`: stabilizzazione 120 s, al più un Pod per 60 s secondo la policy.

**Distinzioni:** HPA cambia il **numero di Pod**; VPA le **requests** per Pod; Cluster Autoscaler/Karpenter il **numero di Node**; KEDA abilita scaling su eventi/metriche esterne. Nel lab è installato HPA, **non è dimostrato un autoscaler dei Node**.

### Test proposti dalla lezione (non abbiamo output eseguiti)

```bash
kubectl -n lab get pod -l app=api -o wide
kubectl -n lab get hpa api -w
kubectl -n lab run carico --rm -it --image=busybox:1.37 \
  --labels=ruolo=client -- \
  sh -c 'while true; do wget -q -O- http://api/ >/dev/null; done'
kubectl -n lab describe hpa api
kubectl -n lab top pods
```

Il generatore `carico` serve a sollecitare l'applicazione. Non è garantito che una sola sorgente faccia aumentare abbastanza la CPU per far scattare l'HPA; fermarlo con `Ctrl+C`.

Test taint didattico della lezione (da fare con cautela e poi ripulire):

```bash
kubectl taint nodes lab-m02 dedicato=batch:NoSchedule
kubectl taint nodes lab-m02 dedicato=batch:NoSchedule-
```

## 12. Comandi rapidi e prossimi controlli

### Stato generale

```bash
kubectl config current-context
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl -n lab get deployments,statefulsets,svc,ingress,networkpolicy,hpa,pdb
kubectl -n lab get pvc
kubectl get pv
kubectl top nodes
kubectl top pods -A
```

### Diagnosticare un problema

```bash
kubectl -n lab describe pod <nome-pod>
kubectl -n lab logs <nome-pod>
kubectl -n lab get events --sort-by=.metadata.creationTimestamp
kubectl -n lab get endpointslices -l kubernetes.io/service-name=web
kubectl -n lab describe hpa api
```

### Controllare rollout e volumi

```bash
kubectl -n lab rollout status deployment/web
kubectl -n lab rollout history deployment/web
kubectl -n lab rollout status statefulset/db
kubectl -n lab get pvc
kubectl -n lab get pdb db
```

### Promemoria di sicurezza e limiti

- Non committare password vere o `APP_KEY` Laravel in YAML, nemmeno in Base64.
- `kubectl apply` dichiara risorse; **non prova** da solo che i Pod siano pronti: verificare `get`, `describe`, `rollout status`, endpoint e test applicativi.
- `kubectl get pods` senza `-n` interroga il namespace corrente (spesso `default`).
- Il lab usa **Kubernetes v1.34.0**, anche se alcuni commenti nei manifest citano 1.35: verificare compatibilità delle feature quando si usa un cluster diverso.
- La persistenza locale Minikube non equivale alla resilienza di uno storage distribuito/cloud.
- PDB copre le eviction volontarie, non i guasti improvvisi né necessariamente `kubectl delete pod`.

---

**Sintesi del percorso:** hai visto come creare due Node su un solo PC, come il Control Plane registra e gestisce lo stato, come Calico connette e filtra i Pod, come Deployment/ReplicaSet mantengono le repliche, come Service e Ingress espongono l'applicazione, come ConfigMap e Secret separano configurazione e codice, come StatefulSet/PVC conservano identità e dati, e come HPA adatta il numero di repliche ai consumi.
