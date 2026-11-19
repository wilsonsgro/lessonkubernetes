# 08 — Troubleshooting: cinque guasti da riconoscere al primo sguardo

Spiegazione di `08-troubleshooting.sh` (questa cartella). Lezione sul sito: http://127.0.0.1:3000/kubernetes/8

## In una frase

Lo script **rompe apposta cinque workload** nel namespace `rotto` (immagine inesistente, processo che crasha, memoria
oltre il limite, CPU che nessun nodo ha, Service che non seleziona niente) e poi li **diagnostica con un metodo** in
cinque tappe: stato → eventi → log → dentro → intorno. Alla fine usa `kubectl debug` per entrare in un Pod la cui
immagine non ha nemmeno una shell.

## Due file con lo stesso nome: quale lanciare

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/lezioni/kubernetes/08-troubleshooting.sh` | **questo**: la lezione, con le spiegazioni nei commenti | `bash 08-troubleshooting.sh rompi` · `diagnosi` · `pulisci` |
| `~/kubernetesprj/kubernetes/08-troubleshooting.sh` | lo script **guidato**: rompe e diagnostica con gli stessi comandi, uno per volta, spiegando prima di eseguire (Invio / s / q) | `bash kubernetes/08-troubleshooting.sh` |

Il gioco proposto dal file: **dopo `rompi`, prima indovina tu la causa** di ogni guasto, poi lancia `diagnosi`.

```bash
bash 08-troubleshooting.sh rompi
kubectl -n rotto get pod -w          # aspetta ~1 minuto
bash 08-troubleshooting.sh diagnosi
bash 08-troubleshooting.sh pulisci
```

## Com'è fatto il file

```
intestazione (commenti)  → il metodo in 5 tappe, la tabella STATUS → dove guardare, NEL PROGETTO VERO
set -euo pipefail        → lo script si ferma al primo errore
NS=rotto                 → il namespace usa-e-getta
guardia_contesto()       → controlla che kubectl punti a "lab" (o a $CONTESTO_LAB)
rompi()                  → crea i cinque guasti
diagnosi()               → li esamina in 6 blocchi
pulisci()                → cancella il namespace
case "$1"                → rompi | diagnosi | pulisci
coda (commenti)          → altri attrezzi, domande da colloquio, riepilogo
```

L'intestazione dichiara Kubernetes 1.35 / kubectl 1.35 (il lab delle altre lezioni gira la 1.34.0).

---

## 1. La teoria nell'intestazione

### Un metodo, non un elenco di comandi

Al colloquio la domanda tipica è "il Pod non parte, cosa fai?". Convince **un metodo**:

| Tappa | Comando | Chi parla |
|---|---|---|
| 1. **STATO** | `kubectl get pod -o wide` | STATUS, RESTARTS, NODE |
| 2. **EVENTI** | `kubectl describe pod` / `get events` | scheduler, kubelet |
| 3. **LOG** | `kubectl logs [--previous]` | l'app |
| 4. **DENTRO** | `kubectl exec` / `kubectl debug` | rete, file, processi |
| 5. **INTORNO** | Service, EndpointSlice, NetworkPolicy, nodo, quota | il resto del cluster |

### STATUS → dove guardare

| STATUS | Chi è in difficoltà / causa tipica | Dove guardi |
|---|---|---|
| `Pending` | **scheduler**: risorse, taint, affinity, PVC | `describe` |
| `ContainerCreating` | **kubelet**: volume, secret mancante, CNI | `describe` |
| `ImagePullBackOff` | nome/tag sbagliato, registry privato senza `imagePullSecrets`, rate limit di Docker Hub | `describe` |
| `CrashLoopBackOff` | il **processo esce**: config, permessi, comando | `logs` |
| `OOMKilled` (137) | limite di memoria superato | `lastState` / `state.terminated` |
| `Running` ma `0/1` | readiness che fallisce | `describe` |
| `Running 1/1` ma niente traffico | Service / selector / porta / policy | `endpointslices` |

È lo schema da imparare a memoria: la colonna STATUS ti dice **già** in quale componente cercare.

### Riquadro «NEL PROGETTO VERO»: guasti veri

In `~/biodistretto/kubernetes`, quattro guasti incontrati costruendolo:

1. **Due CNI accesi.** Il provider minikube lascia attivo `87-podman-bridge.conflist` accanto a kindnet. I Pod prendono
   IP doppi, il plugin CSI va in CrashLoop con «no route to host» verso `10.96.0.1` (l'apiserver) e i PVC restano
   Pending. Si guarda **sul nodo**:
   ```bash
   minikube -p biodistretto ssh -n biodistretto-m02 -- ls /etc/cni/net.d
   grep -n -A3 '87-podman-bridge' ansible/roles/cluster/tasks/main.yml
   ```
2. **Pod che non finiscono mai di cancellarsi** su quella rete rotta: servono `--grace-period=0 --force`, e solo sui
   Pod di `kube-system`.
   ```bash
   grep -n 'grace-period=0' ansible/roles/cluster/tasks/main.yml
   ```
3. **`kubectl cp` con rc 127**: `kubectl cp` usa `tar` dentro il container, e l'immagine MinIO non ce l'ha (127 =
   comando non trovato). Ripiego: port-forward e `mc mirror`.
   ```bash
   grep -n 'port-forward' ansible/roles/dati/tasks/media.yml
   ```
4. **Dopo un riavvio del PC l'API non risponde**: i container dei nodi ripartono, ma kubelet e cri-docker no. Serve
   `minikube start`, ed è per questo che c'è un `@reboot` nel crontab:
   ```bash
   grep -n -B2 -A3 'special_time: reboot' ansible/roles/cluster/tasks/main.yml
   ```

---

## 2. `guardia_contesto()`

```bash
attuale="$(kubectl config current-context)"
[[ "$attuale" == "lab" || "${CONTESTO_LAB:-}" == "$attuale" ]] || {
  echo "STOP: contesto '$attuale' (atteso 'lab')" >&2; exit 1; }
```

Come nella lezione 01, ma con una via d'uscita: se esporti `CONTESTO_LAB=<nome>`, lo script accetta anche quel
contesto (utile per provarlo su un altro cluster di prova). Senza, accetta solo `lab`. Ogni funzione la chiama per prima.

---

## 3. `rompi` — i cinque guasti

Prima crea il namespace in modo **idempotente**:

```bash
kubectl create namespace $NS --dry-run=client -o yaml | kubectl apply -f -
```

`create --dry-run=client -o yaml` **genera** il manifest senza inviarlo; `apply` lo crea o lo lascia com'è. Un
`kubectl create namespace` diretto fallirebbe la seconda volta (già esistente) e con `set -e` fermerebbe lo script.

### Guasto 1 — `immagine`: ImagePullBackOff

```bash
kubectl -n $NS create deployment immagine --image=traefik/whoami:v9.9.9
```

Il tag `v9.9.9` non esiste. Il kubelet prova a scaricarlo, fallisce (`ErrImagePull`), poi riprova con attese sempre più
lunghe: `ImagePullBackOff`.

### Guasto 2 — `crash`: CrashLoopBackOff

```bash
kubectl -n $NS create deployment crash --image=busybox:1.37 \
  -- sh -c 'echo "manca DATABASE_URL" >&2; exit 1'
```

Il processo scrive un errore su stderr ed esce con 1. Il Deployment lo fa ripartire, lui muore di nuovo: il kubelet
allunga l'attesa fra un tentativo e l'altro (back-off) e lo stato diventa `CrashLoopBackOff`. Simula l'app a cui manca
una variabile di configurazione.

### Guasto 3 — `memoria`: OOMKilled

```yaml
kind: Pod
metadata: { name: memoria }
spec:
  restartPolicy: Never
  containers:
    - name: app
      image: busybox:1.37
      command: ["sh", "-c", "head -c 100m /dev/zero | tail > /dev/null"]
      resources:
        limits: { memory: 20Mi }
```

- `head -c 100m /dev/zero` produce 100 MB di zeri; `tail` deve tenere in memoria l'**ultima riga**, e poiché negli zeri
  non c'è mai un a capo, l'"ultima riga" è tutto il flusso: la memoria cresce fino a sfondare il limite di **20Mi**.
- Il kernel uccide il processo (SIGKILL): reason **`OOMKilled`**, exit code **137** (128 + 9).
- `restartPolicy: Never`: è un Pod nudo e non viene riavviato, così lo stato di morte resta in
  `state.terminated` e lo si legge facilmente.

### Guasto 4 — `enorme`: Pending

```yaml
kind: Pod
metadata: { name: enorme }
spec:
  containers:
    - name: app
      image: busybox:1.37
      command: ["sleep", "3600"]
      resources:
        requests: { cpu: "64" }
```

Chiede **64 CPU**. Nessun nodo del lab ha tanto, nemmeno considerando che il kubelet dichiara come capacità tutto il PC
(lezione 01): lo scheduler non trova posto, il Pod resta **Pending** con l'evento `FailedScheduling` "Insufficient cpu".
Nessun container parte, quindi non ci sono log.

### Guasto 5 — `eco`: Service senza endpoint

```bash
kubectl -n $NS create deployment eco --image=traefik/whoami:v1.12
kubectl -n $NS create service clusterip eco --tcp=80:80 --dry-run=client -o yaml \
  | sed 's/app: eco/app: ecco/' | kubectl apply -f -
```

- `create deployment eco` mette ai Pod la label **`app: eco`**; il container si chiama `whoami` (kubectl lo ricava dal
  nome dell'immagine) e whoami, senza `--port`, ascolta sulla 80.
- `create service … --dry-run=client -o yaml` genera un Service con selector `app: eco`; `sed` lo cambia in
  **`app: ecco`** prima dell'apply.
- Risultato: tutti i Pod sono `Running 1/1`, ma il Service **non seleziona nessuno**. È il guasto più subdolo: niente
  è rosso in `get pod`.

---

## 4. `diagnosi` — il metodo applicato

### 1. STATO

```bash
kubectl -n $NS get pod -o wide
```

| Pod | STATUS atteso |
|---|---|
| `immagine-…` | `ImagePullBackOff` (o `ErrImagePull`) |
| `crash-…` | `CrashLoopBackOff` (RESTARTS che sale) |
| `memoria` | `OOMKilled` |
| `enorme` | `Pending`, colonna NODE vuota |
| `eco-…` | `Running 1/1` — il guasto qui non si vede |

### 2. EVENTI

```bash
kubectl -n $NS get events --field-selector type=Warning \
  --sort-by=.lastTimestamp -o custom-columns=OGGETTO:.involvedObject.name,MOTIVO:.reason,MESSAGGIO:.message \
  | cut -c1-160
```

- `--field-selector type=Warning`: solo gli avvisi, niente rumore dei `Normal`.
- `--sort-by=.lastTimestamp`: i più recenti **in fondo**.
- `custom-columns`: tre colonne (oggetto, motivo, messaggio); `cut -c1-160` taglia le righe lunghe.

Vedi i motivi esatti: `Failed` (pull dell'immagine), `BackOff`, `FailedScheduling` (Insufficient cpu).

### 3. LOG del container crashato

```bash
kubectl -n $NS logs deploy/crash --tail=5
kubectl -n $NS logs deploy/crash --previous --tail=5; echo
```

Il commento del file corregge un luogo comune: **durante il back-off il container "attuale" è già quello morto**, quindi
i suoi log sono già l'errore (`manca DATABASE_URL`). `--previous` è l'istanza **prima ancora**, se il runtime la
conserva; altrimenti stampa "unable to retrieve" **ed esce con 0** (provato su k3s). Quindi un `|| ripiego` dopo
`--previous` non scatterebbe mai. `logs deploy/crash` sceglie da solo un Pod del Deployment.

### 4. Perché è morto `memoria`

```bash
kubectl -n $NS get pod memoria \
  -o jsonpath='{.status.containerStatuses[0].state.terminated.reason} exit={.status.containerStatuses[0].state.terminated.exitCode}{"\n"}'
```

Stampa `OOMKilled exit=137`. Qui si legge `state.terminated` (il Pod non ripartirà); per un container che è ripartito
si guarderebbe `lastState.terminated`.

### 5. Il Service `eco` ha endpoint?

```bash
kubectl -n $NS get endpointslices -l kubernetes.io/service-name=eco
kubectl -n $NS get svc eco -o jsonpath='selector={.spec.selector}{"\n"}'
kubectl -n $NS get pod -l app=eco --show-labels
```

L'EndpointSlice **non ha indirizzi**; il selector dice `{"app":"ecco"}`; i Pod hanno `app=eco`. Il confronto delle due
righe è la diagnosi. (Lezione 03: "Service muto, prima gli EndpointSlice".)

### 6. Debug in un Pod senza shell

```bash
pod="$(kubectl -n $NS get pod -l app=eco -o name | head -1)"
kubectl -n $NS debug "$pod" -i --profile=general --image=busybox:1.37 --target=whoami -- \
  sh -c 'ps; wget -qO- localhost/api | head -c 80; echo' || true
```

L'immagine whoami è **FROM scratch**: niente `sh`, niente `ps`, `kubectl exec` non ha niente da eseguire.
`kubectl debug` aggiunge al Pod un **container effimero** (qui busybox):

| Opzione | Perché |
|---|---|
| `--image=busybox:1.37` | gli attrezzi che l'app non ha |
| `--target=whoami` | condivide il **namespace dei processi** del container `whoami`: `ps` mostra il processo dell'app |
| `--profile=general` | il profilo di permessi del container di debug |
| `-i` | serve per **vedere l'output**: senza, il comando gira e non stampa |
| `wget -qO- localhost/api` | il container effimero condivide anche la **rete** del Pod: `localhost` è whoami (porta 80). `head -c 80` tiene i primi 80 caratteri |
| `\|\| true` | con `set -e`, un fallimento del debug non deve fermare lo script |

Il container effimero resta nella spec del Pod (non si può togliere): sparisce solo ricreando il Pod.

---

## 5. `pulisci`

```bash
kubectl delete namespace $NS --wait=false
```

Cancella il namespace e **tutto ciò che contiene**. `--wait=false` restituisce subito il prompt; il namespace resta
`Terminating` ancora per un po'.

---

## 6. Il runner, passo per passo

Il runner (`~/kubernetesprj/kubernetes/08-troubleshooting.sh`) fa `guardia_lab` e poi **gli stessi comandi**, in 16 passi:

| # | Cosa | Note |
|---|---|---|
| 1 | namespace `rotto` (dry-run \| apply) | idempotente |
| 2 | guasto 1 `immagine` | tag `v9.9.9` |
| 3 | guasto 2 `crash` | |
| 4 | guasto 3 `memoria` | "alloca 100 MB con un limite di 20 MiB" |
| 5 | guasto 4 `enorme` | 64 CPU |
| 6 | guasto 5 `eco` + Service con `app: ecco` | creati con `&&`: il Service solo se il Deployment è nato |
| 7 | `sleep 30` | il tempo perché i guasti si manifestino |
| 8 | METODO 1 — `get pod -o wide` | la colonna STATUS dice già il tipo di guasto |
| 9 | METODO 2 — eventi Warning | Failed pull, BackOff, FailedScheduling… |
| 10 | METODO 3 — `logs deploy/crash --tail=5; logs … --previous --tail=5` | qui **senza** l'`echo` finale della lezione |
| 11 | jsonpath di `memoria` | `OOMKilled exit=137` (128 + SIGKILL 9) |
| 12 | `describe pod enorme \| tail -5` | gli eventi in fondo: `FailedScheduling … Insufficient cpu` |
| 13 | EndpointSlice di `eco` | vuoto… |
| 14 | selector del Service + label dei Pod | …perché `ecco` ≠ `eco` |
| 15 | `kubectl debug … --target=whoami` | qui **senza** `\|\| true`: se fallisce, `passo` mostra la riga rossa |
| 16 | `kubectl delete namespace rotto --wait=false` | pulizia |

Il passo 12 non è nella `diagnosi` della lezione: il runner aggiunge il `describe` del Pod Pending.

**Tutti i guasti sono voluti**: i passi 2-6 riescono (gli oggetti vengono creati), è il loro **stato** a essere rotto.
La riga rossa "uscita ≠ 0" può comparire al passo 10 se `--previous` non trova l'istanza precedente (secondo la
lezione su k3s esce 0; su altri runtime il codice può essere diverso).

Se rilanci il runner subito dopo la pulizia, il namespace può essere ancora `Terminating` e le creazioni falliscono:
aspetta che `kubectl get ns rotto` dica `NotFound`.

---

## 7. Altri attrezzi (coda del file)

| Comando | A cosa serve |
|---|---|
| `kubectl debug node/lab-m02 -it --image=busybox:1.37` | shell **sul nodo** (il filesystem del nodo è in `/host`) |
| `kubectl top pod --containers -n X` | CPU/memoria reali per container |
| `kubectl get pod X -o yaml \| grep -A5 lastState` | l'ultima morte |
| `kubectl events -n X --for pod/Y` | gli eventi di un solo oggetto |
| `kubectl get --raw /api/v1/nodes/N/proxy/stats/summary` | metriche del kubelet |
| `journalctl -u kubelet` | log del kubelet, sul nodo |
| `crictl ps -a` / `crictl logs` | il runtime, sotto kubectl |

**Gli eventi durano 1 ora**: per lo storico servono log e metriche (lezione 13).

---

## 8. Le trappole

| Trappola | Cosa succede | Rimedio |
|---|---|---|
| `get pod` tutto verde e "funziona" | il Service può non avere endpoint | guardare gli EndpointSlice |
| fidarsi di `logs --previous \|\| ripiego` | `--previous` può uscire 0 anche senza log | in back-off basta `logs` |
| cercare i log di un Pod Pending | il container non è mai partito | `describe` → eventi dello scheduler |
| `kubectl exec` su un'immagine scratch | niente shell da eseguire | `kubectl debug --target` |
| `kubectl debug` senza `-i` | il comando gira ma non vedi l'output | `-i` |
| `kubectl cp` su immagini senza `tar` | rc 127 | port-forward + client dedicato |
| cercare eventi vecchi | dopo 1 ora non ci sono più | log e metriche centralizzati |
| `create namespace` diretto in uno script | la seconda volta fallisce | `--dry-run=client -o yaml \| kubectl apply -f -` |

---

## 9. La coda: domande da colloquio

- **CrashLoopBackOff ma `kubectl logs` è vuoto.** Prova `--previous`; se è vuoto anche quello, il processo muore
  **prima di scrivere**: comando o entrypoint sbagliato, binario per un'altra architettura (`exec format error`),
  permessi sul file, `readOnlyRootFilesystem` che impedisce di scrivere. `describe` mostra exit code e reason.
- **L'app risponde da dentro il Pod ma non dal Service.** EndpointSlice vuoti (selector o readiness), `targetPort`
  sbagliata, l'app ascolta su `127.0.0.1` invece di `0.0.0.0`, NetworkPolicy.
- **Il nodo è NotReady.** kubelet fermo, disco pieno (DiskPressure), memoria, CNI rotto, certificati scaduti.
  `describe node` → Conditions; sul nodo `journalctl -u kubelet`.

---

## Riepilogo

- Metodo: **stato → eventi → log → dentro → intorno**.
- **Pending = scheduler**; **ImagePull/ContainerCreating = kubelet**; **Crash = app**.
- In back-off `logs` mostra **già** l'istanza morta; **exit 137 = OOM o SIGKILL**.
- **Service muto: prima gli EndpointSlice**.
- **`kubectl debug`** per immagini senza shell e per i nodi.

## Prova da solo

1. Prima di lanciare `diagnosi`, scrivi su un foglio la causa e la tappa del metodo che la rivela per ognuno dei cinque
   guasti. Poi lancia `diagnosi` e confronta: quale guasto non avresti visto con il solo `get pod`?
2. Ripara il Service `eco` senza ricrearlo: `kubectl -n rotto patch svc eco -p '{"spec":{"selector":{"app":"eco"}}}'`,
   poi ricontrolla gli EndpointSlice e chiamalo da un Pod busybox (`wget -qO- eco/api`).
3. Ripara `memoria`: portala a un limite che basti (il Pod è immutabile nelle risorse: va cancellato e ricreato) e
   guarda che stato finale ottiene. Poi prova `kubectl debug node/lab-m02 -it --image=busybox:1.37` e cerca
   `/host/etc/cni/net.d`: quanti file di configurazione CNI ci sono?
