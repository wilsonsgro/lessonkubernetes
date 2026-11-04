#!/usr/bin/env bash
# Lezione 19 — DNS del cluster: resolv.conf, search list, ndots, EndpointSlice, kube-proxy.
source "$(dirname "$0")/../lib/passo.sh"
guardia_lab
titolo "19. DNS e service discovery"
F="$LEZIONI/kubernetes/19-dns-service-discovery.yaml"
X='kubectl -n lab-dns exec rete --'

passo "Chi fa il DNS: Deployment coredns, Service kube-dns (IP fisso), tutti con label k8s-app=kube-dns" \
  'kubectl -n kube-system get deploy,svc,endpointslices -l k8s-app=kube-dns'
nota "Nel lab CoreDNS ha UNA replica: se cade, nessun Pod risolve più niente. In produzione ≥2, anti-affinity, PDB."
passo "La configurazione di CoreDNS (Corefile): plugin kubernetes per cluster.local, forward al DNS del nodo per il resto" \
  'kubectl -n kube-system get cm coredns -o jsonpath="{.data.Corefile}"'
passo "Applica lab-dns: Deployment web (2 Pod), Service web e vuoto, Pod rete e rete-ndots1 (netshoot: dig, tcpdump, curl)" \
  "kubectl apply -f $F && kubectl -n lab-dns rollout status deploy/web --timeout=90s && kubectl -n lab-dns wait --for=condition=Ready pod/rete pod/rete-ndots1 --timeout=180s"
passo "Il resolv.conf del Pod: nameserver = ClusterIP di kube-dns, search costruita dal namespace, ndots:5" \
  "$X cat /etc/resolv.conf; kubectl -n kube-system get svc kube-dns -o jsonpath='kube-dns: {.spec.clusterIP}{\"\n\"}'"
nota "L'ultima voce di search (se c'è) arriva dall'host: è il dominio della rete di casa, ereditato dal nodo."
passo "I tre modi di chiamare lo stesso Service: corto, con il namespace, FQDN. Tutti danno il ClusterIP" \
  "for n in web web.lab-dns web.lab-dns.svc.cluster.local; do printf '%-32s → %s\n' \$n \"\$($X dig +search +short \$n)\"; done; kubectl -n lab-dns get svc web -o jsonpath='ClusterIP di web: {.spec.clusterIP}{\"\n\"}'"
passo "Record SRV: la porta con nome http diventa _http._tcp.<service>. Il client scopre anche la porta" \
  "$X dig +short SRV _http._tcp.web.lab-dns.svc.cluster.local"
passo "ndots:5 misurato: tcpdump sulle domande DNS mentre curl chiama example.com (1 punto, meno di 5)" \
  "$X sh -c 'tcpdump -nni eth0 -l udp port 53 2>/dev/null > /tmp/q & sleep 1; curl -s -o /dev/null -m 5 http://example.com; sleep 1; kill %1; grep -oE \"(A|AAAA)\\? [^ ]+\" /tmp/q | sort | uniq -c'"
passo "Lo stesso con il punto finale: example.com. è assoluto, niente search list" \
  "$X sh -c 'tcpdump -nni eth0 -l udp port 53 2>/dev/null > /tmp/q & sleep 1; curl -s -o /dev/null -m 5 -H \"Host: example.com\" http://example.com./; sleep 1; kill %1; grep -oE \"(A|AAAA)\\? [^ ]+\" /tmp/q | sort | uniq -c'"
passo "Con ndots:1 (dnsConfig nel Pod rete-ndots1) example.com va diretto; web.lab-dns risolve ancora, ma prova prima web.lab-dns. assoluto" \
  "kubectl -n lab-dns exec rete-ndots1 -- sh -c 'grep options /etc/resolv.conf; tcpdump -nni eth0 -l udp port 53 2>/dev/null > /tmp/q & sleep 1; curl -s -o /dev/null -m 5 http://example.com; curl -s -m 3 http://web.lab-dns | head -1; sleep 1; kill %1; grep -oE \"(A|AAAA)\\? [^ ]+\" /tmp/q | sort | uniq -c'"
passo "Trappola degli strumenti: nslookup di busybox dà NXDOMAIN sul nome corto, wget nello stesso container risolve" \
  "kubectl -n lab-dns run bb --rm -i --quiet --restart=Never --image=busybox:1.37 -- sh -c 'sleep 1; nslookup web 2>&1 | tail -2; echo ---; wget -qO- -T 3 http://web | head -1'"
passo "Dietro il nome: le EndpointSlice di web elencano gli IP dei Pod pronti" \
  'kubectl -n lab-dns get endpointslices -l kubernetes.io/service-name=web; kubectl -n lab-dns get pods -l app=web -o custom-columns=POD:.metadata.name,IP:.status.podIP'
passo "Endpoints, la vecchia API: funziona ancora ma è deprecata (guarda il warning)" \
  'kubectl -n lab-dns get endpoints web'
passo "Risolve ≠ funziona: il Service vuoto ha un nome e un IP, ma nessun Pod dietro: kube-proxy rifiuta subito la connessione (uscita 7 voluta)" \
  "$X dig +search +short vuoto; kubectl -n lab-dns get endpointslices -l kubernetes.io/service-name=vuoto; $X curl -s -m 3 http://vuoto"
passo "Il ClusterIP è virtuale: la porta 80 risponde, il ping no (non è l'IP di nessuna interfaccia)" \
  "$X sh -c 'curl -s -m 3 -o /dev/null -w \"porta 80: HTTP %{http_code}\n\" http://web; ping -c 2 -W 1 \$(dig +search +short web) >/dev/null && echo \"ping: risponde\" || echo \"ping: nessuna risposta\"'"
passo "Chi traduce il ClusterIP: kube-proxy. Modalità (vuota = iptables) e le regole KUBE-SVC/KUBE-SEP sul nodo, una SEP per Pod" \
  "kubectl -n kube-system get cm kube-proxy -o jsonpath='{.data.config\\.conf}' | grep -E '^mode'; minikube -p lab ssh -- sudo iptables -t nat -S | grep 'lab-dns/web' | head -6"
passo "Un Pod con hostNetwork usa il DNS del nodo: il nome web non esiste (uscita voluta)" \
  "kubectl -n lab-dns run hn --rm -i --quiet --restart=Never --image=busybox:1.37 --overrides='{\"spec\":{\"hostNetwork\":true}}' -- sh -c 'sleep 1; head -3 /etc/resolv.conf; wget -qO- -T 3 http://web.lab-dns.svc.cluster.local | head -1'"
passo "Con dnsPolicy ClusterFirstWithHostNet torna a usare CoreDNS" \
  "kubectl -n lab-dns run hn2 --rm -i --quiet --restart=Never --image=busybox:1.37 --overrides='{\"spec\":{\"hostNetwork\":true,\"dnsPolicy\":\"ClusterFirstWithHostNet\"}}' -- sh -c 'sleep 1; grep nameserver /etc/resolv.conf; wget -qO- -T 3 http://web.lab-dns.svc.cluster.local | head -1'"
passo "Le stesse domande viste da CoreDNS (nel lab il Corefile ha il plugin log)" \
  'kubectl -n kube-system logs deploy/coredns --since=5m | grep -E "example.com|web.lab-dns" | tail -6'
passo "Pulizia" \
  'kubectl delete ns lab-dns'
