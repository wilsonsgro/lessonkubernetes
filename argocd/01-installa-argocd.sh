#!/usr/bin/env bash
# Argo CD 1 — installazione nel cluster lab, password di admin, CLI e interfaccia web.
source "$(dirname "$0")/comune.sh"
guardia_lab
titolo "Argo CD 1. Installazione"

nota "Chi fa cosa:  Terraform crea le risorse infrastrutturali · minikube è il cluster locale" \
     "              Kubernetes gestisce i container · Argo CD tiene il cluster uguale a quello che c'è in git"

passo "Un namespace tutto per Argo CD (forma idempotente di: kubectl create namespace argocd)" \
  'kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -'
passo "Installo il manifest ufficiale. --server-side: le CRD di Argo superano il limite dell'annotation dell'apply classico; --force-conflicts: se rilanci, Argo vince sui campi già di altri" \
  'kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml'
passo "Le CRD: Argo aggiunge a Kubernetes nuovi tipi di oggetto (Application, AppProject, ApplicationSet)" \
  'kubectl get crd | grep argoproj'
passo "Aspetto che tutti i Deployment siano Available (il primo giro scarica le immagini: qualche minuto)" \
  'kubectl -n argocd wait --for=condition=Available deploy --all --timeout=5m && kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=5m'
passo "I pezzi: server (API+UI), repo-server (legge git e genera i manifest), application-controller (confronta e sincronizza), redis (cache), dex (SSO), notifications, applicationset-controller" \
  'kubectl -n argocd get pods -o wide'
passo "Versione installata (l'immagine del server)" \
  "kubectl -n argocd get deploy argocd-server -o jsonpath='{.spec.template.spec.containers[0].image}{\"\\n\"}'"
passo "Password iniziale di admin: sta in un Secret creato all'installazione (in produzione si cambia e il Secret si cancella)" \
  "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
passo "La CLI argocd, della stessa versione del server, in ~/.local/bin (niente sudo)" \
  "VER=\$(kubectl -n argocd get deploy argocd-server -o jsonpath='{.spec.template.spec.containers[0].image}' | cut -d: -f2); mkdir -p ~/.local/bin && curl -sSL -o ~/.local/bin/argocd https://github.com/argoproj/argo-cd/releases/download/\$VER/argocd-linux-amd64 && chmod +x ~/.local/bin/argocd && argocd version --client --short"
passo "Port-forward in background: la porta 443 del Service argocd-server diventa la 8083 di questo PC (--address 0.0.0.0: raggiungibile anche dal Mac)" \
  "pgrep -f 'port-forward --address 0.0.0.0 svc/argocd-server' || (nohup kubectl -n argocd port-forward --address 0.0.0.0 svc/argocd-server 8083:443 >/tmp/argocd-port-forward.log 2>&1 &); sleep 3; curl -sk -o /dev/null -w 'HTTP %{http_code}\n' https://localhost:8083/"
passo "Login della CLI (--insecure: il certificato è autofirmato; --grpc-web: passa bene attraverso il port-forward)" \
  "argocd login localhost:8083 --username admin --insecure --grpc-web --password \"\$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)\""
passo "Il cluster dove Argo deploya: quello in cui gira (https://kubernetes.default.svc)" \
  'argocd cluster list'
passo "Le Application del cluster (mio-sito arriva con argocd/04)" \
  'argocd app list'

nota "UI:  https://localhost:8083 qui, oppure https://192.168.1.79:8083 dal Mac (utente admin, password del passo sopra)" \
     "Chiudere il port-forward:  pkill -f 'port-forward --address 0.0.0.0 svc/argocd-server'" \
     "Prossimo:  bash argocd/02-git-locale.sh"
