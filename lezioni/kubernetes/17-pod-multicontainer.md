# 17 — Dentro il Pod: init container, sidecar nativi, ciclo di vita

Spiegazione di `17-pod-multicontainer.yaml` (questa cartella).

## In una frase

Il file crea un namespace `lab-pod` con **due Pod e un Job** che mostrano cosa c'è dentro un Pod: un **init container**
che blocca l'app finché una dipendenza non esiste, un **sidecar nativo** (un initContainer con `restartPolicy: Always`)
che condivide rete e volume con l'app, e un **Job con sidecar** che arriva comunque a `Complete`. Il runner aggiunge le
prove di immutabilità del Pod e la differenza fra **fase** e colonna **STATUS**.

## Due file con lo stesso nome: quale lanciare

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/lezioni/kubernetes/17-pod-multicontainer.yaml` | **questo**: i manifest, con la teoria nei commenti | `kubectl apply -f 17-pod-multicontainer.yaml` (ma conviene il guidato) |
| `~/kubernetesprj/kubernetes/17-pod-multicontainer.sh` | lo script **guidato**: applica il file e fa le prove una per volta, spiegando prima di eseguire (Invio / s / q) | `bash kubernetes/17-pod-multicontainer.sh` |

Per imparare conviene lo **guidato**. Questo file va **letto** mentre lo guidato gira: i commenti spiegano il perché.

Versione dichiarata: **Kubernetes 1.34–1.35** (il lab minikube gira la **1.34.0**). Livello 1 — Workload.

## Com'è fatto il file

```
intestazione (commenti)  → il Pod come host logico, i ruoli multi-container, sidecar nativi,
                            fase vs STATUS, restartPolicy, immutabilità, LAB, NEL PROGETTO VERO
Namespace lab-pod
1) Pod ciclo             → init container che aspetta il Service db-finto
2) Pod web-log           → sidecar nativo "spedisci" + app whoami + container "cliente", emptyDir condiviso
3) Job lavoro            → Job con sidecar nativo "battito"
coda (commenti)          → domande da colloquio, riepilogo
```

---

## 1. La teoria nell'intestazione

### Il Pod è un piccolo host logico

Lo scheduler piazza **Pod**, non container: un container gira sempre dentro un Pod. Tutti i container di un Pod
finiscono sullo **stesso nodo** e condividono:

| Cosa | Effetto |
|---|---|
| **rete** | un solo IP, un solo spazio di porte: si parlano su `localhost` |
| **hostname** | il nome del Pod (per questo deve essere un nome DNS valido) |
| **volumi** | quelli dichiarati in `spec.volumes`, montati dove serve |
| **IPC** | memoria condivisa e semafori |

Il **filesystem** dei container invece **non** è condiviso: si passa da un volume. A tenere in piedi i namespace del
kernel del Pod c'è il container **pause**.

### Un Pod, tanti container: quando ha senso

Due container stanno nello stesso Pod se **nascono, scalano e muoiono insieme**. Si scala aggiungendo Pod, mai mettendo
due copie dell'app nello stesso Pod.

| Ruolo | Cosa fa |
|---|---|
| **init** | prepara e finisce: migrazioni, attesa di una dipendenza, permessi su un volume. Uno alla volta, in ordine, ognuno deve uscire con 0 prima del successivo |
| **sidecar** | affianca l'app per tutta la vita: log shipper, proxy mTLS, ricarica della config, git-sync |
| **adapter** | traduce l'uscita dell'app (es. metriche in formato Prometheus) |
| **ambassador** | fa da proxy verso l'esterno (l'app parla con localhost) |

### Sidecar nativi

Stabili dalla 1.33 (nel lab il feature gate `SidecarContainers` è GA). Un sidecar nativo è **un initContainer con
`restartPolicy: Always`**:

- parte nell'ordine degli init, ma **non blocca**: appena è avviato (o appena passa la sua `startupProbe`) parte l'init
  successivo;
- resta acceso per tutta la vita del Pod e viene **riavviato** se cade;
- si spegne **dopo** i container applicativi, in ordine inverso;
- **non tiene in vita un Job**: quando l'app finisce, il Pod finisce.

Prima della 1.28 un sidecar era un container normale: partiva in ordine casuale rispetto all'app e teneva i Job
"Running" per sempre.

### Misurato sul lab: il PID 1 che ignora SIGTERM

Un sidecar `sh -c "while …"` **ignora SIGTERM**: è il PID 1 del container, e il PID 1 non ha handler di default. Il
kubelet aspetta tutto `terminationGracePeriodSeconds` (**30 s**) e poi lo uccide: stato **Error/137** (137 = 128 + 9,
SIGKILL). Il Pod risulta comunque **Succeeded**. Rimedio: `trap` sul TERM, o un processo che gestisce il segnale.

### Fase del Pod ≠ colonna STATUS

La **fase** (`.status.phase`) ha cinque valori: `Pending`, `Running`, `Succeeded`, `Failed`, `Unknown`. Quello che
`kubectl get pod` mostra in **STATUS** è una sintesi più fine: `Init:0/2`, `PodInitializing`, `CrashLoopBackOff`,
`Completed`, `Terminating`… `CrashLoopBackOff` è un Pod in fase **Running** con un container che riparte con attese
crescenti (10 s, 20 s, … fino a 5 min).

### `restartPolicy` del Pod (vale per i container applicativi)

| Valore | Comportamento | Dove |
|---|---|---|
| `Always` | riparte sempre | default, **obbligatoria nei Deployment** |
| `OnFailure` | riparte solo se esce ≠ 0 | Job |
| `Never` | non riparte | Job, Pod di debug |

Da non confondere con il `restartPolicy: Always` **del singolo initContainer**, che lo rende un sidecar.

### I Pod sono (quasi) immutabili

Su un Pod già creato si possono cambiare solo:

- l'**immagine** dei container (il kubelet lo riavvia: `Killing … definition changed`; se il processo ignora SIGTERM il
  cambio arriva dopo i 30 s di grazia, misurato sul lab);
- `activeDeadlineSeconds`;
- **aggiunte** alle `tolerations`;
- poco altro (le risorse con il resize in-place, beta nella 1.34).

Tutto il resto dà `Forbidden: pod updates may not change fields other than…`. Per questo non si modifica un Pod: si
cambia il **template** del Deployment e il ReplicaSet ne crea di nuovi. Un Pod senza controller, se il nodo muore, non
rinasce da nessuna parte.

Nota terminologica: il libro di riferimento chiama "statici" i Pod senza controller, ma in Kubernetes **static Pod** è
un'altra cosa: quelli letti dal kubelet da `/etc/kubernetes/manifests` (lezione 01).

### Riquadro «NEL PROGETTO VERO»

In `~/biodistretto/kubernetes` (branch `kubernetes`):

- Il bucket di MinIO lo crea un **Job** (`minio-init`), non un init container: va fatto **una volta per cluster**, non a
  ogni avvio di un Pod.
  `grep -n -A3 'mc alias' terraform/app/manifests/minio-init.yaml.tftpl`
- Cosa manca, e si vede: dopo un riavvio **nginx e worker ripartono un paio di volte** finché DNS e mariadb non sono
  pronti.
- **Esercizio** proposto dal file: aggiungi al worker un init container che aspetta mariadb (busybox:
  `until nc -z mariadb 3306; do sleep 2; done`) e conta i restart dopo uno stop e start del cluster
  (`minikube -p biodistretto`).
  `grep -n -A3 'name: worker' terraform/app/manifests/app.yaml.tftpl`

---

## 2. I manifest

### Namespace `lab-pod`

Tutto vive qui: la pulizia è un solo `kubectl delete ns lab-pod`.

### 1) Pod `ciclo`: init container che aspetta una dipendenza

```yaml
spec:
  initContainers:
    - name: attendi-db
      image: busybox:1.37
      command: ["sh", "-c", "until nslookup db-finto.lab-pod.svc.cluster.local; do echo aspetto db-finto; sleep 2; done"]
  containers:
    - name: app
      image: busybox:1.37
      command: ["sh", "-c", "echo dipendenza trovata, parto; sleep 3600"]
      resources:
        requests: { cpu: 5m, memory: 8Mi }
        limits: { memory: 16Mi }
```

| Campo | Perché |
|---|---|
| `initContainers[0]` | un ciclo `until … do … done`: riprova ogni 2 s finché `nslookup` riesce, poi esce con 0 |
| nome **completo** `db-finto.lab-pod.svc.cluster.local` | l'`nslookup` di busybox **non applica i search domain** del `resolv.conf` (misurato: `kubernetes.default` → NXDOMAIN) |
| `containers[0]` | parte solo dopo che l'init è uscito con 0; stampa una riga e dorme un'ora |
| `sleep 3600` senza `trap` | è il PID 1 che ignora SIGTERM: servirà al runner per mostrare i 30 s di grazia |

Finché il Service `db-finto` non esiste, STATUS resta **`Init:0/1`** (zero init finiti su uno).

### 2) Pod `web-log`: app + sidecar nativo + cliente

```yaml
spec:
  initContainers:
    - name: spedisci
      image: busybox:1.37
      restartPolicy: Always            # ← questo lo rende un sidecar nativo
      command: ["sh", "-c", "trap 'exit 0' TERM; touch /log/accessi; tail -F /log/accessi & wait"]
      volumeMounts:
        - { name: log, mountPath: /log }
  containers:
    - name: app
      image: traefik/whoami:v1.12
      args: ["--port", "80"]
      ports:
        - containerPort: 80
      volumeMounts:
        - { name: log, mountPath: /log }
    - name: cliente
      image: busybox:1.37
      command: ["sh", "-c", "trap 'exit 0' TERM; while true; do wget -qO- localhost:80 | head -1 >> /log/accessi; sleep 5; done & wait"]
      volumeMounts:
        - { name: log, mountPath: /log }
  volumes:
    - name: log
      emptyDir: {}                     # vive e muore con il Pod
```

(Ogni container ha `requests` cpu 5m e `limits` di memoria piccoli: 16Mi, 32Mi per `app`.)

| Pezzo | Cosa fa |
|---|---|
| `spedisci` | **sidecar nativo**: è fra gli `initContainers` ma con `restartPolicy: Always`. Crea il file e lo segue con `tail -F` (la `-F` riapre il file se sparisce o viene ruotato) |
| `app` | `traefik/whoami` sulla porta 80: risponde con informazioni sulla richiesta. È **FROM scratch**: niente shell, niente `tail`. Il sidecar porta gli strumenti, l'app resta minima |
| `cliente` | ogni 5 s chiama `localhost:80` (**stessa rete** del Pod) e appende la prima riga della risposta in `/log/accessi` |
| `emptyDir` `log` | il volume condiviso, montato in `/log` da tutti e tre: vive e muore con il Pod |

Il trucco `trap 'exit 0' TERM; … & wait`: il comando va in **background** e la shell fa `wait`. Così, quando arriva
SIGTERM, la shell lo riceve subito, esegue il `trap` ed esce con 0. Se il ciclo fosse in primo piano, la shell
aspetterebbe la fine del comando corrente prima di gestire il segnale.

### 3) Job `lavoro`: un Job con sidecar

```yaml
apiVersion: batch/v1
kind: Job
metadata: { name: lavoro, namespace: lab-pod }
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      terminationGracePeriodSeconds: 5
      initContainers:
        - name: battito
          image: busybox:1.37
          restartPolicy: Always
          command: ["sh", "-c", "trap 'exit 0' TERM; while true; do date; sleep 1; done & wait"]
      containers:
        - name: calcola
          image: busybox:1.37
          command: ["sh", "-c", "echo calcolo; sleep 10; echo finito"]
```

| Campo | Perché |
|---|---|
| `backoffLimit: 0` | al primo fallimento il Job è Failed, nessun nuovo tentativo |
| `restartPolicy: Never` | il container `calcola` non riparte |
| `terminationGracePeriodSeconds: 5` | grazia ridotta: se il sidecar non uscisse da solo, verrebbe ucciso dopo 5 s invece di 30 |
| `battito` | sidecar in loop **infinito** (stampa la data ogni secondo) |
| `calcola` | il lavoro vero: 10 s e finisce |

Prima della 1.28 questo Job **non finiva mai**: il loop di `battito` teneva il Pod Running. Con il sidecar nativo, quando
`calcola` esce il kubelet spegne `battito` e il Job va a **Complete**.

---

## 3. Il runner, passo per passo

| # | Passo | Cosa vedi |
|---|---|---|
| — | `guardia_lab` | lo script si ferma se il contesto non è `lab` |
| 1 | `kubectl explain pod.spec.initContainers.restartPolicy \| sed -n "1,14p"` | il sidecar nativo è **un campo dello schema** |
| 2 | `kubectl apply -f $F` | namespace, `ciclo`, `web-log`, `lavoro` |
| 3 | `sleep 5; get pod ciclo; logs ciclo -c attendi-db --tail=3` | `ciclo` fermo in **Init:0/1**; nei log dell'init le righe `aspetto db-finto` |
| 4 | `create service clusterip db-finto --tcp=5432:5432 && wait --for=condition=Ready pod/ciclo && logs ciclo -c app` | creato il Service, l'init lo trova, esce con 0 e **solo allora** parte l'app: `dipendenza trovata, parto` |
| 5 | `wait … pod/web-log; get pod web-log; jsonpath su initContainerStatuses` | **READY 3/3**: conta anche il sidecar. È elencato fra gli init, ma `spedisci: started=true ready=true` |
| 6 | `sleep 6; logs web-log -c spedisci --tail=3` | il sidecar stampa il file che `cliente` scrive nell'emptyDir |
| 7 | `exec web-log -c spedisci -- wget -qO- localhost:80 \| head -3` | dal sidecar raggiungi l'app su localhost, anche se l'app non ha shell |
| 8 | `exec … -c spedisci -- hostname; exec … -c cliente -- hostname` | lo stesso hostname, `web-log`, per tutti i container |
| 9 | `exec … -c cliente -- touch /tmp/solo-qui; exec … -c spedisci -- ls /tmp/solo-qui` | **fallisce apposta (uscita 1)**: il file scritto in `/tmp` fuori dal volume nel sidecar non c'è. Il filesystem **non** è condiviso |
| 10 | `wait --for=condition=Complete job/lavoro; get job; jsonpath fase e stato del sidecar` | il Job arriva a **Complete** nonostante il loop infinito; il Pod è `Succeeded`, il sidecar `terminated` |
| — | `nota` | con `trap 'exit 0' TERM` il sidecar esce pulito (**Completed/0**). Senza trap, misurato: **Error/137** dopo i 30 s di grazia, Pod comunque Succeeded |
| 11 | `patch pod ciclo` con `image: busybox:1.36` + eventi `reason=Killing` | cambiare l'immagine **è permesso**: l'evento `Killing` con il messaggio "definition changed" |
| 12 | ciclo che aspetta `containerStatuses[0].image = busybox:1.36`, poi `immagine=… riavvii=…` | il riavvio arriva solo dopo **~30 s**: il PID 1 è `sh` (`sleep 3600` senza trap), ignora SIGTERM, il kubelet aspetta la grazia prima del SIGKILL. `restartCount` sale a 1 |
| 13 | `patch pod web-log` con `containerPort: 81` | **fallisce apposta (uscita 1)**: `Forbidden`, con l'elenco dei pochi campi modificabili. Il passo finisce con `false` per rendere visibile l'errore anche dopo `head -c 400` |
| 14 | `kubectl -n lab-pod run cade --image=busybox:1.37 -- sh -c "echo muoio; exit 1"`, poi attesa di CrashLoopBackOff | STATUS alterna **Error** e **CrashLoopBackOff**, ma `fase=Running`, con `riavvii` che sale. `kubectl run` crea un Pod con `restartPolicy: Always` |
| 15 | `kubectl -n lab-pod logs cade --previous` | `muoio`: l'uscita dell'istanza **caduta**. Va letto durante il backoff: nell'attimo del riavvio non c'è ancora |
| 16 | `kubectl delete ns lab-pod` | pulizia: il namespace porta via tutto |

Il passo 12 usa un ciclo `for i in $(seq 20)` con `sleep 3` (fino a 60 s) invece di un `sleep` fisso: aspetta la
condizione, non un tempo indovinato.

---

## 4. Trappole

- **`nslookup` di busybox senza search domain**: usa il nome completo `<svc>.<ns>.svc.cluster.local` nell'init, o
  sembrerà che il Service non esista mai.
- **Sidecar come container normale in un Job**: il Job resta Running per sempre. Va dichiarato fra gli
  `initContainers` con `restartPolicy: Always`.
- **`sh -c` come PID 1 senza `trap`**: ignora SIGTERM, ogni stop costa tutta la grazia e finisce a 137.
- **Credere che i container vedano i file l'uno dell'altro**: si passa solo da un volume.
- **Modificare un Pod a mano**: quasi tutto è Forbidden; e un Pod senza controller non rinasce se il nodo muore.
- **Leggere STATUS come se fosse la fase**: `CrashLoopBackOff` è fase Running.
- **`logs` senza `--previous`** su un container che crasha: vedi l'istanza nuova, non quella caduta.
- **"Static Pod"** non vuol dire "Pod senza controller".

---

## 5. Comandi e domande da colloquio

### Comandi (dalla sezione LAB del file)

| Comando | A cosa serve |
|---|---|
| `kubectl -n lab-pod get pod ciclo -w` | segui `Init:0/1` → Running |
| `kubectl -n lab-pod create service clusterip db-finto --tcp=5432:5432` | crea la dipendenza che l'init aspetta |
| `kubectl -n lab-pod logs web-log -c spedisci` | log di **un** container del Pod (`-c`) |
| `kubectl -n lab-pod exec web-log -c spedisci -- wget -qO- localhost:80` | entrare nel container che ha gli strumenti |
| `kubectl -n lab-pod get job lavoro` | Complete anche col sidecar acceso |
| `kubectl -n lab-pod patch pod web-log -p '{"spec":{"containers":[{"name":"app","ports":[{"containerPort":81}]}]}}'` | Forbidden: il Pod è immutabile |
| `kubectl logs <pod> --previous` | l'uscita del container prima del crash |

### Domande

- **Differenza fra init container e sidecar?** L'init gira prima dell'app, uno alla volta, e deve finire con 0. Il
  sidecar nativo è un init con `restartPolicy: Always`: parte prima dell'app, resta acceso per tutta la vita del Pod,
  si spegne dopo.
- **Il mio Job resta Running anche se il lavoro è finito. Perché?** Quasi sempre un sidecar dichiarato come container
  normale (proxy di una service mesh, agente di log): il Pod finisce solo quando finiscono tutti i container. Dalla 1.29
  lo si dichiara come sidecar nativo.
- **Due container dello stesso Pod come comunicano?** Su localhost (stessa rete) o tramite un volume condiviso
  (emptyDir). Non vedono il filesystem l'uno dell'altro.
- **Il Pod è Running ma STATUS dice CrashLoopBackOff. Contraddizione?** No: la fase è Running, un container riparte con
  backoff esponenziale. `kubectl logs --previous` mostra l'uscita dell'istanza caduta.
- **Posso cambiare le porte di un Pod in esecuzione?** No, il Pod è quasi immutabile (si cambia l'immagine, poco altro).
  Si cambia il template del controller e si fa un rollout.

---

## Riepilogo

- Pod = host logico: stesso nodo, IP, porte, hostname e volumi.
- init: in ordine, fino a exit 0 · sidecar nativo: init con `restartPolicy: Always`.
- Il sidecar nativo non blocca i Job; senza `trap` su TERM muore a 137 dopo la grazia.
- Fase (5 valori) ≠ STATUS di kubectl (`CrashLoopBackOff`, `Init:0/1`…).
- Pod quasi immutabile: si cambia il template, non il Pod.

## Prova da solo

1. Aggiungi a `ciclo` un **secondo** init container che aspetta un altro Service (`db-due`) e riapplica (dopo aver
   cancellato il Pod): che STATUS vedi prima e dopo aver creato `db-finto`? E dopo `db-due`?
2. Togli `trap 'exit 0' TERM;` dal comando di `battito` nel Job (cambia anche il nome del Job) e riapplica: con
   `terminationGracePeriodSeconds: 5`, che `reason`/`exitCode` ha il sidecar alla fine, e dopo quanto il Job è Complete?
3. Crea con `kubectl run` un Pod con `--restart=Never` che fa `exit 1`: che fase e che STATUS mostra? Confrontalo con
   `cade` del passo 14.
