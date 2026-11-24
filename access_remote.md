# Accesso dal Mac al cluster minikube `lab`

Come usare `kubectl` dal Mac sul minikube `lab` di questo PC (192.168.1.79), con un kubeconfig che contiene
il token di un ServiceAccount protetto da RBAC, come su EKS/GKE.

## Architettura

```
Mac ──► 192.168.1.79:9999 ──(socat, servizio systemd)──► 192.168.49.2:8443 (apiserver minikube)
```

- L'apiserver di minikube (`192.168.49.2:8443`) sta sulla rete docker interna: dal Mac non si vede.
- `socat` ascolta su `0.0.0.0:9999` e inoltra all'apiserver. Servizio: `minikube-apiserver-forward` (abilitato, riparte al boot).
- Il certificato dell'apiserver vale per `localhost`, `127.0.0.1`, `192.168.49.2`, non per `192.168.1.79`:
  per questo nel kubeconfig c'è `tls-server-name: localhost`.
- Credenziali: ServiceAccount `accessi/wilson-mac`, token nel Secret `accessi/wilson-mac-token`,
  ClusterRoleBinding `wilson-mac` → `cluster-admin`.
- Rete (socat) e permessi (RBAC) sono due problemi separati: il kubeconfig dà accesso all'apiserver,
  ai pod si arriva con `kubectl exec` se l'RBAC lo permette.

## Stato (2026-11-24)

| Dove | Cosa |
|---|---|
| Ubuntu | `/etc/systemd/system/minikube-apiserver-forward.service`, `socat` installato, ufw non attivo |
| Cluster | namespace `accessi`, SA `wilson-mac`, Secret `wilson-mac-token`, ClusterRoleBinding `wilson-mac` |
| Mac | `~/.kube/lab.yaml` (permessi 600), contesto `lab`, namespace di default `lab` |

## 1. Inoltro della porta (una volta sola, con sudo)

```bash
sudo apt-get install -y socat
sudo tee /etc/systemd/system/minikube-apiserver-forward.service >/dev/null <<'EOF'
[Unit]
Description=Inoltro apiserver minikube lab (192.168.49.2:8443) su 0.0.0.0:9999
After=network-online.target docker.service
Wants=network-online.target

[Service]
ExecStart=/usr/bin/socat TCP-LISTEN:9999,bind=0.0.0.0,fork,reuseaddr TCP:192.168.49.2:8443
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now minikube-apiserver-forward
systemctl is-active minikube-apiserver-forward; ss -ltn | grep 9999
```

Atteso `active` e `0.0.0.0:9999`. Dal Mac: `nc -vz 192.168.1.79 9999`.

## 2. ServiceAccount, RBAC e token (sull'Ubuntu)

```bash
kubectl config use-context lab
kubectl create namespace accessi --dry-run=client -o yaml | kubectl apply -f -
kubectl -n accessi create serviceaccount wilson-mac --dry-run=client -o yaml | kubectl apply -f -
kubectl create clusterrolebinding wilson-mac --clusterrole=cluster-admin --serviceaccount=accessi:wilson-mac --dry-run=client -o yaml | kubectl apply -f -
kubectl -n accessi create secret generic wilson-mac-token --type=kubernetes.io/service-account-token --dry-run=client -o yaml | kubectl annotate --local -f - kubernetes.io/service-account.name=wilson-mac -o yaml | kubectl apply -f -
```

## 3. Creare il kubeconfig (sull'Ubuntu)

Senza heredoc: incollando nel terminale si aggiungono spazi a inizio riga, `  EOF` non chiude il blocco
e la shell resta in `heredoc>`. Con `kubectl config set-*` gli spazi non danno fastidio.

```bash
K=~/lab-mac.kubeconfig; rm -f $K
TOKEN=$(kubectl -n accessi get secret wilson-mac-token -o jsonpath='{.data.token}' | base64 -d)
CA=$(kubectl -n accessi get secret wilson-mac-token -o jsonpath='{.data.ca\.crt}')
kubectl config --kubeconfig=$K set-cluster lab --server=https://192.168.1.79:9999 --tls-server-name=localhost
kubectl config --kubeconfig=$K set clusters.lab.certificate-authority-data "$CA"
kubectl config --kubeconfig=$K set-credentials wilson-mac --token="$TOKEN"
kubectl config --kubeconfig=$K set-context lab --cluster=lab --user=wilson-mac --namespace=lab
kubectl config --kubeconfig=$K use-context lab
chmod 600 $K; unset TOKEN CA
kubectl --kubeconfig=$K auth whoami
```

Atteso: `system:serviceaccount:accessi:wilson-mac`. `K=` va definito prima: con `$K` vuota i comandi
scrivono nel kubeconfig di default dell'Ubuntu.

## 4. Copiarlo sul Mac (terminale del Mac)

```bash
mkdir -p ~/.kube
scp wilsonsgro@192.168.1.79:lab-mac.kubeconfig ~/.kube/lab.yaml && chmod 600 ~/.kube/lab.yaml && ssh wilsonsgro@192.168.1.79 'rm ~/lab-mac.kubeconfig'
```

Il file contiene il token `cluster-admin` che non scade: non farne `cat` in chat o in un ticket.

## 5. Usarlo dal Mac

```bash
export KUBECONFIG=~/.kube/lab.yaml
kubectl auth whoami
kubectl get pods -n lab
kubectl -n lab exec -it db-0 -- sh
```

oppure, senza variabile, file indicato comando per comando:

```bash
kubectl --kubeconfig ~/.kube/lab.yaml -n lab exec -it db-0 -- sh
```

`-n lab` si può togliere: il namespace di default del contesto è già `lab`.

### Come kubectl sceglie il kubeconfig

Si ferma al primo che trova:

1. `--kubeconfig <file>` sulla riga di comando;
2. la variabile `KUBECONFIG` (anche più file separati da `:`, che vengono uniti; in caso di conflitto vince il primo);
3. `~/.kube/config`;
4. nessuno: ripiega su `localhost:8080` → `The connection to the server localhost:8080 was refused`.

`export` vale solo nella shell corrente. Per non ripeterlo:
- `cp -n ~/.kube/lab.yaml ~/.kube/config` se sul Mac non c'è già un `~/.kube/config`;
- oppure `export KUBECONFIG=~/.kube/config:~/.kube/lab.yaml` in `~/.zshrc`.

Vale anche per `k9s`, `helm`, Lens. Per vedere cosa si sta usando: `kubectl config current-context`,
`kubectl config view --minify`.

### Pod senza shell

`web` e `api` usano `traefik/whoami`, che non ha `sh`: `exec ... sh` risponde
`exec: "sh": executable file not found in $PATH`. Il permesso c'è, manca la shell. Si entra con un container effimero:

```bash
kubectl -n lab debug -it <pod> --image=busybox:1.37 --target=<nome-container>
```

Il container effimero resta nella spec del pod finché il pod non viene ricreato.

## Ruotare il token

Cancellare e ricreare il Secret con lo stesso nome NON cambia il token. I token legati a un Secret
contengono solo `iss`, `sub`, namespace, nome del Secret, nome e UID del ServiceAccount (niente
`iat`/`exp`/`jti`), e la firma RS256 è deterministica: stessi dati → stesso token, e quello vecchio torna valido.

Per un token nuovo si ricrea il ServiceAccount, che prende un UID nuovo (il ClusterRoleBinding punta al nome e resta valido):

```bash
kubectl -n accessi delete secret wilson-mac-token
kubectl -n accessi delete sa wilson-mac
kubectl -n accessi create sa wilson-mac
kubectl -n accessi create secret generic wilson-mac-token --type=kubernetes.io/service-account-token --dry-run=client -o yaml | kubectl annotate --local -f - kubernetes.io/service-account.name=wilson-mac -o yaml | kubectl apply -f -
sleep 3
```

Poi i passi 3 e 4. Verifica: con il kubeconfig vecchio `kubectl auth whoami` deve dare `Unauthorized`.

In alternativa, token con scadenza (più simile a EKS): `kubectl -n accessi create token wilson-mac --duration=24h`
e il valore va al posto di `token:` nel kubeconfig.

## Ridurre i permessi

`cluster-admin` è comodo ma, se il token esce, vale su tutto il cluster. Per lavorare solo in `lab` (exec compreso):

```bash
kubectl delete clusterrolebinding wilson-mac
kubectl -n lab create rolebinding wilson-mac --clusterrole=edit --serviceaccount=accessi:wilson-mac
```

Il kubeconfig del Mac non cambia. `kubectl auth can-i --list -n lab` mostra cosa può fare.

## Revoca e pulizia

```bash
kubectl -n accessi delete secret wilson-mac-token
kubectl delete clusterrolebinding wilson-mac --ignore-not-found; kubectl delete namespace accessi
sudo systemctl disable --now minikube-apiserver-forward
sudo rm /etc/systemd/system/minikube-apiserver-forward.service; sudo systemctl daemon-reload
```

Sul Mac: `rm ~/.kube/lab.yaml`.

## Problemi

| Sintomo | Causa probabile | Rimedio |
|---|---|---|
| `connection refused` su 9999 | servizio spento, socat su 127.0.0.1 | `systemctl status minikube-apiserver-forward`, `ss -ltn \| grep 9999` |
| connessione aperta ma timeout/EOF | cluster spento o IP del nodo cambiato | `minikube -p lab status`, `minikube -p lab ip`, aggiornare l'IP nel servizio |
| `x509: ... not 192.168.1.79` | manca `tls-server-name` | `tls-server-name: localhost` nel blocco `cluster` |
| `x509: certificate signed by unknown authority` | cluster ricreato, CA nuova | rifare i passi 2–4 |
| `Unauthorized` | Secret o SA cancellati, cluster ricreato | rifare i passi 2–4 |
| `Forbidden` | l'RBAC non lo permette | `kubectl auth can-i --list` |
| `exec: "sh": executable file not found` | immagine senza shell | `kubectl debug` (sopra) |
| `localhost:8080 was refused` sul Mac | nessun kubeconfig letto | `export KUBECONFIG=~/.kube/lab.yaml` |

## Alternativa senza porta 9999: tunnel SSH dal Mac

```bash
ssh -fN -L 18443:192.168.49.2:8443 wilsonsgro@192.168.1.79
kubectl config --kubeconfig ~/.kube/lab.yaml set-cluster lab --server=https://127.0.0.1:18443
```

## shutdown

```bash
# Fermarlo subito, ma lasciarlo ripartire al prossimo avvio:
sudo systemctl stop minikube-apiserver-forward

# Fermarlo e non farlo più ripartire (il file resta, così puoi riaccenderlo con enable --now):
sudo systemctl disable --now minikube-apiserver-forward

# Toglierlo del tutto:
sudo systemctl disable --now minikube-apiserver-forward
sudo rm /etc/systemd/system/minikube-apiserver-forward.service
sudo systemctl daemon-reload
```

## restart

```bash
# Disattivarlo invece di toglierlo (consigliato)
sudo systemctl disable --now minikube-apiserver-forward
# Riattivarlo
sudo systemctl enable --now minikube-apiserver-forward
```

```bash
# Se è stato fatto con la rimozione di tutto
printf '%s\n' '[Unit]' 'Description=Inoltro apiserver minikube lab (192.168.49.2:8443) su 0.0.0.0:9999' 'After=network-online.target docker.service' 'Wants=network-online.target' '' '[Service]' 'ExecStart=/usr/bin/socat
TCP-LISTEN:9999,bind=0.0.0.0,fork,reuseaddr TCP:192.168.49.2:8443' 'Restart=always' 'RestartSec=5' '' '[Install]' 'WantedBy=multi-user.target' | sudo tee /etc/systemd/system/minikube-apiserver-forward.service >/dev/null
sudo systemctl daemon-reload
sudo systemctl enable --now minikube-apiserver-forward
systemctl is-active minikube-apiserver-forward; ss -ltn | grep 9999
```


```bash
## controllare l'ip

minikube -p lab status      # se non è Running: minikube -p lab start
minikube -p lab ip          # deve essere 192.168.49.2

cat /etc/systemd/system/minikube-apiserver-forward.service
# vedere l'ip nell' ExecStart=/usr/bin/socat TCP-LISTEN:9999,bind=0.0.0.0,fork,reuseaddr TCP:192.168.49.2:8443
# se ip di minikube è diverso dall'ip di ExecStart procedere in questo modo

sudo sed -i 's/192\.168\.49\.2:8443/192.168.49.34:8443/' /etc/systemd/system/minikube-apiserver-forward.service
sudo systemctl daemon-reload
sudo systemctl restart minikube-apiserver-forward
grep ExecStart /etc/systemd/system/minikube-apiserver-forward.service

```

