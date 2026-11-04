#!/usr/bin/env bash
# Lezione 11 — Kustomize: base, overlay dev/prod, component, configMapGenerator.
source "$(dirname "$0")/../lib/passo.sh"
guardia_lab
titolo "11. Kustomize"
cartella kustomize

passo "Scrivo la struttura kust/: base comune, overlays dev e prod, component monitoring" \
  "bash $LEZIONI/kubernetes/11-kustomize.sh crea"
passo "La struttura" \
  'find kust -type f | sort'
passo "L'overlay prod: parte dalla base e la modifica con patch, immagini, repliche, component" \
  'cat kust/overlays/prod/kustomization.yaml'
passo "kubectl kustomize: renderizza senza cluster. Guardo cosa cambia in prod" \
  "kubectl kustomize kust/overlays/prod | grep -E 'name: api-config|image:|replicas:|prometheus.io/scrape'"
passo "Differenza fra dev e prod, riga per riga (diff esce con 1 quando i file sono diversi: qui è voluto)" \
  'diff <(kubectl kustomize kust/overlays/dev) <(kubectl kustomize kust/overlays/prod)'
passo "apply -k: applica l'overlay prod" \
  'kubectl apply -k kust/overlays/prod && kubectl -n negozio-prod rollout status deploy/api --timeout=2m'
passo "Il nome della ConfigMap ha un hash: lo genera configMapGenerator dal contenuto" \
  "kubectl -n negozio-prod get deploy api -o jsonpath='{.spec.template.spec.containers[0].envFrom[0].configMapRef.name}{\"\\n\"}'"
passo "Cambio un valore nella base" \
  "sed -i 's/LOG_LEVEL=info/LOG_LEVEL=warn/' kust/base/kustomization.yaml && grep LOG_LEVEL kust/base/kustomization.yaml"
passo "kubectl diff -k: cosa cambierebbe nel cluster (uscita 1 = ci sono differenze, è normale)" \
  'kubectl diff -k kust/overlays/prod'
passo "Riapplico: hash nuovo → nome nuovo → il Deployment cambia → rollout automatico" \
  'kubectl apply -k kust/overlays/prod && kubectl -n negozio-prod rollout status deploy/api --timeout=2m'
passo "Restano entrambe le ConfigMap, vecchia e nuova: il rollback del Deployment ritrova la sua" \
  'kubectl -n negozio-prod get cm'
nota "Pulizia:  kubectl delete ns negozio-prod negozio-dev --ignore-not-found"
