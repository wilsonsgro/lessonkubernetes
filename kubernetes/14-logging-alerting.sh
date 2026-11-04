#!/usr/bin/env bash
# Lezione 14 — log in Loki con Alloy, LogQL, Alertmanager con inhibit e silence, burn rate.
source "$(dirname "$0")/../lib/passo.sh"
guardia_lab
titolo "14. Logging e alerting"
F="$LEZIONI/kubernetes/14-logging-alerting.yaml"
Q() { kubectl -n logalert run "q$RANDOM" --rm -i --restart=Never --quiet --image=curlimages/curl:8.23.0 \
        -- curl -s -G "http://loki:3100/loki/api/v1/$1" --data-urlencode "query=$2"; echo; }
AM() { kubectl -n logalert exec deploy/alertmanager -- amtool --alertmanager.url=http://localhost:9093 "$@"; }

passo "Applico tutto il laboratorio nel namespace logalert: app 'pagamenti' che scrive log JSON, Loki, Alloy, Prometheus, Alertmanager e un ricevitore webhook finto" \
  "kubectl apply -f $F"
passo "Aspetto che i componenti siano pronti" \
  'kubectl -n logalert rollout status deploy/loki deploy/alloy deploy/prometheus deploy/alertmanager deploy/ricevitore deploy/pagamenti --timeout=5m'
passo "Un log dell'app: JSON con level, msg, trace_id. Alloy lo legge dall'API di Kubernetes e lo manda a Loki" \
  'kubectl -n logalert logs deploy/pagamenti --tail=3'
passo "Le label che Loki conosce (aspetto che Alloy abbia mandato i primi log): poche e a bassa cardinalità (app, level, namespace…). trace_id NON è una label" \
  "for i in \$(seq 12); do Q labels '' | grep -q '\"app\"' && break; sleep 5; done; Q labels ''"
passo "Alzo gli errori al 5% (50 volte il budget di uno SLO al 99,9%)" \
  'kubectl -n logalert set env deploy/pagamenti ERRORI=0.05 && kubectl -n logalert rollout status deploy/pagamenti'
passo "LogQL, filtro + parser: solo le righe ERROR, riformattate con trace_id e messaggio. Si cerca DENTRO la riga, non nelle label" \
  "sleep 30; Q query_range '{app=\"pagamenti\"} | json | level=\"ERROR\" | line_format \"{{.trace_id}} {{.msg}}\"' | jq -r '.data.result[].values[][1]' | head -5"
passo "LogQL, query metrica: righe per livello nell'ultimo minuto. | __error__=\"\" scarta le righe che il parser json non capisce: senza, UNA riga rotta fa fallire tutta la query" \
  "Q query 'sum by (level) (count_over_time({app=\"pagamenti\"} | json | __error__=\"\" [1m]))' | jq -r '.data.result[] | \"\\(.metric.level) \\(.value[1])\"'"
passo "Instradamento di Alertmanager senza alert veri: dove andrebbe un alert severity=page?" \
  'kubectl -n logalert exec deploy/alertmanager -- amtool config routes test --config.file=/etc/alertmanager/alertmanager.yml severity=page'
passo "Dopo ~2 minuti di errori: BudgetErroriVeloce (page) è active, i ticket sono suppressed perché inibiti dal page" \
  'sleep 120; AM alert query'
passo "Cosa ha ricevuto il webhook finto: /pager firing" \
  'kubectl -n logalert logs deploy/ricevitore --tail=5'
passo "SILENCE per manutenzione: il page tace per 15 minuti…" \
  'AM silence add alertname=BudgetErroriVeloce --duration=15m --comment=manutenzione && AM silence query'
passo "…e i ticket RESTANO inibiti: un alert silenziato continua a inibire gli altri" \
  'AM alert query --silenced --inhibited'
passo "Fine degli errori: in ~3,5 minuti il page si risolve (la finestra da 5m si svuota), poi il ticket lento diventa active" \
  'kubectl -n logalert set env deploy/pagamenti ERRORI=0'
nota "Rilancia 'kubectl -n logalert exec deploy/alertmanager -- amtool --alertmanager.url=http://localhost:9093 alert query' fra qualche minuto." \
     "Pulizia:  kubectl delete ns logalert"
