#!/usr/bin/env bash
# Lezione 22 — cluster minikube "lab-monitoring" (3 nodi da 3 GiB, Calico): HAProxy della 21 + kube-prometheus-stack, metriche di HAProxy per replica, dashboard e alert.
source "$(dirname "$0")/../lib/passo.sh"
titolo "22. HAProxy osservato con Prometheus e Grafana"
F21="$LEZIONI/kubernetes/21-architettura-e-haproxy.yaml"
F="$LEZIONI/kubernetes/22-architettura-haproxy-prometheus-grafana.yaml"
KPS_VER=93.10.1
HAP_VER=1.57.1

passo "Versioni dei client: kubectl, minikube, helm" \
  'kubectl version --client; minikube version --short; helm version --short'
passo "Crea il cluster 'lab-monitoring': 3 nodi da 3 GiB, Calico. La stack non sta nei 5 nodi da 1 GiB della 21. Qualche minuto" \
  'minikube start -p lab-monitoring --driver=docker --nodes=3 --cpus=2 --memory=3g --cni=calico'
passo "Punta kubectl sul cluster nuovo: da qui lo script controlla che il contesto sia 'lab-monitoring'" \
  'kubectl config use-context lab-monitoring'
guardia_lab lab-monitoring 22-architettura-haproxy-prometheus-grafana.sh
passo "Come nella 21: minikube start torna prima di Calico. Aspetto calico-node pronto sui 3 nodi" \
  'kubectl -n kube-system rollout status daemonset/calico-node --timeout=5m'
passo "I 3 nodi: lab-monitoring è il control plane (primary=true), m02 e m03 i worker" \
  'kubectl get nodes -L minikube.k8s.io/primary -o wide'
passo "metrics-server per kubectl top e per l'HPA della 06. Prometheus NON lo sostituisce: sono due strade diverse" \
  'minikube -p lab-monitoring addons enable metrics-server'
passo "Repo Helm della comunità Prometheus e di HAProxy Technologies, con le versioni fissate" \
  "helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1; helm repo add haproxytech https://haproxytech.github.io/helm-charts >/dev/null 2>&1; helm repo update prometheus-community haproxytech >/dev/null; helm search repo prometheus-community/kube-prometheus-stack --version $KPS_VER; helm search repo haproxytech/kubernetes-ingress --version $HAP_VER"
passo "Chi sceglie i ServiceMonitor, i PodMonitor e le regole: di default solo quelli con la label della Release (NilUsesHelmValues: true)" \
  "helm show values prometheus-community/kube-prometheus-stack --version $KPS_VER | grep -nE '^    (serviceMonitor|podMonitor|rule)SelectorNilUsesHelmValues'"
passo "Installa kube-prometheus-stack, Release 'monitoring': Operator, Prometheus (retention 6h), Alertmanager, Grafana, node-exporter, kube-state-metrics. hostRootFsMount=false perché il nodo minikube è un container. ~3 minuti" \
  "helm upgrade --install monitoring prometheus-community/kube-prometheus-stack --version $KPS_VER -n monitoring --create-namespace --wait --timeout 10m -f - <<'VALORI'
grafana:
  enabled: true
prometheus:
  prometheusSpec:
    retention: 6h
    serviceMonitorSelectorNilUsesHelmValues: false
    serviceMonitorSelector:
      matchLabels:
        release: monitoring
    serviceMonitorNamespaceSelector: {}
alertmanager:
  enabled: true
prometheus-node-exporter:
  hostRootFsMount:
    enabled: false
VALORI"
passo "Che cosa ha installato: i Pod, i Service (monitoring-grafana, monitoring-kube-prometheus-prometheus), l'oggetto Prometheus e le CRD dell'Operator" \
  'kubectl -n monitoring get pods -o wide; kubectl -n monitoring get svc; kubectl -n monitoring get prometheus; kubectl get crd | grep monitoring.coreos.com'
passo "Trappola misurata: con controller.serviceMonitor.enabled il chart HAProxy crea un Service -metrics ClusterIP con dentro il nodePort 30024. Lo faccio vedere SENZA applicarlo: l'apiserver lo rifiuterebbe" \
  "helm template haproxy haproxytech/kubernetes-ingress --version $HAP_VER -n haproxy-controller --set controller.serviceMonitor.enabled=true --set controller.service.nodePorts.stat=30024 | grep -A22 'name: haproxy-kubernetes-ingress-metrics' | grep -E 'kind|name: haproxy|type|nodePort'"
passo "Installa HAProxy come nella 21 (2 repliche su worker diversi, NodePort 30080/30443/30024) più un PodMonitor con release=monitoring: un target per Pod, niente Service in più" \
  "helm upgrade --install haproxy haproxytech/kubernetes-ingress --version $HAP_VER -n haproxy-controller --create-namespace --wait --timeout 5m -f - <<'VALORI'
controller:
  replicaCount: 2
  resources:
    requests: { cpu: 50m, memory: 64Mi }
    limits: { memory: 256Mi }
  service:
    nodePorts: { http: 30080, https: 30443, stat: 30024 }
  podMonitor:
    enabled: true
    extraLabels: { release: monitoring }
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
passo "Il controller e il suo PodMonitor: la label release=monitoring è quella che Prometheus cerca" \
  'kubectl -n haproxy-controller get pods -o wide; kubectl -n haproxy-controller get podmonitor --show-labels'
passo "Le app della 21 (blu 3, verde 2, Ingress app e limitato): stesso manifest, cluster diverso" \
  "kubectl apply -f $F21 && kubectl -n lab-haproxy rollout status deploy/blu && kubectl -n lab-haproxy rollout status deploy/verde"
passo "La lezione 22: app demo-metrics con ServiceMonitor, la demo dietro HAProxy (demo.lab.local), PrometheusRule lezione-22, dashboard come ConfigMap" \
  "kubectl apply -f $F && kubectl -n lab-metrics rollout status deploy/demo-metrics"
passo "Pod pronti non vuol dire HAProxy pronto (21): aspetto 200 su /blu, /verde e su /work della demo" \
  "IP=\$(minikube -p lab-monitoring ip); for h in app.lab.local/blu app.lab.local/verde demo.lab.local/work; do for i in \$(seq 30); do c=\$(curl -s -o /dev/null -w '%{http_code}' -H \"Host: \${h%%/*}\" http://\$IP:30080/\${h#*/}); [ \"\$c\" = 200 ] && break; sleep 1; done; echo \"\$h → \$c dopo \$i tentativi\"; done"
passo "Prometheus in background su :9090 (port-forward), per interrogarlo da qui" \
  'kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 >/dev/null 2>&1 & echo $! > /tmp/pf-22-prom.pid; sleep 5'
passo "I target: due Pod HAProxy (PodMonitor) e demo-metrics (ServiceMonitor). L'Operator deve leggere gli oggetti e ricaricare Prometheus: aspetto fino a 2 minuti" \
  'for i in $(seq 24); do n=$(curl -s localhost:9090/api/v1/targets | jq "[.data.activeTargets[] | select((.labels.namespace==\"haproxy-controller\" or .labels.namespace==\"lab-metrics\") and .health==\"up\")] | length"); [ "$n" -ge 3 ] && break; sleep 5; done; curl -s localhost:9090/api/v1/targets | jq -r ".data.activeTargets[] | select(.labels.namespace==\"haproxy-controller\" or .labels.namespace==\"lab-metrics\") | \"\(.health)  \(.labels.pod)  \(.scrapeUrl)\""'
passo "Quali metriche espone davvero HAProxy: le conto e guardo i server attivi per backend, una riga per REPLICA (label pod)" \
  'curl -s localhost:9090/api/v1/label/__name__/values | jq -r ".data[]" | grep -c "^haproxy_"; curl -s localhost:9090/api/v1/query --data-urlencode "query=haproxy_backend_active_servers{proxy=~\"lab-.*\"}" | jq -r ".data.result[] | \"\(.metric.pod)  \(.metric.proxy)  \(.value[1]) server\""'
passo "Traffico per 30 s: /work della demo e /blu, entrambi attraverso HAProxy" \
  'IP=$(minikube -p lab-monitoring ip); for i in $(seq 150); do curl -s -o /dev/null -H "Host: demo.lab.local" http://$IP:30080/work; curl -s -o /dev/null -H "Host: app.lab.local" http://$IP:30080/blu; sleep 0.2; done; echo fatto'
passo "PromQL: richieste/s della demo (rate su un Counter) e di HAProxy per replica. rate() vuole almeno due scrape nella finestra" \
  'sleep 30; for q in "sum(rate(demo_requests_total[1m]))" "sum by (pod) (rate(haproxy_backend_http_requests_total{proxy=~\"lab-.*\"}[1m]))"; do echo "$q"; curl -s localhost:9090/api/v1/query --data-urlencode "query=$q" | jq -r ".data.result[] | \"   \(.metric.pod // \"totale\")  \(.value[1] | tonumber * 100 | round / 100) /s\""; done'
passo "Il rate limit della 21, ora nel tempo: 12 richieste a limitato.lab.local, poi i 429 contati da OGNI replica (haproxy_frontend_requests_denied_total)" \
  'IP=$(minikube -p lab-monitoring ip); for i in $(seq 12); do curl -s -o /dev/null -w "%{http_code} " -H "Host: limitato.lab.local" http://$IP:30080/; done; echo; sleep 35; curl -s localhost:9090/api/v1/query --data-urlencode "query=haproxy_frontend_requests_denied_total{proxy=\"http\"}" | jq -r ".data.result[] | \"   \(.metric.pod)  \(.value[1]) negate\""'
nota "Le due repliche hanno stick-table separate: i 429 cadono su una sola, o su tutte e due, secondo dove kube-proxy" \
     "ha mandato le connessioni. by (pod) le separa, sum le somma: in una dashboard va deciso e scritto."
passo "Le regole caricate: Prometheus le prende solo con release=monitoring (ruleSelector della Release). HAProxyRateLimitAttivo può essere già firing" \
  'curl -s localhost:9090/api/v1/rules | jq -r ".data.groups[] | select(.name==\"laboratorio.rules\") | .rules[] | \"\(.name)  \(.state)\""'
passo "Incidente provocato: demo-metrics a 0 repliche. Seguo i due alert finché non sono firing (misurato in due corse: pending a +16/+30 s, firing a +76/+91 s) e chiedo /work a HAProxy" \
  'kubectl -n lab-metrics scale deploy/demo-metrics --replicas=0; t0=$(date +%s); prima=""; while [ $(( $(date +%s) - t0 )) -lt 240 ]; do s=$(curl -s localhost:9090/api/v1/rules | jq -r "[.data.groups[] | select(.name==\"laboratorio.rules\") | .rules[] | select(.name!=\"HAProxyRateLimitAttivo\") | \"\(.name)=\(.state)\"] | join(\"  \")"); [ "$s" != "$prima" ] && echo "+$(( $(date +%s) - t0 ))s  $s"; prima=$s; case "$s" in *Disponibile=firing*SenzaServer=firing*) break ;; esac; sleep 5; done; curl -s -o /dev/null -w "/work con 0 repliche → %{http_code}\n" -H "Host: demo.lab.local" http://$(minikube -p lab-monitoring ip):30080/work'
nota "Firing non vuol dire messaggio inviato: Alertmanager li ha, ma nessun receiver è configurato." \
     "Qui scattano insieme; HAProxyBackendSenzaServer guarda dal lato dell'utente e scatta anche quando i Pod sono pronti ma HAProxy non li raggiunge."
passo "Ripristino: una replica, e gli alert tornano inactive" \
  'kubectl -n lab-metrics scale deploy/demo-metrics --replicas=1 && kubectl -n lab-metrics rollout status deploy/demo-metrics'
passo "Quanta memoria usa la stack: netta per nodo (come nella 21) e gli OOM kill" \
  'for n in $(kubectl get nodes -o name | cut -d/ -f2); do docker exec $n sh -c "cd /sys/fs/cgroup; awk -v c=\$(cat memory.current) -v m=\$(cat memory.max) \"/^(active|inactive)_file /{f+=\\\$2} END{printf \\\"%-20s netto %4d Mi = %3d%% di %d Mi · \\\", \\\"$n\\\", (c-f)/2^20, (c-f)*100/m, m/2^20}\" memory.stat; grep oom_kill memory.events"; done'
passo "Grafana in background su :3000, e la dashboard caricata dal sidecar (ConfigMap grafana_dashboard=1): non l'ha creata nessuno a mano" \
  'kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80 >/dev/null 2>&1 & echo $! > /tmp/pf-22-grafana.pid; sleep 5; P=$(kubectl -n monitoring get secret monitoring-grafana -o jsonpath="{.data.admin-password}" | base64 -d); curl -s -u "admin:$P" localhost:3000/api/datasources | jq -r ".[] | \"datasource  \(.name)  uid=\(.uid)\""; curl -s -u "admin:$P" "localhost:3000/api/search?query=Lezione" | jq -r ".[] | \"dashboard   \(.title)  /d/\(.uid)\""'
passo "La password di admin di Grafana: solo nel tuo terminale, mai in un file o in un repository" \
  "kubectl -n monitoring get secret monitoring-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo"
nota "Grafana: http://localhost:3000/d/lezione-22 (utente admin) · Prometheus: http://localhost:9090/targets e /alerts" \
     "Dal Mac, tunnel ssh: ssh -N -L 3000:localhost:3000 -L 9090:localhost:9090 wilsonsgro@192.168.1.79"
passo "Chiudo i port-forward in background" \
  'kill $(cat /tmp/pf-22-prom.pid /tmp/pf-22-grafana.pid 2>/dev/null) 2>/dev/null; rm -f /tmp/pf-22-prom.pid /tmp/pf-22-grafana.pid; echo chiusi'
passo "Pulizia: la lezione 22, le app della 21, HAProxy, la stack e i namespace" \
  "kubectl delete -f $F --ignore-not-found; kubectl delete -f $F21 --ignore-not-found; helm uninstall haproxy -n haproxy-controller; helm uninstall monitoring -n monitoring; kubectl delete namespace haproxy-controller monitoring --ignore-not-found"
passo "helm uninstall non toglie le CRD dell'Operator: restano finché non le cancelli (o cancelli il cluster)" \
  'kubectl get crd | grep monitoring.coreos.com'
nota "Spegnere il cluster senza perderlo:  minikube -p lab-monitoring stop" \
     "Cancellarlo del tutto:              minikube -p lab-monitoring delete" \
     "Tornare al cluster delle altre lezioni: kubectl config use-context lab (dopo minikube -p lab start)"
