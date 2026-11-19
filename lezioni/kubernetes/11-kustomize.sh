#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# 11. KUSTOMIZE: BASE, OVERLAY, PATCH, GENERATOR E COMPONENT
# Versione: kustomize 5.7 (dentro kubectl 1.35: `kubectl apply -k`)
# Livello: 4 — Packaging e delivery
# ═══════════════════════════════════════════════════════════════════════════
# Kustomize non ha template: parte da YAML valido (la base) e lo
# trasforma con overlay dichiarativi. Ciò che vedi in git è YAML vero,
# applicabile e validabile; le differenze tra ambienti sono patch piccole.
#
#   base/                    ciò che è uguale ovunque
#   components/monitoring/   un pezzo opzionale, riusabile tra overlay
#   overlays/dev/            dev = base + 1 replica + debug
#   overlays/prod/           prod = base + 3 repliche + risorse + PDB + monitoring
#
# TRASFORMATORI PRINCIPALI (in kustomization.yaml)
#   namespace, namePrefix/nameSuffix   su tutti gli oggetti
#   labels (includeSelectors: false)   label senza toccare i selector
#                                      immutabili (commonLabels li tocca!)
#   images                             cambia tag/digest senza patch
#   replicas                           cambia le repliche senza patch
#   patches                            strategic merge o JSON 6902 (op/path)
#   configMapGenerator/secretGenerator crea ConfigMap con SUFFISSO HASH e
#                                      aggiorna i riferimenti: cambio di
#                                      config = nuovo nome = rollout
#
# LAB
#   bash 11-kustomize.sh crea
#   kubectl kustomize kust/overlays/prod | less      # rendering, senza cluster
#   diff <(kubectl kustomize kust/overlays/dev) <(kubectl kustomize kust/overlays/prod)
#   bash 11-kustomize.sh prova
#
# ── NEL PROGETTO VERO: il Biodistretto su minikube ───────────────────────
#   ~/biodistretto/kubernetes (branch kubernetes). I grep partono da lì:
#   cd ~/biodistretto/kubernetes · come si usa: il README della cartella
#   Kustomize fa ripartire i Pod quando cambia la config aggiungendo un hash
#   al NOME della ConfigMap (configMapGenerator). Il progetto ottiene lo
#   stesso risultato tenendo fisso il nome e mettendo l'hash in
#   un'annotazione del Pod:
#     grep -n 'checksum_' terraform/app/workload.tf
#     grep -n 'biodistretto/config' terraform/app/manifests/app.yaml.tftpl
#   DA COLLOQUIO: con l'hash nel nome restano le ConfigMap vecchie, utili
#   per il rollback ma da potare. Con l'annotazione no, però il rollback
#   della config passa dal codice.

set -euo pipefail
K=./kust

crea() {
  mkdir -p $K/base $K/components/monitoring $K/overlays/dev $K/overlays/prod

  cat > $K/base/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
spec:
  replicas: 1
  selector:
    matchLabels: { app: api }
  template:
    metadata:
      labels: { app: api }
    spec:
      containers:
        - name: api
          image: traefik/whoami:v1.11
          args: ["--port", "8080"]
          envFrom:
            - configMapRef: { name: api-config }   # il generator aggiunge l'hash qui
          ports:
            - { name: http, containerPort: 8080 }
          readinessProbe:
            httpGet: { path: /health, port: http }
EOF

  cat > $K/base/service.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: api
spec:
  selector: { app: api }
  ports:
    - { name: http, port: 80, targetPort: http }
EOF

  cat > $K/base/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
labels:
  - pairs:
      app.kubernetes.io/part-of: negozio
    includeSelectors: false
configMapGenerator:
  - name: api-config
    literals:
      - LOG_LEVEL=info
EOF

  # ── COMPONENT: attivabile da qualunque overlay ──────────────────────────
  cat > $K/components/monitoring/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component
patches:
  - target: { kind: Deployment, name: api }
    patch: |-
      - op: add
        path: /spec/template/metadata/annotations
        value:
          prometheus.io/scrape: "true"
          prometheus.io/port: "8080"
EOF

  cat > $K/overlays/dev/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: negozio-dev
resources:
  - ../../base
  - namespace.yaml
configMapGenerator:
  - name: api-config
    behavior: merge            # unisce ai valori della base
    literals:
      - LOG_LEVEL=debug
EOF
  printf 'apiVersion: v1\nkind: Namespace\nmetadata:\n  name: negozio-dev\n' > $K/overlays/dev/namespace.yaml

  cat > $K/overlays/prod/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: negozio-prod
resources:
  - ../../base
  - namespace.yaml
  - pdb.yaml
components:
  - ../../components/monitoring
replicas:
  - name: api
    count: 3
images:
  - name: traefik/whoami         # il nome nella base
    newTag: v1.12                # in CI: kustomize edit set image traefik/whoami:<sha>
                                 # (serve il binario kustomize: kubectl non ha "edit")
patches:
  # strategic merge: si scrive come un pezzo dell'oggetto
  - path: risorse.yaml
  # JSON 6902: operazioni precise su un path
  - target: { kind: Deployment, name: api }
    patch: |-
      - op: add
        path: /spec/template/spec/topologySpreadConstraints
        value:
          - maxSkew: 1
            topologyKey: kubernetes.io/hostname
            whenUnsatisfiable: ScheduleAnyway
            labelSelector: { matchLabels: { app: api } }
EOF
  printf 'apiVersion: v1\nkind: Namespace\nmetadata:\n  name: negozio-prod\n' > $K/overlays/prod/namespace.yaml

  cat > $K/overlays/prod/risorse.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
spec:
  template:
    spec:
      containers:
        - name: api              # le liste di container si fondono per "name"
          resources:
            requests: { cpu: 50m, memory: 32Mi }
            limits: { memory: 64Mi }
EOF

  cat > $K/overlays/prod/pdb.yaml <<'EOF'
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: api
spec:
  minAvailable: 2
  selector:
    matchLabels: { app: api }
EOF
  echo "struttura scritta in $K"
}

prova() {
  [[ "$(kubectl config current-context)" == "lab" ]] || { echo "STOP: contesto non 'lab'" >&2; exit 1; }
  kubectl kustomize $K/overlays/prod | grep -E 'name: api-config|image:|replicas:|prometheus.io/scrape'
  kubectl apply -k $K/overlays/prod
  kubectl -n negozio-prod rollout status deploy/api --timeout=2m
  local prima dopo
  prima=$(kubectl -n negozio-prod get deploy api -o jsonpath='{.spec.template.spec.containers[0].envFrom[0].configMapRef.name}')

  # cambio di config → nuovo hash → nuovo nome → rollout automatico
  sed -i 's/LOG_LEVEL=info/LOG_LEVEL=warn/' $K/base/kustomization.yaml
  kubectl diff -k $K/overlays/prod || true      # exit 1 = ci sono differenze
  kubectl apply -k $K/overlays/prod
  kubectl -n negozio-prod rollout status deploy/api --timeout=2m
  dopo=$(kubectl -n negozio-prod get deploy api -o jsonpath='{.spec.template.spec.containers[0].envFrom[0].configMapRef.name}')
  echo "ConfigMap: $prima → $dopo"
  # il vecchio ConfigMap resta: serve per il rollback. Per pulirlo:
  #   kubectl apply -k ... --prune -l app.kubernetes.io/part-of=negozio
  #   o Argo CD con prune attivo.
  kubectl -n negozio-prod get cm
}

case "${1:-}" in
  crea) crea ;;
  prova) prova ;;
  pulisci) kubectl delete ns negozio-prod negozio-dev --ignore-not-found ;;
  *) echo "uso: $0 crea|prova|pulisci" ;;
esac

# ── DOMANDE DA COLLOQUIO ────────────────────────────────────────────────────
# D: Perché commonLabels è pericoloso su un Deployment già in produzione?
# R: Aggiunge le label anche a spec.selector, che è immutabile: l'apply
#    fallisce. `labels` con includeSelectors: false le mette solo nei
#    metadata (e nel template).
#
# D: Strategic merge patch o JSON 6902?
# R: Strategic merge è leggibile e conosce le chiavi di fusione delle
#    liste (containers per name); JSON 6902 serve per operazioni precise
#    (remove, add in un indice, oggetti CRD senza schema di merge).
#
# D: Come promuovi la stessa versione da staging a prod in GitOps?
# R: La CI fa `kustomize edit set image app:<sha>` nell'overlay di staging
#    e apre una PR; la promozione è una PR che copia lo stesso tag (o
#    digest) nell'overlay di prod. L'immagine non si ricostruisce.
#
# D: Kustomize con Helm?
# R: `helmCharts:` in kustomization (con --enable-helm) renderizza un
#    chart e poi lo patcha; oppure helm --post-renderer kustomize.

# ══════════════════════════════════════════════════════════════════════════
# RIEPILOGO
# • Base in YAML vero + overlay per ambiente; component per i pezzi opzionali
# • images e replicas senza patch; patches strategic merge o JSON 6902
# • configMapGenerator: hash nel nome = ogni cambio di config è un rollout
# • labels con includeSelectors: false, non commonLabels
# • kubectl kustomize / diff -k / apply -k; edit set image in CI
# ══════════════════════════════════════════════════════════════════════════
