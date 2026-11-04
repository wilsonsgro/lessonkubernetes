#!/usr/bin/env bash
# Lezione 20 — l'API REST con kubectl proxy e curl, un CRD, e le difese STRIDE misurate su due Pod.
source "$(dirname "$0")/../lib/passo.sh"
guardia_lab
titolo "20. API, CRD e threat model"
F="$LEZIONI/kubernetes/20-api-crd-threat-model.yaml"
API=http://127.0.0.1:9001
trap 'kill $PROXY 2>/dev/null' EXIT

passo "kubectl -v=6 mostra le richieste HTTP vere dietro un comando: verbo, URL, codice" \
  'kubectl get pods -n kube-system -v=6 2>&1 | grep -o "verb=.*" | head -2'
passo "kubectl proxy: l'API su 127.0.0.1:9001, firmata con le mie credenziali (in background)" \
  'kubectl proxy --port 9001 >/dev/null 2>&1 & PROXY=$!; sleep 2; echo "proxy pid $PROXY"'
passo "Il gruppo core sta in /api: una sola versione, v1" \
  "curl -s $API/api | head -6"
passo "Tutti gli altri gruppi stanno in /apis, ognuno con la sua versione preferita" \
  "curl -s $API/apis | python3 -c 'import sys,json; [print(g[\"name\"], \"→\", g[\"preferredVersion\"][\"groupVersion\"]) for g in json.load(sys.stdin)[\"groups\"]]' | head -15"
passo "kubectl get pods = GET su /api/v1/namespaces/<ns>/pods (qui solo i nomi)" \
  "curl -s $API/api/v1/namespaces/kube-system/pods | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d[\"kind\"], [i[\"metadata\"][\"name\"] for i in d[\"items\"]][:4])'"
passo "Creo un Namespace con una POST, senza kubectl: 201 Created" \
  "curl -s -o /dev/null -w 'POST: %{http_code}\n' -X POST -H 'Content-Type: application/json' --data '{\"apiVersion\":\"v1\",\"kind\":\"Namespace\",\"metadata\":{\"name\":\"da-curl\"}}' $API/api/v1/namespaces"
passo "La stessa POST di nuovo: 409 Conflict. Un oggetto inesistente: 404. Il gruppo apps sotto /api invece di /apis: 404" \
  "curl -s -o /dev/null -w 'di nuovo: %{http_code}\n' -X POST -H 'Content-Type: application/json' --data '{\"apiVersion\":\"v1\",\"kind\":\"Namespace\",\"metadata\":{\"name\":\"da-curl\"}}' $API/api/v1/namespaces; curl -s -o /dev/null -w 'inesistente: %{http_code}\n' $API/api/v1/namespaces/da-curl/pods/nessuno; curl -s -o /dev/null -w 'percorso sbagliato: %{http_code}\n' $API/api/apps/v1/deployments"
passo "DELETE: la risposta dice Terminating, la cancellazione è asincrona (finalizer)" \
  "curl -s -X DELETE $API/api/v1/namespaces/da-curl | python3 -c 'import sys,json; print(\"fase:\", json.load(sys.stdin)[\"status\"][\"phase\"])'"
passo "Gli header di API Priority and Fairness: l'apiserver mette ogni richiesta in una coda con priorità" \
  "curl -s -D - -o /dev/null $API/api/v1/namespaces | grep -i '^x-kubernetes-pf'"
passo "Protobuf: lo stesso oggetto nel formato binario dei componenti. Prefisso magico k8s\\0" \
  "curl -s -H 'Accept: application/vnd.kubernetes.protobuf' $API/api/v1/namespaces | head -c 4 | od -c | head -1"
passo "Senza il proxy e senza credenziali: 403 (anonimo riconosciuto, niente permessi). Con un token falso: 401" \
  'S=$(kubectl config view --minify -o jsonpath="{.clusters[0].cluster.server}"); curl -sk -o /dev/null -w "anonimo: %{http_code}\n" $S/api/v1/namespaces; curl -sk -o /dev/null -w "token falso: %{http_code}\n" -H "Authorization: Bearer falso" $S/api/v1/namespaces'
passo "Versioni servite e quelle sparite: niente PodSecurityPolicy (policy/v1beta1, rimossa nella 1.25)" \
  'kubectl api-versions | grep -E "^policy|^networking"; echo "PodSecurityPolicy: $(kubectl api-resources | grep -ci podsecuritypolic) risorse"'
passo "Il vecchio Ingress extensions/v1beta1 non esiste più: no matches for kind (uscita 1 voluta)" \
  'printf "apiVersion: extensions/v1beta1\nkind: Ingress\nmetadata: {name: vecchio, namespace: default}\nspec: {}\n" | kubectl apply --dry-run=server -f -'
passo "Applica namespace lab-api, il CRD Corso e due Pod: blindato (restricted) e normale" \
  "kubectl apply -f $F && kubectl wait --for=condition=Established crd/corsi.lab.esempio.it --timeout=30s && kubectl -n lab-api wait --for=condition=Ready pod/blindato pod/normale --timeout=90s"
passo "Il tipo nuovo è nell'API come quelli nativi: api-resources, explain" \
  'kubectl api-resources --api-group=lab.esempio.it; kubectl explain corso.spec | sed -n "1,4p;/FIELDS/,\$p"'
passo "Due oggetti Corso: il CRD li valida con lo schema e li mostra con le sue colonne" \
  'cat <<Y | kubectl apply -f - && kubectl -n lab-api get crs
apiVersion: lab.esempio.it/v1
kind: Corso
metadata: { name: kubernetes, namespace: lab-api }
spec: { titolo: Kubernetes, ore: 40, livello: medio }
---
apiVersion: lab.esempio.it/v1
kind: Corso
metadata: { name: helm, namespace: lab-api }
spec: { titolo: Helm, ore: 12, livello: base }
Y'
passo "Un Corso non valido: ore 0, livello fuori dall'enum, titolo mancante. L'apiserver lo rifiuta (uscita 1 voluta)" \
  'echo "{\"apiVersion\":\"lab.esempio.it/v1\",\"kind\":\"Corso\",\"metadata\":{\"name\":\"rotto\",\"namespace\":\"lab-api\"},\"spec\":{\"ore\":0,\"livello\":\"esperto\"}}" | kubectl apply -f -'
passo "Gli stessi oggetti via REST: il CRD ha creato il percorso /apis/lab.esempio.it/v1/…" \
  "curl -s $API/apis/lab.esempio.it/v1/namespaces/lab-api/corsi | python3 -c 'import sys,json; [print(i[\"metadata\"][\"name\"], i[\"spec\"]) for i in json.load(sys.stdin)[\"items\"]]'"
passo "Trappola dello shortName: 'cs' sembra libero ma è di componentstatuses, e vince quello" \
  'kubectl api-resources | awk "\$2==\"cs\""'
nota "Nessun controller osserva i Corso: sono solo dati. Un operator è CRD + controller che riconcilia."
passo "STRIDE, Elevation of privilege: Pod normale. root, Seccomp 0 = nessun filtro sulle syscall, le 14 capability di default del runtime, escalation possibile" \
  'kubectl -n lab-api exec normale -- sh -c "id; grep -E \"^(CapEff|NoNewPrivs|Seccomp):\" /proc/1/status"'
passo "Lo stesso nel Pod blindato: utente nobody, Seccomp 2 (RuntimeDefault), CapEff a zero, NoNewPrivs 1" \
  'kubectl -n lab-api exec blindato -- sh -c "id; grep -E \"^(CapEff|NoNewPrivs|Seccomp):\" /proc/1/status"'
passo "STRIDE, Tampering: il normale scrive sul filesystem dell'immagine, il blindato no (uscita 1 voluta)" \
  'kubectl -n lab-api exec normale -- touch /x && echo "normale: scritto /x"; kubectl -n lab-api exec blindato -- touch /x'
passo "STRIDE, Spoofing: il normale ha il token del ServiceAccount montato, il blindato no (uscita 1 voluta)" \
  'kubectl -n lab-api exec normale -- ls /var/run/secrets/kubernetes.io/serviceaccount; kubectl -n lab-api exec blindato -- ls /var/run/secrets/kubernetes.io/serviceaccount'
passo "Cosa ci farebbe un attaccante con quel token: chiedo all'apiserver i permessi del ServiceAccount default" \
  'kubectl auth can-i --list --as=system:serviceaccount:lab-api:default -n lab-api | head -8'
passo "STRIDE, Information disclosure: chi può leggere i Secret in lab-api? (il default no, un admin sì)" \
  'kubectl auth can-i get secrets -n lab-api --as=system:serviceaccount:lab-api:default; kubectl auth can-i get secrets -n lab-api'
passo "STRIDE, Repudiation: l'audit log dell'apiserver nel lab è attivo? (nessun flag audit = nessuna traccia di chi ha fatto cosa)" \
  'kubectl -n kube-system get pod -l component=kube-apiserver -o jsonpath="{.items[0].spec.containers[0].command}" | tr "," "\n" | grep -c audit || echo "→ audit spento"'
passo "Fuori da RBAC: dal nodo vedo i container di tutti i namespace senza passare dall'apiserver" \
  'for n in lab lab-m02; do echo "nodo $n:"; minikube -p lab ssh -n $n -- docker ps --format "{{.Names}}" | grep lab-api; done'
passo "Cancellare il CRD cancella anche tutti i Corso (uscita 1 voluta: il tipo non esiste più)" \
  'kubectl delete crd corsi.lab.esempio.it && kubectl -n lab-api get corsi'
passo "Pulizia" \
  'kill $PROXY; kubectl delete ns lab-api'
