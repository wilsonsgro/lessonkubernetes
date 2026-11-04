#!/usr/bin/env bash
# Argo CD 4 — il ciclo GitOps sul sito: Application, self-heal, nuova versione con un commit, rollback con git revert, prune.
source "$(dirname "$0")/comune.sh"
guardia_lab
titolo "Argo CD 4. GitOps sul sito"
[[ -d "$REPO/.git" ]] || { echo "prima esegui argocd/02 e argocd/03"; exit 1; }
assicura_argocd
SITO="curl -s -H 'Host: mio-sito.local' http://$(minikube -p lab ip)/ | grep -o 'versione: <strong>[^<]*' | sed 's/<strong>//'"

passo "L'Application: QUALE repository e cartella (source) vanno in QUALE cluster e namespace (destination), e come sincronizzare" \
  "cat $REPO/argocd/application.yaml"
passo "La consegno ad Argo CD. È l'unico kubectl apply del sito: da qui in poi lo fa Argo leggendo git" \
  "kubectl apply -f $REPO/argocd/application.yaml"
passo "Aspetto Synced (il cluster è uguale a git) e Healthy (i pod sono pronti)" \
  'argocd app wait mio-sito --sync --health --timeout 180'
passo "Lo stato visto da Argo: revisione git applicata e ogni risorsa con il suo stato" \
  'argocd app get mio-sito'
passo "Gli oggetti nel cluster: nessuno li ha creati a mano" \
  'kubectl -n mio-sito get deploy,pod,svc,ingress'
passo "Il sito attraverso l'Ingress (Host: mio-sito.local)" \
  "$SITO"

titolo "Self-heal: il cluster non si cambia con kubectl"
passo "Modifico il cluster a mano: 5 repliche invece delle 2 scritte in git…" \
  'kubectl -n mio-sito scale deploy mio-sito --replicas=5 && kubectl -n mio-sito get deploy mio-sito'
passo "…selfHeal: true lo riporta a come dice git in pochi secondi" \
  'sleep 15; kubectl -n mio-sito get deploy mio-sito'

titolo "Nuova versione = un commit"
passo "La CI costruirebbe mio-sito:v2; qui build e caricamento a mano" \
  "docker build -q --build-arg VERSIONE=v2 -t mio-sito:v2 $REPO/sito && minikube -p lab image load mio-sito:v2"
passo "Cambio il desiderato IN GIT: immagine v2 e 3 repliche" \
  "cd $REPO && sed -i 's/mio-sito:v1/mio-sito:v2/; s/replicas: 2/replicas: 3/' kubernetes/deployment.yaml && git diff"
passo "Commit e push" \
  "cd $REPO && git commit -qam 'mio-sito v2, 3 repliche' && git push -q origin main && git log --oneline -3"
passo "Argo controlla git ogni 2–3 minuti (120 s + fino a 60 s di jitter); --refresh lo fa subito (in produzione: un webhook dal server git)" \
  'argocd app get mio-sito --refresh >/dev/null && argocd app wait mio-sito --sync --health --timeout 180 >/dev/null && argocd app get mio-sito | grep -E "Sync Status|Health Status"'
passo "Il sito ora è v2 con 3 pod" \
  "$SITO; kubectl -n mio-sito get deploy mio-sito -o wide"
passo "La storia dei deploy: ogni riga è una revisione git" \
  'argocd app history mio-sito'

titolo "Rollback = git revert"
nota "Con il sync automatico 'argocd app rollback' è vietato: il cluster tornerebbe a v2 al giro dopo." \
     "Si torna indietro in git, e git tiene traccia di chi e perché."
passo "Revert dell'ultimo commit e push" \
  "cd $REPO && git revert --no-edit HEAD >/dev/null && git push -q origin main && git log --oneline -3"
passo "Refresh e attesa" \
  'argocd app get mio-sito --refresh >/dev/null && argocd app wait mio-sito --sync --health --timeout 180 >/dev/null && argocd app get mio-sito | grep -E "Sync Status|Health Status"'
passo "Di nuovo v1 con 2 pod" \
  "$SITO; kubectl -n mio-sito get deploy mio-sito -o wide"

titolo "prune: false — cosa succede se tolgo un file da git"
passo "Tolgo ingress.yaml dal repository e faccio push" \
  "cd $REPO && git rm -q kubernetes/ingress.yaml && git commit -qm 'via ingress' && git push -q origin main"
passo "Argo vede la differenza ma NON cancella: l'Ingress resta, l'Application è OutOfSync (requires pruning)" \
  'argocd app get mio-sito --refresh | grep -iE "Sync Status|ingress"; kubectl -n mio-sito get ingress'
passo "Pruning manuale: sync con --prune cancella ciò che non è più in git" \
  'argocd app sync mio-sito --prune >/dev/null; kubectl -n mio-sito get ingress'
passo "Rimetto l'Ingress con un revert: torna nel cluster da solo" \
  "cd $REPO && git revert --no-edit HEAD >/dev/null && git push -q origin main && argocd app get mio-sito --refresh >/dev/null && argocd app wait mio-sito --sync --health --timeout 180 >/dev/null; kubectl -n mio-sito get ingress; $SITO"

titolo "Terraform e Argo CD insieme: la quota vale anche per Argo"
passo "Commit con 8 repliche: la ResourceQuota di Terraform ne permette 6 pod" \
  "cd $REPO && sed -i 's/replicas: 2/replicas: 8/' kubernetes/deployment.yaml && git commit -qam '8 repliche' && git push -q origin main && argocd app get mio-sito --refresh >/dev/null"
passo "Argo applica git (Synced), ma Kubernetes rifiuta i pod oltre la quota: 6 su 8" \
  "sleep 20; kubectl -n mio-sito get deploy mio-sito; kubectl -n mio-sito get events --field-selector reason=FailedCreate -o custom-columns=MSG:.message | tail -2"
passo "Revert: di nuovo 2 repliche" \
  "cd $REPO && git revert --no-edit HEAD >/dev/null && git push -q origin main && argocd app get mio-sito --refresh >/dev/null && argocd app wait mio-sito --sync --health --timeout 180 >/dev/null; kubectl -n mio-sito get deploy mio-sito"

nota "UI:  https://192.168.1.79:8083 → mio-sito: l'albero delle risorse, la storia, i diff." \
     "Facoltativo:  bash argocd/05-stack-con-argocd.sh  (lo stack HAProxy/nginx/PHP/Redis/MariaDB gestito da Argo)" \
     "Pulizia:  bash argocd/99-pulizia.sh"
