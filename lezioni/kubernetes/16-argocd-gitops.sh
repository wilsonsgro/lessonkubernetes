#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# 16. ARGO CD: GITOPS SUL TUO SITO, IN LOCALE
#     TERRAFORM + MINIKUBE + KUBERNETES + ARGO CD + GIT (GITEA)
# Versione: Argo CD 3.6 · Gitea 1.24 · Terraform 1.x (provider kubernetes 2.38)
# Livello: 6 — Laboratorio completo
# ═══════════════════════════════════════════════════════════════════════════
# La lezione 12 ha installato Argo CD e gli ha dato il repository di esempio
# (guestbook su GitHub). Qui Argo CD gestisce il TUO progetto: un sito con
# Dockerfile, i suoi manifest, l'infrastruttura in Terraform. Tutto sul
# cluster minikube "lab" dell'Ubuntu, senza AWS, Azure o cluster remoti:
# anche il server git gira dentro il cluster.
#
# Laboratorio guidato, passo per passo:  ~/kubernetesprj/argocd/01…05
# (sull'Ubuntu 192.168.1.79). Questo file è la lezione: gli stessi comandi,
# con il perché.
#
# ── CHI FA COSA ────────────────────────────────────────────────────────────
#
#   Terraform    crea le risorse INFRASTRUTTURALI: il terreno su cui l'app
#                atterra (qui: namespace, ResourceQuota, LimitRange; in
#                cloud: rete, cluster, database gestiti)
#   minikube     esegue il cluster Kubernetes locale
#   Kubernetes   gestisce i container del sito (Deployment, Service, Ingress)
#   Argo CD      legge git e tiene il cluster UGUALE a quello che c'è scritto
#   la CI        costruisce l'immagine (qui: docker build a mano)
#
#   La frase da colloquio: Terraform dice DOVE, git dice COSA, Argo CD fa sì
#   che il cluster lo rispetti — continuamente, non solo al deploy.
#
# ── PUSH CONTRO PULL ───────────────────────────────────────────────────────
#
#   CI/CD classica (push)              GitOps (pull)
#   ─────────────────────              ─────────────
#   la pipeline fa kubectl/helm        la pipeline fa SOLO commit in git
#   la CI ha le credenziali del        le credenziali restano DENTRO il
#   cluster                            cluster (Argo CD)
#   il cluster può divergere da git    Argo CD confronta di continuo e
#   senza che nessuno se ne accorga    corregge (selfHeal) o segnala
#   rollback = rilanciare un job       rollback = git revert
#   chi ha cambiato cosa: log CI       chi ha cambiato cosa: git log
#
# ── ARCHITETTURA ───────────────────────────────────────────────────────────
#
#   tu (Ubuntu) ── git push ──► Gitea  (namespace gitea, NodePort 30300)
#                                 ▲
#                                 │ git fetch ogni 2–3 minuti (o --refresh)
#                                 │
#   ┌─────────── namespace argocd ┴──────────────────────────────────┐
#   │  argocd-repo-server        clona il repo, genera i manifest    │
#   │                            (YAML, Kustomize, Helm)             │
#   │  argocd-application-       confronta desiderato (git) e        │
#   │  controller                attuale (cluster), sincronizza      │
#   │  argocd-server             API + UI  (port-forward → :8083)    │
#   │  redis, dex, notifications-controller, applicationset-controller│
#   └────────────────────────────┬───────────────────────────────────┘
#                                │ kubectl apply (server-side)
#                                ▼
#   namespace mio-sito  ← creato da TERRAFORM (quota: max 6 pod)
#     Deployment mio-sito (immagine mio-sito:v1) → Service → Ingress
#                                                  host: mio-sito.local
#
# ── IL PROGETTO ────────────────────────────────────────────────────────────
#
#   mio-progetto/
#   ├── terraform/     main.tf, variables.tf        namespace + quota + limiti
#   ├── kubernetes/    deployment, service, ingress quello che Argo applica
#   ├── sito/          Dockerfile, index.html       l'immagine
#   └── argocd/        application.yaml             cosa deve guardare Argo
#
#   Argo guarda SOLO la cartella "kubernetes" (spec.source.path): un commit
#   su terraform/ o sito/ non cambia niente nel cluster. In un'azienda vera
#   spesso i manifest stanno in un repository a parte ("config repo"), così
#   un commit di codice non è un deploy e i permessi sono separati.
#
# ── NEL PROGETTO VERO: il Biodistretto su minikube ───────────────────────
#   ~/biodistretto/kubernetes (branch kubernetes). I grep partono da lì:
#   cd ~/biodistretto/kubernetes · come si usa: il README della cartella
#   Il Biodistretto è push: è Ansible che lancia terraform apply. Per
#   portarlo in GitOps con Argo CD, l'ostacolo vero sono i segreti: oggi li
#   genera Terraform e stanno nel tfstate. In un repo letto da Argo CD
#   servirebbero Sealed Secrets o External Secrets.
#     grep -n '^resource "kubernetes_secret_v1"' terraform/app/segreti.tf
#   I manifest invece sono già YAML, quasi pronti per una Application:
#     ls terraform/app/manifests

set -euo pipefail
kubectl config use-context lab

# ══════════════════════════════════════════════════════════════════════════
# 1. INSTALLAZIONE
# ══════════════════════════════════════════════════════════════════════════

kubectl create namespace argocd

# --server-side: le CRD di Argo (Application in testa) superano i 262144
#   byte dell'annotation last-applied-configuration usata dall'apply
#   classico, che fallisce con "metadata.annotations: Too long".
# --force-conflicts: se rilanci l'installazione (aggiornamento), i campi
#   già posseduti da un altro field manager passano ad Argo invece di dare
#   conflitto.
kubectl apply -n argocd \
  --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# "stable" segue l'ultima release: comodo in laboratorio. In produzione si
# fissa la versione (…/argo-cd/v3.6.0/manifests/install.yaml) o il chart
# Helm argo/argo-cd con una versione precisa, e si aggiorna di proposito.

kubectl get crd | grep argoproj
#   applications.argoproj.io      ← la risorsa che userai sempre
#   applicationsets.argoproj.io   ← genera Application da un modello
#   appprojects.argoproj.io       ← confini: quali repo, cluster, namespace

kubectl -n argocd wait --for=condition=Available deploy --all --timeout=5m
kubectl -n argocd rollout status statefulset/argocd-application-controller
# Il controller è uno StatefulSet: con tanti cluster si "shardano" le
# Application fra più repliche, e ogni replica deve sapere il suo numero.

# Password iniziale (utente admin). Il Secret va cancellato dopo aver
# cambiato la password: argocd account update-password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo

# UI e API. --address 0.0.0.0 la rende raggiungibile anche dal Mac
# (https://192.168.1.79:8083); senza, solo da localhost dell'Ubuntu.
kubectl port-forward svc/argocd-server -n argocd 8083:443 --address 0.0.0.0 &

# CLI della STESSA versione del server, in ~/.local/bin (niente sudo)
VER=$(kubectl -n argocd get deploy argocd-server \
  -o jsonpath='{.spec.template.spec.containers[0].image}' | cut -d: -f2)
curl -sSL -o ~/.local/bin/argocd \
  "https://github.com/argoproj/argo-cd/releases/download/$VER/argocd-linux-amd64"
chmod +x ~/.local/bin/argocd

# --insecure: certificato autofirmato · --grpc-web: la CLI parla gRPC, e
# gRPC-Web passa meglio attraverso port-forward e proxy HTTP/1.1
argocd login localhost:8083 --username admin --insecure --grpc-web \
  --password "$(kubectl -n argocd get secret argocd-initial-admin-secret \
                -o jsonpath='{.data.password}' | base64 -d)"
argocd cluster list
#   https://kubernetes.default.svc  in-cluster  … Unknown  "Cluster has no
#   applications and is not being monitored."  ← normale finché non c'è
#   una Application: Argo osserva un cluster solo se ha qualcosa da fare lì.

# ══════════════════════════════════════════════════════════════════════════
# 2. IL REPOSITORY GIT (GITEA NEL CLUSTER)
# ══════════════════════════════════════════════════════════════════════════
# Argo CD non riceve push: TIRA da git. Senza GitHub serve un server git
# raggiungibile dal repo-server. Gitea: un binario, SQLite, una UI.
#
# Variabili che lo rendono adatto al laboratorio:
#   GITEA__security__INSTALL_LOCK=true                 salta il wizard web
#   GITEA__repository__ENABLE_PUSH_CREATE_USER=true    il primo push crea
#                                                      il repository
#   GITEA__repository__DEFAULT_PUSH_CREATE_PRIVATE=false  pubblico: Argo
#                                                      legge senza credenziali
#
# TRAPPOLA misurata su minikube a 2 nodi: PVC hostpath + subPath, pod finito
# su lab-m02 → CreateContainerConfigError "stat /tmp/hostpath-provisioner/
# gitea/gitea: no such file or directory". Il provisioner di minikube crea la
# cartella del volume solo sul nodo PRIMARIO; senza subPath il kubelet la
# crea da sé (MariaDB della lezione 15/stack gira su m02 senza problemi),
# con subPath la vuole già esistente. Rimedio: nodeSelector
# minikube.k8s.io/primary: "true", oppure niente subPath.

kubectl apply -f gitea.yaml
kubectl -n gitea rollout status deploy/gitea
kubectl -n gitea exec deploy/gitea -- gitea admin user create \
  --username wilson --email wilson@lab.local --admin \
  --must-change-password=false --password "$GITEA_PASS"

cd mio-progetto
git init -b main && git add -A && git commit -m "mio-sito v1"
# Credenziali fuori dall'URL (un URL con password finisce nei log e in
# .git/config): credential.helper store in un file 600
git config credential.helper "store --file ~/kubernetesprj/lavoro/argocd/.git-credentials"
git remote add origin "http://$(minikube -p lab ip):30300/wilson/mio-progetto.git"
git push -u origin main

# DUE indirizzi per lo stesso repository:
#   da te (fuori dal cluster):  http://192.168.49.2:30300/…   (NodePort)
#   da Argo (dentro):           http://gitea.gitea.svc.cluster.local:3000/…
# La prova che Argo lo vede, dal repo-server stesso:
kubectl -n argocd exec deploy/argocd-repo-server -- \
  git ls-remote http://gitea.gitea.svc.cluster.local:3000/wilson/mio-progetto.git

# Repository PRIVATO (GitHub/GitLab veri): si registra con le credenziali,
# che Argo salva in un Secret con l'etichetta
# argocd.argoproj.io/secret-type: repository
#   argocd repo add https://github.com/TUO-UTENTE/mio-progetto.git \
#     --username TUO-UTENTE --password <token in sola lettura>
#   argocd repo add git@github.com:TUO-UTENTE/mio-progetto.git \
#     --ssh-private-key-path ~/.ssh/deploy_key      ← deploy key, sola lettura

# ══════════════════════════════════════════════════════════════════════════
# 3. L'IMMAGINE E TERRAFORM: CIÒ CHE ARGO CD NON FA
# ══════════════════════════════════════════════════════════════════════════

# Dockerfile del sito: nginx + una pagina; la versione entra al build
#   FROM nginx:1.29-alpine
#   ARG VERSIONE=v1
#   COPY index.html /usr/share/nginx/html/index.html
#   RUN sed -i "s/__VERSIONE__/${VERSIONE}/g" /usr/share/nginx/html/index.html
docker build --build-arg VERSIONE=v1 -t mio-sito:v1 sito

# Il docker dell'Ubuntu e i nodi minikube hanno archivi di immagini
# SEPARATI. image load copia l'immagine in OGNI nodo del profilo (verificato
# su lab e lab-m02). Nel deployment: imagePullPolicy: IfNotPresent, altrimenti
# il kubelet prova a scaricarla da Docker Hub e va in ErrImagePull.
minikube -p lab image load mio-sito:v1

minikube -p lab addons enable ingress     # serve per ingress.yaml

# terraform/main.tf (estratto)
#   provider "kubernetes" {
#     config_path    = "~/.kube/config"
#     config_context = "lab"              ← mai il contesto "corrente"
#   }
#   resource "kubernetes_namespace_v1" "sito" {
#     metadata { name = "mio-sito"  labels = { "gestito-da" = "terraform" } }
#   }
#   resource "kubernetes_resource_quota_v1" "sito" {
#     spec { hard = { pods = "6", "requests.cpu" = "500m", … } }
#   }
#   resource "kubernetes_limit_range_v1" "sito" { … default per container … }
cd terraform
terraform init && terraform fmt -check && terraform validate
terraform plan        # 3 to add
terraform apply -auto-approve
# terraform.tfstate e .terraform/ fuori da git (.gitignore);
# .terraform.lock.hcl DENTRO git: fissa la versione esatta del provider.
cd ..

# Chi possiede il namespace? Terraform. L'Application ha comunque
# CreateNamespace=true: se il namespace c'è già non fa niente. Se invece lo
# lasciassi creare ad Argo, NON metterlo anche in Terraform: due padroni
# dello stesso oggetto si correggono a vicenda per sempre.

# ══════════════════════════════════════════════════════════════════════════
# 4. L'APPLICATION
# ══════════════════════════════════════════════════════════════════════════
kubectl apply -f - <<'EOF'
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
EOF
# È l'unico kubectl apply del sito: da qui in poi lo fa Argo leggendo git.
# (Anche l'Application si può tenere in git e farla applicare a un'altra
# Application: il pattern "app of apps".)

argocd app wait mio-sito --sync --health --timeout 180
argocd app get mio-sito

# DUE STATI DIVERSI, da non confondere:
#   Sync Status    Synced / OutOfSync   il cluster è uguale a git?
#   Health Status  Healthy / Progressing / Degraded / Missing / Suspended
#                                       quello che c'è funziona?
#   Synced + Degraded = hai applicato fedelmente una cosa rotta (vedi la
#   quota al punto 8). OutOfSync + Healthy = funziona, ma non è quello che
#   dice git (qualcuno ha toccato il cluster, o il sync non è ancora partito).

curl -s -H 'Host: mio-sito.local' "http://$(minikube -p lab ip)/"
#   versione: v1

# Come Argo riconosce i SUOI oggetti: da Argo CD 3.0 con un'annotation
# (prima era la label app.kubernetes.io/instance, che Helm e altri tool
# usano già per conto loro e creava conflitti):
kubectl -n mio-sito get deploy mio-sito \
  -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/tracking-id}'
#   mio-sito:apps/Deployment:mio-sito/mio-sito

# ══════════════════════════════════════════════════════════════════════════
# 5. SELF-HEAL: IL CLUSTER NON SI CAMBIA CON KUBECTL
# ══════════════════════════════════════════════════════════════════════════
kubectl -n mio-sito scale deploy mio-sito --replicas=5
sleep 15
kubectl -n mio-sito get deploy mio-sito
#   READY 2/2 — misurato: tornato alle 2 di git in meno di 15 secondi.
# Il controller osserva il cluster (watch), quindi la deriva la vede subito;
# è git che invece controlla solo a intervalli (punto 6).
#
# Cosa selfHeal NON corregge: i campi che Argo non gestisce. Un HPA che
# cambia spec.replicas litiga con Argo, a meno di togliere replicas dal
# manifest o di dirgli di ignorarle:
#   spec:
#     ignoreDifferences:
#       - group: apps
#         kind: Deployment
#         jsonPointers: [/spec/replicas]
#     syncPolicy:
#       syncOptions: [RespectIgnoreDifferences=true]

# ══════════════════════════════════════════════════════════════════════════
# 6. NUOVA VERSIONE = UN COMMIT
# ══════════════════════════════════════════════════════════════════════════
docker build --build-arg VERSIONE=v2 -t mio-sito:v2 sito
minikube -p lab image load mio-sito:v2

sed -i 's/mio-sito:v1/mio-sito:v2/; s/replicas: 2/replicas: 3/' kubernetes/deployment.yaml
git commit -am "mio-sito v2, 3 repliche" && git push

# Quando se ne accorge Argo? Il controller ricontrolla git ogni
# timeout.reconciliation (120 s) + un jitter fino a 60 s: fra 2 e 3 minuti.
# Per non aspettare:
argocd app get mio-sito --refresh          # rilegge git adesso
argocd app wait mio-sito --sync --health
# In produzione: un WEBHOOK dal server git a https://<argocd>/api/webhook
# (GitHub, GitLab, Bitbucket, Gogs/Gitea), e il refresh parte al push.

curl -s -H 'Host: mio-sito.local' "http://$(minikube -p lab ip)/"
#   versione: v2   (3 pod)
argocd app history mio-sito        # ogni riga = una revisione git applicata

# Tag immutabili: mio-sito:v2, o lo SHA del commit. Con "latest" git non
# cambia, Argo non vede differenze e il cluster resta sulla vecchia
# immagine: GitOps funziona solo se OGNI versione ha un nome diverso.
# Chi aggiorna il tag in git? La CI (un commit automatico dopo il build) o
# Argo CD Image Updater, che guarda il registry e scrive in git per te.

# ══════════════════════════════════════════════════════════════════════════
# 7. ROLLBACK = GIT REVERT
# ══════════════════════════════════════════════════════════════════════════
argocd app rollback mio-sito 1
#   FailedPrecondition: rollback cannot be initiated when auto-sync is enabled
# Giusto così: il cluster tornerebbe indietro, git direbbe ancora v2 e al
# giro successivo l'auto-sync rimetterebbe v2. Si torna indietro in GIT:
git revert --no-edit HEAD && git push
argocd app get mio-sito --refresh && argocd app wait mio-sito --sync --health
#   versione: v1, 2 pod — e git log dice chi è tornato indietro e perché.

# ══════════════════════════════════════════════════════════════════════════
# 8. PRUNE: COSA SUCCEDE QUANDO TOGLI UN FILE DA GIT
# ══════════════════════════════════════════════════════════════════════════
git rm kubernetes/ingress.yaml && git commit -m "via ingress" && git push
argocd app get mio-sito --refresh
#   Sync Status: OutOfSync
#   Ingress mio-sito  OutOfSync  … (requires pruning)
kubectl -n mio-sito get ingress          # c'è ancora: prune: false
argocd app sync mio-sito --prune         # pruning manuale, deciso da te
kubectl -n mio-sito get ingress          # No resources found
git revert --no-edit HEAD && git push    # torna da solo
#
# prune: false è il default prudente: un errore in git (cartella spostata,
# path sbagliato) non cancella la produzione. Con prune: true togliere un
# file da git TOGLIE l'oggetto dal cluster — più pulito, più pericoloso.
# Paracadute: se git diventasse vuoto, Argo si rifiuta di cancellare tutto
# finché non metti automated.allowEmpty: true.
# Per un singolo oggetto che non deve MAI sparire (un PVC con i dati):
#   metadata.annotations: argocd.argoproj.io/sync-options: Prune=false

# ══════════════════════════════════════════════════════════════════════════
# 9. TERRAFORM E ARGO CD INSIEME: LA QUOTA VALE ANCHE PER ARGO
# ══════════════════════════════════════════════════════════════════════════
sed -i 's/replicas: 2/replicas: 8/' kubernetes/deployment.yaml
git commit -am "8 repliche" && git push && argocd app get mio-sito --refresh
kubectl -n mio-sito get deploy mio-sito
#   READY 6/8
kubectl -n mio-sito get events --field-selector reason=FailedCreate
#   exceeded quota: quota, requested: pods=1, used: pods=6, limited: pods=6
# Argo ha applicato fedelmente git (Synced), Kubernetes ha rifiutato oltre
# la quota messa da Terraform: i limiti dell'infrastruttura valgono per
# chiunque deployi, Argo compreso. Il Deployment resta Progressing e
# diventa Degraded dopo progressDeadlineSeconds (600 s).
git revert --no-edit HEAD && git push

# ══════════════════════════════════════════════════════════════════════════
# 10. ADOTTARE QUELLO CHE C'È GIÀ
# ══════════════════════════════════════════════════════════════════════════
# Non serve ricostruire niente: lo stack HAProxy → nginx → PHP → Redis +
# MariaDB (~/kubernetesprj/stack/stack.yaml) entra in git sotto stack/ e
# una seconda Application lo prende in carico. Se gli oggetti esistono
# già, Argo li ADOTTA (aggiunge l'annotation di tracking) invece di
# ricrearli; MariaDB tiene il suo PVC.
#   spec.source.path: stack
#   spec.destination.namespace: stack-web
#   spec.syncPolicy.automated: { selfHeal: true, prune: true }
argocd app list
#   argocd/mio-sito   … Synced Healthy Auto
#   argocd/stack-web  … Synced Healthy Auto-Prune

# ── PULIZIA ────────────────────────────────────────────────────────────────
# Cancellare un'Application NON cancella i suoi oggetti, a meno che abbia
# il finalizer resources-finalizer.argocd.argoproj.io (allora sì, a cascata).
kubectl -n argocd delete application mio-sito stack-web
(cd terraform && terraform destroy -auto-approve)  # il namespace è suo
kubectl delete ns stack-web gitea
kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl delete ns argocd

# ── DOMANDE DA COLLOQUIO ───────────────────────────────────────────────────
#
# D: Che differenza c'è fra Argo CD e una pipeline che fa helm upgrade?
# R: La direzione e la continuità. La pipeline SPINGE una volta, con le
#    credenziali del cluster fuori dal cluster; Argo TIRA da git e
#    riconcilia sempre: vede la deriva, la corregge (selfHeal) o la
#    segnala (OutOfSync). Git diventa l'unica fonte di verità e l'audit log.
#
# D: Synced ma Degraded: cosa vuol dire?
# R: Che il cluster è identico a git, e git descrive una cosa che non
#    funziona (immagine inesistente, quota superata, probe sbagliata). La
#    correzione è un commit, non un kubectl.
#
# D: Perché argocd app rollback non funziona?
# R: Con il sync automatico è vietato (FailedPrecondition): git direbbe
#    ancora la versione nuova e il giro dopo la rimetterebbe. Si fa git
#    revert. Con il sync manuale invece rollback è permesso, e lascia
#    l'Application OutOfSync rispetto a git finché non sistemi git.
#
# D: Ho fatto push ma Argo non ha deployato. Dove guardi?
# R: 1) è passato il polling (2–3 min) o serve un --refresh / webhook?
#    2) argocd app get: la revisione è quella nuova? se no, targetRevision
#       o path puntano altrove; 3) il repo-server raggiunge git (credenziali,
#    DNS)? argocd repo list; 4) è cambiato un file DENTRO spec.source.path?
#    5) il tag dell'immagine è cambiato davvero, o è sempre "latest"?
#
# D: prune: true o false?
# R: false è prudente (un errore in git non cancella niente, ma restano
#    oggetti orfani da pulire a mano); true tiene il cluster pulito ma un
#    path sbagliato può cancellare molto. Spesso: true con allowEmpty false
#    e Prune=false sugli oggetti con dati (PVC).
#
# D: Come tieni i Secret in un repo GitOps?
# R: Mai in chiaro. Sealed Secrets (cifrati con la chiave del cluster),
#    SOPS (+ plugin o KSOPS), o External Secrets Operator che li legge da
#    Vault / un secret manager: in git c'è solo il riferimento.
#
# D: Terraform e Argo CD: dove passa il confine?
# R: Terraform per ciò che ha un ciclo di vita lungo e sta "sotto" le app
#    (rete, cluster, database gestiti, namespace con quote, l'installazione
#    stessa di Argo); Argo per ciò che cambia a ogni rilascio. Un oggetto
#    ha UN padrone: se lo gestiscono entrambi si correggono all'infinito.
#
# D: Molti ambienti o molti cluster?
# R: Kustomize overlay per ambiente (lezione 11) e un'Application per
#    ambiente; ApplicationSet per generarle da un modello (generatori
#    list, cluster, git directory); AppProject per limitare cosa ogni
#    team può deployare e dove.

# ══════════════════════════════════════════════════════════════════════════
# RIEPILOGO
# • Terraform = dove (namespace, quote); git = cosa; Argo CD = che il
#   cluster lo rispetti, sempre. La CI costruisce solo l'immagine.
# • Install: --server-side (CRD grandi); CLI della stessa versione;
#   tracking per annotation da Argo CD 3.0
# • Sync Status (uguale a git?) ≠ Health Status (funziona?)
# • selfHeal annulla le modifiche a mano; prune decide se un file tolto
#   da git toglie l'oggetto; polling 2–3 min, --refresh o webhook
# • Nuova versione = commit con un tag nuovo; rollback = git revert
# • Gitea nel cluster: due URL (NodePort per te, DNS del Service per Argo)
# ══════════════════════════════════════════════════════════════════════════
