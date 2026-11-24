# Biodistretto su Kubernetes (minikube)

Lo stack di `docker/docker-compose.yml`, senza dozzle, su un cluster minikube a 2 nodi.
Si accende con un solo comando, dal PC del laboratorio:

```bash
cd ~/biodistretto/kubernetes
./deploy.sh                 # crea o allinea tutto, ed è idempotente
./deploy.sh --tags immagini,app   # ricostruisce le immagini e aggiorna i workload
./deploy.sh distruggi       # toglie HAProxy, i workload e il cluster
```

## Chi fa cosa

| Pezzo | Ruolo |
|---|---|
| **Ansible** (`ansible/`) | regista: controlla i prerequisiti, costruisce le immagini, lancia Terraform, importa i dati, configura HAProxy, verifica |
| **Terraform** `terraform/cluster` | crea il cluster minikube `biodistretto` (driver docker, 2 nodi, addon `csi-hostpath-driver`) |
| **Terraform** `terraform/app` | namespace, segreti casuali, CA e certificato TLS, password del sito, ConfigMap, e tutti i workload (`kubernetes_manifest` sui template in `manifests/`) |
| **Kubernetes** | MariaDB, Redis, Elasticsearch, MinIO (StatefulSet con volume), Mailhog, backend PHP-FPM, worker, frontend, nginx |
| **HAProxy** | container `biodistretto-haproxy` sulla rete dell'host: porte 80/443 → NodePort di nginx su ogni nodo, statistiche su `:8404` |
| **minikube** | il cluster, con le immagini caricate nei nodi (`minikube image load`) |

```
browser ──80/443──▶ HAProxy (host, PROXY protocol) ──▶ NodePort 30080/30443 su ogni nodo
                                                     └▶ nginx (2 repliche)
                                                          ├─ /            → frontend (build Vite statica, password)
                                                          ├─ /api /up     → backend PHP-FPM
                                                          ├─ /backend/... → backend PHP-FPM (prefisso /backend)
                                                          └─ /media, /backend/media → MinIO (sola lettura)
```

## Differenze rispetto allo stack docker

- **Frontend**: in docker gira il dev server Vite, che inoltra `/api`, `/up`, `/storage`, `/media` al vhost del backend.
  Qui c'è la build di produzione (`docker/frontend/Dockerfile`) e quelle rotte le fa nginx (`terraform/app/nginx/www.conf.tftpl`).
- **Immagini**: si costruiscono da un contesto pulito (`docker/build.sh`), senza `.env`, `node_modules` e log; il tag è l'ID dell'immagine,
  quindi un cambio di codice fa ripartire i pod e un rilancio senza cambi non tocca niente.
- **Dominio**: `biodistretto.lab` (`www.`, `backend.`), variabile `dominio` in `ansible/group_vars/all.yml`. Il certificato lo firma una CA
  del laboratorio che Terraform crea e Ansible scrive in `ca-biodistretto.crt`.
- **Segreti**: password di MariaDB, MinIO e del sito generate da Terraform; l'`APP_KEY` è quella di `docker/.env`, così i dati cifrati del dump restano leggibili.
- **Dati**: al primo giro Ansible importa `docker/backup/biodistretto.sql` nel database vuoto, copia i media dal volume docker
  `docker_minio_biodistretto` (su una copia del volume, l'originale resta com'è), lancia le migrazioni e `search:reindex`.
- **Media**: il bucket del volume docker ha 3 oggetti; le altre immagini citate in `company_images` mancano già nello stack docker,
  quindi anche qui le schede aziende le mostrano rotte.
- **Riavvio del PC**: riavviare i container dei nodi non basta, perché kubelet e cri-docker li accende solo `minikube start`.
  Per questo il ruolo `cluster` mette nel crontab dell'utente un `@reboot` che lancia `minikube -p biodistretto start`
  (log in `kubernetes/.cache/minikube-avvio.log`); HAProxy riparte da solo (`unless-stopped`). Dopo l'avvio nginx e worker
  fanno qualche riavvio, finché DNS e database non sono pronti; poi il sito risponde in circa 2 minuti.
- **nginx** usa così come sono `nginx.conf`, `proxy_common.conf` e `backend_prefix.conf` di `docker/config/nginx`; cambiano solo i due vhost.

## Trappola del provider minikube

Il provider Terraform di minikube, a differenza della CLI, può lasciare attivo `87-podman-bridge.conflist` accanto a kindnet:
i primi pod prendono IP da quel bridge, altri pod ricevono gli stessi IP da kindnet e il traffico va a vuoto
(«no route to host», plugin CSI in crash, volumi in `Pending`). Per questo `cni = "kindnet"` è esplicito e il ruolo
`cluster` spegne il bridge su ogni nodo dove è ancora acceso, toglie l'interfaccia `cni-podman0` e ricrea, forzando,
solo i pod di `kube-system` di quel nodo (al primo giro i workload con i dati non esistono ancora).

I piani di `community.general.terraform` contengono lo stato, quindi chiavi e password: Ansible li fa scrivere in
`kubernetes/.cache/tf` (0700, fuori da git) e li cancella dopo ogni giro.

## Usarlo dal Mac

Sul Mac, in `/etc/hosts`:

```
IP-DEL-LAB  biodistretto.lab www.biodistretto.lab backend.biodistretto.lab
```

poi `https://www.biodistretto.lab`. Per togliere l'avviso del certificato si importa `kubernetes/ca-biodistretto.crt` tra le CA fidate.
Utente e password del sito:

```bash
cd ~/biodistretto/kubernetes/terraform/app
terraform output -raw utente_accesso; echo
terraform output -raw password_accesso; echo
```

Statistiche di HAProxy: `http://IP-DEL-LAB:8404/`, utente `admin`, password in `kubernetes/.cache/haproxy-stats` (generata da Ansible, fuori da git).

## Comandi utili

```bash
kubectl --context biodistretto -n biodistretto get pods -o wide
kubectl --context biodistretto -n biodistretto logs deploy/backend
kubectl --context biodistretto -n biodistretto exec deploy/backend -- php artisan about
minikube -p biodistretto stop      # spegne senza perdere niente; ./deploy.sh lo riaccende
```

## Requisiti del PC

docker, minikube, terraform, kubectl, ansible (pipx, in `~/.local/bin`); `deploy.sh` aggiunge da solo le collection
`community.general`/`community.docker` e la libreria Python `docker`. Elasticsearch vuole `vm.max_map_count >= 262144`.
