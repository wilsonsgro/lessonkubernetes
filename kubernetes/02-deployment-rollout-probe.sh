#!/usr/bin/env bash
# Lezione 02 — Deployment, rollout, rollback, probe e QoS.
source "$(dirname "$0")/../lib/passo.sh"
guardia_lab
titolo "02. Deployment, rollout e probe"
F="$LEZIONI/kubernetes/02-deployment-rollout-probe.yaml"

passo "Controllo il contesto: deve essere 'lab' prima di ogni apply" \
  'kubectl config current-context'
passo "Applica il manifest: Namespace 'lab' + Deployment 'web' con probe e risorse. apply è dichiarativo: crea o aggiorna" \
  "kubectl apply -f $F"
passo "Aspetta che tutte le repliche nuove siano pronte (readiness probe superata)" \
  'kubectl -n lab rollout status deploy/web'
passo "Cambia immagine: parte un rolling update, un ReplicaSet nuovo sale mentre il vecchio scende" \
  'kubectl -n lab set image deploy/web web=traefik/whoami:v1.11'
passo "Seguo il rolling update fino alla fine: maxSurge 1 / maxUnavailable 0 = mai meno di 3 Pod pronti" \
  'kubectl -n lab rollout status deploy/web && kubectl -n lab get deploy web -o wide'
passo "Annota il motivo del rollout: finisce nella colonna CHANGE-CAUSE della history" \
  'kubectl -n lab annotate deploy/web kubernetes.io/change-cause="whoami v1.11" --overwrite'
passo "Storia dei rollout: ogni revisione è un ReplicaSet conservato" \
  'kubectl -n lab rollout history deploy/web'
passo "Rollback alla revisione 1: Kubernetes rimette in scala il ReplicaSet vecchio" \
  'kubectl -n lab rollout undo deploy/web --to-revision=1 && kubectl -n lab rollout status deploy/web'
passo "Prova che il rollback è avvenuto: l'immagine in uso è di nuovo la v1.12" \
  "kubectl -n lab get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}'; echo"
passo "Gli eventi del namespace: ScalingReplicaSet su e giù, il racconto del rollout" \
  'kubectl -n lab get events --sort-by=.metadata.creationTimestamp | grep -i scaling | tail -8'
passo "I ReplicaSet della storia: uno con le repliche, gli altri a 0 (revisionHistoryLimit decide quanti tenerne)" \
  'kubectl -n lab get rs -o wide'
passo "Classe QoS dei Pod: Guaranteed / Burstable / BestEffort, decide chi viene sfrattato per primo" \
  'kubectl -n lab get pod -o custom-columns=NOME:.metadata.name,QOS:.status.qosClass'
passo "Perché Burstable: requests cpu 50m e memoria 32Mi, limit solo sulla memoria (64Mi). Guaranteed vuole request = limit per cpu E memoria" \
  "kubectl -n lab get deploy web -o jsonpath='{.spec.template.spec.containers[0].resources}'; echo"
nota "Il Deployment resta acceso: la lezione 03 ci mette davanti Service, Ingress e NetworkPolicy."
