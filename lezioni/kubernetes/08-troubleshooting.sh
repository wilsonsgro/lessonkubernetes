#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# 08. TROUBLESHOOTING: CINQUE GUASTI DA RICONOSCERE AL PRIMO SGUARDO
# Versione: Kubernetes 1.35 · kubectl 1.35
# Livello: 3 — Sicurezza e operatività
# ═══════════════════════════════════════════════════════════════════════════
# Al colloquio la domanda tipica è "il Pod non parte, cosa fai?". La
# risposta che convince è un METODO, non un elenco di comandi:
#
#   1. STATO      kubectl get pod -o wide          (STATUS, RESTARTS, NODE)
#   2. EVENTI     kubectl describe pod / get events (scheduler, kubelet)
#   3. LOG        kubectl logs [--previous]         (l'app)
#   4. DENTRO     kubectl exec / kubectl debug      (rete, file, processi)
#   5. INTORNO    Service, EndpointSlice, NetworkPolicy, nodo, quota
#
# STATUS → DOVE GUARDARE
#   Pending              scheduler: risorse, taint, affinity, PVC  → describe
#   ContainerCreating    kubelet: volume, secret mancante, CNI      → describe
#   ImagePullBackOff     nome/tag sbagliato, registry privato senza
#                        imagePullSecrets, rate limit di Docker Hub → describe
#   CrashLoopBackOff     il processo esce: config, permessi, comando → logs
#   OOMKilled (137)      limite di memoria superato               → lastState
#   Running ma 0/1       readiness che fallisce                     → describe
#   Running 1/1 ma niente traffico  Service/selector/porta/policy    → endpointslices
#
# LAB: questo script ROMPE apposta cinque workload nel namespace "rotto",
# poi li diagnostica. Prima indovina tu la causa, poi lancia "diagnosi".
#   bash 08-troubleshooting.sh rompi
#   kubectl -n rotto get pod -w          # aspetta ~1 minuto
#   bash 08-troubleshooting.sh diagnosi
#   bash 08-troubleshooting.sh pulisci

set -euo pipefail
NS=rotto

guardia_contesto() {
  local attuale
  attuale="$(kubectl config current-context)"
  [[ "$attuale" == "lab" || "${CONTESTO_LAB:-}" == "$attuale" ]] || {
    echo "STOP: contesto '$attuale' (atteso 'lab')" >&2; exit 1; }
}

rompi() {
  guardia_contesto
  kubectl create namespace $NS --dry-run=client -o yaml | kubectl apply -f -

  # 1) immagine inesistente
  kubectl -n $NS create deployment immagine --image=traefik/whoami:v9.9.9

  # 2) il processo esce subito con errore
  kubectl -n $NS create deployment crash --image=busybox:1.37 \
    -- sh -c 'echo "manca DATABASE_URL" >&2; exit 1'

  # 3) usa più memoria del limite
  kubectl -n $NS apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: memoria }
spec:
  restartPolicy: Never
  containers:
    - name: app
      image: busybox:1.37
      command: ["sh", "-c", "head -c 100m /dev/zero | tail > /dev/null"]
      resources:
        limits: { memory: 20Mi }
EOF

  # 4) chiede più CPU di quante ne abbia il cluster
  kubectl -n $NS apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: enorme }
spec:
  containers:
    - name: app
      image: busybox:1.37
      command: ["sleep", "3600"]
      resources:
        requests: { cpu: "64" }
EOF

  # 5) il Service non seleziona niente (label sbagliata)
  kubectl -n $NS create deployment eco --image=traefik/whoami:v1.12
  kubectl -n $NS create service clusterip eco --tcp=80:80 --dry-run=client -o yaml \
    | sed 's/app: eco/app: ecco/' | kubectl apply -f -
}

diagnosi() {
  guardia_contesto
  echo "── 1. STATO"
  kubectl -n $NS get pod -o wide

  echo "── 2. EVENTI (Warning, i più recenti in fondo)"
  kubectl -n $NS get events --field-selector type=Warning \
    --sort-by=.lastTimestamp -o custom-columns=OGGETTO:.involvedObject.name,MOTIVO:.reason,MESSAGGIO:.message \
    | cut -c1-160

  echo "── 3. LOG del container crashato"
  # Durante il back-off il container "attuale" È quello morto: i suoi log
  # sono già l'errore. --previous è l'istanza prima ancora, se il runtime
  # la conserva: altrimenti stampa "unable to retrieve" e esce con 0
  # (provato su k3s), quindi un `||` di ripiego non scatterebbe mai.
  kubectl -n $NS logs deploy/crash --tail=5
  kubectl -n $NS logs deploy/crash --previous --tail=5; echo

  echo "── 4. Perché è morto 'memoria'"
  kubectl -n $NS get pod memoria \
    -o jsonpath='{.status.containerStatuses[0].state.terminated.reason} exit={.status.containerStatuses[0].state.terminated.exitCode}{"\n"}'

  echo "── 5. Il Service 'eco' ha endpoint?"
  kubectl -n $NS get endpointslices -l kubernetes.io/service-name=eco
  kubectl -n $NS get svc eco -o jsonpath='selector={.spec.selector}{"\n"}'
  kubectl -n $NS get pod -l app=eco --show-labels

  echo "── 6. Debug in un Pod senza shell: container effimero accanto all'app"
  local pod
  pod="$(kubectl -n $NS get pod -l app=eco -o name | head -1)"
  kubectl -n $NS debug "$pod" -i --profile=general --image=busybox:1.37 --target=whoami -- \
    sh -c 'ps; wget -qO- localhost/api | head -c 80; echo' || true
  # --target condivide il namespace dei processi: vedi i processi
  # dell'app anche se l'immagine è FROM scratch (niente sh, niente ps).
  # -i serve per vedere l'output: senza, il comando gira e non stampa.
}

pulisci() {
  guardia_contesto
  kubectl delete namespace $NS --wait=false
}

case "${1:-}" in
  rompi) rompi ;;
  diagnosi) diagnosi ;;
  pulisci) pulisci ;;
  *) echo "uso: $0 rompi|diagnosi|pulisci" ;;
esac

# ── ALTRI ATTREZZI ──────────────────────────────────────────────────────────
#   kubectl debug node/lab-m02 -it --image=busybox:1.37   # shell sul nodo (/host)
#   kubectl top pod --containers -n X                     # CPU/memoria reali
#   kubectl get pod X -o yaml | grep -A5 lastState        # l'ultima morte
#   kubectl events -n X --for pod/Y                       # eventi di un oggetto
#   kubectl get --raw /api/v1/nodes/N/proxy/stats/summary # metriche del kubelet
#   journalctl -u kubelet                                 # sul nodo
#   crictl ps -a / crictl logs                            # runtime, sotto kubectl
#   Gli eventi durano 1 ora: per lo storico servono log e metriche (lezione 13)

# ── DOMANDE DA COLLOQUIO ────────────────────────────────────────────────────
# D: CrashLoopBackOff ma `kubectl logs` è vuoto.
# R: Prova --previous; se è vuoto anche quello, il processo muore prima
#    di scrivere: comando o entrypoint sbagliato, binario per un'altra
#    architettura (exec format error), permessi sul file, readOnlyRoot
#    che impedisce di scrivere. `describe` mostra exit code e reason.
#
# D: L'app risponde da dentro il Pod ma non dal Service.
# R: EndpointSlice vuoti (selector o readiness), targetPort sbagliata,
#    l'app ascolta su 127.0.0.1 invece di 0.0.0.0, NetworkPolicy.
#
# D: Il nodo è NotReady.
# R: kubelet fermo, disco pieno (DiskPressure), memoria, CNI rotto,
#    certificati scaduti. `describe node` → Conditions; sul nodo
#    journalctl -u kubelet.

# ══════════════════════════════════════════════════════════════════════════
# RIEPILOGO
# • Metodo: stato → eventi → log → dentro → intorno
# • Pending = scheduler; ImagePull/ContainerCreating = kubelet; Crash = app
# • In back-off `logs` mostra già l'istanza morta; exit 137 = OOM o SIGKILL
# • Service muto: prima gli EndpointSlice
# • kubectl debug per immagini senza shell e per i nodi
# ══════════════════════════════════════════════════════════════════════════
