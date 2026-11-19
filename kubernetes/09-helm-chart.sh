#!/usr/bin/env bash
# Lezione 09 — un chart Helm scritto da zero: lint, template, install, upgrade, rollback.
source "$(dirname "$0")/../lib/passo.sh"
guardia_lab
titolo "09. Helm: chart da zero"
cartella helm
NS=lab-helm

passo "Versione di Helm (sul tuo Ubuntu è la 4: server-side apply di default)" \
  'helm version'
passo "Scrivo il chart ./eco con lo script della lezione: Chart.yaml, values.yaml, values.schema.json, template" \
  "bash $LEZIONI/kubernetes/09-helm-chart.sh crea"
passo "Com'è fatto un chart" \
  'find eco -type f | sort'
passo "values.yaml è l'interfaccia pubblica del chart: tutto quello che si può cambiare con --set o -f" \
  'cat eco/values.yaml'
passo "helm lint --strict: errori di struttura e di template prima di toccare il cluster" \
  'helm lint eco --strict'
passo "helm template: renderizza i manifest IN LOCALE, senza cluster. È quello che finirebbe nell'apply. Prima i tipi di oggetto, poi solo l'Ingress con --show-only" \
  'helm template prova eco --set ingress.enabled=true | grep ^kind:; helm template prova eco --set ingress.enabled=true --show-only templates/ingress.yaml'
passo "Lo schema JSON rifiuta replicaCount=0 PRIMA del rendering: errore atteso" \
  'helm template prova eco --set replicaCount=0'
passo "upgrade --install: installa se non c'è, aggiorna se c'è. --wait aspetta che i Pod siano pronti" \
  "helm upgrade --install eco eco -n $NS --create-namespace --wait --timeout 2m"
passo "La storia della release: revision 1, deployed" \
  "helm -n $NS history eco"
passo "Upgrade che cambia solo un valore: --reuse-values tiene gli altri. Il checksum della ConfigMap fa ripartire i Pod" \
  "helm upgrade eco eco -n $NS --reuse-values --set config.messaggio='seconda versione' --wait --timeout 2m"
passo "Upgrade con un'immagine inesistente e --rollback-on-failure: fallisce dopo 60 s e Helm torna da solo alla versione buona" \
  "helm upgrade eco eco -n $NS --reuse-values --set image.tag=v9.9.9 --rollback-on-failure --timeout 60s"
passo "History: revision 3 failed, revision 4 = rollback automatico alla 2" \
  "helm -n $NS history eco"
passo "I valori che l'utente ha passato (non i default)" \
  "helm -n $NS get values eco"
passo "Il manifest effettivamente installato: qui l'immagine in uso" \
  "helm -n $NS get manifest eco | grep -m1 'image:'"
passo "Rollback manuale alla revision 1" \
  "helm -n $NS rollback eco 1 --wait"
passo "Dove Helm salva la storia: un Secret per revision, tipo helm.sh/release.v1" \
  "kubectl -n $NS get secret -l owner=helm"
nota "Il chart ./eco serve alla lezione 10 (dipendenza) e alla 12 (deploy)." \
     "Pulizia:  helm uninstall eco -n $NS && kubectl delete ns $NS"
