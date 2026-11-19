# 16 — Argo CD: GitOps sul tuo sito, in locale

Spiegazione di `16-argocd-gitops.sh` (questa cartella).

## In una frase

Argo CD smette di gestire l'esempio guestbook della lezione 12 e prende in carico **il tuo progetto**: un sito con
Dockerfile, i suoi manifest e l'infrastruttura in Terraform, tutto sul minikube `lab`, con **anche il server git
(Gitea) dentro il cluster**. Vedi dal vivo self-heal, nuova versione con un commit, rollback con `git revert`, prune
e la quota di Terraform che vale anche per Argo.

## Due file con lo stesso nome: quale lanciare

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/lezioni/kubernetes/16-argocd-gitops.sh` | **questo**: la lezione, con le spiegazioni nei commenti | **da leggere**, non da lanciare intero (vedi sotto) |
| `~/kubernetesprj/kubernetes/16-argocd-gitops.sh` | **non esiste**: questa lezione non ha lo script guidato | — |
| `~/kubernetesprj/argocd/01…05` (sull'Ubuntu 192.168.1.79) | il **laboratorio guidato**, passo per passo, citato nell'intestazione | si lanciano in ordine |

A differenza delle altre lezioni `.sh`, questo file **non ha funzioni né un `case`**: è una sequenza di comandi in
ordine, da leggere e copiare a pezzi. Lanciato tutto d'un fiato non funzionerebbe: usa `$GITEA_PASS` e `gitea.yaml`
che non definisce, fa `cd mio-progetto` senza crearlo, mette un `port-forward` in background e contiene apposta
comandi che falliscono (il rollback del punto 7). Il laboratorio guidato è in `~/kubernetesprj/argocd/`.

Versioni dichiarate: **Argo CD 3.6 · Gitea 1.24 · Terraform 1.x (provider kubernetes 2.38)**. Livello 6.

## Com'è fatto il file

```
intestazione (commenti)   → chi fa cosa, push contro pull, architettura, il progetto, NEL PROGETTO VERO
set -euo pipefail + use-context lab
1. Installazione          → Argo CD server-side, CRD, password admin, port-forward, CLI, login
2. Il repository git      → Gitea nel cluster, primo push, due URL
3. Immagine e Terraform   → docker build, image load, ingress, terraform apply
4. L'Application          → il manifest, Sync vs Health, tracking-id
5. Self-heal              → scale a mano annullato
6. Nuova versione         → commit v2 + 3 repliche, refresh, history
7. Rollback               → app rollback rifiutato, git revert
8. Prune                  → togli ingress.yaml da git
9. Terraform + Argo       → 8 repliche contro la quota di 6 pod
10. Adottare l'esistente  → seconda Application stack-web
Pulizia, domande da colloquio, riepilogo
```

---

## 1. La teoria nell'intestazione

### Chi fa cosa

| Pezzo | Mestiere |
|---|---|
| **Terraform** | le risorse **infrastrutturali**, il terreno su cui l'app atterra: qui namespace, ResourceQuota, LimitRange; in cloud rete, cluster, database gestiti |
| **minikube** | esegue il cluster Kubernetes locale |
| **Kubernetes** | gestisce i container del sito (Deployment, Service, Ingress) |
| **Argo CD** | legge git e tiene il cluster **uguale** a quello che c'è scritto |
| **la CI** | costruisce l'immagine (qui: `docker build` a mano) |

La frase da colloquio: **Terraform dice DOVE, git dice COSA, Argo CD fa sì che il cluster lo rispetti —
continuamente, non solo al deploy.**

### Push contro pull

| CI/CD classica (push) | GitOps (pull) |
|---|---|
| la pipeline fa `kubectl`/`helm` | la pipeline fa **solo commit** in git |
| la CI ha le credenziali del cluster | le credenziali restano **dentro** il cluster (Argo CD) |
| il cluster può divergere da git senza che nessuno se ne accorga | Argo CD confronta di continuo e corregge (`selfHeal`) o segnala |
| rollback = rilanciare un job | rollback = `git revert` |
| chi ha cambiato cosa: log della CI | chi ha cambiato cosa: `git log` |

### L'architettura

```
tu (Ubuntu) ── git push ──► Gitea (namespace gitea, NodePort 30300)
                              ▲  git fetch ogni 2–3 minuti (o --refresh)
namespace argocd:
  argocd-repo-server              clona il repo, genera i manifest (YAML, Kustomize, Helm)
  argocd-application-controller   confronta desiderato (git) e attuale (cluster), sincronizza
  argocd-server                   API + UI (port-forward → :8083)
  redis, dex, notifications-controller, applicationset-controller
                              │  kubectl apply (server-side)
                              ▼
namespace mio-sito ← creato da TERRAFORM (quota: max 6 pod)
  Deployment mio-sito (immagine mio-sito:v1) → Service → Ingress (host: mio-sito.local)
```

### Il progetto

```
mio-progetto/
├── terraform/     main.tf, variables.tf        namespace + quota + limiti
├── kubernetes/    deployment, service, ingress quello che Argo applica
├── sito/          Dockerfile, index.html       l'immagine
└── argocd/        application.yaml             cosa deve guardare Argo
```

Argo guarda **solo** la cartella `kubernetes` (`spec.source.path`): un commit su `terraform/` o `sito/` non cambia
niente nel cluster. In azienda spesso i manifest stanno in un repository a parte (**config repo**): così un commit di
codice non è un deploy e i permessi sono separati.

### Riquadro «NEL PROGETTO VERO»

In `~/biodistretto/kubernetes` (branch `kubernetes`) il Biodistretto è **push**: è Ansible che lancia
`terraform apply`. Per portarlo in GitOps l'ostacolo vero sono **i segreti**: oggi li genera Terraform e stanno nel
tfstate; in un repo letto da Argo CD servirebbero Sealed Secrets o External Secrets.

```bash
grep -n '^resource "kubernetes_secret_v1"' terraform/app/segreti.tf
ls terraform/app/manifests        # i manifest sono già YAML, quasi pronti per una Application
```

---

## 2. Installazione di Argo CD

```bash
set -euo pipefail
kubectl config use-context lab
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

| Opzione | Perché |
|---|---|
| `use-context lab` | qui il contesto si **imposta**, non si controlla come nella `guardia_lab` delle altre lezioni |
| `--server-side` | le CRD di Argo (Application in testa) superano i **262144 byte** dell'annotation `last-applied-configuration` dell'apply classico, che fallisce con `metadata.annotations: Too long`. Il server-side apply non scrive quell'annotation |
| `--force-conflicts` | se rilanci l'installazione (aggiornamento), i campi già posseduti da un altro field manager passano ad Argo invece di dare conflitto |
| `stable` | segue l'ultima release: comodo in lab. In produzione si **fissa** la versione (`…/argo-cd/v3.6.0/manifests/install.yaml`) o il chart Helm `argo/argo-cd` con versione precisa |

Le CRD che arrivano:

```bash
kubectl get crd | grep argoproj
#   applications.argoproj.io      ← la risorsa che userai sempre
#   applicationsets.argoproj.io   ← genera Application da un modello
#   appprojects.argoproj.io       ← confini: quali repo, cluster, namespace
```

Attesa e controller:

```bash
kubectl -n argocd wait --for=condition=Available deploy --all --timeout=5m
kubectl -n argocd rollout status statefulset/argocd-application-controller
```

Il controller è uno **StatefulSet**: con tanti cluster si "shardano" le Application fra più repliche, e ogni replica
deve sapere il suo numero (identità stabile, come `mariadb-0`).

### Password, UI, CLI, login

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
kubectl port-forward svc/argocd-server -n argocd 8083:443 --address 0.0.0.0 &
```

- La password iniziale dell'utente `admin` sta in un Secret: va **cancellato** dopo aver cambiato la password
  (`argocd account update-password`).
- `--address 0.0.0.0`: la UI è raggiungibile anche dal Mac (`https://192.168.1.79:8083`); senza, solo da localhost
  dell'Ubuntu. La `&` la manda in background.

```bash
VER=$(kubectl -n argocd get deploy argocd-server \
  -o jsonpath='{.spec.template.spec.containers[0].image}' | cut -d: -f2)
curl -sSL -o ~/.local/bin/argocd \
  "https://github.com/argoproj/argo-cd/releases/download/$VER/argocd-linux-amd64"
chmod +x ~/.local/bin/argocd
```

La CLI si scarica **della stessa versione del server**, letta dal tag dell'immagine di `argocd-server`
(`cut -d: -f2` prende quello che c'è dopo i due punti). In `~/.local/bin`: niente sudo.

```bash
argocd login localhost:8083 --username admin --insecure --grpc-web --password "$(…)"
argocd cluster list
```

- `--insecure`: il certificato è autofirmato.
- `--grpc-web`: la CLI parla gRPC; gRPC-Web passa meglio attraverso port-forward e proxy HTTP/1.1.
- `cluster list` mostra `https://kubernetes.default.svc  in-cluster … Unknown "Cluster has no applications and is not
  being monitored."` — **normale** finché non c'è un'Application: Argo osserva un cluster solo se ha qualcosa da fare lì.

---

## 3. Il repository git: Gitea nel cluster

Argo CD **non riceve push: tira da git**. Senza GitHub serve un server git raggiungibile dal repo-server. Gitea: un
binario, SQLite, una UI. Le variabili che lo rendono adatto al lab:

| Variabile | Effetto |
|---|---|
| `GITEA__security__INSTALL_LOCK=true` | salta il wizard web |
| `GITEA__repository__ENABLE_PUSH_CREATE_USER=true` | il **primo push crea** il repository |
| `GITEA__repository__DEFAULT_PUSH_CREATE_PRIVATE=false` | repository pubblico: Argo legge **senza credenziali** |

### Trappola misurata: PVC hostpath + subPath su 2 nodi

Su minikube a 2 nodi, con PVC hostpath e `subPath`, il pod finito su `lab-m02` va in **CreateContainerConfigError**:

```
stat /tmp/hostpath-provisioner/gitea/gitea: no such file or directory
```

Il provisioner di minikube crea la cartella del volume **solo sul nodo primario**. Senza `subPath` il kubelet la crea da
sé; con `subPath` la vuole già esistente. Rimedi: `nodeSelector` `minikube.k8s.io/primary: "true"`, oppure niente
`subPath`.

### Installazione e primo push

```bash
kubectl apply -f gitea.yaml
kubectl -n gitea rollout status deploy/gitea
kubectl -n gitea exec deploy/gitea -- gitea admin user create \
  --username wilson --email wilson@lab.local --admin \
  --must-change-password=false --password "$GITEA_PASS"

cd mio-progetto
git init -b main && git add -A && git commit -m "mio-sito v1"
git config credential.helper "store --file ~/kubernetesprj/lavoro/argocd/.git-credentials"
git remote add origin "http://$(minikube -p lab ip):30300/wilson/mio-progetto.git"
git push -u origin main
```

- `gitea admin user create` gira **dentro** il pod (`exec deploy/gitea`): crea l'utente admin `wilson` da riga di comando.
- Le credenziali **fuori dall'URL**: un URL con la password finisce nei log e in `.git/config`. `credential.helper store`
  in un file con permessi 600.
- `minikube -p lab ip` + NodePort `30300`: l'indirizzo dall'esterno del cluster.

### Due indirizzi per lo stesso repository

| Chi | URL |
|---|---|
| tu, fuori dal cluster | `http://192.168.49.2:30300/…` (NodePort) |
| Argo, dentro il cluster | `http://gitea.gitea.svc.cluster.local:3000/…` (DNS del Service) |

La prova che Argo lo vede, **dal repo-server stesso**:

```bash
kubectl -n argocd exec deploy/argocd-repo-server -- \
  git ls-remote http://gitea.gitea.svc.cluster.local:3000/wilson/mio-progetto.git
```

Se risponde con gli hash dei ref, rete, DNS e permessi vanno.

Repository **privato** (GitHub/GitLab veri): si registra con le credenziali, che Argo salva in un Secret con
l'etichetta `argocd.argoproj.io/secret-type: repository`:

```bash
argocd repo add https://github.com/TUO-UTENTE/mio-progetto.git --username TUO-UTENTE --password <token in sola lettura>
argocd repo add git@github.com:TUO-UTENTE/mio-progetto.git --ssh-private-key-path ~/.ssh/deploy_key
```

La deploy key è in **sola lettura**: Argo non deve poter scrivere nel repo.

---

## 4. L'immagine e Terraform: ciò che Argo CD non fa

### Il Dockerfile

```dockerfile
FROM nginx:1.29-alpine
ARG VERSIONE=v1
COPY index.html /usr/share/nginx/html/index.html
RUN sed -i "s/__VERSIONE__/${VERSIONE}/g" /usr/share/nginx/html/index.html
```

La versione entra **al build** (`--build-arg`) e sostituisce il segnaposto `__VERSIONE__` nella pagina: così con
`curl` vedi quale immagine risponde.

```bash
docker build --build-arg VERSIONE=v1 -t mio-sito:v1 sito
minikube -p lab image load mio-sito:v1
minikube -p lab addons enable ingress
```

Il docker dell'Ubuntu e i nodi minikube hanno **archivi di immagini separati**. `image load` copia l'immagine in
**ogni** nodo del profilo (verificato su `lab` e `lab-m02`). Nel Deployment serve `imagePullPolicy: IfNotPresent`,
altrimenti il kubelet prova a scaricarla da Docker Hub e va in **ErrImagePull**.

### Terraform (estratto di `main.tf`)

```hcl
provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "lab"              # mai il contesto "corrente"
}
resource "kubernetes_namespace_v1" "sito" {
  metadata { name = "mio-sito"  labels = { "gestito-da" = "terraform" } }
}
resource "kubernetes_resource_quota_v1" "sito" {
  spec { hard = { pods = "6", "requests.cpu" = "500m", … } }
}
resource "kubernetes_limit_range_v1" "sito" { … default per container … }
```

- `config_context = "lab"` fissato: Terraform non deve dipendere da quale contesto è attivo in quel momento.
- La quota `pods = "6"` sarà la protagonista del punto 9.
- Il LimitRange dà i **default** di requests/limits ai container: con una quota su `requests.cpu`, un Pod senza
  requests verrebbe rifiutato (lezione 18).

```bash
cd terraform
terraform init && terraform fmt -check && terraform validate
terraform plan        # 3 to add
terraform apply -auto-approve
```

`plan` dice **3 to add**: namespace, quota, LimitRange. `terraform.tfstate` e `.terraform/` **fuori** da git
(`.gitignore`); `.terraform.lock.hcl` **dentro** git: fissa la versione esatta del provider.

**Chi possiede il namespace?** Terraform. L'Application ha comunque `CreateNamespace=true`: se il namespace c'è già non
fa niente. Ma se lo lasciassi creare ad Argo, **non** metterlo anche in Terraform: due padroni dello stesso oggetto si
correggono a vicenda per sempre.

---

## 5. L'Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: mio-sito
  namespace: argocd            # le Application vivono nel namespace di Argo
spec:
  project: default             # AppProject: limita repo/cluster/namespace
  source:
    repoURL: http://gitea.gitea.svc.cluster.local:3000/wilson/mio-progetto.git
    targetRevision: HEAD       # ramo di default; o "main", un tag, uno SHA
    path: kubernetes           # SOLO questa cartella
  destination:
    server: https://kubernetes.default.svc   # il cluster dove gira Argo
    namespace: mio-sito        # dove finiscono gli oggetti senza namespace
  syncPolicy:
    automated:
      selfHeal: true           # una modifica a mano nel cluster viene annullata
      prune: false             # un file tolto da git NON cancella l'oggetto
    syncOptions:
      - CreateNamespace=true
```

| Campo | Perché |
|---|---|
| `metadata.namespace: argocd` | le Application vivono nel namespace di Argo, non in quello dell'app |
| `project: default` | l'AppProject decide quali repo, cluster e namespace sono permessi |
| `repoURL` | l'URL **interno** di Gitea (DNS del Service), non il NodePort |
| `targetRevision: HEAD` | il ramo di default; può essere `main`, un tag, uno SHA |
| `path: kubernetes` | solo questa cartella diventa manifest |
| `destination.server` | `https://kubernetes.default.svc` = il cluster dove gira Argo stesso |
| `destination.namespace` | dove finiscono gli oggetti che non dichiarano un namespace |
| `automated` | sync automatico a ogni cambio in git |
| `selfHeal: true` | le modifiche a mano nel cluster vengono annullate |
| `prune: false` | togliere un file da git **non** cancella l'oggetto |

È **l'unico `kubectl apply` del sito**: da qui in poi lo fa Argo leggendo git. Anche l'Application si può tenere in git
e farla applicare a un'altra Application: il pattern **app of apps**.

```bash
argocd app wait mio-sito --sync --health --timeout 180
argocd app get mio-sito
curl -s -H 'Host: mio-sito.local' "http://$(minikube -p lab ip)/"
#   versione: v1
```

### Due stati diversi, da non confondere

| Stato | Valori | Domanda |
|---|---|---|
| **Sync Status** | Synced / OutOfSync | il cluster è uguale a git? |
| **Health Status** | Healthy / Progressing / Degraded / Missing / Suspended | quello che c'è funziona? |

- **Synced + Degraded** = hai applicato fedelmente una cosa rotta (la quota del punto 9).
- **OutOfSync + Healthy** = funziona, ma non è quello che dice git (qualcuno ha toccato il cluster, o il sync non è
  ancora partito).

### Come Argo riconosce i suoi oggetti

Da Argo CD 3.0 con un'**annotation** (prima era la label `app.kubernetes.io/instance`, che Helm e altri tool usano già
per conto loro e creava conflitti):

```bash
kubectl -n mio-sito get deploy mio-sito \
  -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/tracking-id}'
#   mio-sito:apps/Deployment:mio-sito/mio-sito
```

Formato: `<app>:<gruppo>/<Kind>:<namespace>/<nome>`. Nel jsonpath i punti del nome dell'annotation si scappano con `\.`.

---

## 6. Self-heal: il cluster non si cambia con kubectl

```bash
kubectl -n mio-sito scale deploy mio-sito --replicas=5
sleep 15
kubectl -n mio-sito get deploy mio-sito
#   READY 2/2 — misurato: tornato alle 2 di git in meno di 15 secondi.
```

Il controller **osserva il cluster** (watch), quindi la deriva la vede subito. È **git** che invece controlla solo a
intervalli (punto 7).

Cosa selfHeal **non** corregge: i campi che Argo non gestisce. E un **HPA** che cambia `spec.replicas` litiga con Argo,
a meno di togliere `replicas` dal manifest o di dirgli di ignorarle:

```yaml
spec:
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers: [/spec/replicas]
  syncPolicy:
    syncOptions: [RespectIgnoreDifferences=true]
```

---

## 7. Nuova versione = un commit

```bash
docker build --build-arg VERSIONE=v2 -t mio-sito:v2 sito
minikube -p lab image load mio-sito:v2
sed -i 's/mio-sito:v1/mio-sito:v2/; s/replicas: 2/replicas: 3/' kubernetes/deployment.yaml
git commit -am "mio-sito v2, 3 repliche" && git push
argocd app get mio-sito --refresh          # rilegge git adesso
argocd app wait mio-sito --sync --health
curl -s -H 'Host: mio-sito.local' "http://$(minikube -p lab ip)/"
#   versione: v2   (3 pod)
argocd app history mio-sito        # ogni riga = una revisione git applicata
```

**Quando se ne accorge Argo?** Il controller ricontrolla git ogni `timeout.reconciliation` (**120 s**) + un jitter fino
a **60 s**: fra 2 e 3 minuti. Per non aspettare: `--refresh`. In produzione: un **webhook** dal server git a
`https://<argocd>/api/webhook` (GitHub, GitLab, Bitbucket, Gogs/Gitea), e il refresh parte al push.

**Tag immutabili**: `mio-sito:v2`, o lo SHA del commit. Con `latest` git non cambia, Argo non vede differenze e il
cluster resta sulla vecchia immagine: GitOps funziona solo se **ogni versione ha un nome diverso**. Chi aggiorna il tag
in git? La CI (un commit automatico dopo il build) o **Argo CD Image Updater**, che guarda il registry e scrive in git.

---

## 8. Rollback = git revert

```bash
argocd app rollback mio-sito 1
#   FailedPrecondition: rollback cannot be initiated when auto-sync is enabled
```

**Fallisce apposta.** Giusto così: il cluster tornerebbe indietro, git direbbe ancora v2 e al giro successivo
l'auto-sync rimetterebbe v2. Si torna indietro **in git**:

```bash
git revert --no-edit HEAD && git push
argocd app get mio-sito --refresh && argocd app wait mio-sito --sync --health
#   versione: v1, 2 pod — e git log dice chi è tornato indietro e perché.
```

---

## 9. Prune: cosa succede quando togli un file da git

```bash
git rm kubernetes/ingress.yaml && git commit -m "via ingress" && git push
argocd app get mio-sito --refresh
#   Sync Status: OutOfSync
#   Ingress mio-sito  OutOfSync  … (requires pruning)
kubectl -n mio-sito get ingress          # c'è ancora: prune: false
argocd app sync mio-sito --prune         # pruning manuale, deciso da te
kubectl -n mio-sito get ingress          # No resources found
git revert --no-edit HEAD && git push    # torna da solo
```

- Con `prune: false` l'Ingress resta, e l'Application diventa **OutOfSync** con la dicitura `requires pruning`.
- `sync --prune` è il pruning **manuale**: lo decidi tu.
- Il revert rimette il file in git e l'Ingress **torna da solo** (sync automatico).

`prune: false` è il default prudente: un errore in git (cartella spostata, path sbagliato) non cancella la produzione.
Con `prune: true` togliere un file **toglie l'oggetto** dal cluster: più pulito, più pericoloso.

- Paracadute: se git diventasse **vuoto**, Argo si rifiuta di cancellare tutto finché non metti
  `automated.allowEmpty: true`.
- Per un singolo oggetto che non deve **mai** sparire (un PVC con i dati):
  `metadata.annotations: argocd.argoproj.io/sync-options: Prune=false`.

---

## 10. Terraform e Argo CD insieme: la quota vale anche per Argo

```bash
sed -i 's/replicas: 2/replicas: 8/' kubernetes/deployment.yaml
git commit -am "8 repliche" && git push && argocd app get mio-sito --refresh
kubectl -n mio-sito get deploy mio-sito
#   READY 6/8
kubectl -n mio-sito get events --field-selector reason=FailedCreate
#   exceeded quota: quota, requested: pods=1, used: pods=6, limited: pods=6
git revert --no-edit HEAD && git push
```

Argo ha applicato **fedelmente** git (**Synced**), Kubernetes ha **rifiutato** oltre la quota messa da Terraform: i
limiti dell'infrastruttura valgono per chiunque deployi, Argo compreso. Il Deployment resta **Progressing** e diventa
**Degraded** dopo `progressDeadlineSeconds` (600 s). È il caso **Synced + Degraded**: la correzione è un commit (qui il
revert), non un `kubectl`.

`--field-selector reason=FailedCreate` filtra gli eventi del ReplicaSet che non riesce a creare i Pod.

---

## 11. Adottare quello che c'è già

Non serve ricostruire niente: lo stack HAProxy → nginx → PHP → Redis + MariaDB (`~/kubernetesprj/stack/stack.yaml`)
entra in git sotto `stack/` e una **seconda Application** lo prende in carico:

```yaml
spec.source.path: stack
spec.destination.namespace: stack-web
spec.syncPolicy.automated: { selfHeal: true, prune: true }
```

Se gli oggetti esistono già, Argo li **adotta** (aggiunge l'annotation di tracking) invece di ricrearli; MariaDB tiene
il suo PVC.

```bash
argocd app list
#   argocd/mio-sito   … Synced Healthy Auto
#   argocd/stack-web  … Synced Healthy Auto-Prune
```

La colonna finale dice la politica: `Auto` (senza prune) contro `Auto-Prune`.

---

## 12. Pulizia

```bash
kubectl -n argocd delete application mio-sito stack-web
(cd terraform && terraform destroy -auto-approve)  # il namespace è suo
kubectl delete ns stack-web gitea
kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl delete ns argocd
```

- Cancellare un'Application **non cancella i suoi oggetti**, a meno che abbia il finalizer
  `resources-finalizer.argocd.argoproj.io` (allora sì, a cascata).
- Il namespace `mio-sito` lo toglie **Terraform**, perché è suo: un padrone, un oggetto.

---

## 13. Trappole

- **`kubectl apply` classico sulle CRD di Argo** → `metadata.annotations: Too long`: serve `--server-side`.
- **CLI di versione diversa dal server**: si scarica quella del tag dell'immagine.
- **Repo privato non registrato**: il repo-server non clona; prova con `git ls-remote` dal repo-server.
- **subPath + hostpath su minikube multi-nodo** → CreateContainerConfigError sul nodo non primario.
- **Immagine solo nel docker dell'host** → ErrImagePull: `minikube image load` e `imagePullPolicy: IfNotPresent`.
- **Tag `latest`**: git non cambia, Argo non vede niente.
- **`argocd app rollback` con auto-sync** → FailedPrecondition. Si usa `git revert`.
- **HPA + `replicas` nel manifest**: Argo e HPA litigano; `ignoreDifferences` o togli `replicas`.
- **Due padroni** (Terraform e Argo) per lo stesso oggetto: si correggono all'infinito.
- **Cancellare l'Application** lascia gli oggetti, senza il finalizer.

---

## 14. Domande da colloquio

- **Argo CD contro una pipeline che fa `helm upgrade`?** Direzione e continuità. La pipeline **spinge** una volta, con
  le credenziali del cluster fuori dal cluster; Argo **tira** da git e riconcilia sempre: vede la deriva, la corregge
  (selfHeal) o la segnala (OutOfSync). Git diventa l'unica fonte di verità e l'audit log.
- **Synced ma Degraded?** Il cluster è identico a git, e git descrive una cosa che non funziona (immagine inesistente,
  quota superata, probe sbagliata). La correzione è un commit, non un `kubectl`.
- **Perché `argocd app rollback` non funziona?** Con il sync automatico è vietato (FailedPrecondition): git direbbe
  ancora la versione nuova e il giro dopo la rimetterebbe. Con il sync manuale il rollback è permesso, e lascia
  l'Application OutOfSync finché non sistemi git.
- **Ho fatto push ma Argo non ha deployato. Dove guardi?** 1) è passato il polling (2–3 min) o serve `--refresh` /
  webhook? 2) `argocd app get`: la revisione è quella nuova? Se no, `targetRevision` o `path` puntano altrove. 3) il
  repo-server raggiunge git (credenziali, DNS)? `argocd repo list`. 4) è cambiato un file **dentro** `spec.source.path`?
  5) il tag dell'immagine è cambiato davvero, o è sempre `latest`?
- **`prune: true` o `false`?** `false` è prudente (niente cancellazioni, ma oggetti orfani da pulire a mano); `true`
  tiene il cluster pulito ma un path sbagliato può cancellare molto. Spesso: `true` con `allowEmpty` false e
  `Prune=false` sugli oggetti con dati (PVC).
- **Secret in un repo GitOps?** Mai in chiaro. Sealed Secrets (cifrati con la chiave del cluster), SOPS (+ plugin o
  KSOPS), o External Secrets Operator che li legge da Vault / un secret manager: in git c'è solo il riferimento.
- **Terraform e Argo CD: dove passa il confine?** Terraform per ciò che ha un ciclo di vita lungo e sta "sotto" le app
  (rete, cluster, database gestiti, namespace con quote, l'installazione stessa di Argo); Argo per ciò che cambia a ogni
  rilascio. Un oggetto ha **un** padrone.
- **Molti ambienti o molti cluster?** Kustomize overlay per ambiente (lezione 11) e un'Application per ambiente;
  ApplicationSet per generarle da un modello (generatori list, cluster, git directory); AppProject per limitare cosa
  ogni team può deployare e dove.

### Comandi da sapere

| Comando | A cosa serve |
|---|---|
| `kubectl apply --server-side --force-conflicts -f install.yaml` | installare/aggiornare Argo CD |
| `argocd app get <app> --refresh` | rilegge git adesso |
| `argocd app wait <app> --sync --health` | aspetta che sia Synced e Healthy |
| `argocd app history <app>` | le revisioni git applicate |
| `argocd app sync <app> --prune` | sync con pruning manuale |
| `argocd app list` | tutte le Application con stato e politica |
| `kubectl -n argocd exec deploy/argocd-repo-server -- git ls-remote <url>` | il repo-server vede il repo? |
| `kubectl get events --field-selector reason=FailedCreate` | Pod rifiutati (quota) |

---

## Riepilogo

- Terraform = **dove** (namespace, quote); git = **cosa**; Argo CD = che il cluster lo rispetti, sempre. La CI
  costruisce solo l'immagine.
- Install: `--server-side` (CRD grandi); CLI della stessa versione; tracking per annotation da Argo CD 3.0.
- Sync Status (uguale a git?) ≠ Health Status (funziona?).
- selfHeal annulla le modifiche a mano; prune decide se un file tolto da git toglie l'oggetto; polling 2–3 min,
  `--refresh` o webhook.
- Nuova versione = commit con un tag nuovo; rollback = `git revert`.
- Gitea nel cluster: due URL (NodePort per te, DNS del Service per Argo).

## Prova da solo

1. Con l'Application sincronizzata, cambia a mano l'immagine del Deployment
   (`kubectl -n mio-sito set image deploy/mio-sito <container>=mio-sito:v2`) e misura con `get deploy -w` quanto ci
   mette selfHeal a rimettere quella di git.
2. Aggiungi all'Application `ignoreDifferences` su `/spec/replicas` con `RespectIgnoreDifferences=true`, poi rifai lo
   `scale --replicas=5` del punto 6: questa volta resta a 5? Che Sync Status mostra `argocd app get`?
3. Togli `selfHeal` e `automated` (sync manuale), fai un commit v2 e poi prova `argocd app rollback mio-sito 1`: ora
   passa? In che Sync Status resta l'Application rispetto a git?
