#!/usr/bin/env bash
# Lezione 13 — kube-prometheus-stack, ServiceMonitor, PrometheusRule, Grafana.
source "$(dirname "$0")/../lib/passo.sh"
guardia_lab
titolo "13. Observability con Prometheus"
F="$LEZIONI/kubernetes/13-observability.yaml"

passo "Aggiungo il repository dei chart della comunità Prometheus" \
  'helm repo add prometheus-community https://prometheus-community.github.io/helm-charts; helm repo update prometheus-community'
passo "Installo kube-prometheus-stack (Prometheus Operator, Prometheus, Alertmanager, Grafana, node-exporter, kube-state-metrics). I due *NilUsesHelmValues=false fanno leggere a Prometheus i ServiceMonitor di TUTTI i namespace; hostRootFsMount=false serve perché il nodo minikube è un container. ~1,5 GB di RAM, qualche minuto" \
  'helm upgrade --install mon prometheus-community/kube-prometheus-stack -n monitoring --create-namespace --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false --set prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=false --set prometheus-node-exporter.hostRootFsMount.enabled=false --wait --timeout 10m'
passo "Cosa è stato installato" \
  'kubectl -n monitoring get pods'
passo "Le CRD dell'operatore: ServiceMonitor e PrometheusRule sono oggetti Kubernetes come gli altri" \
  'kubectl get crd | grep monitoring.coreos.com'
passo "Applico l'app d'esempio nel namespace lab-oss + ServiceMonitor (cosa raccogliere) + PrometheusRule (alert su error rate, error budget e Pod in restart)" \
  "kubectl apply -f $F"
passo "Prometheus in background su :9090 (port-forward), per interrogarlo da qui" \
  'kubectl -n monitoring port-forward svc/mon-kube-prometheus-stack-prometheus 9090 >/dev/null 2>&1 & echo $! > /tmp/pf-prom.pid; sleep 5'
passo "Il target dell'app è UP? L'operatore deve prima leggere il ServiceMonitor e ricaricare Prometheus: aspetto fino a 2 minuti" \
  "for i in \$(seq 24); do curl -s localhost:9090/api/v1/targets | jq -e '[.data.activeTargets[] | select(.labels.namespace==\"lab-oss\" and .health==\"up\")] | length > 0' >/dev/null && break; sleep 5; done; curl -s localhost:9090/api/v1/targets | jq -r '.data.activeTargets[] | select(.labels.namespace==\"lab-oss\") | \"\\(.labels.job) \\(.health)\"'"
passo "Genero errori per 4 minuti: chiamo /err e / in alternanza" \
  "kubectl -n lab-oss run carico --restart=Never --image=busybox:1.37 -- sh -c 'end=\$((\$(date +%s)+240)); while [ \$(date +%s) -lt \$end ]; do wget -q -O- http://app:8080/err; wget -q -O- http://app:8080/; done'"
passo "PromQL, metodo RED: richieste al secondo (Rate) per codice di risposta. rate() vuole almeno due campioni: aspetto 40 s di traffico" \
  "sleep 40; curl -s localhost:9090/api/v1/query --data-urlencode 'query=sum by (code) (rate(http_requests_total{namespace=\"lab-oss\"}[2m]))' | jq '.data.result'"
passo "Dopo ~2 minuti gli alert dell'app (App…) passano da pending a firing (dopo il 'for' della regola). TargetDown, etcd… firing sono normali su minikube: etcd, scheduler e controller-manager ascoltano solo su 127.0.0.1 del nodo e Prometheus non li raggiunge" \
  "sleep 120; curl -s localhost:9090/api/v1/alerts | jq -r '.data.alerts[] | \"\\(.labels.alertname) \\(.state)\"'"
passo "Password di Grafana (utente admin): Grafana è su http://localhost:3001 dopo il prossimo passo" \
  "kubectl -n monitoring get secret mon-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo"
passo "Grafana in primo piano su :3001 (dashboard già pronte: Kubernetes / Compute Resources). Ctrl+C per chiudere" \
  'kubectl -n monitoring port-forward svc/mon-grafana 3001:80'
passo "Chiudo il port-forward di Prometheus e il Pod di carico" \
  'kill $(cat /tmp/pf-prom.pid) 2>/dev/null; kubectl -n lab-oss delete pod carico --ignore-not-found'
nota "Interfaccia di Prometheus:  kubectl -n monitoring port-forward svc/mon-kube-prometheus-stack-prometheus 9090" \
     "  → http://localhost:9090/targets   http://localhost:9090/alerts" \
     "Pulizia:  helm uninstall mon -n monitoring; kubectl delete ns monitoring lab-oss"
