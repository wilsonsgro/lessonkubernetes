# 20 — L'API di Kubernetes, i CRD e il threat model (STRIDE)

Spiegazione di `20-api-crd-threat-model.yaml` (questa cartella). Lezione sul sito: http://127.0.0.1:3000/kubernetes/20

## In una frase

Tutto passa dall'apiserver: la lezione la tratta per quello che è, **un'API REST su HTTPS**, e la interroga con `curl`
attraverso `kubectl proxy` (codici 201, 409, 404, 401, 403). Poi la **estende** con un CRD (`Corso`, gruppo
`lab.esempio.it`) e infine la guarda da attaccante: le sei minacce **STRIDE**, misurate confrontando un Pod `normale` con
un Pod `blindato`.

## Due file con lo stesso nome: quale lanciare

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/lezioni/kubernetes/20-api-crd-threat-model.yaml` | **questo**: i manifest, con la teoria nei commenti | `kubectl apply -f 20-api-crd-threat-model.yaml` (ma conviene il guidato) |
| `~/kubernetesprj/kubernetes/20-api-crd-threat-model.sh` | lo script **guidato**: fa le chiamate REST, applica il file e fa le prove STRIDE una per volta, spiegando prima di eseguire (Invio / s / q) | `bash kubernetes/20-api-crd-threat-model.sh` |

Per imparare conviene lo **guidato**. Questo file va **letto** mentre lo guidato gira: i commenti spiegano il perché.

Versione dichiarata: **Kubernetes 1.34–1.35** (il lab minikube gira la **1.34.0**). Livello 3 — Sicurezza e operatività.

## Com'è fatto il file

```
intestazione (commenti)  → l'API REST, codici misurati, gruppi e versioni, kubectl proxy,
                            CRD e trappole, STRIDE, misura normale vs blindato, LAB, NEL PROGETTO VERO
Namespace lab-api
CustomResourceDefinition corsi.lab.esempio.it → il tipo Corso, con schema e colonne
Pod blindato             → soddisfa Pod Security "restricted", token tolto
Pod normale              → lo stesso senza protezioni, per confronto
coda (commenti)          → domande da colloquio, riepilogo
```

Gli oggetti `Corso` **non** stanno nel file: li crea il runner (passo 16), insieme a uno non valido.

---

## 1. La teoria nell'intestazione

### Tutto passa dall'apiserver

kubectl, kubelet, scheduler, controller, Argo CD: **nessun componente parla con un altro direttamente**, e solo
l'apiserver parla con etcd. Capire l'API vuol dire capire Kubernetes; proteggere l'API vuol dire proteggere il cluster.

### L'API è REST su HTTPS

Verbo HTTP + percorso = operazione su una risorsa:

| Richiesta | Operazione | Risposta |
|---|---|---|
| `GET /api/v1/namespaces/lab/pods` | lista (`kubectl get`) | 200 |
| `GET /api/v1/namespaces/lab/pods/x` | un oggetto | 200 |
| `POST /api/v1/namespaces` | crea | **201 Created** |
| `PUT` / `PATCH …` | aggiorna | 200 |
| `DELETE /api/v1/namespaces/x` | cancella | 200 (Terminating) |

Più `?watch=true` per lo **stream degli eventi**: così lavorano i controller.

Codici misurati nel lab:

| Codice | Quando |
|---|---|
| 201 | creazione |
| 409 | nome già esistente |
| 404 | oggetto inesistente, **oppure gruppo nel percorso sbagliato** |
| 401 | non so chi sei (token falso) |
| 403 | so chi sei, non puoi |

Senza credenziali l'apiserver del lab risponde **403, non 401**: l'utente anonimo esiste (`system:anonymous`) ma non ha
permessi su `/api`.

### Gruppi e versioni: il percorso dice il gruppo

| Gruppo | Percorso | Esempi |
|---|---|---|
| **core** (gruppo vuoto) | `/api/v1/…` | Pod, Service, Secret… |
| **gruppi con nome** | `/apis/<gruppo>/<versione>/…` | `apps/v1`, `batch/v1`, `networking.k8s.io/v1`… |

`apiVersion` nel YAML = gruppo/versione: `apps/v1`, oppure solo `v1` per il core.

Maturità: `v1alpha1` (spenta di default) → `v1beta1` → `v1` (GA). Le versioni beta **vengono rimosse**:
`extensions/v1beta1` per gli Ingress, `policy/v1beta1` per le PodSecurityPolicy (rimosse nella 1.25, nel lab non
esistono più).

| Comando | Cosa dice |
|---|---|
| `kubectl api-versions` | i gruppo/versione serviti |
| `kubectl api-resources --api-group=apps` | le risorse di un gruppo |
| `kubectl explain <kind>` | GROUP e VERSION da usare |

Formati: **JSON** per noi, **Protobuf** (prefisso magico `k8s\0`) fra i componenti.

### `kubectl proxy`

Apre l'API su `127.0.0.1` **senza TLS** e firma ogni richiesta con **le tue credenziali**. Comodo per curl; ma chiunque
sulla macchina lo può usare. **Mai `--address 0.0.0.0`**: daresti i tuoi permessi alla rete.

Le risposte portano gli header `X-Kubernetes-Pf-*`: **API Priority and Fairness**, il limitatore di concorrenza
dell'apiserver.

### Estendere l'API: CustomResourceDefinition

Un CRD aggiunge un **tipo nuovo**, con il suo percorso REST, validazione (schema OpenAPI) e colonne per `kubectl get`.
**Da solo è un archivio di dati**: il comportamento lo dà un **controller** (operator) che osserva quegli oggetti e
riconcilia. Argo CD (lezione 16) e Calico sono fatti così: nel lab ci sono **22 CRD di `projectcalico.org` e 3 di
`argoproj.io`**.

Trappole misurate:

- uno **shortName già usato perde**: `cs` è di `componentstatuses`, il tuo CRD non risponde a `kubectl get cs`
  (warning "could also match…");
- **cancellare il CRD cancella TUTTI gli oggetti** di quel tipo;
- scope `Namespaced` → percorso con `/namespaces/<ns>/`; `Cluster` → senza.

### Threat model con STRIDE

Prima le minacce, poi le difese. Sei categorie, ognuna con la sua contromisura in Kubernetes e un controllo che puoi
fare sul cluster:

| | Minaccia | Contromisure in Kubernetes |
|---|---|---|
| **S** Spoofing | fingersi un altro componente o Pod | mTLS fra componenti (CA del cluster), identità per ServiceAccount, token solo dove servono (`automountServiceAccountToken: false`), token proiettati con scadenza e audience |
| **T** Tampering | alterare immagini, manifest, dati | registry privato, immagini per **digest** e firmate (cosign + admission), GitOps come unica via di modifica, `readOnlyRootFilesystem` |
| **R** Repudiation | "non sono stato io" | **audit log** dell'apiserver (non attivo di default: serve una audit policy), log spediti fuori dal cluster, utenti personali e non condivisi |
| **I** Information disclosure | leggere ciò che non si deve | Secret cifrati at-rest (KMS, chiave **fuori** dal cluster), RBAC stretto su get/list secrets, etcd raggiungibile solo dall'apiserver |
| **D** Denial of service | esaurire il cluster | ResourceQuota e LimitRange (lezione 18), limite di PID per Pod (impostazione del kubelet), apiserver non esposto su internet, control plane in HA |
| **E** Elevation of privilege | da Pod a nodo, da utente a admin | Pod Security `restricted` (lezione 07): non-root, `allowPrivilegeEscalation: false`, drop ALL, seccomp RuntimeDefault; RBAC minimo, niente cluster-admin ai ServiceAccount |

### Misurato nel lab: Pod normale contro `blindato`

| | Pod normale | blindato |
|---|---|---|
| Seccomp | `0` (nessun filtro!) | `2` (filtro RuntimeDefault) |
| CapEff | `00000000a80425fb` (14 capability) | `0000000000000000` (nessuna) |
| uid | `0` (root) | `65534` (nobody) |
| NoNewPrivs | `0` | `1` |
| token SA | montato | assente |
| `touch /x` | riesce | `Read-only file system` |

**Il default non è sicuro**: seccomp è spento finché non lo chiedi (o finché il kubelet non ha `--seccomp-default`).

Come si leggono: `Seccomp`, `CapEff` e `NoNewPrivs` sono righe di `/proc/1/status`, lo stato del processo principale del
container. `CapEff` è una maschera esadecimale delle capability effettive; `NoNewPrivs 1` vuol dire che il processo non
può guadagnare privilegi (setuid, file capabilities).

**Fuori dall'API, e quindi fuori da RBAC**: chi ha SSH sul nodo (o `minikube ssh`) vede container e Secret montati senza
passare dall'apiserver. **Accesso ai nodi = accesso al cluster.**

### Riquadro «NEL PROGETTO VERO»

STRIDE sul Biodistretto (`~/biodistretto/kubernetes`, branch `kubernetes`), dalle cose trovate davvero:

| Categoria | Cosa | Dove guardare |
|---|---|---|
| Information disclosure | `community.general.terraform` lasciava in `/tmp` un piano con dentro lo stato, cioè chiavi e password. Rimedio: `TMPDIR` privato e pulizia in un `always` | `grep -n -A1 'environment:' ansible/roles/app/tasks/main.yml` |
| Information disclosure | la `.env` del backend finiva nell'immagine. Rimedio: build da un contesto pulito (lezione 12) | — |
| Elevation | HAProxy gira come root in rete host, ed Elasticsearch è senza sicurezza. Va bene in laboratorio, in produzione no | `grep -n -A1 'xpack.security.enabled' terraform/app/manifests/dati.yaml.tftpl` |
| Spoofing | il sito chiede una password (basic auth), e TLS usa la CA del laboratorio, che il browser deve importare | — |
| DoS | `maxconn` in HAProxy, limit di memoria su ogni container | `grep -n 'maxconn' ansible/roles/haproxy/templates/haproxy.cfg.j2` |

---

## 2. I manifest

### Namespace `lab-api`

Contiene i Pod e gli oggetti `Corso`. Il CRD invece **non** sta nel namespace: una CRD è sempre cluster-scoped, anche
quando il tipo che definisce è `Namespaced`.

### Il CRD `corsi.lab.esempio.it`

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: corsi.lab.esempio.it            # <plurale>.<gruppo>: obbligatorio
spec:
  group: lab.esempio.it
  scope: Namespaced
  names:
    plural: corsi
    singular: corso
    kind: Corso
    shortNames: [crs]                   # non `cs`: è già di componentstatuses
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              required: [titolo]
              properties:
                titolo: { type: string }
                ore: { type: integer, minimum: 1 }
                livello: { type: string, enum: [base, medio, avanzato] }
      additionalPrinterColumns:
        - { name: Titolo, type: string, jsonPath: .spec.titolo }
        - { name: Ore, type: integer, jsonPath: .spec.ore }
        - { name: Livello, type: string, jsonPath: .spec.livello }
```

| Campo | Perché |
|---|---|
| `metadata.name` | **obbligatoriamente** `<plurale>.<gruppo>` |
| `group: lab.esempio.it` | il gruppo nel percorso: `/apis/lab.esempio.it/v1/…` |
| `scope: Namespaced` | gli oggetti stanno in un namespace: percorso con `/namespaces/<ns>/corsi` |
| `names` | `plural` per l'URL e `kubectl get corsi`, `singular` per `kubectl get corso`, `kind` per il YAML |
| `shortNames: [crs]` | abbreviazione: `kubectl get crs`. Non `cs`, che perde contro `componentstatuses` |
| `served: true` | questa versione risponde all'API |
| `storage: true` | è la versione con cui gli oggetti si salvano in etcd (una sola può esserlo) |
| `openAPIV3Schema` | la **validazione**: `spec.titolo` obbligatorio, `ore` intero ≥ 1, `livello` solo `base`/`medio`/`avanzato` |
| `additionalPrinterColumns` | le colonne di `kubectl get corsi`, prese con un `jsonPath` dall'oggetto |

### Pod `blindato`: Pod Security "restricted", senza token

```yaml
spec:
  automountServiceAccountToken: false
  securityContext:
    runAsNonRoot: true
    runAsUser: 65534
    seccompProfile: { type: RuntimeDefault }
  containers:
    - name: app
      image: busybox:1.37
      command: ["sleep", "infinity"]
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities: { drop: [ALL] }
      resources:
        requests: { cpu: 5m, memory: 8Mi }
        limits: { memory: 16Mi }
```

| Campo | Livello | Minaccia STRIDE |
|---|---|---|
| `automountServiceAccountToken: false` | Pod | **S**: niente token da rubare |
| `runAsNonRoot: true` | Pod | **E**: il kubelet rifiuta di avviare un container che girerebbe come root |
| `runAsUser: 65534` | Pod | **E**: l'utente `nobody` (serve perché busybox di suo partirebbe come root) |
| `seccompProfile: RuntimeDefault` | Pod | **E**: filtro sulle syscall del runtime (`Seccomp: 2`) |
| `allowPrivilegeEscalation: false` | container | **E**: `NoNewPrivs 1` |
| `readOnlyRootFilesystem: true` | container | **T**: il filesystem dell'immagine non si scrive |
| `capabilities: drop: [ALL]` | container | **E**: `CapEff` a zero |
| `resources` | container | **D**: un tetto di memoria |

### Pod `normale`

Lo stesso busybox con `sleep infinity` e le stesse `resources`, ma **senza** alcun `securityContext` e con il token
montato. È il default, e serve da confronto.

---

## 3. Il runner, passo per passo

Il runner definisce `API=http://127.0.0.1:9001` e `trap 'kill $PROXY 2>/dev/null' EXIT`: il proxy in background viene
chiuso anche se esci a metà con `q`.

### Parte 1 — l'API REST

| # | Passo | Cosa vedi |
|---|---|---|
| — | `guardia_lab` | lo script si ferma se il contesto non è `lab` |
| 1 | `kubectl get pods -n kube-system -v=6 2>&1 \| grep -o "verb=.*" \| head -2` | le **richieste HTTP vere** dietro un comando: verbo, URL, codice |
| 2 | `kubectl proxy --port 9001 … & PROXY=$!` | l'API su `127.0.0.1:9001`, firmata con le tue credenziali |
| 3 | `curl -s $API/api` | il gruppo **core** sta in `/api`: una sola versione, `v1` |
| 4 | `curl -s $API/apis` + python che stampa `nome → preferredVersion` | tutti gli altri gruppi in `/apis`, ognuno con la sua versione preferita |
| 5 | `curl -s $API/api/v1/namespaces/kube-system/pods` + python | `kubectl get pods` = GET su quel percorso: `PodList` e i primi nomi |
| 6 | `curl -X POST … {"kind":"Namespace","metadata":{"name":"da-curl"}}` | **201** Created, senza kubectl |
| 7 | la stessa POST; GET di un Pod inesistente; `$API/api/apps/v1/deployments` | **409** Conflict, **404**, **404** (gruppo `apps` sotto `/api` invece di `/apis`) |
| 8 | `curl -X DELETE $API/api/v1/namespaces/da-curl` + `status.phase` | `fase: Terminating`: la cancellazione è **asincrona** (finalizer) |
| 9 | `curl -D - … \| grep -i '^x-kubernetes-pf'` | gli header di **API Priority and Fairness** |
| 10 | `curl -H 'Accept: application/vnd.kubernetes.protobuf' … \| head -c 4 \| od -c` | `k 8 s \0`: il prefisso magico del Protobuf |
| 11 | server preso da `kubectl config view --minify`, `curl -sk` senza credenziali e con `Bearer falso` | `anonimo: 403`, `token falso: 401` |
| 12 | `kubectl api-versions \| grep -E "^policy\|^networking"` e conteggio di PodSecurityPolicy | i gruppi serviti, e **0** risorse PodSecurityPolicy |
| 13 | un Ingress `extensions/v1beta1` con `apply --dry-run=server` | **fallisce apposta (uscita 1)**: `no matches for kind`, quella versione non esiste più |

`--dry-run=server` fa arrivare la richiesta all'apiserver (validazione e admission comprese) ma **non scrive** niente.

### Parte 2 — il CRD

| # | Passo | Cosa vedi |
|---|---|---|
| 14 | `apply -f $F`, `wait --for=condition=Established crd/corsi.lab.esempio.it`, `wait … pod/blindato pod/normale` | il CRD pronto a ricevere oggetti, i due Pod Ready |
| 15 | `api-resources --api-group=lab.esempio.it; explain corso.spec` | il tipo nuovo è nell'API come quelli nativi: nome, shortName `crs`, i campi `titolo`, `ore`, `livello` |
| 16 | applica i Corso `kubernetes` (40 ore, medio) e `helm` (12 ore, base), poi `kubectl -n lab-api get crs` | gli oggetti con le **colonne del CRD**: Titolo, Ore, Livello |
| 17 | un Corso `rotto` con `ore: 0`, `livello: esperto`, senza `titolo` | **fallisce apposta (uscita 1)**: l'apiserver lo rifiuta con lo schema (minimum, enum, required) |
| 18 | `curl -s $API/apis/lab.esempio.it/v1/namespaces/lab-api/corsi` + python | gli stessi oggetti via REST: il CRD ha **creato il percorso** |
| 19 | `kubectl api-resources \| awk '$2=="cs"'` | la trappola dello shortName: `cs` è di `componentstatuses` |
| — | `nota` | nessun controller osserva i Corso: **sono solo dati**. Un operator è CRD + controller che riconcilia |

### Parte 3 — STRIDE misurato

| # | Passo | Cosa vedi |
|---|---|---|
| 20 | `exec normale -- sh -c "id; grep -E '^(CapEff\|NoNewPrivs\|Seccomp):' /proc/1/status"` | **E**: root, `Seccomp 0` (nessun filtro sulle syscall), le 14 capability di default del runtime, `NoNewPrivs 0` |
| 21 | lo stesso in `blindato` | utente `nobody` (65534), `Seccomp 2`, `CapEff` a zero, `NoNewPrivs 1` |
| 22 | `touch /x` nei due Pod | **T**: il normale scrive (`normale: scritto /x`), il blindato **fallisce apposta (uscita 1)**: `Read-only file system` |
| 23 | `ls /var/run/secrets/kubernetes.io/serviceaccount` nei due Pod | **S**: il normale ha il token montato (`ca.crt`, `namespace`, `token`), il blindato **fallisce apposta (uscita 1)**: la cartella non c'è |
| 24 | `kubectl auth can-i --list --as=system:serviceaccount:lab-api:default -n lab-api \| head -8` | cosa ci farebbe un attaccante con quel token: i permessi del ServiceAccount `default` |
| 25 | `auth can-i get secrets` come SA `default`, poi come te | **I**: il SA `default` **no**, tu (admin) **sì** |
| 26 | i flag del Pod `kube-apiserver` filtrati con `grep -c audit` | **R**: `0` e `→ audit spento`. Nessun flag audit = nessuna traccia di chi ha fatto cosa |
| 27 | `minikube -p lab ssh -n $n -- docker ps --format "{{.Names}}" \| grep lab-api` sui nodi `lab` e `lab-m02` | **fuori da RBAC**: dal nodo vedi i container di `lab-api` senza passare dall'apiserver |
| 28 | `kubectl delete crd corsi.lab.esempio.it && kubectl -n lab-api get corsi` | **fallisce apposta (uscita 1)**: il tipo non esiste più, e con lui **tutti i Corso** |
| 29 | `kill $PROXY; kubectl delete ns lab-api` | pulizia |

Nel passo 26 `grep -c` stampa il numero di righe trovate ed esce con 1 quando sono zero: è proprio l'uscita 1 che fa
scattare `|| echo "→ audit spento"`.

---

## 4. Trappole

- **Gruppo nel percorso sbagliato** (`/api/apps/v1/…`): 404, come un oggetto che non c'è.
- **403 non vuol dire "token sbagliato"**: vuol dire "ti conosco, non puoi". Il token falso dà 401.
- **`kubectl proxy --address 0.0.0.0`**: espone i tuoi permessi a chiunque raggiunga la porta.
- **Manifest con API rimosse** (`extensions/v1beta1`, `policy/v1beta1`): `no matches for kind`. `kubectl explain` dice
  il GROUP/VERSION giusto.
- **shortName in conflitto**: perde il tuo CRD, in silenzio (solo un warning).
- **`delete crd`** cancella tutti gli oggetti di quel tipo.
- **CRD senza controller**: crei oggetti e non succede niente. Non è un errore, è la natura del CRD.
- **Il default non protegge**: seccomp spento, token montato, root possibile.
- **Audit log spento** di default: niente Repudiation coperta.
- **SSH sul nodo** scavalca RBAC.

---

## 5. Comandi e domande da colloquio

### Comandi (dalla sezione LAB del file)

| Comando | A cosa serve |
|---|---|
| `kubectl proxy --port 9001 &` | l'API su localhost per curl |
| `curl -s localhost:9001/api ; curl -s localhost:9001/apis \| head` | gruppo core e gruppi con nome |
| `curl -si -X POST -H 'Content-Type: application/json' --data '{"apiVersion":"v1","kind":"Namespace","metadata":{"name":"da-curl"}}' localhost:9001/api/v1/namespaces \| head -1` | una creazione a mano: `201 Created` |
| `kubectl -n lab-api get corsi ; kubectl get --raw /apis/lab.esempio.it/v1/namespaces/lab-api/corsi` | il CRD con kubectl e in REST grezzo |
| `kubectl -n lab-api exec blindato -- grep -E 'Seccomp\|CapEff\|NoNewPrivs' /proc/1/status` | le difese del processo |
| `kubectl get … -v=6` | le richieste HTTP dietro un comando |
| `kubectl auth can-i --list --as=system:serviceaccount:<ns>:<sa>` | tutti i permessi di un'identità |

`kubectl get --raw` fa la stessa GET di curl, ma con le credenziali del kubeconfig e senza bisogno del proxy.

### Domande

- **Cosa succede quando lancio `kubectl apply`?** kubectl trasforma il YAML in JSON e fa GET + PATCH (o POST) via HTTPS
  all'apiserver. L'apiserver autentica, autorizza (RBAC), passa per gli admission controller (mutating, poi validating:
  qui Pod Security e le quote), valida lo schema e scrive in etcd. Poi i controller reagiscono.
- **401 o 403?** 401: credenziali assenti o non valide. 403: identità riconosciuta, permesso negato. Un utente anonimo
  può ricevere 403, non 401.
- **Che cos'è un operator?** Un CRD (il tipo nuovo) più un controller che lo riconcilia: osserva gli oggetti con watch
  e porta il mondo allo stato dichiarato.
- **Come faresti il threat model di un cluster?** STRIDE sui flussi (utente → apiserver, Pod → Pod, CI → registry →
  cluster, nodo → etcd). Per ogni categoria una difesa e un controllo verificabile: `auth can-i`, Pod Security,
  NetworkPolicy, audit log, cifratura dei Secret, quote.
- **Un Pod senza securityContext ha seccomp?** Di default no (`Seccomp: 0` nel lab). Serve `seccompProfile`
  `RuntimeDefault` nel Pod, Pod Security `restricted` che lo impone, o il kubelet con `--seccomp-default`.

---

## Riepilogo

- API REST: verbo + percorso; core in `/api/v1`, gli altri in `/apis/<gruppo>/<ver>`.
- POST 201 · conflitto 409 · non trovato 404 · 401 chi sei? · 403 non puoi.
- CRD = tipo nuovo + schema; senza controller è solo dati; shortName unico.
- STRIDE: per ogni minaccia una difesa e un comando che la verifica.
- Il default non protegge: seccomp spento, token montato, root possibile.

## Prova da solo

1. Con il proxy acceso, fai con `curl` un `PATCH` che aggiunge una label al Namespace `lab-api`
   (`-H 'Content-Type: application/merge-patch+json'`, corpo `{"metadata":{"labels":{"prova":"si"}}}`): che codice
   torna? Controlla con `kubectl get ns lab-api --show-labels`.
2. Aggiungi al CRD un campo `spec.docente` di tipo stringa e una colonna `Docente`, riapplica e crea un Corso che lo
   usa: compare nella `get crs`? Cosa succede a un Corso con un campo `spec.prezzo` che lo schema non conosce?
3. Applica al namespace `lab-api` la label `pod-security.kubernetes.io/enforce=restricted`, poi prova a ricreare il Pod
   `normale` (cancellalo e riapplica il file): cosa dice l'apiserver, e quali campi del Pod `blindato` mancano a
   `normale` secondo il messaggio?
