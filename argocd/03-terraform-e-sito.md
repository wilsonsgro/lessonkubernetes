# Argo CD 3 — Immagine del sito e Terraform

Spiegazione di `03-terraform-e-sito.sh` (questa cartella). Laboratorio della lezione Kubernetes 16:
http://127.0.0.1:3000/kubernetes/16.

## In una frase

Prepara **tutto quello che Argo CD non fa**: costruisce l'immagine `mio-sito:v1` e la carica nei nodi, accende
l'ingress, e con **Terraform** crea il namespace `mio-sito` con quota e limiti.

## Prima di lanciarlo

Lo script 02: se `lavoro/argocd/mio-progetto/.git` non c'è, si ferma con «prima esegui argocd/02-git-locale.sh».

## La nota: cosa NON fa Argo CD

Argo CD **applica manifest**. Non costruisce immagini (lo fa la CI, qui un `docker build` a mano) e non crea il
terreno su cui girano (il namespace con quote e limiti lo fa Terraform).

## I passi

| Passo | Comando | Cosa vedi / perché |
|---|---|---|
| 1 | `cat $REPO/sito/Dockerfile` | il Dockerfile (sotto) |
| 2 | `docker build -q --build-arg VERSIONE=v1 -t mio-sito:v1 $REPO/sito` | l'immagine `mio-sito:v1`. **Tag immutabile**: per cambiare versione si cambia tag, non si sovrascrive `v1` |
| 3 | `minikube -p lab image load mio-sito:v1 && minikube -p lab image ls \| grep mio-sito` | minikube **non vede** le immagini del docker dell'Ubuntu: i nodi sono container con il loro runtime. `image load` le copia nei nodi, senza un registry |
| 4 | `minikube -p lab addons enable ingress >/dev/null && kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=3m` | il controller ingress-nginx, che serve a `ingress.yaml`. Se è già acceso (lezione 01) non cambia niente |
| 5 | `cat $REPO/terraform/main.tf` | il codice dell'infrastruttura (sotto) |
| 6 | `cd $REPO/terraform && terraform init -input=false` | scarica il provider `hashicorp/kubernetes` e prepara `.terraform/`, che è in `.gitignore` |
| 7 | `terraform fmt -check -diff && terraform validate` | stile e coerenza del codice, senza toccare il cluster |
| 8 | `terraform plan -input=false` | cosa creerebbe: **3 risorse** (namespace, ResourceQuota, LimitRange) |
| 9 | `terraform apply -input=false -auto-approve` | le crea |
| 10 | `kubectl get ns mio-sito --show-labels && kubectl -n mio-sito describe resourcequota quota` | il namespace con l'etichetta `gestito-da=terraform`, e la quota: quanto potrà metterci Argo |
| 11 | `terraform state list && git -C $REPO status --short --ignored terraform` | lo **stato** di Terraform è locale (`terraform.tfstate`) e **fuori da git**: `status --ignored` lo mostra fra gli ignorati, con `.terraform/` |
| 12 | `git add terraform/.terraform.lock.hcl && { git commit -qm 'terraform: lock del provider' \|\| true; } && git push -q origin main && git log --oneline -2` | il **lock file invece va in git**: fissa la versione esatta del provider per chiunque cloni il progetto |

## Il Dockerfile

```dockerfile
FROM nginx:1.29-alpine
ARG VERSIONE=v1
COPY index.html /usr/share/nginx/html/index.html
RUN sed -i "s/__VERSIONE__/${VERSIONE}/g" /usr/share/nginx/html/index.html
```

`index.html` contiene `versione: <strong>__VERSIONE__`. Al build `sed` sostituisce il segnaposto con il valore di
`--build-arg VERSIONE`: la versione finisce **dentro l'immagine**. Lo script 04 la legge dalla pagina per sapere quale
versione sta girando.

## Il Terraform

`terraform` richiede Terraform `>= 1.5` e il provider `hashicorp/kubernetes ~> 2.38`. Il provider usa
`~/.kube/config` e il contesto `lab` (variabili `kubeconfig` e `contesto`): Terraform parla con lo stesso cluster di
kubectl, ma lo sceglie **da sé**, senza dipendere dal contesto attivo.

| Risorsa | Cosa crea |
|---|---|
| `kubernetes_namespace_v1.sito` | il namespace `mio-sito` (variabile `namespace`) con l'etichetta `gestito-da = "terraform"` |
| `kubernetes_resource_quota_v1.sito` | la quota `quota`: `pods` = `var.max_pod` (6), `requests.cpu` 500m, `requests.memory` 256Mi, `limits.cpu` 2, `limits.memory` 1Gi |
| `kubernetes_limit_range_v1.sito` | il LimitRange `default`: ai container senza risorse dà request 20m / 16Mi e limit 100m / 64Mi |

Output: `namespace`, il nome del namespace creato.

Perché il LimitRange serve: con una ResourceQuota su `requests.*` e `limits.*`, Kubernetes **rifiuta** i Pod che non
dichiarano le risorse. Il LimitRange le mette per default.

Con i Pod del sito (request 20m / 16Mi, limit 100m / 64Mi) il limite che si raggiunge per primo è `pods: 6`: lo
script 04 lo mette alla prova con 8 repliche.

## Perché la divisione Terraform / Argo CD

| | Terraform | Argo CD |
|---|---|---|
| Cosa | il terreno: namespace, quote, limiti | cosa ci gira: Deployment, Service, Ingress |
| Stato | `terraform.tfstate` locale, fuori da git | il cluster stesso, confrontato con git |
| Quando cambia | di rado | a ogni rilascio (un commit) |

Il namespace è di Terraform: per questo la pulizia (script 99) lo toglie con `terraform destroy`, non con kubectl.

## Trappole

- Dimenticare il passo 3: il Deployment userebbe `mio-sito:v1` con `imagePullPolicy: IfNotPresent`, non la troverebbe
  nel nodo e proverebbe a scaricarla da Docker Hub: `ImagePullBackOff`.
- `terraform.tfstate` è solo su questo PC: se lo perdi, Terraform non sa più di aver creato il namespace.

## Prova da solo

1. `docker images | grep mio-sito` e `minikube -p lab image ls | grep mio-sito`: l'immagine è in due posti. Quale
   dei due usa il cluster?
2. `kubectl -n mio-sito describe limitrange default`: quali valori mette ai container senza risorse?
3. Cambia `max_pod` in `variables.tf` a `"4"` e lancia `terraform plan`: cosa cambierebbe, e su quale risorsa?
   Poi rimettilo a `"6"`.
