#!/usr/bin/env bash
# Lezione 18 — Namespace con ResourceQuota e LimitRange, e la prova che non isolano la rete.
source "$(dirname "$0")/../lib/passo.sh"
guardia_lab
titolo "18. Namespace: quote, limiti e cosa non isolano"
F="$LEZIONI/kubernetes/18-namespace-quote.yaml"

passo "Cosa NON sta in un Namespace: le risorse cluster-scoped di questo cluster" \
  'kubectl api-resources --namespaced=false -o name | head -20'
passo "I Namespace esistenti, con la label automatica kubernetes.io/metadata.name" \
  'kubectl get ns -L kubernetes.io/metadata.name'
passo "Applica lab-team-a (quota + LimitRange + Deployment riempi da 2 Pod) e lab-team-b, vuoto" \
  "kubectl apply -f $F && kubectl -n lab-team-a rollout status deploy/riempi --timeout=90s"
passo "describe ns: quota usata/tetto e LimitRange in una sola vista" \
  'kubectl describe ns lab-team-a'
passo "Un Pod SENZA resources: il LimitRange gli dà i default, e così la quota lo accetta" \
  'kubectl -n lab-team-a run nudo --image=busybox:1.37 -- sleep 3600 && kubectl -n lab-team-a get pod nudo -o jsonpath="{.spec.containers[0].resources}{\"\n\"}"'
passo "Lo stesso Pod in lab-team-b (niente LimitRange): resources vuote, BestEffort" \
  'kubectl -n lab-team-b run nudo --image=busybox:1.37 -- sleep 3600 && kubectl -n lab-team-b get pod nudo -o jsonpath="resources={.spec.containers[0].resources} qos={.status.qosClass}{\"\n\"}"'
passo "Un container che chiede 300Mi di limit: oltre il max del LimitRange, rifiutato (uscita 1 voluta)" \
  'kubectl -n lab-team-a run grosso --image=busybox:1.37 --overrides="{\"spec\":{\"containers\":[{\"name\":\"grosso\",\"image\":\"busybox:1.37\",\"command\":[\"sleep\",\"3600\"],\"resources\":{\"limits\":{\"memory\":\"300Mi\"}}}]}}"'
passo "Quanto resta: 3 Pod su 4. Scalo riempi a 6 repliche" \
  'kubectl -n lab-team-a scale deploy riempi --replicas=6 && sleep 8 && kubectl -n lab-team-a get deploy riempi && kubectl -n lab-team-a get pods'
passo "Il Deployment non dà errore: il motivo è negli eventi del ReplicaSet" \
  'kubectl -n lab-team-a get events --field-selector reason=FailedCreate -o custom-columns=MESSAGGIO:.message --no-headers | tail -1 | cut -c1-220'
passo "La quota conta le RICHIESTE dichiarate, non il consumo: confronta Used con kubectl top" \
  'kubectl -n lab-team-a describe quota tetto | tail -8; for i in $(seq 18); do kubectl -n lab-team-a top pods >/dev/null 2>&1 && break; sleep 5; done; kubectl -n lab-team-a top pods'
passo "Nomi unici solo dentro il Namespace: un Service riempi anche in lab-team-b, nessun conflitto" \
  'kubectl -n lab-team-b create service clusterip riempi --tcp=80:80 && kubectl get svc -A --field-selector metadata.name=riempi'
passo "La rete NON è isolata: da lab-team-b raggiungo riempi di lab-team-a col nome riempi.lab-team-a" \
  'kubectl -n lab-team-b exec nudo -- wget -qO- -T 3 http://riempi.lab-team-a | head -2'
passo "Ora una NetworkPolicy in lab-team-a: ingresso solo dallo stesso Namespace (namespaceSelector sulla label automatica)" \
  'cat <<Y | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: solo-team-a, namespace: lab-team-a }
spec:
  podSelector: {}
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels: { kubernetes.io/metadata.name: lab-team-a }
Y'
passo "Stessa richiesta da lab-team-b: timeout. L'isolamento lo fa la policy (applicata da Calico), non il Namespace (uscita 1 voluta)" \
  'kubectl -n lab-team-b exec nudo -- wget -qO- -T 3 http://riempi.lab-team-a'
passo "Da dentro lab-team-a passa ancora" \
  'kubectl -n lab-team-a exec nudo -- wget -qO- -T 3 http://riempi | head -1'
passo "Trappola del contesto: cambio il Namespace di default, kubectl get pods ora guarda lab-team-a" \
  'kubectl config set-context --current --namespace=lab-team-a && kubectl get pods --no-headers | wc -l && kubectl config view --minify -o jsonpath="namespace del contesto: {..namespace}{\"\n\"}"'
passo "…e lo rimetto a default, se no i comandi delle altre lezioni cercano nel posto sbagliato" \
  'kubectl config set-context --current --namespace=default'
passo "Pulizia: cancellare un Namespace cancella tutto quello che contiene" \
  'kubectl delete ns lab-team-a lab-team-b'
