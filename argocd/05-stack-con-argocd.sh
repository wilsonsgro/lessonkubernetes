#!/usr/bin/env bash
# Argo CD 5 — l'infrastruttura che hai già (stack/stack.yaml) passa sotto Argo CD senza ricostruirla.
source "$(dirname "$0")/comune.sh"
guardia_lab
titolo "Argo CD 5. Lo stack HAProxy → nginx → PHP → Redis + MariaDB gestito da Argo"
[[ -d "$REPO/.git" ]] || { echo "prima esegui argocd/02-git-locale.sh"; exit 1; }
assicura_argocd
NODO="$(minikube -p lab ip)"

nota "Se lo stack gira già (bash stack/stack.sh), Argo ADOTTA gli oggetti esistenti: niente da ricreare." \
     "Qui prune: true — togliere un oggetto da git lo toglie dal cluster (diverso da mio-sito)."

passo "Lo stesso stack.yaml entra nel repository, cartella stack/" \
  "mkdir -p $REPO/stack && cp $PRJ/stack/stack.yaml $REPO/stack/ && cd $REPO && git add stack && { git commit -qm 'stack-web sotto Argo CD' || true; } && git push -q origin main && git log --oneline -1"
passo "L'Application dello stack (path: stack, prune e selfHeal attivi)" \
  "cat $REPO/argocd/stack-web.yaml && kubectl apply -f $REPO/argocd/stack-web.yaml"
passo "Attesa: MariaDB inizializza il database, ci vuole un po'" \
  'argocd app wait stack-web --sync --health --timeout 300 >/dev/null; argocd app list'
passo "Ogni oggetto porta l'annotation di tracking di Argo: così sa quali oggetti sono suoi (Argo CD 3.x usa l'annotation, non più l'etichetta)" \
  "kubectl -n stack-web get deploy,statefulset -o custom-columns='NOME:.metadata.name,TRACKING:.metadata.annotations.argocd\\.argoproj\\.io/tracking-id'"
passo "Una richiesta attraverso tutta la catena" \
  "for i in \$(seq 20); do curl -sf http://$NODO:30080/ | grep -q visite && break; sleep 2; done; curl -s -i http://$NODO:30080/ | grep -iE 'x-servito-da|php_pod|nginx_pod|mariadb|visite'"
passo "Scalare php da 3 a 4 si fa in git" \
  "cd $REPO && sed -i '/name: php\$/,/replicas:/ s/replicas: 3/replicas: 4/' stack/stack.yaml && git diff --stat && git commit -qam 'php a 4 repliche' && git push -q origin main"
passo "Refresh: php sale a 4" \
  'argocd app get stack-web --refresh >/dev/null && argocd app wait stack-web --sync --health --timeout 180 >/dev/null; kubectl -n stack-web get deploy php'
passo "Revert: di nuovo 3" \
  "cd $REPO && git revert --no-edit HEAD >/dev/null && git push -q origin main && argocd app get stack-web --refresh >/dev/null && argocd app wait stack-web --sync --health --timeout 180 >/dev/null; kubectl -n stack-web get deploy php"

nota "Pulizia:  bash argocd/99-pulizia.sh"
