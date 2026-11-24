#!/usr/bin/env bash
# Lezione 21 — cluster minikube "lab-haproxy" (5 nodi da 1 GiB, Calico) con HAProxy come Ingress controller al posto di ingress-nginx.
source "$(dirname "$0")/../lib/passo.sh"
titolo "21. Architettura con HAProxy come Ingress controller"
F="$LEZIONI/kubernetes/21-architettura-e-haproxy.yaml"
CHART_VER=1.57.1

passo "Versioni dei client: kubectl, minikube, helm (HAProxy si installa con Helm)" \
  'kubectl version --client; minikube version --short; helm version --short'
passo "Prima prova SENZA --force: minikube rifiuta 1 GiB per nodo (minimo 1800 MB). Uscita 23 voluta" \
  'minikube start -p lab-haproxy --driver=docker --nodes=5 --cpus=2 --memory=1g --cni=calico'
passo "Crea il cluster 'lab-haproxy': 5 nodi (container docker) da 1 GiB, Calico. --force scavalca il minimo. Qualche minuto" \
  'minikube start -p lab-haproxy --driver=docker --nodes=5 --cpus=2 --memory=1g --cni=calico --force'
passo "Punta kubectl sul cluster nuovo: da qui lo script controlla che il contesto sia 'lab-haproxy'" \
  'kubectl config use-context lab-haproxy'
guardia_lab lab-haproxy 21-architettura-e-haproxy.sh
passo "minikube start torna prima che Calico sia su in tutti i nodi: un Pod schedulato adesso fallisce il sandbox (/var/lib/calico/nodename assente) e riparte una volta. Aspetto calico-node pronto sui 5 nodi" \
  'kubectl -n kube-system rollout status daemonset/calico-node --timeout=5m && kubectl -n kube-system get pods -l k8s-app=calico-node -o wide'
passo "I 5 nodi: lab-haproxy è il control plane (label minikube.k8s.io/primary=true), m02–m05 i worker" \
  'kubectl get nodes -L minikube.k8s.io/primary -o wide'
passo "Addon metrics-server per kubectl top. NON si abilita 'ingress': installerebbe ingress-nginx" \
  'minikube -p lab-haproxy addons enable metrics-server'
passo "Gli addon di ingress di minikube: ingress (nginx), ingress-dns, kong. HAProxy non c'è: serve Helm" \
  'minikube -p lab-haproxy addons list | grep -iE "ingress|kong|haproxy"'
passo "Repo Helm di HAProxy Technologies e versione del chart" \
  "helm repo add haproxytech https://haproxytech.github.io/helm-charts >/dev/null 2>&1; helm repo update haproxytech >/dev/null; helm search repo haproxytech/kubernetes-ingress --version $CHART_VER"
passo "Trappola: il chart chiede 2 GiB di request per replica. Su nodi da 1 GiB lo scheduler le accetta lo stesso (Capacity = tutto il PC, lezione 01)" \
  "helm show values haproxytech/kubernetes-ingress --version $CHART_VER | sed -n '/^  resources:/,/^\$/p' | head -7"
passo "Installa HAProxy: 2 repliche su worker diversi (mai sul control plane, già al limite), request da 64 Mi, NodePort fissi 30080 http, 30443 https, 30024 stats" \
  "helm upgrade --install haproxy haproxytech/kubernetes-ingress --version $CHART_VER -n haproxy-controller --create-namespace --wait --timeout 5m -f - <<'VALORI'
controller:
  replicaCount: 2
  resources:
    requests: { cpu: 50m, memory: 64Mi }
    limits: { memory: 256Mi }
  service:
    nodePorts: { http: 30080, https: 30443, stat: 30024 }
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - { key: minikube.k8s.io/primary, operator: NotIn, values: ['true'] }
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - topologyKey: kubernetes.io/hostname
          labelSelector:
            matchLabels: { app.kubernetes.io/name: kubernetes-ingress }
VALORI"
passo "Il controller: 2 Pod su due worker, un Service NodePort, l'IngressClass 'haproxy'" \
  'kubectl -n haproxy-controller get pods -o wide; kubectl -n haproxy-controller get svc; kubectl get ingressclass'
passo "Quanto è vicino al limite ogni nodo: memoria netta (senza cache dei file) su 1024 Mi, e gli OOM kill" \
  'for n in $(kubectl get nodes -o name | cut -d/ -f2); do docker exec $n sh -c "cd /sys/fs/cgroup; awk -v c=\$(cat memory.current) -v m=\$(cat memory.max) \"/^(active|inactive)_file /{f+=\\\$2} END{printf \\\"%-16s netto %4d Mi = %3d%% di %d Mi · \\\", \\\"$n\\\", (c-f)/2^20, (c-f)*100/m, m/2^20}\" memory.stat; grep oom_kill memory.events"; done'
nota "Il control plane sta intorno all'80% netto (misurato 839 Mi su 1024): per questo HAProxy e le app" \
     "vanno sui worker. Se vedi oom_kill > 0 sul control plane, il cluster è troppo stretto: --memory=2g."
passo "Applica namespace lab-haproxy, le app blu (3) e verde (2), i Service e i due Ingress di classe haproxy" \
  "kubectl apply -f $F && kubectl -n lab-haproxy rollout status deploy/blu && kubectl -n lab-haproxy rollout status deploy/verde"
passo "Pod pronti non vuol dire HAProxy pronto: il controller deve vedere Ingress ed EndpointSlice e scrivere i backend. Aspetto che /blu e /verde rispondano 200" \
  "IP=\$(minikube -p lab-haproxy ip); for p in blu verde; do for i in \$(seq 30); do c=\$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: app.lab.local' http://\$IP:30080/\$p); [ \"\$c\" = 200 ] && break; sleep 1; done; echo \"/\$p → \$c dopo \$i tentativi\"; done"
passo "Dove sono finiti i Pod: sparsi sui worker dal topologySpreadConstraints" \
  'kubectl -n lab-haproxy get pods -o wide'
passo "Dall'host attraverso HAProxy: /blu/ciao arriva al Pod come /ciao (path-rewrite). Hostname dice chi ha risposto" \
  "curl -s -H 'Host: app.lab.local' http://\$(minikube -p lab-haproxy ip):30080/blu/ciao | grep -E 'Hostname|GET'; curl -s -H 'Host: app.lab.local' http://\$(minikube -p lab-haproxy ip):30080/verde | grep -E 'Hostname|GET'"
passo "Sei richieste a /blu: roundrobin. Le 2 repliche di HAProxy girano ognuna per conto suo, quindi la sequenza non è perfetta" \
  "IP=\$(minikube -p lab-haproxy ip); for i in 1 2 3 4 5 6; do curl -s -H 'Host: app.lab.local' http://\$IP:30080/blu | grep Hostname; done"
passo "Senza header Host nessuna regola combacia: 404 di HAProxy (il backend di default)" \
  "curl -s -o /dev/null -w '%{http_code}\n' http://\$(minikube -p lab-haproxy ip):30080/"
passo "La config che il controller ha SCRITTO da sé: un backend per Service, una riga server per IP di Pod (non il ClusterIP)" \
  'kubectl -n haproxy-controller exec deploy/haproxy-kubernetes-ingress -- sed -n "/^backend lab-haproxy_svc_blu/,/^\$/p;/^backend lab-haproxy_svc_verde/,/^\$/p" /etc/haproxy/haproxy.cfg; kubectl -n lab-haproxy get endpointslices'
passo "Reload contati prima di scalare: colonna reloads del processo master" \
  'kubectl -n haproxy-controller exec deploy/haproxy-kubernetes-ingress -- sh -c "echo show proc | socat stdio /run/haproxy-master.sock | head -2"'
passo "Scalo blu a 5: il controller aggiunge i server con la Runtime API ('add server'), senza ricaricare" \
  'kubectl -n lab-haproxy scale deploy/blu --replicas=5 && kubectl -n lab-haproxy rollout status deploy/blu && sleep 5; kubectl -n haproxy-controller logs deploy/haproxy-kubernetes-ingress --since=60s | grep -E "add server|New server" | tail -4'
passo "Reload di nuovo: lo stesso numero di prima. I 5 server ci sono, visti dal socket runtime (srv_op_state 2 = UP)" \
  'kubectl -n haproxy-controller exec deploy/haproxy-kubernetes-ingress -- sh -c "echo show proc | socat stdio /run/haproxy-master.sock | head -2; echo show servers state lab-haproxy_svc_blu_http | socat stdio /run/haproxy-runtime-api.sock | cut -d\" \" -f4-6"'
nota "kubectl exec deploy/… sceglie UNO dei due Pod: l'altro ha la sua config e i suoi contatori."
passo "Rate limit su limitato.lab.local: 5 richieste ogni 10 s, poi 429. Con 2 repliche ne passano fino a 10" \
  "IP=\$(minikube -p lab-haproxy ip); for i in \$(seq 12); do curl -s -o /dev/null -w '%{http_code} ' -H 'Host: limitato.lab.local' http://\$IP:30080/; done; echo"
passo "La pagina statistiche di HAProxy in CSV: backend, server, stato. Nel browser è http://IP:30024/stats" \
  "curl -s \"http://\$(minikube -p lab-haproxy ip):30024/stats;csv\" | cut -d, -f1,2,18 | grep -E '^(# pxname|lab-haproxy_svc)'"
passo "Riporto blu a 3: i server in più escono a caldo come sono entrati" \
  'kubectl -n lab-haproxy scale deploy/blu --replicas=3 && sleep 10; kubectl -n haproxy-controller logs deploy/haproxy-kubernetes-ingress --since=30s | grep -iE "delete|del server" | tail -2'
passo "Pulizia: le app e il namespace lab-haproxy, poi il controller HAProxy" \
  "kubectl delete -f $F --ignore-not-found; helm uninstall haproxy -n haproxy-controller; kubectl delete namespace haproxy-controller --ignore-not-found"
nota "Spegnere il cluster senza perderlo:  minikube -p lab-haproxy stop" \
     "Cancellarlo del tutto:              minikube -p lab-haproxy delete" \
     "Tornare al cluster delle altre lezioni: kubectl config use-context lab (dopo minikube -p lab start)"
