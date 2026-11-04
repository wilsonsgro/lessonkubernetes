#!/usr/bin/env bash
# Lezione 01 — crea il cluster minikube "lab" (2 nodi, Calico) e guarda come è fatto.
source "$(dirname "$0")/../lib/passo.sh"
titolo "01. Architettura di Kubernetes e laboratorio minikube"

passo "Versioni dei client: kubectl parla con l'apiserver, minikube crea il cluster" \
  'kubectl version --client; minikube version'
passo "Contesti noti a kubectl: il contesto dice A QUALE cluster arrivano i comandi" \
  'kubectl config get-contexts'
passo "Crea il cluster 'lab': driver docker (ogni nodo è un container), 2 nodi per affinity/spread, Calico perché il CNI di default non applica le NetworkPolicy. Ci mette qualche minuto" \
  'minikube start -p lab --driver=docker --nodes=2 --cpus=2 --memory=4g --cni=calico'
passo "Addon ingress: installa il controller ingress-nginx (serve alla lezione 03)" \
  'minikube -p lab addons enable ingress'
passo "Addon metrics-server: abilita 'kubectl top' e l'autoscaling HPA (lezione 06)" \
  'minikube -p lab addons enable metrics-server'
passo "Punta kubectl sul cluster nuovo: da qui in poi tutti gli script controllano che il contesto sia 'lab'" \
  'kubectl config use-context lab'
passo "I nodi: lab è il control plane, lab-m02 il worker. -o wide mostra IP, OS, runtime" \
  'kubectl get nodes -o wide'
passo "Il control plane è fatto di Pod in kube-system: apiserver, etcd, scheduler, controller-manager, più CoreDNS, kube-proxy, calico" \
  'kubectl get pods -n kube-system -o wide'
passo "Quei Pod sono STATICI: il kubelet li legge da questa cartella del nodo, non dall'apiserver" \
  'minikube -p lab ssh -- sudo ls /etc/kubernetes/manifests'
passo "La stessa cartella sull'host Ubuntu NON esiste: il nodo è un container, il suo filesystem non è quello del PC (uscita 2 voluta)" \
  'ls /etc/kubernetes/manifests'
passo "etcd: un solo membro (etcd-lab), sul control plane. Due nodi Kubernetes non vogliono dire due copie del database" \
  'kubectl -n kube-system get pod -l component=etcd -o wide'
nota "Quorum etcd = floor(N/2)+1:  1 membro → 0 guasti tollerati · 3 → 1 · 4 → 1 · 5 → 2." \
     "Per questo si usano 3 o 5 membri, mai 4, e su macchine diverse."
passo "Cosa crede di avere Kubernetes: Capacity e Allocatable di ogni nodo" \
  'kubectl get nodes -o custom-columns=NOME:.metadata.name,CPU:.status.capacity.cpu,MEMORIA:.status.capacity.memory,CPU_ALLOC:.status.allocatable.cpu,MEM_ALLOC:.status.allocatable.memory'
passo "Cosa ha davvero il container-nodo: --memory=4g è un limite del cgroup, --cpus=2 non viene applicato (cpu.max = max)" \
  'docker exec lab cat /sys/fs/cgroup/memory.max /sys/fs/cgroup/cpu.max; docker exec lab nproc'
passo "Quanto è vicino al limite: memory.current comprende la cache dei file, che il kernel recupera. Contano il netto e gli OOM kill" \
  'for n in lab lab-m02; do docker exec $n sh -c "cd /sys/fs/cgroup; awk -v c=\$(cat memory.current) -v m=\$(cat memory.max) \"/^(active|inactive)_file /{f+=\\\$2} END{printf \\\"%-8s totale %5d Mi · cache %5d Mi · netto %5d Mi = %d%% di %d Mi\\\\n\\\", \\\"$n\\\", c/2^20, f/2^20, (c-f)/2^20, (c-f)*100/m, m/2^20}\" memory.stat; grep oom_kill memory.events"; done'
passo "kubectl top (aspetto il metrics-server, dopo un avvio ci mette fino a un minuto): consumo osservato, in percentuale della Capacity sopra (tutto l'host), non di 2 CPU / 4 GiB" \
  'for i in $(seq 30); do kubectl top nodes >/dev/null 2>&1 && break; sleep 5; done; kubectl top nodes'
nota "Con il driver docker ogni nodo vede tutte le CPU e la RAM del PC: lo scheduler conta su ~16 GiB per nodo," \
     "ma il container-nodo viene ucciso dal kernel a 4 GiB. In un cluster vero Capacity = la macchina."
passo "Tutti i tipi di oggetto che l'apiserver conosce (nome corto, gruppo API, namespaced o no)" \
  'kubectl api-resources | head -30'
passo "kubectl explain: la documentazione di un campo, direttamente dallo schema del cluster" \
  'kubectl explain deployment.spec.strategy.rollingUpdate'
passo "Crea un Deployment imperativo con 2 repliche (in produzione si usa YAML, qui serve a vedere la riconciliazione)" \
  'kubectl create deployment eco --image=traefik/whoami:v1.12 --replicas=2'
passo "Aspetta che il rollout sia completo: le repliche sono pronte" \
  'kubectl rollout status deployment/eco'
passo "Auto-riparazione: cancello i Pod e guardo (-w) il ReplicaSet ricrearli da solo. Dura 15 secondi" \
  'kubectl get pods -l app=eco -w & W=$!; sleep 2; kubectl delete pod -l app=eco --wait=false; sleep 13; kill $W'
nota "I Pod cancellati passano da Terminating a Error: whoami esce con codice 2 al SIGTERM (misurato)." \
     "Non è un guasto: conta che i due Pod nuovi arrivino a Running."
passo "Gli eventi raccontano il perché: SuccessfulCreate del ReplicaSet, Scheduled, Pulled, Started" \
  'kubectl get events --sort-by=.metadata.creationTimestamp | tail -12'
passo "Un Service davanti a eco, per vedere il terzo tipo di IP" \
  'kubectl expose deployment eco --port=80 && kubectl get svc eco'
passo "Tre IP diversi: del NODO (rete docker 192.168.49.x), del POD (10.244.x, rete Calico), del SERVICE (ClusterIP virtuale, rete 10.96.0.0/12: da 10.96 a 10.111)" \
  'kubectl get nodes -o custom-columns=NODO:.metadata.name,IP:.status.addresses[0].address; kubectl get pods -l app=eco -o custom-columns=POD:.metadata.name,IP:.status.podIP,NODO:.spec.nodeName; kubectl get svc eco -o custom-columns=SERVICE:.metadata.name,CLUSTER-IP:.spec.clusterIP'
passo "Trappola: senza -n, kubectl guarda solo il namespace 'default'. Qui eco c'è, il control plane no" \
  'kubectl get pods; echo "--- in tutti i namespace: $(kubectl get pods -A --no-headers | wc -l) Pod"'
passo "Pulizia del Deployment e del Service di prova" \
  'kubectl delete deployment,service eco'
nota "Per spegnere il cluster senza perderlo:  minikube -p lab stop" \
     "Per riaccenderlo:                       minikube -p lab start" \
     "Per cancellarlo del tutto:              minikube -p lab delete"
