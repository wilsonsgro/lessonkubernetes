#!/usr/bin/env bash
# Lezione 04 — ConfigMap e Secret: variabili d'ambiente contro file montati.
source "$(dirname "$0")/../lib/passo.sh"
guardia_lab
titolo "04. ConfigMap e Secret"
F="$LEZIONI/kubernetes/04-configmap-secret.yaml"

passo "Applica ConfigMap app-config, Secret db e il Deployment 'conf' che li usa in due modi: env e volume" \
  "kubectl apply -f $F"
passo "Aspetta il rollout" \
  'kubectl -n lab rollout status deploy/conf'
passo "Prendo il nome di un Pod (lo uso nei passi successivi)" \
  'P=$(kubectl -n lab get pod -l app=conf -o name | head -1); echo $P'
passo "Dentro il Pod: la variabile d'ambiente e il file montato dalla ConfigMap" \
  "kubectl -n lab exec \$P -- sh -c 'echo LOG_LEVEL=\$LOG_LEVEL; cat /etc/app/app.properties'"
passo "Il volume è fatto di link simbolici: ..data punta a una cartella con data e ora. È così che l'aggiornamento è atomico" \
  'kubectl -n lab exec $P -- ls -la /etc/app'
passo "Modifico la ConfigMap senza riavviare niente" \
  "kubectl -n lab patch cm app-config --type merge -p '{\"data\":{\"LOG_LEVEL\":\"debug\",\"app.properties\":\"feature.x=true\\n\"}}'"
passo "Dopo ~60 s: il FILE è cambiato, la VARIABILE no (le env si leggono solo all'avvio del container)" \
  "sleep 60; kubectl -n lab exec \$P -- sh -c 'echo LOG_LEVEL=\$LOG_LEVEL; cat /etc/app/app.properties'"
passo "Un Secret è solo base64, non cifrato: chi può leggerlo lo decodifica. Per questo RBAC sui Secret e cifratura at-rest" \
  "kubectl -n lab get secret db -o jsonpath='{.data.password}' | base64 -d; echo"
passo "Per far prendere la nuova env serve un container nuovo: rollout restart crea Pod nuovi con la ConfigMap aggiornata" \
  'kubectl -n lab rollout restart deploy/conf && kubectl -n lab rollout status deploy/conf'
passo "Nel Pod nuovo anche la VARIABILE vale debug (vale lo stesso per Laravel con config:cache: si rifà all'avvio)" \
  "P=\$(kubectl -n lab get pod -l app=conf --field-selector=status.phase=Running -o name | tail -1); kubectl -n lab exec \$P -- sh -c 'echo LOG_LEVEL=\$LOG_LEVEL; cat /etc/app/app.properties'"
nota "In git: il manifest del Secret con valori finti (secret.example.yaml), quello vero in .gitignore." \
     "Base64 non cifra; una password finita in un commit si cambia, .gitignore non riscrive la storia."
