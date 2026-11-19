#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# 01. ARCHITETTURA DI KUBERNETES E LABORATORIO SU UBUNTU
# Versione: Kubernetes 1.34–1.35 · minikube 1.37 · kubectl 1.35
# Livello: 0 — Fondamenta
# ═══════════════════════════════════════════════════════════════════════════
# Kubernetes non "esegue container": RICONCILIA. Tu dichiari uno stato
# desiderato (spec), dei controller lo confrontano in continuo con lo stato
# osservato (status) e agiscono finché coincidono. Tutto il resto del corso
# è una conseguenza di questa frase.
#
# CONTROL PLANE
#   • kube-apiserver   unica porta d'ingresso: autentica, autorizza (RBAC),
#                      passa dagli admission controller, scrive in etcd.
#                      È stateless: si scala orizzontalmente dietro un LB.
#   • etcd             key-value con consenso Raft. Quorum = (n/2)+1:
#                      3 nodi reggono 1 guasto, 5 ne reggono 2. Numero pari
#                      = nessun vantaggio. Backup: `etcdctl snapshot save`.
#   • kube-scheduler   sceglie il nodo per i Pod senza nodeName:
#                      filtro (risorse, taint, affinity) → punteggio → bind.
#   • controller-manager  i loop: Deployment→ReplicaSet→Pod, Node, Job,
#                      EndpointSlice, ServiceAccount token…
#
# NODO
#   • kubelet          legge i Pod assegnati al suo nodo, parla col
#                      runtime via CRI (containerd/CRI-O), esegue le probe,
#                      riporta lo status. NON gestisce Pod di altri nodi.
#   • kube-proxy       traduce i Service in regole iptables/IPVS/nftables
#                      (con Cilium può non esserci: eBPF).
#   • CNI              dà un IP a ogni Pod; modello "flat": ogni Pod parla
#                      con ogni Pod senza NAT. Le NetworkPolicy le applica
#                      il CNI (Calico, Cilium), non Kubernetes.
#
# Cosa succede con `kubectl apply -f deploy.yaml` (domanda classica):
#   1. kubectl → POST/PATCH all'apiserver (authn → authz → mutating
#      admission → validazione schema → validating admission → etcd)
#   2. il Deployment controller vede il nuovo oggetto → crea un ReplicaSet
#   3. il ReplicaSet controller crea N Pod (senza nodo)
#   4. lo scheduler assegna un nodo a ogni Pod (binding)
#   5. il kubelet di quel nodo vede il Pod → CRI: pull, sandbox, container
#   6. CNI assegna l'IP; probe readiness OK → il Pod entra negli EndpointSlice
#   Nessuno "chiama" il componente successivo: ognuno osserva l'apiserver
#   (watch) e reagisce. Per questo il sistema si auto-ripara.
#
# ── NEL PROGETTO VERO: il Biodistretto su minikube ───────────────────────
#   ~/biodistretto/kubernetes (branch kubernetes). I grep partono da lì:
#   cd ~/biodistretto/kubernetes · come si usa: il README della cartella
#   Il cluster non nasce da `minikube start` ma da una risorsa Terraform:
#   2 nodi (biodistretto, biodistretto-m02), driver docker, CNI kindnet.
#     grep -n -A9 'resource "minikube_cluster"' terraform/cluster/main.tf
#   Gli addon sono una variabile: metrics-server per `kubectl top`, e
#   csi-hostpath-driver per lo storage che regge con più nodi (lezione 05).
#     grep -n -A9 'variable "addon"' terraform/cluster/variables.tf
#   Differenza con il cluster `lab`: lì il CNI è Calico, qui è kindnet.
#   Il provider minikube lasciava acceso anche un secondo CNI (lezione 08).

set -euo pipefail

# ── LABORATORIO SU UBUNTU (ssh wilsonsgro@192.168.1.79) ────────────────────
# minikube con driver docker: il "nodo" è un container. Profilo dedicato
# "lab" → contesto kubectl "lab", separato da qualunque cluster vero.
#
# ⚠ Sul tuo Ubuntu il contesto attuale di kubectl è un cluster GKE.
#   Prima di ogni apply: guarda dove stai puntando. Questa riga va in
#   ogni script che modifica un cluster.
guardia_contesto() {
  local atteso="lab"
  local attuale
  attuale="$(kubectl config current-context)"
  if [[ "$attuale" != "$atteso" ]]; then
    echo "STOP: contesto '$attuale', atteso '$atteso'" >&2
    echo "      kubectl config use-context $atteso" >&2
    exit 1
  fi
}

crea_cluster() {
  # calico: il CNI di default di minikube NON applica le NetworkPolicy
  # (lezione 03). 2 nodi: servono per affinity e spread (lezione 06).
  minikube start -p lab \
    --driver=docker \
    --nodes=2 \
    --cpus=2 --memory=4g \
    --cni=calico
  # senza --kubernetes-version minikube usa la versione che supporta meglio
  #
  # Con il driver docker ogni nodo è un container: --memory=4g diventa un
  # limite del cgroup, --cpus=2 no (cpu.max resta "max"). E il kubelet dichiara
  # come Capacity tutto l'host (sul PC del lab 12 CPU, ~16 GiB per nodo):
  # lo scheduler conta su risorse che il container non ha, e le % di
  # `kubectl top` sono calcolate su quella Capacity. Si controlla con:
  #   kubectl get nodes -o custom-columns=NOME:.metadata.name,CPU:.status.capacity.cpu,MEM:.status.allocatable.memory
  #   docker exec lab cat /sys/fs/cgroup/memory.max /sys/fs/cgroup/cpu.max
  # Per sapere quanto manca al limite non basta memory.current: comprende la
  # cache dei file, che il kernel recupera (sul lab 3,8 GiB "usati", di cui
  # 1,5 di cache: netto 57%). Contano il netto e oom_kill in memory.events:
  #   docker exec lab grep -E '^(active|inactive)_file ' /sys/fs/cgroup/memory.stat
  #   docker exec lab grep oom_kill /sys/fs/cgroup/memory.events

  minikube -p lab addons enable ingress          # ingress-nginx (lezione 03)
  minikube -p lab addons enable metrics-server   # kubectl top + HPA (lezione 06)
  kubectl config use-context lab
}

esplora() {
  guardia_contesto
  kubectl get nodes -o wide
  kubectl get pods -n kube-system -o wide       # apiserver, etcd, scheduler… sono Pod statici
  # I Pod statici li crea il kubelet dai file in /etc/kubernetes/manifests:
  minikube -p lab ssh -- sudo ls /etc/kubernetes/manifests
  # Quali API esistono e con che versione:
  kubectl api-resources | head -30
  kubectl explain deployment.spec.strategy.rollingUpdate
  # Riconciliazione dal vivo: cancella un Pod gestito e guarda tornarlo
  kubectl create deployment eco --image=traefik/whoami:v1.12 --replicas=2
  kubectl rollout status deployment/eco
  kubectl get pods -l app=eco -w &   # in un altro terminale è più leggibile
  local osservatore=$!
  kubectl delete pod -l app=eco --wait=false
  sleep 10; kill "$osservatore" || true      # ferma il -w, non i Pod
  kubectl get events --sort-by=.metadata.creationTimestamp | tail -12
  # Tre IP da non confondere: NODO (rete docker 192.168.49.x), POD (10.244.x,
  # Calico) e SERVICE (ClusterIP virtuale nella rete 10.96.0.0/12, cioè 10.96–10.111:
  # nessuno lo "possiede").
  kubectl expose deployment eco --port=80
  kubectl get nodes,pods,svc -o wide
  # Senza -n si guarda solo il namespace corrente (default): "No resources
  # found" non vuol dire cluster vuoto.
  kubectl get pods -A
  # Un solo membro etcd: due nodi Kubernetes non sono due copie del database.
  # Quorum = floor(N/2)+1 → 3 membri reggono 1 guasto, 4 ancora 1, 5 ne reggono 2.
  kubectl -n kube-system get pod -l component=etcd
  kubectl delete deployment,service eco
}

spegni() {
  minikube -p lab stop      # conserva lo stato
  # minikube delete -p lab  # cancella tutto
}

case "${1:-}" in
  crea)    crea_cluster ;;
  esplora) esplora ;;
  spegni)  spegni ;;
  *) echo "uso: $0 crea|esplora|spegni" ;;
esac

# ── kubectl DA COLLOQUIO ────────────────────────────────────────────────────
#   kubectl get pod -A -o wide --field-selector=status.phase!=Running
#   kubectl get events -A --sort-by=.lastTimestamp
#   kubectl describe pod X              # eventi: scheduling, pull, probe
#   kubectl logs X -c app --previous    # log del container PRIMA del crash
#   kubectl get deploy X -o yaml | less # spec + status + managedFields
#   kubectl diff -f file.yaml           # cosa cambierebbe un apply
#   kubectl apply --server-side -f ...  # SSA: field ownership sul server
#   kubectl auth can-i create pods --as=system:serviceaccount:lab:app
#   kubectl get --raw /readyz?verbose   # salute dell'apiserver

# ── DOMANDE DA COLLOQUIO ────────────────────────────────────────────────────
# D: Perché etcd con 3 o 5 nodi e non 4?
# R: Il quorum di 4 è 3: tolleri 1 guasto come con 3 nodi, ma con più
#    latenza di scrittura. I dispari massimizzano i guasti tollerati.
#
# D: L'apiserver cade. I Pod già in esecuzione si fermano?
# R: No. I kubelet continuano a far girare ciò che hanno; non ci sono
#    nuovi scheduling, nessun self-healing, nessun aggiornamento Endpoint.
#    Il data plane va avanti, il control plane è congelato.
#
# D: Differenza tra apply client-side e server-side?
# R: Client-side calcola il merge con l'annotazione last-applied.
#    Server-side (SSA) traccia per ogni campo il "manager" proprietario
#    (managedFields): due tool che scrivono lo stesso campo vanno in
#    conflitto esplicito invece di sovrascriversi in silenzio. Helm 4 e
#    Argo CD lo usano di default.
#
# D: Cosa fa un admission controller? Esempio?
# R: Intercetta la richiesta dopo authz e prima di etcd. Mutating
#    (es. inietta un sidecar, imposta default) e Validating (es. Pod
#    Security Admission, Kyverno/Gatekeeper, ValidatingAdmissionPolicy
#    in CEL, nativa dalla 1.30).

# ══════════════════════════════════════════════════════════════════════════
# RIEPILOGO
# • Kubernetes = stato desiderato + controller che riconciliano via watch
# • apiserver unica porta, etcd unica fonte di verità (quorum dispari)
# • kubelet esegue, scheduler sceglie il nodo, CNI dà la rete
# • Lab: minikube profilo "lab", 2 nodi, calico, ingress, metrics-server
# • Prima di ogni apply: kubectl config current-context
# ══════════════════════════════════════════════════════════════════════════
