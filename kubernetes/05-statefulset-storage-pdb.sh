#!/usr/bin/env bash
# Lezione 05 — StatefulSet, PVC e PodDisruptionBudget.
source "$(dirname "$0")/../lib/passo.sh"
guardia_lab
titolo "05. StatefulSet, storage e PDB"
F="$LEZIONI/kubernetes/05-statefulset-storage-pdb.yaml"

passo "Applica Service headless 'db', StatefulSet 'db' con 3 repliche e volumeClaimTemplates, PDB" \
  "kubectl apply -f $F"
passo "Lo StatefulSet crea i Pod IN ORDINE: db-0, poi db-1, poi db-2 (ognuno parte quando il precedente è Ready)" \
  'kubectl -n lab rollout status sts/db'
passo "Ogni Pod ha il SUO PVC (dati-db-0, dati-db-1…): il disco segue il nome, non il nodo" \
  'kubectl -n lab get pod,pvc -l app=db'
passo "Il Pod scrive nel suo disco chi è e quando è partito" \
  'kubectl -n lab exec db-0 -- cat /data/identita'
passo "Cancello db-0 e aspetto che torni: stesso nome, stesso PVC" \
  'kubectl -n lab delete pod db-0 && kubectl -n lab wait --for=condition=Ready pod/db-0 --timeout=120s'
passo "Ora le righe sono due: il Pod nuovo ha ritrovato il disco del vecchio" \
  'kubectl -n lab exec db-0 -- cat /data/identita'
passo "DNS stabile per ogni replica: <pod>.<service>.<namespace>.svc.cluster.local (con busybox serve il nome completo)" \
  'kubectl -n lab run dns --rm -i --quiet --restart=Never --image=busybox:1.37 -- nslookup db-1.db.lab.svc.cluster.local'
passo "Scale down a 1: spariscono db-2 e db-1, ma i loro PVC RESTANO (protezione dei dati)" \
  'kubectl -n lab scale sts/db --replicas=1; sleep 10; kubectl -n lab get pod,pvc -l app=db'
passo "Torna a 3 repliche: db-1 e db-2 ritrovano i loro PVC" \
  'kubectl -n lab scale sts/db --replicas=3 && kubectl -n lab rollout status sts/db'
passo "Drain del worker: sfratta i Pod rispettando il PDB (maxUnavailable: 1). Se il PDB non lo consente, il drain aspetta e riprova" \
  'kubectl -n lab get pdb db; kubectl drain lab-m02 --ignore-daemonsets --delete-emptydir-data --timeout=90s'
passo "Dopo il drain: lab-m02 è Ready,SchedulingDisabled (cordon) e sopra restano solo i Pod dei DaemonSet (calico, kube-proxy)" \
  'kubectl get nodes; kubectl get pods -A -o wide --field-selector spec.nodeName=lab-m02'
passo "Le repliche db sono tutte su lab, e il PDB è tornato a 1 disruption permessa" \
  'kubectl -n lab get pod -l app=db -o wide; kubectl -n lab get pdb db'
passo "Riapri il nodo allo scheduling (drain lo aveva messo in cordon)" \
  'kubectl uncordon lab-m02 && kubectl get nodes'
passo "uncordon NON riporta indietro i Pod: restano dove sono finiti. Il nodo riceverà solo Pod NUOVI" \
  'kubectl -n lab get pod -l app=db -o wide'
