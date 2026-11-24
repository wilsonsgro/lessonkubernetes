### In una frase

Il Biodistretto è un sito vero (Laravel, Vite, MariaDB, Elasticsearch, MinIO) portato da Docker Compose a un cluster
**minikube a 2 nodi** con **un solo comando**, `./deploy.sh`. **Ansible** fa da regista e lancia **Terraform**, che
crea il cluster e tutti i workload; **HAProxy** sull'host porta il traffico ai NodePort di nginx. Sono i pezzi delle
lezioni 21, 22 e 23, messi insieme in un progetto che deve funzionare davvero.

### Chi fa cosa, e dove l'hai già visto

| Pezzo | Nel progetto | Lezione |
|---|---|---|
| `deploy.sh` | installa le collection, aggiunge la libreria `docker` al venv di pipx e lancia il playbook | 23, parte 08 |
| Ansible `site.yml` | **sette ruoli, un tag per ruolo**: prerequisiti, cluster, immagini, app, dati, haproxy, verifica | 23, parte 08 |
| Terraform `terraform/cluster` | il cluster `biodistretto` con il provider `scott-the-programmer/minikube`: driver docker, 2 nodi, `cni = "kindnet"` | 22 |
| Terraform `terraform/app` | namespace, Secret, CA e certificato, ConfigMap e tutti i workload come `kubernetes_manifest` | 22 e 04 |
| Kubernetes | StatefulSet con volume per i dati, Deployment per backend, worker, frontend e nginx (2 repliche) | 02, 05 |
| HAProxy | container sulla rete dell'host: 80/443 → NodePort 30080/30443 su ogni nodo, statistiche su `:8404` | 21 |

### La catena al contrario

Nella parte 10 Terraform crea i nodi e scrive l'inventario per Ansible. Qui succede il contrario: è **Ansible a
lanciare Terraform**, con `community.general.terraform`, e a usarne gli output. Gli output dello stack `app` (la CA,
utente e password del sito) finiscono in `tf_app.outputs`. La CA viene scritta in `ca-biodistretto.crt` per il
browser, e la password serve alla verifica finale.

Al posto di un inventario scritto da Terraform c'è l'**elenco dei nodi**: Ansible legge gli InternalIP con
`kubectl get nodes` e li passa al template `haproxy.cfg.j2`, che scrive una riga `server` per ogni nodo con
`{% for nome, ip in nodi %}`.

### Il percorso di una richiesta

```
browser ──80/443──▶ HAProxy (host, PROXY protocol) ──▶ NodePort 30080/30443 su ogni nodo
                                                     └▶ nginx (2 repliche)
                                                          ├─ /            → frontend
                                                          ├─ /api /up     → backend PHP-FPM
                                                          └─ /media       → MinIO (sola lettura)
```

- HAProxy lavora in **`mode tcp`**: non decifra il TLS. Lo termina nginx con il certificato creato da Terraform.
- **`send-proxy-v2`**: HAProxy apre la connessione con l'intestazione del PROXY protocol; nginx ascolta con
  `listen … proxy_protocol` e ricava l'IP vero del client con `real_ip_header proxy_protocol`.
- Il controllo di salute (`option httpchk GET /healthz`, `check port 30081`) va su un **NodePort a parte**: nginx
  risponde `ok` sulla porta 8081 del Pod (`bordo.conf`).
- Il Service di nginx ha **`externalTrafficPolicy: Local`**: un nodo senza un Pod di nginx non risponde al
  controllo e HAProxy lo toglie dal giro. È lo stesso ragionamento sul Pod locale della lezione 21.

### Terraform nel progetto

- **Due stack separati** (`cluster` e `app`), ognuno con il suo state: il cluster si crea una volta, i workload
  cambiano spesso.
- I manifest sono **template** (`templatefile`) decodificati con `provider::kubernetes::manifest_decode_multi`, e
  diventano risorse `kubernetes_manifest` con **`for_each` su `"Kind/nome"`**: togliere un manifest non sposta gli
  altri.
- Le password le genera Terraform (`random_password`), come la CA e il certificato del sito (provider `tls`) e
  l'htpasswd del sito (`loafoe/htpasswd`). Tutto finisce **nello state**, che `.gitignore` esclude (`*.tfstate`,
  `*.tfplan`).
- Un'**annotazione con il checksum** della configurazione (`biodistretto/config`) sul template dei Pod: se cambia la
  config, i Pod ripartono. È il `checksum/config` delle lezioni 04 e 09, fatto con `sha256(jsonencode(…))`.
- **Tag dell'immagine = ID dell'immagine**: un cambio di codice produce un ID nuovo e i Pod ripartono; un rilancio
  senza cambi lascia lo stesso ID e non tocca niente.

### Ansible nel progetto

- **Idempotente per contratto**: il secondo giro di `./deploy.sh` deve dare `changed=0`, per questo ogni `command`
  ha il suo `changed_when`. I `register` di sola lettura hanno `changed_when: false`.
- **Segreti fuori da git**: l'`APP_KEY` si legge da `docker/.env` con `slurp` e **`no_log: true`**, e arriva a
  Terraform come variabile d'ambiente `TF_VAR_app_key`. La password delle statistiche la crea il lookup `password` in
  `.cache/haproxy-stats`, la prima volta, e poi la rilegge.
- **`block` / `always`**: i piani di `community.general.terraform` contengono lo state, quindi chiavi e password.
  `TMPDIR` punta a `.cache/tf` (0700), e `always` la svuota anche se Terraform fallisce.
- **Verifica senza `sleep` fissi**: `uri` sulle statistiche di HAProxy con `until` / `retries` finché tutti i nodi
  sono UP, poi `curl` con `failed_when` sui codici attesi: 301 da http, 401 senza password, 200 sull'API.

### Trappole vere, trovate facendo

- **Il bridge podman del provider minikube**: a differenza della CLI può lasciare attivo `87-podman-bridge.conflist`
  accanto a kindnet. Pod diversi prendono gli stessi IP e il traffico va a vuoto («no route to host», CSI in crash,
  volumi `Pending`). Rimedio: `cni = "kindnet"` esplicito, bridge spento su ogni nodo, Pod di `kube-system` ricreati
  solo dove serviva.
- **I piani in `/tmp`**: senza un `TMPDIR` privato, il modulo terraform di Ansible lascia un `tmp*.tfplan` con dentro
  lo state a ogni giro. Guardare i log non basta: si apre un piano e si cercano le chiavi.
- **Il riavvio del PC**: rimettere su i container dei nodi non basta, perché kubelet e cri-docker li accende solo
  `minikube start`. Il ruolo `cluster` mette un `@reboot` nel crontab dell'utente.

### Verifica rapida (progetto reale)

1. Chi lancia Terraform in questo progetto, e come arrivano ad Ansible gli output (CA, password del sito)?
2. Perché i piani di Terraform vanno in una cartella privata, svuotata in un blocco `always`?
3. Come viene generato l'elenco dei `server` nella configurazione di HAProxy?
4. Perché HAProxy controlla la salute su un NodePort a parte, e che cosa c'entra `externalTrafficPolicy: Local`?
5. A che cosa servono `send-proxy-v2` da una parte e `listen … proxy_protocol` dall'altra?
6. Perché il tag dell'immagine è il suo ID, e che effetto ha su un rilancio di `./deploy.sh` senza modifiche?
7. Dove nascono le password del database, e perché non stanno in git?
8. Che cosa è andato storto con il bridge podman, e come si è rimediato?
