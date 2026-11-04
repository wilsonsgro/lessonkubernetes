#!/usr/bin/env bash
# Argo CD 2 — un server git (Gitea) dentro il cluster e il push del progetto: la "fonte di verità" che Argo legge.
source "$(dirname "$0")/comune.sh"
guardia_lab
titolo "Argo CD 2. Il repository git locale"
mkdir -p "$LAVORO/argocd"
[[ -s "$GITEA_PASS_FILE" ]] || { head -c 18 /dev/urandom | base64 | tr -d '/+=' > "$GITEA_PASS_FILE"; chmod 600 "$GITEA_PASS_FILE"; }

nota "Argo CD non riceve push: TIRA da un repository git. Al posto di GitHub uso Gitea nel cluster," \
     "così tutto resta su questo PC. Con GitHub cambierebbe solo repoURL nell'Application."

passo "Gitea: namespace, disco (PVC), Deployment e Service NodePort 30300" \
  "kubectl apply -f $ARGO/gitea.yaml"
passo "Aspetto Gitea pronto (risponde su /api/healthz)" \
  'kubectl -n gitea rollout status deploy/gitea --timeout=3m'
passo "Utente wilson (admin di Gitea). La password è generata e sta in lavoro/argocd/.gitea-pass. Se esiste già l'errore è voluto" \
  "kubectl -n gitea exec deploy/gitea -- gitea admin user create --username wilson --email wilson@lab.local --admin --must-change-password=false --password \"\$(cat $GITEA_PASS_FILE)\""
passo "Il progetto: copio il modello argocd/mio-progetto in lavoro/ (solo la prima volta, poi resta la sua storia git)" \
  "[[ -d $REPO/.git ]] || cp -r $ARGO/mio-progetto $REPO; cd $REPO && find . -path ./.git -prune -o -type f -print | sort"
passo "Ne faccio un repository git con un primo commit (ramo main)" \
  "cd $REPO && { [[ -d .git ]] || git init -q -b main; } && git config user.name wilson && git config user.email wilson@lab.local && git add -A && { git commit -q -m 'mio-sito v1' || true; } && git log --oneline"
passo "Credenziali per il push in un file del lavoro (credential.helper store), non nell'URL" \
  "cd $REPO && git config credential.helper \"store --file $LAVORO/argocd/.git-credentials\" && printf 'http://wilson:%s@%s\n' \"\$(cat $GITEA_PASS_FILE)\" \"\${GITEA#http://}\" > $LAVORO/argocd/.git-credentials && chmod 600 $LAVORO/argocd/.git-credentials"
passo "Remote origin su Gitea, visto da questo PC tramite il NodePort ($GITEA)" \
  "cd $REPO && { git remote get-url origin >/dev/null 2>&1 && git remote set-url origin $GITEA/wilson/mio-progetto.git || git remote add origin $GITEA/wilson/mio-progetto.git; } && git remote -v"
passo "Push: Gitea crea il repository al primo push (push-to-create), pubblico in lettura" \
  "cd $REPO && git push -u origin main"
passo "Lo stesso repository visto DA DENTRO il cluster, dal repo-server di Argo CD: è l'indirizzo che userà l'Application" \
  'kubectl -n argocd exec deploy/argocd-repo-server -- git ls-remote http://gitea.gitea.svc.cluster.local:3000/wilson/mio-progetto.git'

nota "UI di Gitea:  $GITEA  (utente wilson, password in $GITEA_PASS_FILE)" \
     "Prossimo:  bash argocd/03-terraform-e-sito.sh"
