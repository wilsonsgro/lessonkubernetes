#!/usr/bin/env bash
# Argo CD — pulizia: toglie Application, sito, stack, Gitea e Argo CD; gli script e il modello restano.
source "$(dirname "$0")/comune.sh"
guardia_lab
titolo "Argo CD. Pulizia"

passo "Cancello le Application. Senza il finalizer resources-finalizer.argocd.argoproj.io gli oggetti nel cluster RESTANO: li tolgo dopo" \
  'kubectl -n argocd delete application mio-sito stack-web --ignore-not-found'
passo "Il namespace del sito lo ha creato Terraform: lo toglie Terraform" \
  "cd $REPO/terraform && terraform destroy -input=false -auto-approve"
passo "Lo stack e Gitea" \
  'kubectl delete ns stack-web gitea --ignore-not-found'
passo "Argo CD: stesso manifest dell'installazione, in delete (toglie anche CRD e ruoli a livello di cluster)" \
  'kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --ignore-not-found >/dev/null; kubectl delete ns argocd --ignore-not-found'
passo "Port-forward, immagini del sito nei nodi e cartella di lavoro" \
  "pkill -f 'port-forward --address 0.0.0.0 svc/argocd-server'; minikube -p lab image rm mio-sito:v1 mio-sito:v2; rm -rf $LAVORO/argocd"
