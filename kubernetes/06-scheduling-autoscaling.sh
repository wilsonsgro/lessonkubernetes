#!/usr/bin/env bash
# Lezione 06 — scheduling (spread, priorità, taint) e autoscaling HPA.
source "$(dirname "$0")/../lib/passo.sh"
guardia_lab
titolo "06. Scheduling e autoscaling"
F="$LEZIONI/kubernetes/06-scheduling-autoscaling.yaml"

passo "Applica PriorityClass, Service e NetworkPolicy, Deployment 'api' con topologySpreadConstraints, HPA al 60% di CPU" \
  "kubectl apply -f $F"
passo "Colonna NODE: i Pod sono distribuiti su lab e lab-m02 grazie allo spread" \
  'kubectl -n lab get pod -l app=api -o wide'
passo "Metriche dal metrics-server: i Pod nuovi le hanno dopo ~1 minuto (finché mancano l'HPA non può decidere). Aspetto che arrivino" \
  'for i in $(seq 30); do kubectl top pod -n lab -l app=api >/dev/null 2>&1 && break; sleep 5; done; kubectl top pod -n lab -l app=api'
passo "Genero carico in background per 120 s: un Pod con ruolo=client (ammesso dalla NetworkPolicy) che chiama api in loop" \
  "kubectl -n lab run carico --restart=Never --image=busybox:1.37 --labels=ruolo=client -- sh -c 'end=\$((\$(date +%s)+120)); while [ \$(date +%s) -lt \$end ]; do wget -q -O- http://api/ >/dev/null; done'"
passo "Guardo l'HPA per 90 s: TARGETS sale sopra il 60% e REPLICAS aumenta" \
  'timeout 90 kubectl -n lab get hpa api -w || true'
passo "Il 60% è delle REQUESTS (20m per Pod), non del nodo: la soglia è 12m medi per Pod. Confronta con il consumo" \
  "kubectl -n lab get deploy api -o jsonpath='{.spec.template.spec.containers[0].resources.requests}'; echo; kubectl -n lab top pod -l app=api"
nota "Esempio misurato sul lab: TARGETS 375% = 75m per Pod su 20m di request." \
     "desiderate = ceil(2 × 375 / 60) = 13 → tagliate a maxReplicas 8; la policy +100% ogni 15 s le fa salire 2 → 4 → 8."
passo "Gli eventi di scala: perché l'HPA ha deciso di salire" \
  'kubectl -n lab describe hpa api | tail -15'
passo "Taint sul worker: da ora nessun Pod NUOVO senza toleration va su lab-m02 (quelli già lì restano: NoSchedule, non NoExecute)" \
  'kubectl taint nodes lab-m02 dedicato=batch:NoSchedule; kubectl describe node lab-m02 | grep -A2 Taints'
passo "Tolgo il taint: il trattino finale significa 'rimuovi'" \
  'kubectl taint nodes lab-m02 dedicato=batch:NoSchedule-'
passo "Pulizia del Pod di carico (l'HPA riscende da solo: dopo 120 s di calo, un Pod al minuto)" \
  'kubectl -n lab delete pod carico --ignore-not-found'
