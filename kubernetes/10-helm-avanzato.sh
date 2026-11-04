#!/usr/bin/env bash
# Lezione 10 — chart ombrello, hook, helm test, registry OCI.
source "$(dirname "$0")/../lib/passo.sh"
guardia_lab
titolo "10. Helm avanzato"
cartella helm
NS=lab-piattaforma
[[ -d eco ]] || { echo "prima esegui la lezione 09: serve ./eco"; exit 1; }

passo "Registry OCI locale sulla porta 5000: qui pubblicheremo il chart come artefatto OCI" \
  'docker ps --format "{{.Names}}" | grep -qx registry || docker run -d --name registry -p 5000:5000 registry:3'
passo "Scrivo il chart ombrello ./piattaforma: dipende da eco (due volte, con alias) + Job di migrazione come hook + test" \
  "bash $LEZIONI/kubernetes/10-helm-avanzato.sh crea"
passo "Le dipendenze dichiarate in Chart.yaml" \
  'cat piattaforma/Chart.yaml'
passo "helm dependency update: scarica le dipendenze in charts/ e scrive Chart.lock (versioni bloccate, va in git)" \
  'helm dependency update piattaforma && cat piattaforma/Chart.lock'
passo "Installo: prima gira il Job pre-install/pre-upgrade (migrazione), poi i Deployment" \
  "helm upgrade --install demo piattaforma -n $NS --create-namespace --wait --timeout 3m"
passo "I Deployment creati dalle dipendenze" \
  "kubectl -n $NS get deploy"
passo "helm test: lancia i Pod con l'annotazione helm.sh/hook: test e ne mostra i log" \
  "helm test demo -n $NS --logs"
passo "Upgrade con migrazione che fallisce: l'hook fallisce e l'upgrade si FERMA prima di toccare i Deployment" \
  "helm upgrade demo piattaforma -n $NS --set migrazione.fallisci=true --set frontend.replicaCount=3 --wait --timeout 2m"
passo "Prova: il frontend ha ancora 1 replica, l'upgrade non è arrivato fin lì" \
  "kubectl -n $NS get deploy demo-frontend -o jsonpath='repliche={.spec.replicas}{\"\\n\"}'"
passo "Il Job fallito resta per il debug: si leggono i suoi log" \
  "kubectl -n $NS logs job/demo-migrazione"
passo "helm package: il chart diventa un archivio versionato" \
  'helm package ./eco'
passo "helm push: pubblico l'archivio nel registry OCI (--plain-http perché il registry locale non ha TLS)" \
  'helm push eco-0.1.0.tgz oci://localhost:5000/charts --plain-http'
passo "Leggo il chart direttamente dal registry" \
  'helm show chart oci://localhost:5000/charts/eco --version 0.1.0 --plain-http'
passo "Renderizzo dal registry: in CI si installa così, senza clonare il repo del chart" \
  'helm template da-oci oci://localhost:5000/charts/eco --version 0.1.0 --plain-http | grep -m1 image:'
nota "Pulizia:  helm uninstall demo -n $NS && kubectl delete ns $NS" \
     "Il registry resta acceso per la lezione 12; per toglierlo:  docker rm -f registry"
