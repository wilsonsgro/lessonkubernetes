# 07 — Sicurezza: RBAC, ServiceAccount e Pod Security Admission

Spiegazione di `07-rbac-pod-security.yaml` (questa cartella). Lezione sul sito: http://127.0.0.1:3000/kubernetes/7

## In una frase

Il file crea un namespace **`lab-sicuro`** in cui la **Pod Security Admission** applica il profilo **`restricted`**, un
**ServiceAccount `deployer`** con un **Role** di minimo privilegio (legge Pod e config, gestisce i Deployment, niente
Secret né exec né delete) e un **nginx non-root** che quel profilo lo supera. Il runner interroga l'apiserver con
`kubectl auth can-i --as` e poi prova a lanciare un Pod "qualunque", che viene **rifiutato**.

## Due file con lo stesso nome: quale lanciare

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/lezioni/kubernetes/07-rbac-pod-security.yaml` | **questo**: i manifest, con la teoria nei commenti | si **legge**; lo applica il runner (o a mano: `kubectl apply -f 07-rbac-pod-security.yaml`) |
| `~/kubernetesprj/kubernetes/07-rbac-pod-security.sh` | lo script **guidato**: applica, interroga i permessi, prova la PSA, un passo per volta (Invio / s / q) | `bash kubernetes/07-rbac-pod-security.sh` |

Questa lezione non dipende dalle precedenti: crea il suo namespace.

## Com'è fatto il file

```
intestazione (commenti)  → teoria: authn → authz → admission, RBAC in 4 oggetti, verbi che sorprendono,
                           comandi LAB, NEL PROGETTO VERO
Namespace lab-sicuro     → label PSA: enforce + warn restricted
ServiceAccount deployer  → identità senza token montato di default
Role deployer            → cosa può fare (solo allow)
RoleBinding deployer     → a chi (il SA) e dove (lab-sicuro)
Deployment nginx         → un Pod che passa "restricted"
commenti                 → oltre il cluster: la catena di fornitura
coda (commenti)          → domande da colloquio, riepilogo
```

Versione: Kubernetes 1.34–1.35 (lab 1.34.0), `rbac.authorization.k8s.io/v1`, PSA "restricted".

---

## 1. La teoria nell'intestazione

### Tre domande, sempre in quest'ordine

Ogni richiesta all'apiserver passa tre controlli:

| Fase | Domanda | Con cosa |
|---|---|---|
| **Autenticazione** | chi sei? | certificato client, token **OIDC** (persone), token del **ServiceAccount** (Pod) |
| **Autorizzazione** | puoi farlo? | **RBAC**: verbo + risorsa (+ nome) + namespace |
| **Admission** | è accettabile? | **PSA**, policy (Kyverno, ValidatingAdmissionPolicy) |

Kubernetes **non ha "utenti" come oggetti**: un utente è solo un nome dentro un certificato o un token. I
**ServiceAccount** invece sono oggetti veri, in un namespace: sono le identità dei Pod.

### RBAC in 4 oggetti

| Oggetto | Risponde a |
|---|---|
| `Role` / `ClusterRole` | **cosa** si può fare (solo allow, additivo: non esiste un "deny") |
| `RoleBinding` / `ClusterRoleBinding` | **a chi**, e **dove** |

Un **ClusterRole legato con un RoleBinding** vale **solo in quel namespace**: è il modo per riusare un ruolo standard
(`view`, `edit`) per ogni team, senza riscriverlo.

### Verbi che sorprendono

| Permesso | Che cosa dà davvero |
|---|---|
| `get` su `secrets` | leggere **tutti** i segreti (con `list`, senza nemmeno sapere il nome) |
| `create` su `pods` | leggere **ogni secret / SA del namespace**: monti il secret o il token in un Pod tuo |
| `escalate` / `bind` / `impersonate` | scalare i propri privilegi |
| `pods/exec`, `nodes/proxy` | eseguire comandi |

### I comandi LAB dell'intestazione

```bash
kubectl apply -f 07-rbac-pod-security.yaml
SA=system:serviceaccount:lab-sicuro:deployer
kubectl auth can-i get pods  -n lab-sicuro --as=$SA      # yes
kubectl auth can-i get secrets -n lab-sicuro --as=$SA    # no
kubectl auth can-i patch deployments -n lab --as=$SA     # no: altro namespace
kubectl auth can-i --list -n lab-sicuro --as=$SA
kubectl -n lab-sicuro run root --image=busybox:1.37 -- sleep 1d
  ↑ RIFIUTATO dalla PSA "restricted": il messaggio elenca cosa manca
kubectl -n lab-sicuro get pod                            # nginx Running
```

Il nome di un ServiceAccount per RBAC ha sempre la forma `system:serviceaccount:<namespace>:<nome>`. Con `--as` ti fai
**passare** per lui (impersonation): tu, admin del lab, puoi farlo.

### Riquadro «NEL PROGETTO VERO»

In `~/biodistretto/kubernetes`:

- il **worker** gira come uid/gid **1000**, Elasticsearch con **fsGroup 1000**:
  ```bash
  grep -n -A2 'runAsUser' terraform/app/manifests/app.yaml.tftpl
  ```
- il resto gira **come vuole l'immagine**. **Esercizio senza cambiare niente**:
  ```bash
  kubectl --context biodistretto label --dry-run=server --overwrite ns \
    biodistretto pod-security.kubernetes.io/enforce=restricted
  ```
  Con `--dry-run=server` l'apiserver valuta la modifica ma **non la salva**: le righe di **Warning** dicono quali Pod
  violerebbero il profilo e perché.
- **Fuori dal cluster**: il container HAProxy gira **come root in rete host**, perché senza privilegi le porte 80 e 443
  dell'host non si aprono.
  ```bash
  grep -n -E 'network_mode|user:' ansible/roles/haproxy/tasks/main.yml
  ```

---

## 2. Il Namespace `lab-sicuro` e la Pod Security Admission

```yaml
metadata:
  name: lab-sicuro
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/warn: restricted
```

La **PSA** è nativa (ha sostituito PodSecurityPolicy) e si configura **con label sul namespace**.

| Modo | Effetto |
|---|---|
| `enforce` | **rifiuta** i Pod che violano il profilo |
| `audit` | li accetta ma **annota** la violazione nel log di audit |
| `warn` | li accetta ma **avvisa** il client (le righe `Warning:` di kubectl) |

| Livello | Cosa permette |
|---|---|
| `privileged` | tutto |
| `baseline` | blocca le escalation note (privileged, hostNetwork, hostPath…) |
| `restricted` | in più: non-root, niente escalation, capabilities tolte, seccomp |

`enforce-version: latest` = usa le regole della versione di Kubernetes in esecuzione. Qui `warn` è uguale a `enforce`:
il warning serve soprattutto quando i due livelli differiscono (migrazione graduale, vedi le domande).

Attenzione: la PSA controlla i **Pod**. Un Deployment che viola il profilo viene **accettato**; è il ReplicaSet che poi
non riesce a creare i Pod (con `warn` lo vedi subito all'apply).

---

## 3. Il ServiceAccount `deployer`

```yaml
kind: ServiceAccount
metadata:
  name: deployer
  namespace: lab-sicuro
automountServiceAccountToken: false
```

Un'identità per chi deve fare deploy (una pipeline, un operatore). `automountServiceAccountToken: false`: i Pod che usano
questo SA **non ricevono il token** a meno che non lo chiedano esplicitamente. Il token si monta **solo dove serve**.

---

## 4. Il Role `deployer` — regola per regola

```yaml
rules:
  - apiGroups: [""]
    resources: [pods, pods/log, services, configmaps]
    verbs: [get, list, watch]
  - apiGroups: [apps]
    resources: [deployments]
    verbs: [get, list, watch, create, update, patch]
  - apiGroups: [apps]
    resources: [deployments/scale]
    verbs: [patch]
```

| Regola | Concede | Perché |
|---|---|---|
| core (`""`) | **leggere** Pod, log dei Pod, Service, ConfigMap | `""` è il gruppo **core** dell'API. `pods/log` è una **sottorisorsa**: va nominata a parte |
| `apps` / `deployments` | leggere, creare e modificare Deployment | il lavoro di un deployer |
| `apps` / `deployments/scale` | `patch` della sottorisorsa scale | per `kubectl scale` |

E quello che **manca** è il punto (commento del file): **niente secrets, niente pods/exec, niente delete**. Minimo
privilegio. Un `Role` vale solo nel suo namespace (`lab-sicuro`).

Nota: il deployer può **creare Deployment**, e quindi indirettamente far creare Pod nel namespace. Per la regola dei
"verbi che sorprendono", è un potere da tenere presente; qui lo limitano la PSA `restricted` e il fatto che il SA non ha
accesso ai Secret via API.

---

## 5. Il RoleBinding `deployer`

```yaml
subjects:
  - kind: ServiceAccount
    name: deployer
    namespace: lab-sicuro
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: deployer
```

- `subjects`: **a chi** — il ServiceAccount (per un SA il `namespace` va sempre indicato).
- `roleRef`: **quale** ruolo. È **immutabile**: per cambiarlo si cancella e si ricrea il binding.
- Il binding sta in `lab-sicuro`: per questo `can-i patch deployments -n lab` dà **no**.

---

## 6. Il Deployment `nginx` — un Pod che passa `restricted`

Il commento del file: è il `securityContext` che **ogni** workload dovrebbe avere, non un caso speciale.

### A livello di Pod

```yaml
automountServiceAccountToken: false
securityContext:
  runAsNonRoot: true
  runAsUser: 101
  runAsGroup: 101
  fsGroup: 101
  seccompProfile:
    type: RuntimeDefault
```

| Campo | Perché |
|---|---|
| `automountServiceAccountToken: false` | nginx non parla con l'apiserver: niente token |
| `runAsNonRoot: true` | richiesto da restricted: il kubelet non avvia il container se girerebbe come root |
| `runAsUser` / `runAsGroup: 101` | l'utente `nginx` dell'immagine unprivileged |
| `fsGroup: 101` | i volumi montati diventano del gruppo 101, così nginx può scriverci |
| `seccompProfile: RuntimeDefault` | **richiesto da restricted**: filtra le syscall con il profilo del runtime |

### A livello di container

```yaml
image: nginxinc/nginx-unprivileged:1.31-alpine
ports:
  - containerPort: 8080
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: ["ALL"]
volumeMounts:
  - { name: tmp, mountPath: /tmp }
resources:
  requests: { cpu: 10m, memory: 16Mi }
  limits: { memory: 64Mi }
volumes:
  - name: tmp
    emptyDir: {}
```

| Campo | Perché |
|---|---|
| immagine `nginx-unprivileged` | ascolta su **8080**, non su 80: un utente non root non può aprire porte sotto la 1024 |
| `allowPrivilegeEscalation: false` | richiesto da restricted |
| `capabilities.drop: ["ALL"]` | richiesto da restricted |
| `readOnlyRootFilesystem: true` | non richiesto da restricted, ma buona prassi (come nella lezione 02) |
| volume `tmp` (`emptyDir`) su `/tmp` | con la root in sola lettura, **le cartelle scrivibili si dichiarano**: nginx deve scrivere file temporanei |

---

## 7. Il runner, passo per passo

Il runner imposta `SA=system:serviceaccount:lab-sicuro:deployer`, chiama `guardia_lab`, poi 7 passi:

| # | Comando | Cosa vedi |
|---|---|---|
| 1 | `kubectl apply -f …/07-rbac-pod-security.yaml` | namespace, serviceaccount, role, rolebinding, deployment creati |
| 2 | `kubectl auth can-i get pods -n lab-sicuro --as=$SA` | `yes` |
| 3 | `kubectl auth can-i get secrets -n lab-sicuro --as=$SA` | `no` — **e la riga rossa "uscita 1"**: `can-i` esce 1 quando la risposta è no. È voluto |
| 4 | `kubectl auth can-i patch deployments -n lab --as=$SA` | `no` (uscita 1, voluto): un RoleBinding vale solo nel suo namespace |
| 5 | `kubectl auth can-i --list -n lab-sicuro --as=$SA` | la tabella Resources / Verbs: le tre regole del Role più i permessi di base che ogni utente autenticato ha (es. `selfsubjectaccessreviews`) |
| 6 | `kubectl -n lab-sicuro run root --image=busybox:1.37 -- sleep 1d` | **fallisce apposta**: `Error from server (Forbidden): … violates PodSecurity "restricted:latest"` con l'elenco di ciò che manca (allowPrivilegeEscalation, capabilities, runAsNonRoot, seccompProfile) |
| 7 | `rollout status deploy/nginx --timeout=90s && get pod` | l'nginx del manifest è `Running`: non-root, niente privilegi, seccomp RuntimeDefault, capabilities tolte |

Il passo 6 è il cuore della lezione: `kubectl run` crea **direttamente un Pod**, quindi la PSA lo blocca subito e
l'errore arriva al terminale. Il Pod `root` **non viene creato**: non c'è niente da pulire.

---

## 8. Oltre il cluster: la catena di fornitura

| Pratica | Strumenti |
|---|---|
| immagini firmate e verificate all'admission | cosign / Sigstore |
| scansione CVE in CI e SBOM | Trivy, Grype; Syft |
| immagini minime e riferimenti immutabili | distroless o FROM scratch, tag immutabili o digest `@sha256` |
| policy as code ("niente `:latest`", "requests obbligatorie", "solo registry interni") | Kyverno / OPA Gatekeeper / ValidatingAdmissionPolicy |
| sorveglianza a runtime | Falco (syscall sospette) |
| credenziali cloud senza chiavi statiche | Workload Identity / IRSA: il Pod le ottiene dal suo ServiceAccount |

---

## 9. Le trappole

| Trappola | Cosa succede | Rimedio |
|---|---|---|
| dare `create pods` pensando "non legge i secret" | monta qualunque secret in un Pod suo | trattare `create pods` come accesso ai secret |
| dare `get` (o `list`) su secrets per comodità | legge tutti i segreti del namespace | mai nei ruoli di lettura; `view` non li include |
| `roleRef` da cambiare | l'update viene rifiutato: è immutabile | cancellare e ricreare il binding |
| Deployment che viola la PSA | accettato, ma i Pod non nascono | `warn` all'apply; guardare gli eventi del ReplicaSet |
| root filesystem read-only senza volumi scrivibili | l'app crasha cercando di scrivere | `emptyDir` sulle cartelle che servono (`/tmp`) |
| immagine che ascolta su 80 come non-root | non può aprire la porta | immagine "unprivileged" su 8080 |
| passare un namespace esistente a `enforce` di colpo | i Pod nuovi vengono rifiutati | prima `warn`/`audit` (o `--dry-run=server`), poi `enforce` |
| leggere "no" come errore dello script | `can-i` esce 1 sul no | è la risposta, non un guasto |

---

## 10. La coda: domande da colloquio

- **Come dai a un team accesso in sola lettura al suo namespace?** RoleBinding nel namespace verso il ClusterRole
  predefinito **`view`**, con subject il **gruppo OIDC** del team (non i singoli utenti).
- **Perché `view` non include i secrets e `edit` sì?** Leggere un secret è un'escalation (token, password). `edit`
  include la creazione di Pod, che dà comunque accesso ai secret: per questo `edit` ≈ chi può leggere i secret del
  namespace.
- **Un Pod viene rifiutato con "violates PodSecurity restricted".** Il messaggio elenca i campi: `allowPrivilegeEscalation`,
  `capabilities`, `runAsNonRoot`, `seccompProfile`. Si corregge il `securityContext`; per migrare un namespace prima si
  mette `warn`/`audit`, si guarda cosa romperebbe, poi `enforce`.
- **Il token del ServiceAccount: com'è fatto oggi?** Token **proiettato** (BoundServiceAccountToken): JWT con audience
  e **scadenza** (1 h, rinnovato dal kubelet), legato al Pod. I vecchi Secret di tipo token senza scadenza non si creano
  più in automatico.

### Comandi da sapere

| Comando | A cosa serve |
|---|---|
| `kubectl auth can-i <verbo> <risorsa> -n <ns> --as=system:serviceaccount:<ns>:<sa>` | che cosa può fare un'identità |
| `kubectl auth can-i --list -n <ns> --as=…` | tutti i suoi permessi |
| `kubectl label --dry-run=server --overwrite ns <ns> pod-security.kubernetes.io/enforce=restricted` | chi violerebbe il profilo, senza applicarlo |
| `kubectl get ns lab-sicuro --show-labels` | le label PSA di un namespace |

---

## Riepilogo

- **Authn → Authz (RBAC) → Admission**, sempre in quest'ordine.
- **Role/ClusterRole = cosa**; **(Cluster)RoleBinding = a chi e dove**.
- **`create pods` ≈ leggere i secret**: il minimo privilegio si verifica con `can-i`.
- **PSA restricted** per namespace: non-root, no escalation, drop ALL, seccomp.
- **Supply chain**: firma, scansione, policy, identità senza chiavi statiche.

## Prova da solo

1. `kubectl auth can-i delete deployments -n lab-sicuro --as=$SA` e `kubectl auth can-i create pods/exec -n lab-sicuro
   --as=$SA`: cosa rispondono, e quale riga del Role (o la sua assenza) lo spiega?
2. Crea un RoleBinding in `lab-sicuro` che leghi il SA `deployer` al ClusterRole predefinito `view` (`kubectl create
   rolebinding …`), poi ripeti `can-i get secrets` e `can-i get pods -n lab`: cosa cambia e cosa no?
3. Togli dal Deployment `nginx` il blocco `seccompProfile` e riapplica: che `Warning` stampa kubectl? Il Deployment
   viene accettato? E i Pod nuovi (`kubectl -n lab-sicuro get rs` e `describe rs`)? Rimetti il blocco.
