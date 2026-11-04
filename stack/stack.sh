#!/usr/bin/env bash
# Guida allo stack HAProxy → nginx → PHP-FPM → Redis + MariaDB (stack.yaml).
#   bash stack.sh                 → sul minikube "lab"
#   CLUSTER=microk8s bash stack.sh → su MicroK8s
source "$(dirname "$0")/../lib/passo.sh"
F="$(cd "$(dirname "$0")" && pwd)/stack.yaml"
NS=stack-web

if [[ "${CLUSTER:-lab}" == microk8s ]]; then
  kubectl() { microk8s kubectl "$@"; }
  NODO=192.168.1.79
else
  guardia_lab
  NODO="$(minikube -p lab ip)"
fi
URL="http://$NODO:30080"
titolo "Stack HAProxy + nginx + PHP + Redis + MariaDB  (${CLUSTER:-lab})"

passo "Applico tutto il file: namespace, Secret, 5 componenti con i loro Service e ConfigMap" \
  "kubectl apply -f $F"
passo "Aspetto che ogni componente sia pronto (MariaDB è il più lento: inizializza il database)" \
  "kubectl -n $NS rollout status statefulset/mariadb --timeout=180s && for d in redis php nginx haproxy; do kubectl -n $NS rollout status deploy/\$d --timeout=120s; done"
passo "HAProxy trova i pod nginx interrogando il DNS ogni secondo: aspetto che li veda tutti UP (di solito pochi secondi)" \
  "for i in \$(seq 30); do up=\$(curl -s 'http://$NODO:30404/stats;csv' | grep -c '^nginx,web.*,UP,'); [ \"\$up\" -ge 2 ] && break; sleep 1; done; echo \"server nginx UP in HAProxy: \$up\""
passo "Cosa gira: 1 haproxy, 2 nginx, 3 php, 1 redis, 1 mariadb" \
  "kubectl -n $NS get pods -o wide"
passo "I Service: haproxy è NodePort (raggiungibile da fuori), gli altri ClusterIP; nginx e mariadb sono headless (None)" \
  "kubectl -n $NS get svc"
passo "Una richiesta attraverso tutta la catena: HAProxy sceglie un nginx, nginx passa a un php, php parla con Redis e MariaDB" \
  "curl -s -i $URL/ | grep -iE 'x-servito-da|php_pod|nginx_pod|mariadb|visite'"
passo "Sei richieste: cambiano il server HAProxy, il pod nginx e il pod php; il contatore Redis è condiviso" \
  "for i in 1 2 3 4 5 6; do curl -s -D - $URL/ | tr -d '\r' | grep -iE 'x-servito-da|_pod|visite' | tr -d ' \n'; echo; done"
passo "Statistiche di HAProxy (anche dal browser: $URL → porta 30404/stats). Qui in CSV: server, stato" \
  "curl -s 'http://$NODO:30404/stats;csv' | cut -d, -f1,2,18 | grep -E '^nginx' | column -t -s,"
passo "HAProxy scopre i pod nginx dal DNS del Service headless: un record A per ogni pod pronto" \
  "kubectl -n $NS run dns --rm -i --restart=Never --quiet --image=busybox:1.37 -- nslookup nginx.$NS.svc.cluster.local"
passo "Scalo nginx a 4 repliche…" \
  "kubectl -n $NS scale deploy/nginx --replicas=4 && kubectl -n $NS rollout status deploy/nginx"
passo "…e dopo pochi secondi HAProxy ha 4 server UP, senza ricaricare la configurazione (server-template + resolvers)" \
  "sleep 10; curl -s 'http://$NODO:30404/stats;csv' | cut -d, -f1,2,18 | grep -E '^nginx' | column -t -s,"
passo "Cancello un pod php: il Deployment lo ricrea, le richieste continuano ad andare a buon fine" \
  "kubectl -n $NS delete \$(kubectl -n $NS get pod -l app=php -o name | head -1) --wait=false; for i in 1 2 3 4 5; do curl -s -o /dev/null -w '%{http_code} ' $URL/; sleep 1; done; echo"
passo "Log di HAProxy: una riga per richiesta (frontend, backend/server scelto, tempi, codice). Le sonde TCP del kubelet non compaiono grazie a option dontlognull" \
  "kubectl -n $NS logs deploy/haproxy --tail=5"
passo "Dentro MariaDB con il client: il database e l'utente creati dalle variabili del Secret" \
  "kubectl -n $NS exec mariadb-0 -- sh -c 'mariadb -uapp -p\"\$MARIADB_PASSWORD\" -e \"select current_user(), version(); show databases;\"'"
passo "Dentro Redis: il contatore che i pod php incrementano" \
  "kubectl -n $NS exec deploy/redis -- redis-cli get visite"
passo "Il disco di MariaDB: un PVC dalla StorageClass di default del cluster" \
  "kubectl -n $NS get pvc; kubectl get storageclass"
nota "Dal Mac (minikube non è raggiungibile dalla LAN):" \
     "  sull'Ubuntu:  kubectl -n $NS port-forward --address 0.0.0.0 svc/haproxy 8090:80 8404:8404" \
     "  dal Mac:      http://192.168.1.79:8090/   e   http://192.168.1.79:8404/stats" \
     "Su MicroK8s il NodePort è già sull'host: http://192.168.1.79:30080/" \
     "Pulizia:  kubectl delete namespace $NS"
