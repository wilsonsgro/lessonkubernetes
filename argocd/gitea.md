# gitea.yaml — un server git dentro il cluster

Spiegazione di `gitea.yaml` (questa cartella). Lo applica lo script `02-git-locale.sh` (passo 1).

## In una frase

Argo CD **tira** da un repository git. Invece di GitHub, qui il repository sta su **Gitea dentro il cluster `lab`**:
tutto resta sul PC. Il file crea quattro oggetti: Namespace, PVC, Deployment e Service.

## Gli oggetti

### Namespace `gitea`

Tutto Gitea sta nel suo namespace. Così la pulizia è un solo comando (`kubectl delete ns gitea`, script 99).

### PersistentVolumeClaim `gitea`

| Campo | Valore | Perché |
|---|---|---|
| `accessModes` | `[ReadWriteOnce]` | un solo nodo alla volta monta il disco: basta, c'è una replica |
| `storage` | `1Gi` | repository e database di Gitea sono piccoli |

Non indica `storageClassName`: usa quella di default di minikube (`standard`, hostpath).

### Deployment `gitea`

| Campo | Valore | Perché |
|---|---|---|
| `replicas` | `1` | Gitea con SQLite non si replica |
| `strategy.type` | `Recreate` | all'aggiornamento prima **spegne** il Pod vecchio, poi accende il nuovo. Con `RollingUpdate` due Pod userebbero lo stesso disco RWO e lo stesso file SQLite nello stesso momento |
| `nodeSelector` | `minikube.k8s.io/primary: "true"` | il Pod sta sul **nodo principale** (`lab`). Il commento in cima al file spiega perché: il provisioner hostpath di minikube crea la cartella del volume solo lì, e un `subPath` la vuole già esistente. Sull'altro nodo il Pod non partirebbe |
| `securityContext.fsGroup` | `1000` | i file del volume diventano del gruppo 1000, con cui gira l'immagine *rootless* |
| `image` | `gitea/gitea:1.24-rootless` | Gitea che gira senza root |
| `containerPort` | `3000` | la porta HTTP di Gitea |

Le variabili d'ambiente `GITEA__sezione__CHIAVE` sostituiscono le voci del file di configurazione `app.ini`:

| Variabile | Effetto |
|---|---|
| `GITEA__database__DB_TYPE=sqlite3` | database in un file, niente Postgres o MySQL |
| `GITEA__security__INSTALL_LOCK=true` | salta la procedura di installazione web: è già configurato |
| `GITEA__server__ROOT_URL=http://gitea.gitea.svc.cluster.local:3000/` | l'indirizzo "ufficiale" è quello **interno** al cluster, lo stesso che usa Argo CD |
| `GITEA__server__DISABLE_SSH=true` | solo HTTP, niente server SSH |
| `GITEA__service__DISABLE_REGISTRATION=true` | nessuno si può registrare da solo: l'utente lo crea lo script 02 |
| `GITEA__repository__ENABLE_PUSH_CREATE_USER=true` | **push-to-create**: il primo `git push` crea il repository, senza passare dalla UI |
| `GITEA__repository__DEFAULT_PUSH_CREATE_PRIVATE=false` | il repository creato così è **pubblico in lettura**: Argo CD lo legge senza credenziali |

`readinessProbe` su `/api/healthz`, porta 3000: il Pod riceve traffico solo quando Gitea risponde.

Un solo volume `dati` (il PVC) montato **due volte** con `subPath` diversi:

| mountPath | subPath | Contenuto |
|---|---|---|
| `/var/lib/gitea` | `dati` | repository e database |
| `/etc/gitea` | `config` | `app.ini` |

### Service `gitea`

`type: NodePort`, porta 3000 → `nodePort: 30300`. Gitea si raggiunge in due modi:

| Da dove | Indirizzo | Chi lo usa |
|---|---|---|
| dall'Ubuntu | `http://<IP del nodo>:30300` (per esempio `http://192.168.49.2:30300`) | tu, `git push`, la UI |
| da dentro il cluster | `http://gitea.gitea.svc.cluster.local:3000` | Argo CD (`repoURL` dell'Application) |

I nodi minikube (192.168.49.x) si vedono solo dall'Ubuntu, non dal Mac.

## Trappole

- Togliere il `nodeSelector` sembra innocuo, ma se lo scheduler mette il Pod su `lab-m02` il volume con `subPath` non
  si monta. È lo stesso limite dell'hostpath di minikube con due nodi che compare nella lezione 05.
- `INSTALL_LOCK` e `DISABLE_REGISTRATION` insieme: senza l'utente creato dallo script 02 non c'è modo di entrare.
- Il repository è **pubblico**: va bene sul lab. Con un repository privato l'Application avrebbe bisogno di
  credenziali (un Secret di tipo repository in Argo CD).

## Prova da solo

1. `kubectl -n gitea get pod -o wide`: su quale nodo gira? Confrontalo con `kubectl get nodes --show-labels | grep primary`.
2. `kubectl -n gitea exec deploy/gitea -- ls /etc/gitea /var/lib/gitea`: cosa c'è nei due subPath?
3. `kubectl -n gitea exec deploy/gitea -- id`: con quale utente e gruppo gira Gitea? Torna con `fsGroup: 1000`?
