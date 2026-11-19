# Argo CD 2 — Il repository git locale

Spiegazione di `02-git-locale.sh` (questa cartella). Laboratorio della lezione Kubernetes 16:
http://127.0.0.1:3000/kubernetes/16.

## In una frase

Mette **Gitea** nel cluster, crea l'utente `wilson`, copia il progetto modello in `lavoro/`, ne fa un repository git
e lo **pusha** su Gitea. È la «fonte di verità» che Argo CD leggerà.

## Prima di lanciarlo

Lo script 01 (Argo CD installato): l'ultimo passo usa il `repo-server` di Argo.

## Cosa fa prima dei passi

```bash
mkdir -p "$LAVORO/argocd"
[[ -s "$GITEA_PASS_FILE" ]] || { head -c 18 /dev/urandom | base64 | tr -d '/+=' > "$GITEA_PASS_FILE"; chmod 600 "$GITEA_PASS_FILE"; }
```

Se il file della password non c'è (o è vuoto), ne genera una: 18 byte casuali in base64, senza i caratteri `/ + =`
che darebbero fastidio in un URL. `chmod 600`: la legge solo il tuo utente. Rilanciando lo script la password **resta
la stessa**.

## La nota: Argo CD tira, non riceve

Argo CD non riceve push: è lui che **legge** un repository git a intervalli. Qui il repository è Gitea nel cluster.
Con GitHub cambierebbe solo `repoURL` nell'Application.

## I passi

| Passo | Comando | Cosa vedi / perché |
|---|---|---|
| 1 | `kubectl apply -f $ARGO/gitea.yaml` | namespace, disco (PVC), Deployment e Service NodePort 30300. Spiegato in `gitea.md` |
| 2 | `kubectl -n gitea rollout status deploy/gitea --timeout=3m` | aspetta Gitea pronto (la readiness probe su `/api/healthz`) |
| 3 | `kubectl -n gitea exec deploy/gitea -- gitea admin user create --username wilson … --admin --must-change-password=false --password "$(cat …)"` | crea l'utente `wilson`, admin di Gitea, con la password del file. **Se l'utente esiste già (rilancio) l'errore è voluto**: lo script va avanti |
| 4 | `[[ -d $REPO/.git ]] \|\| cp -r $ARGO/mio-progetto $REPO; cd $REPO && find … -type f -print \| sort` | copia il modello in `lavoro/argocd/mio-progetto` **solo la prima volta**: dopo resta la sua storia git. Poi elenca i file |
| 5 | `git init -q -b main` (se serve), `git config user.name/user.email`, `git add -A`, `git commit -m 'mio-sito v1' \|\| true`, `git log --oneline` | il repository con il primo commit sul ramo `main`. Il `\|\| true`: al rilancio non c'è niente da committare, e non è un errore |
| 6 | `git config credential.helper "store --file $LAVORO/argocd/.git-credentials"` + `printf 'http://wilson:%s@%s\n' … > …/.git-credentials; chmod 600` | le credenziali per il push stanno **in un file del lavoro**, non nell'URL del remote (dove finirebbero in `git remote -v` e nella configurazione) |
| 7 | `git remote set-url origin … \|\| git remote add origin $GITEA/wilson/mio-progetto.git; git remote -v` | il remote `origin` verso Gitea **visto dall'Ubuntu** (IP del nodo, porta 30300). Aggiorna l'URL se esiste già: l'IP del nodo può cambiare |
| 8 | `git push -u origin main` | il push. Gitea **crea il repository al primo push** (push-to-create), pubblico in lettura |
| 9 | `kubectl -n argocd exec deploy/argocd-repo-server -- git ls-remote http://gitea.gitea.svc.cluster.local:3000/wilson/mio-progetto.git` | lo stesso repository visto **da dentro il cluster**, dal repo-server di Argo CD. È l'indirizzo che userà l'Application. Se stampa l'hash di `main`, Argo potrà leggerlo |

## Due indirizzi per lo stesso repository

| Chi | Indirizzo |
|---|---|
| tu, dall'Ubuntu (`git push`) | `http://<IP del nodo>:30300/wilson/mio-progetto.git` |
| Argo CD, dentro il cluster | `http://gitea.gitea.svc.cluster.local:3000/wilson/mio-progetto.git` |

## Il progetto copiato

```
lavoro/argocd/mio-progetto/
├── terraform/    main.tf, variables.tf          → namespace, ResourceQuota, LimitRange (script 03)
├── kubernetes/   deployment, service, ingress   → quello che Argo CD applica (script 04)
├── sito/         Dockerfile, index.html         → l'immagine mio-sito:v1 / v2
├── argocd/       application.yaml, stack-web.yaml
└── .gitignore    .terraform/, *.tfstate, *.tfstate.*
```

**I commit li fai qui**, non in `argocd/mio-progetto/`, che resta il modello pulito.

## Alla fine

- UI di Gitea: `http://<IP del nodo>:30300`, solo dall'Ubuntu. Utente `wilson`, password in `lavoro/argocd/.gitea-pass`.
- Prossimo: `bash argocd/03-terraform-e-sito.sh`.

## Trappole

- `.gitea-pass` e `.git-credentials` contengono la password **in chiaro**: per questo `chmod 600` e la cartella
  `lavoro/` è fuori da git.
- Se cancelli `lavoro/argocd` ma non Gitea, al rilancio nasce una password nuova ma l'utente `wilson` ha ancora la
  vecchia: il passo 3 fallisce (utente già esistente) e il push del passo 8 viene rifiutato. Rimedio: la pulizia
  completa (`99-pulizia.sh`) oppure `kubectl delete ns gitea` prima di rilanciare.

## Prova da solo

1. `git -C ~/kubernetesprj/lavoro/argocd/mio-progetto remote -v`: c'è la password nell'URL? Dove sta allora?
2. Apri la UI di Gitea dal browser dell'Ubuntu: il repository è pubblico o privato?
3. Fai un commit qualsiasi in `lavoro/argocd/mio-progetto`, pusha, poi rilancia solo il passo 9 (`DA=9`): l'hash è cambiato?
