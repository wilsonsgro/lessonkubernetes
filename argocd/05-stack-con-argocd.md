# Argo CD 5 — Lo stack HAProxy → nginx → PHP → Redis + MariaDB gestito da Argo

Spiegazione di `05-stack-con-argocd.sh` (questa cartella). Facoltativo. Laboratorio della lezione Kubernetes 16:
http://127.0.0.1:3000/kubernetes/16.

## In una frase

Lo stack della sezione 4 del README (`~/kubernetesprj/stack/stack.yaml`) passa **sotto Argo CD** senza ricostruirlo,
con `prune: true`: da qui in poi lo stack si cambia con un commit.

## Prima di lanciarlo

- Lo script 02 (il repository): senza `lavoro/argocd/mio-progetto/.git` si ferma.
- All'inizio chiama `assicura_argocd` (`comune.sh`): port-forward e login.
- Lo stack **non** deve per forza girare già: se gira (`bash stack/stack.sh`), Argo **adotta** gli oggetti esistenti
  e non ricrea niente; se non gira, li crea.

## La nota: prune true

Qui `prune: true`: togliere un oggetto da git lo **toglie dal cluster**. È il contrario di `mio-sito` (script 04),
dove `prune: false` lascia l'oggetto e segnala OutOfSync.

## L'Application (`mio-progetto/argocd/stack-web.yaml`)

| Campo | Valore |
|---|---|
| `metadata.name` | `stack-web` (nel namespace `argocd`) |
| `source.repoURL` | lo stesso repository di Gitea di `mio-sito` |
| `source.path` | `stack`: un'altra cartella dello stesso repository |
| `destination.namespace` | `stack-web` |
| `syncPolicy.automated` | `selfHeal: true`, `prune: true` |

Una cartella, un'Application: lo stesso repository può alimentarne più di una.

## I passi

| Passo | Comando | Cosa vedi / perché |
|---|---|---|
| 1 | `mkdir -p $REPO/stack && cp $PRJ/stack/stack.yaml $REPO/stack/ && git add stack && { git commit -qm 'stack-web sotto Argo CD' \|\| true; } && git push -q origin main && git log --oneline -1` | lo **stesso** `stack.yaml` entra nel repository, cartella `stack/`. Il `\|\| true`: al rilancio non c'è niente da committare |
| 2 | `cat $REPO/argocd/stack-web.yaml && kubectl apply -f $REPO/argocd/stack-web.yaml` | mostra l'Application e la consegna ad Argo |
| 3 | `argocd app wait stack-web --sync --health --timeout 300 >/dev/null; argocd app list` | attesa più lunga (300 s): MariaDB deve inizializzare il database. Poi le due Application, `mio-sito` e `stack-web` |
| 4 | `kubectl -n stack-web get deploy,statefulset -o custom-columns='NOME:.metadata.name,TRACKING:.metadata.annotations.argocd\.argoproj\.io/tracking-id'` | ogni oggetto porta l'**annotation di tracking** di Argo: così Argo sa quali oggetti sono suoi. Argo CD 3.x usa l'annotation, non più l'etichetta. I `\.` servono perché il nome dell'annotation contiene dei punti |
| 5 | ciclo di `curl -sf http://<IP nodo>:30080/` (fino a 20 × 2 s), poi `curl -s -i … \| grep -iE 'x-servito-da\|php_pod\|nginx_pod\|mariadb\|visite'` | una richiesta attraverso **tutta la catena**: HAProxy (NodePort 30080) → nginx → PHP → Redis e MariaDB. Le righe filtrate dicono chi ha servito la richiesta (`X-Servito-Da` lo aggiunge HAProxy con il nome del server nginx), i Pod di nginx e php, MariaDB e il contatore di visite |
| 6 | `sed -i '/name: php$/,/replicas:/ s/replicas: 3/replicas: 4/' stack/stack.yaml && git diff --stat && git commit -qam 'php a 4 repliche' && git push -q origin main` | scalare php **da 3 a 4 si fa in git**. Il `sed` lavora solo sull'intervallo che va dalla prima riga `name: php` (è quella del **Service** php) al primo `replicas:` dopo, che è quello del Deployment php. Così non tocca le repliche di nginx (2) e degli altri. Funziona perché nel file il Service sta subito prima del suo Deployment |
| 7 | `argocd app get stack-web --refresh … && argocd app wait …; kubectl -n stack-web get deploy php` | php sale a 4 |
| 8 | `git revert --no-edit HEAD … && git push … && argocd app get --refresh … && argocd app wait …; kubectl -n stack-web get deploy php` | revert: di nuovo 3 |

## Adottare invece di ricreare

Quando lo stack gira già, Argo trova nel namespace oggetti con lo stesso nome e tipo di quelli in git: li prende in
carico, aggiunge l'annotation di tracking e li confronta. Se coincidono non tocca niente: niente downtime e niente
database reinizializzato.

## Alla fine

- Pulizia: `bash argocd/99-pulizia.sh`, che toglie anche il namespace `stack-web`.
- Da ora lo stack **si cambia in git**: un `kubectl edit` su `stack-web` viene annullato dal self-heal.

## Trappole

- Con `prune: true` un errore in git (un file cancellato per sbaglio, un `path` sbagliato) **cancella** gli oggetti dal
  cluster, compreso lo StatefulSet di MariaDB. Il PVC di uno StatefulSet però non è un oggetto del manifest: nasce dal
  `volumeClaimTemplates` e di solito sopravvive.
- Se rilanci `bash stack/stack.sh` dopo questo script, il `kubectl apply` dello stack e Argo scrivono sugli stessi
  oggetti: vince git, al giro dopo.

## Prova da solo

1. `kubectl -n stack-web scale deploy php --replicas=1` e poi, dopo 20 secondi, `kubectl -n stack-web get deploy php`:
   chi ha vinto?
2. Nel repository, togli dal file `stack.yaml` un oggetto piccolo (per esempio un Service), committa e pusha: con
   `prune: true` cosa succede nel cluster? Poi fai il revert.
3. `kubectl -n stack-web get pvc` prima e dopo l'esercizio 2: i dischi sono rimasti?
