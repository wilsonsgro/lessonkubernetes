#!/usr/bin/env bash
# Lezione 15 — stack completo su MicroK8s: un cluster diverso dal lab minikube.
source "$(dirname "$0")/../lib/passo.sh"
titolo "15. Stack completo su MicroK8s"
L="$LEZIONI/kubernetes/15-stack-microk8s.sh"
K="microk8s kubectl"

nota "Qui non si usa kubectl ma 'microk8s kubectl': ha il suo kubeconfig, non tocca il contesto 'lab'." \
     "Se MicroK8s non è installato:  bash $L installa   (poi: newgrp microk8s)"
passo "Accendo MicroK8s (chiede la password di sudo) e aspetto che sia pronto" \
  'sudo microk8s start && microk8s status --wait-ready | head -15'
passo "Versione e nodo: un solo nodo, che è l'Ubuntu stesso (non un container come in minikube)" \
  "microk8s version; $K get nodes -o wide"
passo "Addon: dns (CoreDNS), hostpath-storage (StorageClass su cartelle del nodo), ingress (nginx su 80/443 dell'host)" \
  "bash $L addon"
passo "Dati: MariaDB e Elasticsearch in StatefulSet con PVC, Redis come cache; credenziali generate in un Secret" \
  "bash $L dati"
passo "Il Secret contiene password casuali, nessuna è scritta nel manifest" \
  "$K -n stack get secret mariadb-cred -o jsonpath='{.data}' | jq 'keys'"
passo "I PVC sono legati a cartelle sotto /var/snap/microk8s/common/default-storage" \
  "$K -n stack get pvc; ls /var/snap/microk8s/common/default-storage/ 2>/dev/null | head"
passo "App PHP con 3 repliche, Service e Ingress su host stack.lab" \
  "bash $L app"
passo "6 richieste: cambia il pod che risponde, il contatore Redis sale per tutti, MariaDB ed Elasticsearch rispondono" \
  "bash $L verifica"
passo "Headlamp: UI web con il pod SENZA permessi e un token in sola lettura che scade fra 8 ore" \
  "bash $L headlamp"
passo "I certificati del nodo: gli IP nei SAN devono comprendere 192.168.1.79" \
  "bash $L certificati"
nota "Dal Mac:  curl -H 'Host: stack.lab' http://192.168.1.79/" \
     "Smontare tutto e spegnere MicroK8s:  bash $L smonta"
