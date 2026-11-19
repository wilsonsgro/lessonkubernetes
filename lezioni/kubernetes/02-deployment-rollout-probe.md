# 02 — Deployment: rolling update, probe, risorse e shutdown pulito

Spiegazione di `02-deployment-rollout-probe.yaml` (questa cartella). Lezione sul sito: http://127.0.0.1:3000/kubernetes/2

## In una frase

Il file crea il Namespace `lab` e un **Deployment `web`** con 3 repliche di `traefik/whoami`, configurato per
aggiornarsi **senza togliere capacità**: rolling update con `maxSurge 1` / `maxUnavailable 0`, tre probe
(startup, readiness, liveness), requests/limits, un `preStop` che ritarda lo spegnimento e un `securityContext`
restrittivo. Il runner lo applica, fa un rolling update, lo annota, guarda la storia e torna indietro con un rollback.

## Due file con lo stesso nome: quale lanciare

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/lezioni/kubernetes/02-deployment-rollout-probe.yaml` | **questo**: il manifest, con la teoria nei commenti | si **legge**; lo applica il runner (o a mano: `kubectl apply -f 02-deployment-rollout-probe.yaml`) |
| `~/kubernetesprj/kubernetes/02-deployment-rollout-probe.sh` | lo script **guidato**: applica il manifest e fa rollout, history, undo, uno per volta spiegando prima di eseguire (Invio / s / q) | `bash kubernetes/02-deployment-rollout-probe.sh` |

Un `.yaml` non si "lancia": si applica. Per imparare usa lo **guidato** e tieni aperto questo file accanto.

## Com'è fatto il file

```
intestazione (commenti)  → teoria: Deployment → ReplicaSet, i 3 ingredienti dello zero-downtime, comandi LAB,
                           riquadro NEL PROGETTO VERO
Namespace lab            → lo spazio dove vivono gli oggetti di tutte le lezioni
Deployment web           → il workload: strategia, risorse, probe, preStop, securityContext
coda (commenti)          → domande da colloquio, riepilogo
```

Versione indicata nell'intestazione: Kubernetes 1.34–1.35 (il lab minikube gira la **1.34.0**), API `apps/v1`.

---

## 1. La teoria nell'intestazione

### Un Deployment gestisce ReplicaSet, non Pod

```
Deployment web ──crea──▶ ReplicaSet (uno per ogni versione del template) ──crea──▶ Pod
```

- Ogni modifica al **pod template** (immagine, env, annotazioni *del template*) crea un **ReplicaSet nuovo**.
- Il **rollout** sposta repliche dal ReplicaSet vecchio al nuovo, rispettando `maxSurge` e `maxUnavailable`.
- I ReplicaSet vecchi **non vengono cancellati**: restano a 0 repliche. Sono la **storia** che usa
  `kubectl rollout undo`.

Cambiare invece qualcosa **fuori** dal template (per esempio `replicas`) non crea un ReplicaSet nuovo: scala quello
esistente.

### Zero-downtime non è automatico

Servono **tre cose insieme**:

| Ingrediente | Cosa garantisce |
|---|---|
| `readinessProbe` | il Pod nuovo riceve traffico solo quando è pronto |
| `maxUnavailable: 0` | non togli capacità prima di averne aggiunta |
| shutdown pulito (`preStop` + `terminationGracePeriodSeconds`) | il Pod vecchio smette di ricevere traffico **prima** di morire |

Ne manca una e durante un rollout qualche richiesta va persa.

### I comandi LAB dell'intestazione

```bash
kubectl config current-context                    # deve dire "lab"
kubectl apply -f 02-deployment-rollout-probe.yaml
kubectl -n lab rollout status deploy/web
kubectl -n lab set image deploy/web web=traefik/whoami:v1.11
kubectl -n lab annotate deploy/web kubernetes.io/change-cause="whoami v1.11" --overwrite
kubectl -n lab rollout history deploy/web
kubectl -n lab rollout undo deploy/web --to-revision=1
kubectl -n lab get rs -o wide                     # i ReplicaSet della storia
kubectl -n lab get pod -o custom-columns=NOME:.metadata.name,QOS:.status.qosClass
```

Il commento sotto `rollout history` riporta un fatto **provato**: senza l'`annotate`, anche la revisione 2 dice
"prima versione". `change-cause` si copia dal Deployment al ReplicaSet a ogni rollout, quindi se non la cambi
ti porti dietro quella vecchia.

### Riquadro «NEL PROGETTO VERO»

In `~/biodistretto/kubernetes` (branch `kubernetes`; come si usa: il README della cartella) backend, frontend e nginx
sono Deployment con `replicas: ${repliche}` (una variabile del template Terraform). Le probe cambiano secondo il
processo:

- **php-fpm non parla HTTP** → probe `tcpSocket` sulla porta **9000** (controlla solo che la porta accetti connessioni);
- **nginx** ha una porta dedicata solo alla salute: **8081**, con `path: /healthz`.

```bash
grep -n -B1 -A2 'tcpSocket' terraform/app/manifests/app.yaml.tftpl
grep -n -A3 'path: /healthz' terraform/app/manifests/app.yaml.tftpl
```

Risorse: `requests` su tutti, e `limits` **solo sulla memoria** (niente CPU throttling, come qui). Terraform aspetta la
fine del rollout prima di proseguire:

```bash
grep -n 'rollout =' terraform/app/workload.tf
```

Il rollout lì parte da solo quando cambia la configurazione: lo vedrai nella lezione 04.

---

## 2. Il Namespace `lab`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: lab
```

Un Namespace è una "cartella" logica per gli oggetti. Tutte le lezioni lavorano in `lab`: per questo ogni comando ha
`-n lab`. Sta nello stesso file del Deployment e **viene prima** (separato da `---`): `kubectl apply` crea gli oggetti
nell'ordine del file, quindi il Namespace esiste quando arriva il Deployment.

---

## 3. Il Deployment `web` — campo per campo

### `metadata`

| Campo | Valore | Perché |
|---|---|---|
| `name` / `namespace` | `web` / `lab` | il nome usato in tutti i comandi: `deploy/web` |
| `labels` | `app.kubernetes.io/name: web` | label "raccomandata" di Kubernetes; la usano i selettori |
| `annotations` | `kubernetes.io/change-cause: "prima versione"` | testo che compare nella colonna CHANGE-CAUSE di `rollout history` |

### `spec` del Deployment

| Campo | Valore | Cosa fa |
|---|---|---|
| `replicas` | `3` | quante copie del Pod vuoi |
| `revisionHistoryLimit` | `5` | quanti ReplicaSet vecchi tenere per l'undo (oltre, i più vecchi vengono cancellati) |
| `progressDeadlineSeconds` | `120` | se il rollout non avanza per 120 s, la condition `Progressing` diventa `False`: `rollout status` esce con errore e **la CI fallisce** invece di restare appesa |
| `minReadySeconds` | `5` | un Pod deve essere pronto da 5 s prima di contare come "available": filtra i Pod che passano la readiness e poi crollano subito |
| `selector.matchLabels` | `app.kubernetes.io/name: web` | quali Pod appartengono al Deployment. **Immutabile dopo la creazione**: per cambiarlo devi cancellare e ricreare |
| `strategy.type` | `RollingUpdate` | sostituzione graduale. L'alternativa `Recreate` spegne tutto e poi riaccende (downtime, ma mai due versioni insieme) |
| `rollingUpdate.maxSurge` | `1` | durante il rollout al massimo **3+1 = 4** Pod |
| `rollingUpdate.maxUnavailable` | `0` | mai sotto **3** Pod pronti |

Con `maxSurge 1` e `maxUnavailable 0` il rollout procede così: sale **un** Pod nuovo, aspetta che sia pronto (e
available dopo 5 s), poi spegne **un** Pod vecchio; ripete tre volte.

La label del `template.metadata.labels` deve combaciare con il `selector`, altrimenti l'apiserver rifiuta il Deployment.

### Il container `web`

```yaml
terminationGracePeriodSeconds: 30
containers:
  - name: web
    image: traefik/whoami:v1.12
    args: ["--port", "8080"]
    ports:
      - name: http
        containerPort: 8080
```

- `traefik/whoami` è un server HTTP minuscolo che risponde con i dati della richiesta. L'immagine è **FROM scratch**:
  dentro non c'è una shell né `/bin/sleep` (conta per il `preStop`).
- `args: ["--port", "8080"]` lo fa ascoltare sulla 8080 (sopra la 1024: un utente non root può aprirla).
- La porta ha un **nome**, `http`: le probe la richiamano per nome (`port: http`) invece che per numero.
- `terminationGracePeriodSeconds: 30`: tempo massimo fra la richiesta di spegnimento e il SIGKILL.

### Risorse e QoS

```yaml
resources:
  requests:
    cpu: 50m
    memory: 32Mi
  limits:
    memory: 64Mi
```

| Concetto | Cosa vuol dire |
|---|---|
| `requests` | quanto usa lo **scheduler** per scegliere il nodo (riserva) |
| `limits` | tetto a runtime: CPU oltre il limite → **throttling**; memoria oltre il limite → **OOMKilled** (exit 137) |
| `50m` | 50 millicore = 5% di un core |

La **classe QoS** del Pod la calcola Kubernetes dalle risorse:

| QoS | Quando | Sotto pressione di memoria |
|---|---|---|
| **Guaranteed** | request = limit per CPU **e** memoria su tutti i container | sfrattato per ultimo |
| **Burstable** | almeno una request, ma non Guaranteed | in mezzo |
| **BestEffort** | nessuna request né limit | sfrattato per primo |

Qui i Pod sono **Burstable**: c'è una request di CPU senza limit di CPU, e la memoria ha request 32Mi ≠ limit 64Mi.
Il runner lo fa vedere apposta (passi 12 e 13).

Prassi diffusa, scritta nel file: **limit di memoria sì, limit di CPU spesso no**. Il throttling CFS rallenta il
processo anche quando il nodo ha CPU libera, e la latenza sale.

### Le tre probe

```yaml
startupProbe:
  httpGet: { path: /health, port: http }
  periodSeconds: 2
  failureThreshold: 30       # fino a 60 s per partire
readinessProbe:
  httpGet: { path: /health, port: http }
  periodSeconds: 5
  failureThreshold: 2
livenessProbe:
  httpGet: { path: /health, port: http }
  periodSeconds: 10
  failureThreshold: 3
```

| Probe | Se fallisce | Qui |
|---|---|---|
| **startup** | finché non passa, le altre due **non partono**; se esaurisce il budget, il container viene riavviato | budget = `failureThreshold × period` = 30 × 2 s = **60 s** per partire |
| **readiness** | il Pod **esce dagli EndpointSlice** (niente traffico), ma **non** viene riavviato | ogni 5 s; fuori dopo 2 fallimenti (~10 s) |
| **liveness** | il kubelet **riavvia** il container | ogni 10 s; riavvio dopo 3 fallimenti (~30 s) |

Tutte e tre fanno `GET /health` sulla porta `http`: risposta 2xx/3xx = successo.

**Errore classico** (dal file): una liveness che controlla il database. Il DB rallenta, tutte le liveness falliscono,
il kubelet riavvia tutti i Pod: hai trasformato un rallentamento in un'interruzione. La liveness controlla solo che
**il processo sia vivo**; le dipendenze, se proprio, le controlla la readiness.

### Shutdown pulito: `preStop`

```yaml
lifecycle:
  preStop:
    sleep:
      seconds: 5
```

Quando un Pod viene cancellato succedono **in parallelo** due cose:

1. il kubelet esegue il `preStop` e poi manda **SIGTERM** al processo;
2. il control plane toglie il Pod dagli **Endpoint**, e kube-proxy / l'ingress aggiornano le loro regole.

Il secondo è più lento: per qualche secondo arrivano ancora richieste a un processo che sta chiudendo → **502**.
Il `preStop` con `sleep: 5` **ritarda il SIGTERM di 5 s**, il tempo perché il Pod esca dagli Endpoint.

- È l'azione **nativa** `sleep` (beta dalla 1.30, stabile nella 1.34 del lab): non chiede `/bin/sleep`
  nell'immagine. Con whoami (FROM scratch) un `exec: ["sleep","5"]` fallirebbe.
- Il tempo del `preStop` **conta dentro** i 30 s di `terminationGracePeriodSeconds`.
- Riduce i 502, **non garantisce da sola** lo zero downtime.

### `securityContext` del container

| Campo | Valore | Perché |
|---|---|---|
| `allowPrivilegeEscalation` | `false` | il processo non può guadagnare privilegi (setuid ecc.) |
| `readOnlyRootFilesystem` | `true` | il filesystem del container è in sola lettura: un attaccante non scrive binari |
| `runAsNonRoot` | `true` | il kubelet rifiuta di avviare il container se girerebbe come root |
| `runAsUser` | `65532` | UID non privilegiato esplicito (serve perché un'immagine scratch non dichiara un utente) |
| `capabilities.drop` | `["ALL"]` | toglie tutte le capability Linux |

Questi campi sono esattamente quelli che chiede il profilo **restricted** di Pod Security (lezione 07).

---

## 4. Il runner, passo per passo

Il runner (`~/kubernetesprj/kubernetes/02-deployment-rollout-probe.sh`) chiama prima `guardia_lab` (si ferma se il
contesto non è `lab`), poi esegue 13 passi:

| # | Comando | Cosa vedi |
|---|---|---|
| 1 | `kubectl config current-context` | `lab` |
| 2 | `kubectl apply -f …/02-deployment-rollout-probe.yaml` | `namespace/lab created`, `deployment.apps/web created` (o `unchanged`/`configured` se c'era già: apply è dichiarativo) |
| 3 | `kubectl -n lab rollout status deploy/web` | attende finché le 3 repliche superano la readiness: `successfully rolled out` |
| 4 | `kubectl -n lab set image deploy/web web=traefik/whoami:v1.11` | cambia l'immagine del template → **revisione 2**, nuovo ReplicaSet |
| 5 | `rollout status` + `get deploy web -o wide` | il rolling update fino alla fine; la colonna IMAGES dice `v1.11` |
| 6 | `kubectl -n lab annotate deploy/web kubernetes.io/change-cause="whoami v1.11" --overwrite` | il motivo finisce nella CHANGE-CAUSE della revisione corrente |
| 7 | `kubectl -n lab rollout history deploy/web` | due revisioni: 1 "prima versione", 2 "whoami v1.11" |
| 8 | `rollout undo deploy/web --to-revision=1` + `rollout status` | il ReplicaSet vecchio torna in scala |
| 9 | `get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}'` | `traefik/whoami:v1.12`: il rollback è avvenuto |
| 10 | `get events --sort-by=.metadata.creationTimestamp \| grep -i scaling \| tail -8` | gli eventi `ScalingReplicaSet` su e giù: il racconto del rollout |
| 11 | `kubectl -n lab get rs -o wide` | un ReplicaSet con le repliche, gli altri a 0 |
| 12 | `get pod -o custom-columns=NOME:…,QOS:.status.qosClass` | `Burstable` per tutti e tre |
| 13 | `get deploy web -o jsonpath='{…resources}'` | `{"limits":{"memory":"64Mi"},"requests":{"cpu":"50m","memory":"32Mi"}}`: il motivo del Burstable |

Nessun passo fallisce apposta in questa lezione. La `nota` finale dice: **il Deployment resta acceso**, perché la
lezione 03 ci mette davanti Service, Ingress e NetworkPolicy.

Due cose da notare:

- Dopo l'**undo** la storia non "torna indietro": la revisione 1 viene **rinumerata** come nuova revisione (3), e la 1
  sparisce dalla history. Il ReplicaSet è lo stesso di prima.
- L'`annotate` del passo 6 è sul **Deployment**: per questo, come dice l'intestazione, senza di lui la revisione 2
  avrebbe ereditato "prima versione".

---

## 5. Le trappole

| Trappola | Cosa succede | Rimedio |
|---|---|---|
| liveness che controlla una dipendenza (DB) | un rallentamento del DB riavvia tutti i Pod | liveness = solo "il processo è vivo" |
| niente startupProbe con avvio lento | la liveness uccide il container prima che sia partito | startupProbe con budget sufficiente |
| `maxUnavailable` > 0 senza readiness | i Pod nuovi ricevono traffico prima di essere pronti | readiness + `maxUnavailable: 0` |
| `preStop` con `exec sleep` su immagine scratch | il comando non esiste, il preStop fallisce | azione nativa `sleep:` |
| cambiare il `selector` | l'apiserver rifiuta: è immutabile | cancellare e ricreare il Deployment |
| dimenticare `change-cause` | la history ripete la causa vecchia | `annotate … --overwrite` a ogni rollout |
| limit di CPU basso | throttling e latenza anche con CPU libera | spesso solo request di CPU |

---

## 6. La coda: domande da colloquio

- **Il rollout è bloccato a metà. Come lo diagnostichi?** `kubectl rollout status` (scade con
  `progressDeadlineSeconds`), `kubectl get rs` (il nuovo ha Pod non pronti), `describe pod` del nuovo:
  ImagePullBackOff, readiness che fallisce, Pending per risorse. Con `maxUnavailable 0` il vecchio continua a servire:
  niente outage. Poi `kubectl rollout undo`.
- **Perché cambiare un ConfigMap non riavvia i Pod?** Il ConfigMap non fa parte del pod template: il Deployment non vede
  differenze. Soluzioni: annotazione checksum nel template (Helm, lezione 09), `configMapGenerator` con suffisso hash
  (Kustomize, lezione 11), o `kubectl rollout restart`, che aggiunge un'annotazione `restartedAt` al template.
- **Exit code 137 vs 143?** 137 = 128+9 = **SIGKILL** (OOMKilled o grace period scaduto); 143 = 128+15 = **SIGTERM**
  gestito male. Il motivo: `kubectl get pod -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}'`
  → `OOMKilled` o `Error`.
- **Blue/green e canary con un Deployment nudo?** Blue/green: due Deployment, il Service cambia selector. Canary rozzo:
  due Deployment con la stessa label del Service e repliche in proporzione. Canary vero (per percentuale, con analisi
  delle metriche): Argo Rollouts, Flagger, o pesi su Ingress/Traefik (corso HAProxy & Traefik).

### Comandi da sapere

| Comando | A cosa serve |
|---|---|
| `kubectl -n lab rollout status deploy/web` | attende la fine del rollout (esce ≠0 oltre `progressDeadlineSeconds`) |
| `kubectl -n lab rollout history deploy/web` | le revisioni con CHANGE-CAUSE |
| `kubectl -n lab rollout undo deploy/web --to-revision=1` | rollback a una revisione |
| `kubectl -n lab rollout restart deploy/web` | ricrea i Pod senza cambiare l'immagine |
| `kubectl -n lab get rs -o wide` | i ReplicaSet (la storia) |
| `kubectl -n lab get pod -o custom-columns=NOME:.metadata.name,QOS:.status.qosClass` | la QoS di ogni Pod |

---

## Riepilogo

- Deployment → ReplicaSet → Pod; ogni cambio del **template** = nuovo ReplicaSet.
- Zero-downtime = **readiness** + **maxUnavailable 0** + **preStop/grace period**.
- **startup** protegge l'avvio, **readiness** toglie traffico, **liveness** riavvia.
- **requests** per lo scheduler, **limits** a runtime; la **QoS** decide gli sfratti.
- `rollout status / history / undo`; `progressDeadlineSeconds` per la CI.

## Prova da solo

1. Cambia l'immagine in un tag che non esiste (es. `traefik/whoami:v0.0.0`) con `set image`: guarda `get rs` e
   `rollout status`. Quanti Pod vecchi restano pronti? Dopo quanto `rollout status` si arrende? Poi `rollout undo`.
2. Porta `maxUnavailable` a `1` e `maxSurge` a `0`, rifai un `set image` e confronta con `get pod -w`: quanti Pod pronti
   ci sono al minimo durante il rollout?
3. Metti `limits.cpu: 50m` (uguale alla request) e `limits.memory: 32Mi` (uguale alla request), riapplica e rileggi la
   colonna QOS: che classe ottieni adesso, e perché?
