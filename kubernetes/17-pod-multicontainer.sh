#!/usr/bin/env bash
# Lezione 17 — init container, sidecar nativi e ciclo di vita del Pod, nel namespace lab-pod.
source "$(dirname "$0")/../lib/passo.sh"
guardia_lab
titolo "17. Dentro il Pod: init, sidecar, ciclo di vita"
F="$LEZIONI/kubernetes/17-pod-multicontainer.yaml"

passo "Il sidecar nativo è un campo dello schema: restartPolicy dentro initContainers" \
  'kubectl explain pod.spec.initContainers.restartPolicy | sed -n "1,14p"'
passo "Applica namespace lab-pod, Pod ciclo (init che aspetta), Pod web-log (app + sidecar + cliente), Job lavoro" \
  "kubectl apply -f $F"
passo "ciclo è fermo in Init:0/1: il suo init cerca il Service db-finto, che non esiste ancora" \
  'sleep 5; kubectl -n lab-pod get pod ciclo; kubectl -n lab-pod logs ciclo -c attendi-db --tail=3'
passo "Creo il Service: l'init lo trova, esce con 0, e solo allora parte l'app" \
  'kubectl -n lab-pod create service clusterip db-finto --tcp=5432:5432 && kubectl -n lab-pod wait --for=condition=Ready pod/ciclo --timeout=60s && kubectl -n lab-pod logs ciclo -c app'
passo "web-log: READY 3/3 conta anche il sidecar. È elencato fra gli init, ma è ancora acceso" \
  'kubectl -n lab-pod wait --for=condition=Ready pod/web-log --timeout=90s; kubectl -n lab-pod get pod web-log; kubectl -n lab-pod get pod web-log -o jsonpath="{range .status.initContainerStatuses[*]}{.name}: started={.started} ready={.ready}{\"\n\"}{end}"'
passo "Il sidecar legge il file che il container cliente scrive nell'emptyDir condiviso" \
  'sleep 6; kubectl -n lab-pod logs web-log -c spedisci --tail=3'
passo "Stessa rete: dal sidecar raggiungo l'app su localhost:80, anche se l'app non ha shell" \
  'kubectl -n lab-pod exec web-log -c spedisci -- wget -qO- localhost:80 | head -3'
passo "Stesso hostname per tutti i container: il nome del Pod" \
  'kubectl -n lab-pod exec web-log -c spedisci -- hostname; kubectl -n lab-pod exec web-log -c cliente -- hostname'
passo "Filesystem NON condiviso: un file scritto in /tmp dal cliente, fuori dal volume, nel sidecar non c'è (uscita 1 voluta)" \
  'kubectl -n lab-pod exec web-log -c cliente -- touch /tmp/solo-qui; kubectl -n lab-pod exec web-log -c spedisci -- ls /tmp/solo-qui'
passo "Il Job: il sidecar battito è in loop infinito, eppure il Job arriva a Complete (prima della 1.28 restava Running)" \
  'kubectl -n lab-pod wait --for=condition=Complete job/lavoro --timeout=90s; kubectl -n lab-pod get job lavoro; kubectl -n lab-pod get pod -l job-name=lavoro -o jsonpath="{.items[0].status.phase} · sidecar: {.items[0].status.initContainerStatuses[0].state.terminated.reason}/{.items[0].status.initContainerStatuses[0].state.terminated.exitCode}{\"\n\"}"'
nota "Con trap 'exit 0' TERM il sidecar esce pulito (Completed/0)." \
     "Senza trap, misurato sul lab: Error/137 dopo i 30 s di grazia, Pod comunque Succeeded."
passo "Immutabilità: cambiare l'immagine di un Pod esistente è permesso. Il kubelet lo annuncia (Killing: definition changed) e riavvia il container" \
  'kubectl -n lab-pod patch pod ciclo -p "{\"spec\":{\"containers\":[{\"name\":\"app\",\"image\":\"busybox:1.36\"}]}}" && sleep 3 && kubectl -n lab-pod get events --field-selector involvedObject.name=ciclo,reason=Killing -o custom-columns=MOTIVO:.reason,MESSAGGIO:.message'
passo "Il riavvio arriva solo dopo ~30 s: il PID 1 del container è sh, ignora SIGTERM, e il kubelet aspetta la grazia prima del SIGKILL" \
  'for i in $(seq 20); do [ "$(kubectl -n lab-pod get pod ciclo -o jsonpath="{.status.containerStatuses[0].image}")" = busybox:1.36 ] && break; sleep 3; done; kubectl -n lab-pod get pod ciclo -o jsonpath="immagine={.status.containerStatuses[0].image} riavvii={.status.containerStatuses[0].restartCount}{\"\n\"}"'
passo "Cambiare le porte no: Forbidden, con l'elenco dei pochi campi modificabili (uscita 1 voluta)" \
  'kubectl -n lab-pod patch pod web-log -p "{\"spec\":{\"containers\":[{\"name\":\"app\",\"ports\":[{\"containerPort\":81}]}]}}" 2>&1 | head -c 400; echo; false'
passo "Fase ≠ STATUS: un container che esce sempre con 1 e restartPolicy Always. STATUS alterna Error e CrashLoopBackOff, la fase resta Running" \
  'kubectl -n lab-pod run cade --image=busybox:1.37 -- sh -c "echo muoio; exit 1"; for i in $(seq 30); do kubectl -n lab-pod get pod cade --no-headers | grep -q CrashLoopBackOff && break; sleep 2; done; kubectl -n lab-pod get pod cade; kubectl -n lab-pod get pod cade -o jsonpath="fase={.status.phase} riavvii={.status.containerStatuses[0].restartCount}{\"\n\"}"'
passo "logs --previous: l'uscita dell'istanza caduta, quella che serve per capire il crash (letto durante il backoff: nell'attimo del riavvio non c'è ancora)" \
  'kubectl -n lab-pod logs cade --previous'
passo "Pulizia: il namespace porta via tutto" \
  'kubectl delete ns lab-pod'
