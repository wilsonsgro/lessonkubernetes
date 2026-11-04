#!/usr/bin/env bash
# Lezione 08 — rompo cinque workload apposta e li diagnostico con il metodo.
source "$(dirname "$0")/../lib/passo.sh"
guardia_lab
titolo "08. Troubleshooting"
NS=rotto

passo "Namespace di prova (dry-run | apply: idempotente, non fallisce se esiste già)" \
  "kubectl create namespace $NS --dry-run=client -o yaml | kubectl apply -f -"
passo "Guasto 1, ImagePullBackOff: un tag che non esiste" \
  "kubectl -n $NS create deployment immagine --image=traefik/whoami:v9.9.9"
passo "Guasto 2, CrashLoopBackOff: il processo esce subito con errore" \
  "kubectl -n $NS create deployment crash --image=busybox:1.37 -- sh -c 'echo \"manca DATABASE_URL\" >&2; exit 1'"
passo "Guasto 3, OOMKilled: alloca 100 MB con un limite di 20 MiB" \
  "kubectl -n $NS apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: memoria }
spec:
  restartPolicy: Never
  containers:
    - name: app
      image: busybox:1.37
      command: [\"sh\", \"-c\", \"head -c 100m /dev/zero | tail > /dev/null\"]
      resources:
        limits: { memory: 20Mi }
EOF"
passo "Guasto 4, Pending: chiede 64 CPU, nessun nodo le ha" \
  "kubectl -n $NS apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: enorme }
spec:
  containers:
    - name: app
      image: busybox:1.37
      command: [\"sleep\", \"3600\"]
      resources:
        requests: { cpu: \"64\" }
EOF"
passo "Guasto 5, Service senza endpoint: il selector dice app=ecco, i Pod hanno app=eco" \
  "kubectl -n $NS create deployment eco --image=traefik/whoami:v1.12 && kubectl -n $NS create service clusterip eco --tcp=80:80 --dry-run=client -o yaml | sed 's/app: eco/app: ecco/' | kubectl apply -f -"
passo "Aspetto 30 s che i guasti si manifestino" \
  'sleep 30'
passo "METODO 1 — STATO: la colonna STATUS dice già il tipo di guasto" \
  "kubectl -n $NS get pod -o wide"
passo "METODO 2 — EVENTI Warning, i più recenti in fondo: il motivo esatto (Failed pull, BackOff, FailedScheduling…)" \
  "kubectl -n $NS get events --field-selector type=Warning --sort-by=.lastTimestamp -o custom-columns=OGGETTO:.involvedObject.name,MOTIVO:.reason,MESSAGGIO:.message | cut -c1-160"
passo "METODO 3 — LOG del container che crasha, e --previous per il tentativo PRECEDENTE (quello morto)" \
  "kubectl -n $NS logs deploy/crash --tail=5; kubectl -n $NS logs deploy/crash --previous --tail=5"
passo "Perché è morto 'memoria': reason OOMKilled, exit code 137 (128 + SIGKILL 9)" \
  "kubectl -n $NS get pod memoria -o jsonpath='{.status.containerStatuses[0].state.terminated.reason} exit={.status.containerStatuses[0].state.terminated.exitCode}{\"\\n\"}'"
passo "Pending: describe mostra il messaggio dello scheduler (Insufficient cpu)" \
  "kubectl -n $NS describe pod enorme | tail -5"
passo "Service senza endpoint: EndpointSlice vuoto…" \
  "kubectl -n $NS get endpointslices -l kubernetes.io/service-name=eco"
passo "…perché selector e label non combaciano" \
  "kubectl -n $NS get svc eco -o jsonpath='selector={.spec.selector}{\"\\n\"}'; kubectl -n $NS get pod -l app=eco --show-labels"
passo "Debug di un Pod SENZA shell: container effimero busybox che condivide i processi dell'app (--target)" \
  "P=\$(kubectl -n $NS get pod -l app=eco -o name | head -1); kubectl -n $NS debug \$P -i --profile=general --image=busybox:1.37 --target=whoami -- sh -c 'ps; wget -qO- localhost/api | head -c 80; echo'"
passo "Pulizia: via il namespace e tutto quello che contiene" \
  "kubectl delete namespace $NS --wait=false"
