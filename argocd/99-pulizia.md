# Argo CD — Pulizia

Spiegazione di `99-pulizia.sh` (questa cartella).

## In una frase

Toglie quello che gli script 01–05 hanno messo **nel cluster** e nella cartella di lavoro:
- le Application e il sito;
- lo stack e Gitea;
- Argo CD, il port-forward, le immagini nei nodi e `lavoro/argocd`.

Gli script e il modello `mio-progetto/` restano, e restano anche alcune cose fuori dal cluster (sezione «Cosa NON
toglie»).

## I passi, nell'ordine giusto

| Passo | Comando | Perché in questo punto |
|---|---|---|
| 1 | `kubectl -n argocd delete application mio-sito stack-web --ignore-not-found` | **per prime le Application**, finché Argo c'è. Senza il finalizer `resources-finalizer.argocd.argoproj.io` (le due Application non ce l'hanno) cancellare un'Application **non** cancella gli oggetti che gestiva: restano nel cluster, e li tolgono i passi dopo. Il vantaggio: Argo non prova a ricrearli mentre li togli |
| 2 | `cd $REPO/terraform && terraform destroy -input=false -auto-approve` | il namespace `mio-sito` (con quota e LimitRange) l'ha creato **Terraform**: lo toglie Terraform. Cancellando il namespace spariscono anche Deployment, Service e Ingress del sito |
| 3 | `kubectl delete ns stack-web gitea --ignore-not-found` | lo stack e Gitea, con i loro dischi: il PVC di Gitea e quello di MariaDB (nato dal `volumeClaimTemplates` dello StatefulSet). Cancellare il namespace cancella anche i PVC |
| 4 | `kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --ignore-not-found >/dev/null; kubectl delete ns argocd --ignore-not-found` | Argo CD con **lo stesso manifest dell'installazione**, in delete: toglie anche quello che non sta nel namespace, cioè le CRD e i ClusterRole. Poi il namespace |
| 5 | `pkill -f 'port-forward --address 0.0.0.0 svc/argocd-server'; minikube -p lab image rm mio-sito:v1 mio-sito:v2; rm -rf $LAVORO/argocd` | il port-forward, le immagini del sito caricate nei nodi, e `lavoro/argocd`: il repository di lavoro, la password di Gitea, le credenziali git e lo stato di Terraform |

`--ignore-not-found` evita l'errore quando un **oggetto** non c'è (passi 3 e 4). Non basta quando manca il **tipo**:
vedi il passo 1 nella sezione sotto.

## Perché quell'ordine

- Prima le Application, poi gli oggetti: altrimenti il self-heal li ricreerebbe.
- Terraform prima di cancellare `lavoro/argocd` (passo 5): lo **stato** di Terraform sta lì dentro. Senza lo stato
  Terraform non saprebbe più cosa ha creato, e il namespace `mio-sito` resterebbe da togliere a mano.
- Argo CD per ultimo fra gli oggetti del cluster.

## Cosa può comparire in rosso

- **Passo 1**, se la pulizia è già stata fatta: il passo 4 del giro prima ha tolto le CRD di Argo, quindi kubectl non
  conosce più il tipo `application` e fallisce. `--ignore-not-found` copre un oggetto assente, non un tipo che non
  esiste. È innocuo: non c'è niente da cancellare.
- **Passo 2**, due casi diversi:
  - `lavoro/argocd` non c'è più (pulizia già fatta, o script 02 mai lanciato): il `cd` fallisce;
  - lo script 02 è stato lanciato ma il 03 no: la cartella `terraform/` c'è, perché il 02 copia tutto il modello. Ma
    manca `terraform init`, quindi fallisce `terraform destroy`.

  Attenzione: lo script 04 controlla solo che il repository esista, quindi può girare anche senza il 03. In quel caso il
  namespace `mio-sito` l'ha creato **Argo** (`CreateNamespace=true`), non Terraform, e dopo la pulizia resta. Si
  toglie con `kubectl delete ns mio-sito`.
- **Passo 5**: la riga rossa dipende dall'**ultimo** comando, `rm -rf`, che riesce sempre. Se il port-forward era
  già chiuso o le immagini non ci sono, `pkill` e `image rm` falliscono, ma il rosso non compare.

## Cosa NON toglie

- Il cluster `lab` (per quello: `minikube -p lab stop` o `delete`).
- Le immagini `mio-sito:v1` e `v2` nel docker **dell'Ubuntu** (passo 5 le toglie solo dai nodi):
  `docker rmi mio-sito:v1 mio-sito:v2`.
- La CLI `~/.local/bin/argocd`.
- Il log del port-forward, `/tmp/argocd-port-forward.log`.
- L'ingress-nginx acceso dallo script 03 (serve anche alla lezione 03).

## Controllo dopo la pulizia

```bash
kubectl get ns | grep -E 'argocd|gitea|mio-sito|stack-web'   # niente
kubectl get crd | grep argoproj                                # niente
pgrep -fa 'svc/argocd-server'                                  # niente
ls ~/kubernetesprj/lavoro/argocd                               # «No such file or directory»
```
