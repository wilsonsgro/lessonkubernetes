# 12 — CI/CD e GitOps: dalla commit al cluster

Spiegazione di `12-cicd-gitops.yaml` (questa cartella). Lezione sul sito: http://127.0.0.1:3000/kubernetes/12

## In una frase

Il file contiene **due documenti YAML**: una **pipeline GitLab CI completa** (`lint → test → build → scan → deploy`)
che non tocca mai il cluster ma scrive in un **repo di configurazione**, e l'**Application di Argo CD** che osserva quel
repo e riconcilia il cluster. Il guidato rifà a mano i passi della pipeline sul lab (build, scan con Trivy, push, deploy
con Helm) e poi installa **Argo CD** per vedere dal vivo sync automatico e **self-heal**.

## Due file con lo stesso nome: quale lanciare

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/lezioni/kubernetes/12-cicd-gitops.yaml` | **questo**: la pipeline e l'Application, con le spiegazioni nei commenti | **si legge**. Non si applica così com'è: il primo documento è un `.gitlab-ci.yml`, non un oggetto Kubernetes, e l'Application punta a un repo di config che sul lab non c'è |
| `~/kubernetesprj/kubernetes/12-cicd-gitops.sh` | lo script **guidato**: esegue a mano gli stessi passi della pipeline e installa Argo CD con un'Application di esempio, spiegando prima di eseguire (Invio / s / q) | `bash kubernetes/12-cicd-gitops.sh` |

Il guidato lavora in `lavoro/helm` e **si ferma** se manca `./eco`: `prima esegui la lezione 09: serve ./eco`. Usa anche
il registry della lezione 10 (porta 5000); se non è acceso lo accende lui.

## Com'è fatto il file

```
intestazione (commenti)       → push vs pull, la pipeline, i principi, LAB a mano, NEL PROGETTO VERO
documento 1: .gitlab-ci.yml   → stages, variables, default, workflow, i job
---
documento 2: Application      → eco-prod, sync automatico con prune e selfHeal
coda (commenti)               → strategie di rilascio, domande da colloquio, riepilogo
```

---

## 1. La teoria nell'intestazione

Versioni: **GitLab CI · BuildKit · Trivy · Helm 4 · Argo CD 3**. Livello 5 "Produzione".

### Due modelli di deploy

| Modello | Come funziona | Pro / contro |
|---|---|---|
| **PUSH** | la pipeline ha le credenziali del cluster e fa `helm upgrade` | semplice; ma la CI diventa un punto con accesso alla produzione, e se qualcuno cambia il cluster a mano nessuno se ne accorge |
| **PULL** (GitOps) | la pipeline aggiorna un **repo di configurazione**; un agente **nel cluster** (Argo CD, Flux) lo osserva e riconcilia | git è la fonte di verità, ogni cambio è una commit revisionata, il **drift** si vede e si corregge, il rollback è un `git revert` |

È la stessa idea della lezione 01 (stato desiderato + controller che riconcilia), spostata un livello più su: lo stato
desiderato sta in git, il controller è Argo CD.

### La pipeline

```
lint → test → build (immagine con tag = SHA) → scan → push
     → aggiorna il repo di config (staging, automatico)
     → promozione a prod (manuale, stessa immagine, nessuna rebuild)
```

### I principi

- **build once, deploy many**: lo stesso digest in ogni ambiente;
- **tag immutabili** (SHA o SemVer), mai `:latest` in un manifest;
- la pipeline **fallisce** su CVE critiche, non le segnala e basta;
- segreti dalla CI (variabili protette/masked) o da **OIDC**, non nel repo;
- prod solo da branch protetto, con approvazione (environment).

### Il laboratorio a mano (senza GitLab)

```bash
docker build -t localhost:5000/eco:$(git rev-parse --short HEAD) .
docker run --rm aquasec/trivy:latest image --severity CRITICAL --exit-code 1 <immagine>
helm upgrade --install eco ./eco --set image.tag=<sha> --rollback-on-failure --wait
# Argo CD sul minikube:
kubectl create ns argocd
kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
kubectl -n argocd port-forward svc/argocd-server 8443:443
```

Il guidato fa questi passi con qualche differenza (vedi sezione 4): il tag è una **data**, non lo SHA di git.

### Riquadro «NEL PROGETTO VERO»

In `~/biodistretto/kubernetes` la pipeline è **locale** (`deploy.sh` → Ansible), ma segue le stesse regole:

```bash
cd ~/biodistretto/kubernetes
grep -n 'exclude' docker/build.sh                               # contesto pulito, senza .env
grep -n 'cut -c1-12' docker/build.sh                            # tag = ID dell'immagine
grep -n 'image load' ansible/roles/immagini/tasks/main.yml      # niente registry
```

- L'immagine si costruisce da un **contesto pulito**, senza `.env`: il backend non ha un `.dockerignore` e la `.env`
  finirebbe nell'immagine.
- Il tag è l'**ID dell'immagine**: stesso contenuto, stesso tag, nessun rollout inutile. È l'equivalente locale del tag
  con lo SHA del commit.
- Non c'è un registry: `minikube image load` e `IfNotPresent` nei Pod.
- Lo smoke test dopo il deploy è il ruolo `verifica` (lezione 07 Terraform).

---

## 2. Documento 1: la pipeline GitLab, pezzo per pezzo

### Intestazione della pipeline

```yaml
stages: [lint, test, build, scan, deploy-staging, deploy-prod]
variables:
  IMAGE: "$CI_REGISTRY_IMAGE"
  TAG: "$CI_COMMIT_SHORT_SHA"
  CONFIG_REPO: "gitlab.com/wilsonsgro/lessons-config.git"
default:
  interruptible: true
workflow:
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
```

| Pezzo | Perché |
|---|---|
| `stages` | l'ordine delle fasi: un job di una fase parte quando la precedente è finita bene |
| `IMAGE` / `TAG` | registry del progetto GitLab e **SHA corto del commit**: tag immutabile |
| `CONFIG_REPO` | il repo di configurazione su cui scrive la CI (GitOps) |
| `interruptible: true` | una push nuova cancella la pipeline vecchia ancora in corso |
| `workflow.rules` | la pipeline esiste solo per le merge request e per il branch di default |

### `helm-lint` (stage `lint`, immagine `alpine/k8s:1.35.9`)

```yaml
- helm lint chart/ --strict
- helm template ci chart/ -f chart/values-prod.yaml | kubeconform -strict -summary -
```

Il lint della lezione 09, più la validazione degli **schemi** Kubernetes dei manifest renderizzati con i valori di
prod (`kubeconform -strict`, il `-` finale = legge da stdin).

### `unit-test` (stage `test`, immagine `node:24-alpine`)

- `cache.key.files: [yarn.lock]` → la cache di `node_modules/` si invalida **solo** se cambia il lock;
- `yarn install --frozen-lockfile` → installa esattamente il lock, fallisce se non è allineato;
- `artifacts.reports.junit: junit.xml` → i test falliti compaiono nella merge request.

### `build` (stage `build`, immagine `moby/buildkit:rootless`)

| Pezzo | Perché |
|---|---|
| `moby/buildkit:rootless` | build **senza privilegi**: niente `docker:dind` privilegiato |
| `BUILDKITD_FLAGS: --oci-worker-no-process-sandbox` | serve a BuildKit rootless per girare in un container non privilegiato |
| `before_script` | scrive `~/.docker/config.json` con le credenziali del registry GitLab (`$CI_REGISTRY_USER` / `$CI_REGISTRY_PASSWORD`, variabili fornite da GitLab) |
| `buildctl-daemonless.sh build --frontend dockerfile.v0 --local context=. --local dockerfile=.` | build del Dockerfile della cartella |
| `--output type=image,name=$IMAGE:$TAG,push=true` | l'immagine con tag = SHA viene **pushata** subito |
| `--export-cache` / `--import-cache type=registry,ref=$IMAGE:cache` | la cache dei layer sta nel registry (`mode=max` = anche gli stadi intermedi): build veloci anche su runner sempre nuovi |

### `trivy` (stage `scan`, immagine `aquasec/trivy:latest`)

```yaml
entrypoint: [""]
script:
  - trivy image --exit-code 1 --severity CRITICAL --ignore-unfixed $IMAGE:$TAG
```

- `entrypoint: [""]` toglie l'entrypoint dell'immagine, così GitLab può eseguire lo `script`;
- `TRIVY_USERNAME` / `TRIVY_PASSWORD` per leggere l'immagine dal registry privato;
- `--exit-code 1 --severity CRITICAL`: con almeno una CVE critica il job **fallisce** e la pipeline si ferma;
- `--ignore-unfixed`: ignora le CVE per cui non esiste ancora una correzione (non potresti farci niente).

### `.aggiorna-config` — il cuore del GitOps

```yaml
.aggiorna-config: &aggiorna-config
  image: alpine/k8s:1.35.9
  script:
    - git clone "https://ci:${CONFIG_TOKEN}@${CONFIG_REPO}" config
    - cd config/overlays/$AMBIENTE
    - kustomize edit set image "eco=$IMAGE:$TAG"
    - git -c user.name=ci -c user.email=ci@example.invalid commit -am "eco $TAG → $AMBIENTE"
    - git push origin HEAD:main
```

- Il punto davanti al nome (`.aggiorna-config`) lo rende un **job nascosto**: non gira da solo, è un modello.
- `&aggiorna-config` è un'**ancora YAML**; i job la riusano con `<<: *aggiorna-config`.
- La CI **non tocca il cluster**: clona il repo di config, aggiorna il tag nell'overlay dell'ambiente con
  `kustomize edit set image` (lezione 11), fa commit e push. Il resto lo fa Argo CD.
- `CONFIG_TOKEN` non è nel file: è una variabile CI protetta.

### `deploy-staging` e `deploy-prod`

| | staging | prod |
|---|---|---|
| `AMBIENTE` | `staging` | `prod` |
| `environment` | `staging` | `production`: approvazioni e accessi sull'environment **protetto** |
| `rules` | solo sul branch di default | solo sul branch di default, `when: manual`: la promozione è **un clic**, stessa immagine |
| `resource_group` | — | `production`: mai due deploy prod in parallelo |

---

## 3. Documento 2: l'Application di Argo CD `eco-prod`

In un repo vero è un **file a parte** (nel repo di config o in quello di Argo): un `.gitlab-ci.yml` deve contenere solo
la pipeline. I controlli consigliati prima della commit, uno per parte:

```bash
uvx check-jsonschema --builtin-schema vendor.gitlab-ci .gitlab-ci.yml
kubectl apply --dry-run=server -f application.yaml      # con i CRD di Argo installati
```

| Campo | Valore | Perché |
|---|---|---|
| `apiVersion` / `kind` | `argoproj.io/v1alpha1` / `Application` | una CRD installata da Argo CD |
| `metadata.namespace` | `argocd` | le Application vivono nel namespace di Argo, non in quello dell'app |
| `finalizers` | `resources-finalizer.argocd.argoproj.io` | cancelli l'Application → Argo cancella anche le risorse che gestiva |
| `source.repoURL` / `targetRevision` / `path` | `…/lessons-config.git`, `main`, `overlays/prod` | cosa osservare. Argo riconosce da solo Kustomize, Helm o YAML |
| `destination` | `https://kubernetes.default.svc`, namespace `eco-prod` | il cluster dove gira Argo stesso |
| `automated.prune: true` | | cancella ciò che **non è più in git** |
| `automated.selfHeal: true` | | annulla le modifiche fatte **a mano** |
| `syncOptions` | `CreateNamespace=true`, `ServerSideApply=true` | crea il namespace di destinazione; usa il server-side apply |
| `retry` | `limit: 3`, backoff `10s`, `factor: 2`, `maxDuration: 2m` | un sync fallito si ritenta 3 volte con attese crescenti |

---

## 4. Il percorso del guidato, passo per passo

All'inizio `TAG="$(date +%Y%m%d%H%M%S)"`: sul lab il tag immutabile è la **data e ora**, non lo SHA di git.

### Parte 1: la pipeline a mano

| # | Comando | Cosa vedi |
|---|---|---|
| 1 | `printf 'FROM traefik/whoami:v1.12\nLABEL org.opencontainers.image.revision=$TAG\n' > Dockerfile && cat Dockerfile` | un Dockerfile minimo; la label OCI `revision` porta il tag (in CI sarebbe il Dockerfile del repo) |
| 2 | `docker build -t localhost:5000/eco:$TAG .` | **BUILD** con tag immutabile. Mai `latest` in produzione |
| 3 | `docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest image --severity CRITICAL --exit-code 1 localhost:5000/eco:$TAG` | **SCAN**: con `--exit-code 1` una CVE CRITICAL farebbe fallire la pipeline. Il socket Docker montato permette a Trivy di leggere l'immagine locale. Il primo giro scarica il database delle vulnerabilità ed è **lento** |
| 4 | `docker ps … \| grep -qx registry \|\| docker run -d --name registry -p 5000:5000 registry:3; docker push localhost:5000/eco:$TAG` | **PUSH** nel registry della lezione 10 (lo accende se manca) |
| 5 | `minikube -p lab image load localhost:5000/eco:$TAG` | i nodi minikube sono container: il loro `localhost` **non è** quello dell'host, quindi l'immagine si carica direttamente nei nodi |
| 6 | `helm upgrade --install eco eco -n lab-cicd --create-namespace --set image.repository=localhost:5000/eco --set image.tag=$TAG --set image.pullPolicy=IfNotPresent --rollback-on-failure --wait --timeout 2m` | **DEPLOY** del chart della 09: lo stesso artefatto, promosso cambiando solo il tag. `IfNotPresent` usa l'immagine caricata al passo 5 senza tentare il pull |
| 7 | `kubectl -n lab-cicd get deploy -o jsonpath='{..image}'` | verifica: l'immagine in esecuzione è `localhost:5000/eco:<data>` |

### Parte 2: GitOps con Argo CD

| # | Comando | Cosa vedi |
|---|---|---|
| 8 | `kubectl create ns argocd --dry-run=client -o yaml \| kubectl apply -f -` | crea il namespace in modo **idempotente** (non fallisce se c'è già) |
| 9 | `kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml` | installa Argo CD. `--server-side` perché le CRD sono **troppo grandi** per l'apply client-side (l'annotazione `last-applied` supererebbe il limite) |
| 10 | `kubectl -n argocd rollout status deploy/argocd-server --timeout=5m && kubectl -n argocd get pods` | i componenti: server, repo-server, application-controller… |
| 11 | `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' \| base64 -d; echo` | la password iniziale di `admin`. Va cambiata e il Secret cancellato |
| 12 | `kubectl apply -f - <<'EOF' … EOF` | un'Application vera: `guestbook` dal repo pubblico `https://github.com/argoproj/argocd-example-apps.git`, `targetRevision: HEAD`, `path: guestbook`, namespace `guestbook`, `automated: { prune: true, selfHeal: true }`, `CreateNamespace=true` |
| 13 | `sleep 60; kubectl -n argocd get application guestbook; kubectl -n guestbook get deploy` | dopo circa un minuto: **Synced** e **Healthy**, il Deployment è nel cluster **senza che nessuno abbia fatto apply** |
| 14 | `kubectl -n guestbook scale deploy guestbook-ui --replicas=5` | **modifica a mano** del cluster: 5 repliche invece di 1 (drift) |
| 15 | `sleep 20; kubectl -n guestbook get deploy guestbook-ui` | **self-heal**: Argo CD lo riporta a quello che dice git. Il cluster non si cambia con kubectl, si cambia con un commit |
| 16 | `kubectl -n argocd port-forward svc/argocd-server 8443:443` | la UI su `https://localhost:8443` (utente `admin`, password del passo 11). Resta in primo piano: Ctrl+C per chiudere. Con `AUTO=1` il passo viene **saltato** (regola di `passo.sh` per i port-forward) |

Nota finale: pulizia con `kubectl -n argocd delete application guestbook; kubectl delete ns argocd guestbook lab-cicd`.
L'Application vera con overlay Kustomize e la pipeline GitLab completa sono nel file della lezione.

L'Application `guestbook` del guidato e la `eco-prod` del file hanno la stessa forma; cambiano il repo (pubblico di
esempio contro il repo di config del corso) e le opzioni in più di `eco-prod` (finalizer, `ServerSideApply`, `retry`).

---

## 5. Le trappole

- **`docker:dind` in CI** richiede container privilegiati sul runner: chi controlla la pipeline controlla l'host.
- **`:latest`** in un manifest: non sai cosa gira, il rollback non ha un punto fermo.
- **Scan che segnala ma non blocca**: senza `--exit-code 1` Trivy stampa e la pipeline prosegue.
- **Registry su `localhost` e minikube**: dentro il nodo `localhost:5000` non è il registry dell'host; per questo il
  guidato usa `minikube image load`.
- **Apply client-side delle CRD di Argo CD**: troppo grandi, serve `--server-side`.
- **Rollback dalla UI di Argo**: è d'emergenza, disattiva l'auto-sync e lascia git diverso dal cluster.
- **Database**: le migrazioni devono essere compatibili all'indietro, o il rollback dell'app rompe tutto.

---

## 6. La coda: strategie di rilascio

| Strategia | Come funziona |
|---|---|
| **rolling** | il default del Deployment; rollback = `rollout undo` o revert |
| **blue/green** | due versioni complete, si sposta il traffico **tutto insieme** |
| **canary** | una percentuale crescente, con analisi delle metriche: Argo Rollouts / Flagger leggono Prometheus e annullano da soli se l'error rate sale |
| **feature flag** | il rilascio del codice è separato dall'attivazione |

Il vincolo è il database: migrazioni **expand → migrate → contract**.

---

## 7. Comandi e domande da colloquio

### Comandi da sapere

| Comando | A cosa serve |
|---|---|
| `trivy image --exit-code 1 --severity CRITICAL --ignore-unfixed <img>` | scan bloccante |
| `minikube -p lab image load <img>` | carica un'immagine nei nodi senza registry |
| `kubectl create ns X --dry-run=client -o yaml \| kubectl apply -f -` | creazione idempotente |
| `kubectl apply --server-side -f install.yaml` | apply di oggetti molto grandi (CRD) |
| `kubectl -n argocd get application <nome>` | stato di sync e salute |
| `kustomize edit set image "eco=$IMAGE:$TAG"` | aggiorna il tag nell'overlay (dalla CI) |
| `uvx check-jsonschema --builtin-schema vendor.gitlab-ci .gitlab-ci.yml` | valida la pipeline prima del commit |

### Domande

- **Perché non `docker:dind` in CI?** Richiede container privilegiati sul runner: chi controlla la pipeline controlla
  l'host. BuildKit rootless, Kaniko o Buildah fanno la build senza privilegi.
- **Qualcuno ha fatto `kubectl edit` in produzione. Con GitOps cosa succede?** Argo segna l'App **OutOfSync**; con
  `selfHeal` la riporta allo stato di git entro pochi minuti. La correzione vera passa da una MR.
- **Come fai il rollback in GitOps?** `git revert` della commit di promozione: Argo sincronizza lo stato precedente.
  Il rollback dall'interfaccia di Argo è d'emergenza.
- **Dove stanno i segreti della pipeline?** Variabili CI protette e mascherate; meglio ancora **OIDC**: il job ottiene
  un token a scadenza (`id_tokens` di GitLab) e lo scambia con credenziali temporanee del cloud o di Vault. Nessuna
  chiave statica.
- **Push o pull?** Vedi la tabella della sezione 1: nel pull la CI non ha credenziali del cluster e il drift si vede.

---

## Riepilogo

- Push (la CI fa `helm upgrade`) contro Pull/GitOps (Argo CD riconcilia da git).
- Build once, deploy many: tag = SHA, promozione senza rebuild.
- Build senza privilegi (BuildKit rootless), scan bloccante (Trivy).
- Argo CD: `automated` + `prune` + `selfHeal`; rollback = `git revert`.
- Rilasci: rolling, blue/green, canary con analisi; migrazioni expand/contract.

## Prova da solo

1. Con l'Application `guestbook` attiva, cancella a mano il Deployment
   (`kubectl -n guestbook delete deploy guestbook-ui`) e guarda `kubectl -n argocd get application guestbook` per un
   minuto: cosa succede e quale campo della `syncPolicy` lo causa?
2. Ripeti i passi 1-6 del guidato con un tag nuovo e poi `helm -n lab-cicd history eco`: quante revision ci sono e
   cosa cambia fra l'una e l'altra (`helm -n lab-cicd get values eco --revision N`)?
3. Separa i due documenti del file in `.gitlab-ci.yml` e `application.yaml` e lancia sul secondo
   `kubectl apply --dry-run=server -f application.yaml` (con Argo CD installato): passa? E se togli `spec.destination`?
