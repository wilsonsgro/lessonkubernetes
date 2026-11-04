#!/usr/bin/env bash
# Lezione 07 — RBAC con ServiceAccount e Pod Security Admission "restricted".
source "$(dirname "$0")/../lib/passo.sh"
guardia_lab
titolo "07. RBAC e Pod Security"
F="$LEZIONI/kubernetes/07-rbac-pod-security.yaml"
SA=system:serviceaccount:lab-sicuro:deployer

passo "Applica namespace lab-sicuro (PSA restricted), ServiceAccount deployer, Role, RoleBinding e un nginx non-root" \
  "kubectl apply -f $F"
passo "auth can-i --as: chiedo all'apiserver cosa può fare il ServiceAccount. Leggere i Pod: sì" \
  "kubectl auth can-i get pods -n lab-sicuro --as=$SA"
passo "Leggere i Secret: no, il Role non lo concede" \
  "kubectl auth can-i get secrets -n lab-sicuro --as=$SA"
passo "Modificare Deployment in un ALTRO namespace: no, un RoleBinding vale solo nel suo namespace" \
  "kubectl auth can-i patch deployments -n lab --as=$SA"
passo "Tutti i permessi del ServiceAccount nel namespace" \
  "kubectl auth can-i --list -n lab-sicuro --as=$SA"
passo "Un Pod busybox qualunque (root, senza securityContext) viene RIFIUTATO dalla PSA: il messaggio elenca cosa manca" \
  'kubectl -n lab-sicuro run root --image=busybox:1.37 -- sleep 1d'
passo "L'nginx del manifest invece gira: non-root, niente privilegi, seccomp RuntimeDefault, capabilities tolte" \
  'kubectl -n lab-sicuro rollout status deploy/nginx --timeout=90s && kubectl -n lab-sicuro get pod'
