# Argo CD 1 — Installazione

Spiegazione di `01-installa-argocd.sh` (questa cartella). È il laboratorio guidato della lezione Kubernetes 16:
http://127.0.0.1:3000/kubernetes/16 (spiegazione della lezione: `../lezioni/kubernetes/16-argocd-gitops.md`).

## In una frase

Installa **Argo CD** nel cluster `lab`, ti dà la password di `admin`, scarica la CLI `argocd`, apre l'interfaccia
web sulla porta **8083** e fa il login.

## Prima di lanciarlo

- Il cluster `lab` acceso: lo script parte con `guardia_lab` e si ferma se kubectl non punta a `lab`
  (`bash kubernetes/01-architettura-e-lab.sh` per crearlo).
- Internet: il manifest e la CLI si scaricano da GitHub.

```bash
cd ~/kubernetesprj
bash argocd/01-installa-argocd.sh
```

## La nota iniziale: chi fa cosa

| Strumento | Ruolo |
|---|---|
| Terraform | crea le risorse infrastrutturali (qui: namespace, quota, limiti, nello script 03) |
| minikube | il cluster locale |
| Kubernetes | gestisce i container |
| Argo CD | tiene il cluster **uguale a quello che c'è in git** |

## I passi

| Passo | Comando | Cosa vedi / perché |
|---|---|---|
| 1 | `kubectl create namespace argocd --dry-run=client -o yaml \| kubectl apply -f -` | il namespace `argocd`. È la forma **idempotente** di `create namespace`: rilanciato non dà errore |
| 2 | `kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml` | il manifest ufficiale, versione `stable`. `--server-side`: le CRD di Argo sono così grandi da superare il limite dell'annotation `last-applied` dell'apply classico. `--force-conflicts`: se rilanci, Argo diventa proprietario dei campi già scritti da altri |
| 3 | `kubectl get crd \| grep argoproj` | i **nuovi tipi di oggetto** che Argo aggiunge a Kubernetes: Application, AppProject, ApplicationSet |
| 4 | `kubectl -n argocd wait --for=condition=Available deploy --all --timeout=5m && kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=5m` | aspetta che tutto sia pronto. La prima volta scarica le immagini: qualche minuto. Il controller è uno StatefulSet, non un Deployment, per questo c'è il secondo comando |
| 5 | `kubectl -n argocd get pods -o wide` | i pezzi di Argo CD (tabella sotto) |
| 6 | `kubectl -n argocd get deploy argocd-server -o jsonpath='{…containers[0].image}'` | la versione installata, letta dall'immagine del server |
| 7 | `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' \| base64 -d; echo` | la **password iniziale di admin**. I valori dei Secret sono in base64, da qui il `base64 -d`. In produzione si cambia e il Secret si cancella |
| 8 | `VER=$(… \| cut -d: -f2); curl -sSL -o ~/.local/bin/argocd …/download/$VER/argocd-linux-amd64 && chmod +x …` | la CLI `argocd` **della stessa versione del server** (il tag dell'immagine del passo 6), in `~/.local/bin`, senza sudo |
| 9 | `pgrep -f '…svc/argocd-server' \|\| (nohup kubectl -n argocd port-forward --address 0.0.0.0 svc/argocd-server 8083:443 … &); sleep 3; curl -sk … https://localhost:8083/` | il **port-forward in background**: la 443 del Service diventa la 8083 dell'Ubuntu. `--address 0.0.0.0` lo rende raggiungibile anche dal Mac. Il `curl` finale stampa `HTTP <codice>`. `pgrep` evita di accenderne un secondo |
| 10 | `argocd login localhost:8083 --username admin --insecure --grpc-web --password "…"` | il login della CLI. `--insecure`: il certificato è autofirmato. `--grpc-web`: la CLI parla gRPC, e attraverso il port-forward passa meglio incapsulato in HTTP |
| 11 | `argocd cluster list` | il cluster dove Argo deploya: quello in cui gira, `https://kubernetes.default.svc` |
| 12 | `argocd app list` | le Application: ancora nessuna (`mio-sito` arriva con lo script 04) |

### I Pod di Argo CD (passo 5)

| Componente | Cosa fa |
|---|---|
| `argocd-server` | API e interfaccia web |
| `argocd-repo-server` | legge git e genera i manifest (YAML, Helm, Kustomize) |
| `argocd-application-controller` | confronta il cluster con git e sincronizza |
| `argocd-redis` | cache |
| `argocd-dex-server` | SSO |
| `argocd-notifications-controller` | notifiche |
| `argocd-applicationset-controller` | genera Application da modelli (ApplicationSet) |

## Alla fine

- **UI**: `https://localhost:8083` sull'Ubuntu, `https://192.168.1.79:8083` dal Mac. Utente `admin`, password del
  passo 7. Il browser avvisa del certificato autofirmato: è atteso.
- **Chiudere il port-forward**: `pkill -f 'port-forward --address 0.0.0.0 svc/argocd-server'`.
- **Dopo un riavvio del PC** il port-forward non c'è più: lo riaccendono da soli gli script 04 e 05
  (`assicura_argocd` in `comune.sh`), oppure `DA=9 bash argocd/01-installa-argocd.sh`.
- **Prossimo**: `bash argocd/02-git-locale.sh`.

## Trappole

- `stable` è un riferimento **mobile**: rilanciando fra un mese puoi ottenere un'altra versione. Per un'installazione
  ripetibile si usa il tag di una release al posto di `stable`.
- Il log del port-forward sta in `/tmp/argocd-port-forward.log`: se la UI non risponde, guarda lì.
- Con `--address 0.0.0.0` la UI è aperta a tutta la rete di casa.

## Prova da solo

1. `kubectl api-resources --api-group=argoproj.io`: quali tipi ha aggiunto Argo, e sono namespaced?
2. `kubectl -n argocd get statefulset,deploy`: perché il controller è uno StatefulSet?
3. Chiudi il port-forward e rilancia solo il passo 9 con `DA=9`: il `pgrep` cosa evita?
