#!/usr/bin/env bash
# Lezione 03 — Service, Ingress e NetworkPolicy (richiede la 02 applicata).
source "$(dirname "$0")/../lib/passo.sh"
guardia_lab
titolo "03. Service, Ingress e NetworkPolicy"
F="$LEZIONI/kubernetes/03-service-ingress-networkpolicy.yaml"

passo "Applica Service 'web', Ingress su web.lab.local e due NetworkPolicy (deny di default + allow per ruolo=client)" \
  "kubectl apply -f $F"
passo "EndpointSlice: gli IP dei Pod pronti dietro al Service. Vuoto = selector sbagliato o Pod non ready" \
  'kubectl -n lab get endpointslices -l kubernetes.io/service-name=web'
passo "Pod usa-e-getta CON label ruolo=client: la NetworkPolicy lo lascia passare. Lo sleep dà tempo al CNI di imparare l'IP del Pod" \
  "kubectl -n lab run curl --rm -i --quiet --restart=Never --image=curlimages/curl:8.23.0 --labels=ruolo=client -- sh -c 'sleep 8; curl -s web/api'"
passo "Chi può entrare in web: Pod con ruolo=client OPPURE dal namespace ingress-nginx. Le policy si sommano, il deny di default chiude il resto" \
  'kubectl -n lab describe networkpolicy web-allow | sed -n "/Allowing ingress/,/Allowing egress/p"'
passo "Pod SENZA label: la NetworkPolicy lo blocca, curl va in timeout dopo 3 secondi" \
  "kubectl -n lab run intruso --rm -i --quiet --restart=Never --image=curlimages/curl:8.23.0 -- sh -c 'sleep 8; curl -s -m 3 web/api; echo uscita=\$?'"
passo "Dall'host attraverso l'Ingress: il controller sceglie il backend in base all'header Host" \
  "curl -s -H 'Host: web.lab.local' http://\$(minikube -p lab ip)/api"
