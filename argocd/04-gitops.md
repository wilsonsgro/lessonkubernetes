# Argo CD 4 — GitOps sul sito

Spiegazione di `04-gitops.sh` (questa cartella). Laboratorio della lezione Kubernetes 16:
http://127.0.0.1:3000/kubernetes/16.

## In una frase

Il ciclo GitOps completo su `mio-sito`:
- consegni l'Application ad Argo CD e il sito appare da solo;
- una modifica fatta a mano viene annullata (self-heal);
- una nuova versione è un commit, e il rollback è un `git revert`;
- con `prune: false` togliere un file da git non cancella l'oggetto;
- la quota di Terraform vale anche per Argo.

## Prima di lanciarlo

Gli script 02 e 03: senza `lavoro/argocd/mio-progetto/.git` si ferma («prima esegui argocd/02 e argocd/03»).
All'inizio chiama `assicura_argocd` (`comune.sh`): riaccende il port-forward e il login se servono.

Lo script definisce `SITO`, il comando che legge la versione dal sito attraverso l'Ingress:

```bash
curl -s -H 'Host: mio-sito.local' http://<IP del nodo>/ | grep -o 'versione: <strong>[^<]*' | sed 's/<strong>//'
```

L'header `Host:` fa scegliere all'ingress-nginx la regola di `mio-sito.local`, senza toccare `/etc/hosts`. Stampa
`versione: v1` (o `v2`).

## L'Application (`mio-progetto/argocd/application.yaml`)

```yaml
kind: Application
metadata: { name: mio-sito, namespace: argocd }
spec:
  project: default
  source:
    repoURL: http://gitea.gitea.svc.cluster.local:3000/wilson/mio-progetto.git
    targetRevision: HEAD
    path: kubernetes
  destination:
    server: https://kubernetes.default.svc
    namespace: mio-sito
  syncPolicy:
    automated: { selfHeal: true, prune: false }
    syncOptions: [CreateNamespace=true]
```

| Campo | Significato |
|---|---|
| `source` | **quale** repository (l'indirizzo interno di Gitea), quale revisione (`HEAD`: l'ultimo commit del ramo di default) e quale cartella (`kubernetes/`) |
| `destination` | **dove**: il cluster in cui gira Argo e il namespace `mio-sito` |
| `automated` | sincronizza da solo quando git cambia |
| `selfHeal: true` | se qualcuno cambia il cluster a mano, Argo lo riporta a com'è in git |
| `prune: false` | se un file sparisce da git, Argo **non** cancella l'oggetto: lo segnala e aspetta |
| `CreateNamespace=true` | creerebbe il namespace se non ci fosse. Qui c'è già: l'ha creato Terraform (script 03) |

L'Application sta nel namespace `argocd`, non in `mio-sito`: è un oggetto di Argo, non del sito.

Cosa c'è in `kubernetes/`:
- un Deployment `mio-sito` con 2 repliche, immagine `mio-sito:v1` e `imagePullPolicy: IfNotPresent`;
- una readiness probe su `/`, request 20m / 16Mi e limit 100m / 64Mi;
- un Service sulla porta 80;
- un Ingress `nginx` per l'host `mio-sito.local`.

## I passi

### Primo deploy

| Passo | Comando | Cosa vedi / perché |
|---|---|---|
| 1 | `cat $REPO/argocd/application.yaml` | l'Application (sopra) |
| 2 | `kubectl apply -f $REPO/argocd/application.yaml` | la consegni ad Argo. È **l'unico `kubectl apply` del sito**: da qui in poi applica Argo, leggendo git |
| 3 | `argocd app wait mio-sito --sync --health --timeout 180` | aspetta **Synced** (cluster = git) e **Healthy** (Pod pronti) |
| 4 | `argocd app get mio-sito` | la revisione git applicata e lo stato di ogni risorsa |
| 5 | `kubectl -n mio-sito get deploy,pod,svc,ingress` | gli oggetti nel cluster: nessuno li ha creati a mano |
| 6 | `$SITO` | `versione: v1`, attraverso l'Ingress |

### Self-heal: il cluster non si cambia con kubectl

| Passo | Comando | Cosa vedi / perché |
|---|---|---|
| 7 | `kubectl -n mio-sito scale deploy mio-sito --replicas=5 && kubectl -n mio-sito get deploy mio-sito` | modifichi il cluster a mano: 5 repliche invece delle 2 di git |
| 8 | `sleep 15; kubectl -n mio-sito get deploy mio-sito` | `selfHeal: true` l'ha riportato a **2**: git vince |

### Nuova versione = un commit

| Passo | Comando | Cosa vedi / perché |
|---|---|---|
| 9 | `docker build -q --build-arg VERSIONE=v2 -t mio-sito:v2 $REPO/sito && minikube -p lab image load mio-sito:v2` | l'immagine v2: in un progetto vero la costruirebbe la CI |
| 10 | `sed -i 's/mio-sito:v1/mio-sito:v2/; s/replicas: 2/replicas: 3/' kubernetes/deployment.yaml && git diff` | cambi lo stato desiderato **in git**: immagine v2 e 3 repliche |
| 11 | `git commit -qam 'mio-sito v2, 3 repliche' && git push -q origin main && git log --oneline -3` | commit e push |
| 12 | `argocd app get mio-sito --refresh … && argocd app wait … && argocd app get mio-sito \| grep -E "Sync Status\|Health Status"` | Argo rilegge git ogni 2–3 minuti (120 s + fino a 60 s di jitter). `--refresh` lo fa subito; in produzione c'è un webhook dal server git |
| 13 | `$SITO; kubectl -n mio-sito get deploy mio-sito -o wide` | `versione: v2` e 3 Pod |
| 14 | `argocd app history mio-sito` | la storia dei deploy: ogni riga è una revisione git |

### Rollback = git revert

La nota spiega perché **non** si usa `argocd app rollback`: con il sync automatico è vietato, perché al giro dopo
il cluster tornerebbe a v2, cioè a quello che dice git. Si torna indietro in git, che tiene traccia di chi e perché.

| Passo | Comando | Cosa vedi / perché |
|---|---|---|
| 15 | `git revert --no-edit HEAD >/dev/null && git push -q origin main && git log --oneline -3` | un commit nuovo che annulla l'ultimo. La storia non si riscrive |
| 16 | refresh e attesa, come al passo 12 | Synced e Healthy |
| 17 | `$SITO; kubectl -n mio-sito get deploy mio-sito -o wide` | di nuovo `versione: v1` con 2 Pod |

### prune: false — togliere un file da git

| Passo | Comando | Cosa vedi / perché |
|---|---|---|
| 18 | `git rm -q kubernetes/ingress.yaml && git commit -qm 'via ingress' && git push -q origin main` | tolgo l'Ingress dal repository |
| 19 | `argocd app get mio-sito --refresh \| grep -iE "Sync Status\|ingress"; kubectl -n mio-sito get ingress` | Argo vede la differenza ma **non cancella**: l'Ingress resta, e l'Application è **OutOfSync** (l'Ingress è segnato «requires pruning») |
| 20 | `argocd app sync mio-sito --prune >/dev/null; kubectl -n mio-sito get ingress` | pruning **manuale**: il sync con `--prune` cancella ciò che non è più in git. L'Ingress sparisce |
| 21 | `git revert --no-edit HEAD … && git push … && argocd app get --refresh … && argocd app wait …; kubectl -n mio-sito get ingress; $SITO` | il revert rimette il file in git e l'Ingress **torna da solo**, con il sito |

### Terraform e Argo CD insieme

| Passo | Comando | Cosa vedi / perché |
|---|---|---|
| 22 | `sed -i 's/replicas: 2/replicas: 8/' … && git commit -qam '8 repliche' && git push … && argocd app get mio-sito --refresh` | in git 8 repliche, ma la ResourceQuota di Terraform permette **6 Pod** |
| 23 | `sleep 20; kubectl -n mio-sito get deploy mio-sito; kubectl -n mio-sito get events --field-selector reason=FailedCreate -o custom-columns=MSG:.message \| tail -2` | Argo applica git (**Synced**: il Deployment dice 8), ma Kubernetes **rifiuta** i Pod oltre la quota: il Deployment resta a **6 su 8**. Gli eventi `FailedCreate` del ReplicaSet dicono «exceeded quota» |
| 24 | `git revert … && git push … && argocd app wait …; kubectl -n mio-sito get deploy mio-sito` | di nuovo 2 repliche |

La lezione: **Synced non vuol dire che tutto gira**. Argo garantisce che gli oggetti siano uguali a git. Se poi
Kubernetes li accetta o no lo decidono quota, admission e risorse.

## Alla fine

- UI: `https://192.168.1.79:8083` → `mio-sito`: l'albero delle risorse, la storia, i diff.
- Facoltativo: `bash argocd/05-stack-con-argocd.sh`.
- Pulizia: `bash argocd/99-pulizia.sh`.

## Trappole

- Rilanciare lo script da capo **non** riparte pulito: il repository ha già i commit del giro prima. I `sed` del passo
  10 e del 22 cercano `replicas: 2` e `mio-sito:v1`: dopo i revert ci sono di nuovo, quindi funziona, ma la storia
  git si allunga.
- Lo `sleep 15` del passo 8 è un'attesa fissa: se il self-heal è più lento, vedi ancora 5 repliche. Rilancia il get.
- `$SITO` passa dall'Ingress: dopo il passo 20 l'Ingress non c'è. ingress-nginx risponde lo stesso, ma con il suo 404
  di default, e `$SITO` stampa una riga vuota perché nella pagina non c'è `versione:`. Per questo il passo 21 rimette
  l'Ingress prima di leggere la versione.

## Prova da solo

1. Cambia a mano l'immagine (`kubectl -n mio-sito set image deploy/mio-sito sito=mio-sito:v2`) e guarda
   `argocd app get mio-sito` subito e dopo 20 secondi: cosa succede?
2. Togli `selfHeal: true` dall'Application (`kubectl -n argocd edit application mio-sito`) e rifai lo `scale` a 5:
   cosa dice `argocd app get`? Poi rimetti l'Application com'era: `kubectl apply -f
   ~/kubernetesprj/lavoro/argocd/mio-progetto/argocd/application.yaml`.
3. Prova `argocd app rollback mio-sito 1`: che errore dà, e perché?
