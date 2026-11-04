# Variabili e aiuti condivisi dagli script di Argo CD (sopra la libreria comune lib/passo.sh).
source "$(dirname "${BASH_SOURCE[0]}")/../lib/passo.sh"
export PATH="$HOME/.local/bin:$PATH"
ARGO="$PRJ/argocd"
REPO="$LAVORO/argocd/mio-progetto"
GITEA="http://$(minikube -p lab ip 2>/dev/null):30300"
GITEA_PASS_FILE="$LAVORO/argocd/.gitea-pass"

assicura_argocd() {
  pgrep -f 'port-forward --address 0.0.0.0 svc/argocd-server' >/dev/null || {
    nohup kubectl -n argocd port-forward --address 0.0.0.0 svc/argocd-server 8083:443 >/tmp/argocd-port-forward.log 2>&1 &
    sleep 3
  }
  argocd account get-user-info >/dev/null 2>&1 || argocd login localhost:8083 --username admin --insecure --grpc-web \
    --password "$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)" >/dev/null
}

push_e_refresh() {
  git -C "$REPO" push -q origin main && argocd app get mio-sito --refresh >/dev/null && argocd app wait mio-sito --sync --health --timeout 180 >/dev/null
}
