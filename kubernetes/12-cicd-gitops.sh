#!/usr/bin/env bash
# Lezione 12 — i passi di una pipeline a mano (build, scan, deploy) e GitOps con Argo CD.
source "$(dirname "$0")/../lib/passo.sh"
guardia_lab
titolo "12. CI/CD e GitOps"
cartella helm
[[ -d eco ]] || { echo "prima esegui la lezione 09: serve ./eco"; exit 1; }
TAG="$(date +%Y%m%d%H%M%S)"

passo "Un Dockerfile minimo per l'app (in CI sarebbe quello del repository)" \
  "printf 'FROM traefik/whoami:v1.12\nLABEL org.opencontainers.image.revision=$TAG\n' > Dockerfile && cat Dockerfile"
passo "BUILD: l'immagine prende un tag immutabile (in CI è lo SHA del commit, qui la data). Mai 'latest' in produzione" \
  "docker build -t localhost:5000/eco:$TAG ."
passo "SCAN con Trivy: --exit-code 1 fa FALLIRE la pipeline se trova vulnerabilità CRITICAL. Il primo giro scarica il database (lento)" \
  "docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest image --severity CRITICAL --exit-code 1 localhost:5000/eco:$TAG"
passo "PUSH nel registry (quello della lezione 10, porta 5000)" \
  "docker ps --format '{{.Names}}' | grep -qx registry || docker run -d --name registry -p 5000:5000 registry:3; docker push localhost:5000/eco:$TAG"
passo "minikube non vede il localhost dell'host: carico l'immagine direttamente nei nodi del cluster" \
  "minikube -p lab image load localhost:5000/eco:$TAG"
passo "DEPLOY: lo stesso artefatto costruito una volta, promosso cambiando solo il tag. --rollback-on-failure se non parte" \
  "helm upgrade --install eco eco -n lab-cicd --create-namespace --set image.repository=localhost:5000/eco --set image.tag=$TAG --set image.pullPolicy=IfNotPresent --rollback-on-failure --wait --timeout 2m"
passo "Verifica: l'immagine in esecuzione è quella appena costruita" \
  "kubectl -n lab-cicd get deploy -o jsonpath='{..image}{\"\\n\"}'"

titolo "GitOps: Argo CD tira dal repository invece di ricevere push dalla CI"
passo "Namespace di Argo CD" \
  'kubectl create ns argocd --dry-run=client -o yaml | kubectl apply -f -'
passo "Installo Argo CD dal manifest ufficiale (--server-side: le CRD sono troppo grandi per l'apply client-side)" \
  'kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml'
passo "Aspetto che i componenti siano pronti (server, repo-server, application-controller…)" \
  'kubectl -n argocd rollout status deploy/argocd-server --timeout=5m && kubectl -n argocd get pods'
passo "Password iniziale di admin: è in un Secret creato all'installazione (va cambiata e il Secret cancellato)" \
  "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
passo "Una Application vera: il repository pubblico di esempio di Argo (guestbook), sync automatico con prune e selfHeal" \
  "kubectl apply -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    targetRevision: HEAD
    path: guestbook
  destination:
    server: https://kubernetes.default.svc
    namespace: guestbook
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions: [CreateNamespace=true]
EOF"
passo "Dopo ~1 minuto: Synced e Healthy, il Deployment è nel cluster senza che nessuno abbia fatto apply" \
  'sleep 60; kubectl -n argocd get application guestbook; kubectl -n guestbook get deploy'
passo "SELF-HEAL: modifico il cluster a mano (5 repliche invece di 1)…" \
  'kubectl -n guestbook scale deploy guestbook-ui --replicas=5'
passo "…e Argo CD lo riporta a come dice git. Il cluster non si cambia con kubectl, si cambia con un commit" \
  'sleep 20; kubectl -n guestbook get deploy guestbook-ui'
passo "UI di Argo CD: apri https://localhost:8443 (utente admin, password del passo sopra). Ctrl+C per chiudere" \
  'kubectl -n argocd port-forward svc/argocd-server 8443:443'
nota "Pulizia:  kubectl -n argocd delete application guestbook; kubectl delete ns argocd guestbook lab-cicd" \
     "Nel file della lezione c'è l'Application vera con overlay Kustomize e la pipeline GitLab completa."
