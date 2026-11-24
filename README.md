# kubernetesprj: laboratorio guidato su Ubuntu

Gli stessi comandi delle lezioni di **Kubernetes & Helm** e di **Terraform & Ansible**
(il sito delle lezioni è http://127.0.0.1:3000 sul Mac), raccolti in script che **spiegano
ogni comando prima di eseguirlo**. Funziona così: lanci lo script, leggi cosa sta per
succedere, premi Invio e guardi l'output. Dopo, ricopi i comandi a mano per impararli.

Le stesse lezioni, con appunti, quiz, glossario e simulazioni, sono anche un sito statico in
`site/`, servito da nginx su http://lessons.kubernates.local: lezioni 01–09 e approfondimenti 21
(HAProxy), 22 (Terraform), 23 (Ansible) e 24 (il Biodistretto, vedi sezione 10). Build e test
girano solo in Docker: istruzioni in `site/README.md`.

Tutto gira su questo PC (Ubuntu, `192.168.1.79`), senza cloud.

---

## 1. Come funziona uno script

Ogni passo stampa tre cose:

```
[05] Cambia immagine: parte un rolling update, un ReplicaSet nuovo sale…   ← cosa fa (azzurro)
  $ kubectl -n lab set image deploy/web web=traefik/whoami:v1.11          ← il comando (giallo)
     [Invio] esegui · [s] salta · [q] esci ›                               ← tocca a te
```

| Tasto | Effetto |
|---|---|
| **Invio** | esegue il comando |
| **s** | salta il passo e passa al successivo |
| **q** | esce dallo script |

Quando un comando finisce con un errore compare in rosso `↳ uscita N`. **Non è sempre un
problema**: molti passi falliscono apposta, per insegnare qualcosa (una validazione che
rifiuta un valore, una NetworkPolicy che blocca, un upgrade che torna indietro con un rollback).
La spiegazione del passo dice sempre se l'errore è voluto. Lo script non si ferma mai da solo.

Puoi mettere queste variabili davanti al comando:

| Variabile | Esempio | Effetto |
|---|---|---|
| `AUTO=1` | `AUTO=1 bash kubernetes/02-…sh` | esegue tutto senza chiedere (per un ripasso veloce) |
| `DA=n` | `DA=7 bash kubernetes/05-…sh` | parte dal passo 7 (se eri uscito a metà) |
| `CLUSTER=microk8s` | `CLUSTER=microk8s bash stack/stack.sh` | solo per lo stack: usa MicroK8s invece di minikube |

Con `AUTO=1` vengono saltati i `port-forward` in primo piano (Argo CD nella lezione 12,
Grafana nella 13), perché non finirebbero mai.

---

## 2. Prima di iniziare: controlla gli strumenti

```bash
cd ~/kubernetesprj
for c in docker kubectl helm minikube terraform ansible jq curl; do printf '%-10s ' $c; command -v $c || echo MANCA; done
docker ps                    # deve rispondere senza sudo
```

- Se manca **terraform**, lo installa `bash terraform/00-installa.sh` (vedi sezione 5).
- Se manca **ansible**, apri un terminale nuovo (sta in `~/.local/bin`), oppure lancia
  `export PATH="$HOME/.local/bin:$PATH"`.
- Risorse: il cluster `lab` usa 2 nodi da 2 CPU e 4 GB ciascuno. La lezione 13
  (Prometheus) aggiunge circa 1,5 GB. Il PC ha 12 CPU e 15 GB e basta, ma tieni acceso
  **un laboratorio pesante alla volta** (la sezione 8 spiega come spegnerli).

---

## 3. Percorso Kubernetes & Helm (minikube)

### 3.1 Crea il cluster (una volta sola)

```bash
cd ~/kubernetesprj
bash kubernetes/01-architettura-e-lab.sh
```

Lo script crea il cluster minikube **`lab`**:

- 2 nodi, `lab` e `lab-m02`, che sono container Docker;
- la CNI Calico, che serve per le NetworkPolicy;
- gli addon ingress e metrics-server.

Ci vogliono alcuni minuti. Poi lo script esplora il control plane e mostra come i Pod
si riparano da soli.

Da qui in poi **ogni script controlla che kubectl punti al cluster `lab`**, e si ferma
se non è così. Puoi controllare tu quando vuoi:

```bash
kubectl config current-context     # deve dire: lab
kubectl get nodes                  # lab e lab-m02, Ready
```

### 3.2 Le lezioni, in ordine

Per ogni lezione c'è una **spiegazione** in `lezioni/kubernetes/NN-nome.md`, accanto al file della
lezione. Contiene la teoria, gli oggetti campo per campo e la tabella dei passi dello script guidato:
cosa vedi a ogni passo e quali passi falliscono apposta. Ci sono anche le domande da colloquio e tre
esercizi. Leggila mentre lo script gira. L'indice con i link è in `kubernetes/README.md`.

| Script | Cosa impari | Dipende da |
|---|---|---|
| `02-deployment-rollout-probe.sh` | Deployment, rolling update, rollback, probe, QoS | 01 |
| `03-service-ingress-networkpolicy.sh` | Service, EndpointSlice, Ingress, NetworkPolicy (un Pod passa, l'altro no) | **la 02 applicata** |
| `04-configmap-secret.sh` | ConfigMap come variabile d'ambiente e come file, aggiornamento a caldo, Secret | 01 |
| `05-statefulset-storage-pdb.sh` | StatefulSet, un PVC per Pod, DNS stabile, drain con PDB | 01 |
| `06-scheduling-autoscaling.sh` | distribuzione sui nodi, taint, HPA che sale sotto carico | 01 |
| `07-rbac-pod-security.sh` | ServiceAccount, Role, `auth can-i`, Pod Security "restricted" | 01 |
| `08-troubleshooting.sh` | 5 guasti creati apposta (ImagePull, CrashLoop, OOM, Pending, Service senza endpoint) e il metodo per diagnosticarli | 01 |
| `09-helm-chart.sh` | un chart scritto da zero: lint, template, install, upgrade, rollback | 01 |
| `10-helm-avanzato.sh` | chart ombrello, hook, `helm test`, registry OCI | **la 09** (usa il chart `eco`) |
| `11-kustomize.sh` | base e overlay dev/prod, configMapGenerator, `kubectl diff` | 01 |
| `12-cicd-gitops.sh` | build → scansione con Trivy → push → deploy con Helm; Argo CD con self-heal | **la 09** |
| `13-observability.sh` | kube-prometheus-stack, ServiceMonitor, PromQL, alert, Grafana | 01 (pesante: circa 1,5 GB) |
| `14-logging-alerting.sh` | Loki, LogQL, Alertmanager con inhibit e silence, burn rate | 01 |
| `15-stack-microk8s.sh` | uno stack completo su **MicroK8s**, con le differenze rispetto a minikube e k3s | sezione 3.4 |
| `17-pod-multicontainer.sh` | init container, sidecar nativo (`restartPolicy: Always`), Job che finisce col sidecar acceso, SIGTERM e PID 1, Pod quasi immutabile | 01 |
| `18-namespace-quote.sh` | ResourceQuota e LimitRange, Deployment fermo a 3/6 per la quota, rete fra Namespace aperta finché una NetworkPolicy non la chiude | 01 |
| `19-dns-service-discovery.sh` | `resolv.conf`, search list e `ndots:5` misurati con tcpdump e con il log di CoreDNS, record SRV, Service senza Pod, iptables di kube-proxy | 01 (scarica netshoot, circa 200 MB) |
| `20-api-crd-threat-model.sh` | l'API REST con `kubectl proxy` e curl (201/409/404, 401 contro 403), un CRD con schema, STRIDE con le difese misurate su due Pod | 01 |
| `21-architettura-e-haproxy.sh` | cluster `lab-haproxy` (5 nodi da 1 GiB, `--force`), HAProxy come Ingress controller con Helm al posto di ingress-nginx, `haproxy.cfg` scritto dal controller, `add server` senza reload, rate limit 429 | nessuna: cluster suo, a `lab` spento |

Esempio:

```bash
bash kubernetes/02-deployment-rollout-probe.sh
bash kubernetes/03-service-ingress-networkpolicy.sh
```

In fondo a ogni script c'è un passo o una riga grigia **«Pulizia»** con i comandi per
togliere quello che lo script ha creato. Conviene usarla prima delle lezioni pesanti
(12, 13 e 14).

### 3.2.1 Le domande del diario (`appunti_kubernetes.md`) e il passo che risponde

Il diario segna come «proposti, senza output» diversi comandi lanciati a mano dai file delle
lezioni. Gli script li eseguono e mostrano il risultato:

| Domanda rimasta aperta nel diario | Dove la vedi |
|---|---|
| Perché `kubectl top` dà percentuali così basse? | 01: Capacity del nodo = tutto l'host (12 CPU, ~16 GiB); `--memory=4g` è un limite del cgroup, `--cpus=2` no |
| Nodo, Pod, ClusterIP: tre IP diversi | 01: le tre colonne una accanto all'altra |
| «No resources found» = cluster vuoto? | 01: `get pods` contro `get pods -A` |
| Quanti membri etcd ha il lab? | 01: uno solo, `etcd-lab` |
| Perché due Pod erano più giovani del Deployment? | 01 e 02: `get events` |
| L'update e il rollback sono avvenuti davvero? | 02: `rollout status` e l'immagine letta dopo l'undo |
| L'intruso è bloccato? Il curl dall'host passa dall'Ingress? | 03: passi `intruso` (timeout, uscita 28) e `curl -H Host` (risponde un Pod `web`) |
| La variabile d'ambiente si aggiorna? | 04: no, finché un `rollout restart` non crea Pod nuovi |
| `db-1.db.lab.svc.cluster.local` si risolve? | 05: passo `dns` |
| Il drain finisce? Il PDB cosa permette? Dopo l'uncordon i Pod tornano? | 05: il drain ritenta «would violate the pod's disruption budget» finché la replica sfrattata è di nuovo pronta; su m02 restano solo calico e kube-proxy; dopo l'uncordon i Pod **non** tornano |
| Il 60% dell'HPA di cosa è? | 06: delle requests (20m → 12m per Pod), accanto al consumo reale |

### 3.3 Interfacce web (Argo CD, Grafana, Prometheus)

Le lezioni 12 e 13 aprono un `port-forward` in primo piano, che resta acceso finché non
premi **Ctrl+C**. Il port-forward ascolta su `localhost` **dell'Ubuntu**:

- dal browser dell'Ubuntu: `https://localhost:8443` per Argo CD, `http://localhost:3001` per Grafana.
- dal **Mac**: rilancia lo stesso comando con `--address 0.0.0.0` e usa l'IP dell'Ubuntu, per esempio:
  ```bash
  kubectl -n monitoring port-forward --address 0.0.0.0 svc/mon-grafana 3001:80
  # sul Mac: http://192.168.1.79:3001
  ```

I nodi minikube (`192.168.49.x`) si vedono **solo dall'Ubuntu**, non dalla rete di casa.

### 3.4 Lezione 15: MicroK8s

MicroK8s è un'altra distribuzione di Kubernetes, installata direttamente sull'Ubuntu (non
dentro container). Ha un suo comando, `microk8s kubectl`, quindi non tocca il cluster `lab`.

```bash
snap list microk8s                                       # è installato?
bash lezioni/kubernetes/15-stack-microk8s.sh installa    # solo se NON è installato (chiede sudo)
newgrp microk8s                                          # solo dopo un'installazione nuova
bash kubernetes/15-stack-microk8s.sh                     # chiede la password di sudo per avviarlo
```

Lo stack si raggiunge anche dal Mac: `curl -H 'Host: stack.lab' http://192.168.1.79/`.
Per togliere tutto: `bash lezioni/kubernetes/15-stack-microk8s.sh smonta`.

Se usi MicroK8s e minikube nello stesso periodo, **tienine acceso uno alla volta**.

---

## 4. Lo stack HAProxy + nginx + PHP + Redis + MariaDB

È il cluster di prova da avere subito sotto mano:

```
client ─► HAProxy (NodePort 30080, statistiche 30404)
             │  trova i Pod nginx dal DNS
             ▼
          nginx × 2 ──FastCGI──► php-fpm × 3 ──► Redis (contatore visite)
                                              └─► MariaDB (StatefulSet + disco)
```

```bash
bash stack/stack.sh                       # sul cluster lab (serve la lezione 01)
CLUSTER=microk8s bash stack/stack.sh      # oppure su MicroK8s
```

Lo script applica `stack/stack.yaml` e poi ti mostra:

- una richiesta che attraversa tutta la catena (header `x-servito-da`, Pod nginx, Pod php);
- il bilanciamento del carico;
- le statistiche di HAProxy;
- nginx portato a 4 repliche senza riavviare HAProxy;
- un Pod php cancellato senza che le richieste diano errore;
- il client MariaDB e il contatore in Redis.

Per vederlo dal **Mac**:

```bash
# sull'Ubuntu (minikube):
kubectl -n stack-web port-forward --address 0.0.0.0 svc/haproxy 8090:80 8404:8404
# sul Mac:  http://192.168.1.79:8090/      e      http://192.168.1.79:8404/stats
```

Con MicroK8s il port-forward non serve: `http://192.168.1.79:30080/` e
`http://192.168.1.79:30404/stats`.

Il file `stack/stack.yaml` è fatto per essere letto. Prova a cambiare le repliche, le
immagini o la configurazione di HAProxy, poi riapplica con `kubectl apply -f stack/stack.yaml`.

Pulizia: `kubectl delete namespace stack-web`.

---

## 5. Percorso Terraform & Ansible

Questo percorso non usa il cluster. Terraform usa il **Docker locale** come se fosse un cloud,
e Ansible entra nei container invece che in server raggiunti via SSH.

### 5.1 Installazione (una volta sola)

```bash
bash terraform/00-installa.sh
```

Lo script:

- aggiunge il repository ufficiale HashiCorp e installa `terraform` (chiede sudo);
- installa con pipx, senza sudo, ansible-core, le collection `community.docker` e
  `ansible.posix` e `ansible-lint`.

Ansible è già installato, quindi quei passi diranno che c'è già.
Alla fine **apri un terminale nuovo**.

### 5.2 Le lezioni, in ordine

Accanto a ogni script c'è la sua **spiegazione**: `terraform/NN-nome.md`, anche per la 00. Spiega il file della
lezione che lo script usa (`lezioni/terraform/`), blocco per blocco, e i passi dello script: cosa vedi e quali
falliscono apposta. Ci sono anche le trappole, le domande da colloquio e tre esercizi.

| Script | Cosa impari | Dipende da |
|---|---|---|
| `01-workflow-provider-state.sh` | init, plan -out, apply, state, drift, -replace, destroy | 00 |
| `02-variabili-for-each-espressioni.sh` | variabili con validation, for_each, output, console | 00 |
| `03-stato-remoto-import-moved.sh` | state su PostgreSQL con lock, import, refactoring con moved | 00 |
| `04-moduli-ambienti.sh` | un modulo e due ambienti (dev e prod) con state separati | 00 |
| `05-test-check-pipeline.sh` | `terraform test` con mock, blocco check | 00 |
| `06-ansible-inventario-adhoc.sh` | 3 "server" (web1, web2, db1), inventario, comandi ad-hoc, idempotenza | 00 |
| `07-ansible-playbook.sh` | playbook: check e diff, handler, tag, limit, validate, lint | **la 06** |
| `08-ansible-ruoli-collection.sh` | un ruolo con argument_specs | **la 06** |
| `09-ansible-vault-rolling-update.sh` | segreti con Vault, rolling update a lotti | **la 06** |
| `10-terraform-piu-ansible.sh` | Terraform crea i nodi e scrive l'inventario, Ansible li configura | 00 |

La lezione 03 ha un passo sul **lock** dello state:

1. lo script ti chiede di aprire un secondo terminale e lanciare `terraform apply`;
2. lascia quell'apply fermo alla domanda;
3. nel primo terminale, il plan successivo mostra "Error acquiring the state lock".

Se non vuoi farlo, premi Invio comunque: il passo va avanti senza lock.

I container `web1`, `web2` e `db1` creati dalla 06 restano accesi per la 07, la 08 e la 09.

---

## 6. Argo CD: GitOps sul tuo sito

Argo CD si aggiunge a quello che c'è già, senza ricostruire niente. Chi fa cosa:

| Strumento | Ruolo |
|---|---|
| **Terraform** | crea le risorse infrastrutturali (qui: namespace `mio-sito` con quota e limiti) |
| **minikube** | esegue il cluster Kubernetes locale (`lab`) |
| **Kubernetes** | gestisce i container del sito |
| **Argo CD** | legge git e tiene il cluster uguale a quello che c'è scritto |

Argo CD **tira** da un repository git. Al posto di GitHub c'è **Gitea dentro il cluster**,
così tutto resta su questo PC. Con GitHub cambierebbe solo `repoURL` nell'Application.

Il progetto modello è `argocd/mio-progetto/`, con la stessa forma di un progetto vero:

```
mio-progetto/
├── terraform/      main.tf, variables.tf          → namespace, ResourceQuota, LimitRange
├── kubernetes/     deployment, service, ingress   → quello che Argo CD applica
├── sito/           Dockerfile, index.html         → l'immagine mio-sito:v1 / v2
├── stack/          (lo aggiunge lo script 05)     → lo stack della sezione 4
└── argocd/         application.yaml, stack-web.yaml
```

Lo script 02 lo copia in `lavoro/argocd/mio-progetto` e ne fa un repository git: **i commit li fai lì**.

| Script | Cosa fa |
|---|---|
| `argocd/01-installa-argocd.sh` | namespace, manifest ufficiale `stable`, password di admin, CLI `argocd` in `~/.local/bin`, port-forward 8083 in background, login |
| `argocd/02-git-locale.sh` | Gitea nel cluster (NodePort 30300), utente `wilson`, primo commit e push |
| `argocd/03-terraform-e-sito.sh` | build di `mio-sito:v1` e caricamento nei nodi, ingress, `terraform init/plan/apply` |
| `argocd/04-gitops.sh` | l'Application, il self-heal, v2 con un commit, rollback con `git revert`, `prune: false`, la quota di Terraform che vale anche per Argo |
| `argocd/05-stack-con-argocd.sh` | facoltativo: lo stack HAProxy/nginx/PHP/Redis/MariaDB passa sotto Argo CD (con `prune: true`) |
| `argocd/99-pulizia.sh` | toglie Application, sito, stack, Gitea e Argo CD |

Accanto a ogni script c'è la sua **spiegazione** (`argocd/NN-nome.md`), e così anche per `comune.sh` e `gitea.yaml`.
Ogni spiegazione contiene:
- i passi uno per uno: cosa vedi, quali falliscono apposta, cosa resta in rosso e perché;
- i file di `mio-progetto/` che lo script usa: Application, Deployment, Terraform, Dockerfile;
- le trappole e, per gli script 01–05 e `gitea.yaml`, tre esercizi.

```bash
bash argocd/01-installa-argocd.sh     # poi 02, 03, 04 in ordine; 05 facoltativo
```

- **UI di Argo CD**: `https://192.168.1.79:8083` dal Mac, oppure `https://localhost:8083`
  sull'Ubuntu. Utente `admin`, la password la stampa lo script 01.
- **UI di Gitea**: `http://192.168.49.2:30300`, solo dall'Ubuntu. Utente `wilson`, password in
  `lavoro/argocd/.gitea-pass`.
- Dopo un `git push`, Argo controlla git ogni 2–3 minuti (120 s + fino a 60 s di jitter); `argocd app get mio-sito --refresh` lo fa subito.
- Dopo un riavvio del PC il port-forward non c'è più: lo riaccendono da soli gli script 04 e 05,
  oppure rilancia il passo 9 dello script 01 (`DA=9 bash argocd/01-installa-argocd.sh`).

---

## 7. Dove finiscono i file

| Cartella | Contenuto |
|---|---|
| `kubernetes/`, `terraform/`, `stack/`, `argocd/` | gli script da lanciare (`argocd/` contiene anche `gitea.yaml` e il modello `mio-progetto/`) |
| `lib/passo.sh` | le funzioni comuni (il passo guidato, il controllo del contesto `lab`) |
| `kubernetes/README.md` | l'indice degli script Kubernetes: cosa impari, da cosa dipende, link alla spiegazione |
| `terraform/*.md` | la spiegazione di ogni script Terraform & Ansible (00–10), accanto allo script |
| `argocd/*.md` | la spiegazione di ogni script di Argo CD (01–05, 99), di `comune.sh` e di `gitea.yaml` |
| `lezioni/` | copia dei file delle lezioni (manifest, `.tf`, playbook): **leggili** mentre lo script li applica |
| `lezioni/kubernetes/*.md` | la spiegazione di ogni lezione Kubernetes (01–20): cosa fa il file, passo per passo lo script guidato, trappole, esercizi |
| `site/` | il sito didattico (Node in Docker): sorgenti in `site/content/`, build in `site/dist/` (non in git); vedi `site/README.md` |
| `lavoro/` | la creano gli script: chart Helm, overlay Kustomize, progetti Terraform con il loro state, inventari Ansible. Puoi cancellarla quando vuoi |

Per rifare una lezione Terraform da zero, cancella la sua cartella dopo il destroy,
per esempio `rm -rf lavoro/iac/01`.

---

## 8. Spegnere tutto e tornare a un PC pulito

| Cosa | Comando |
|---|---|
| fermare il cluster senza perderlo | `minikube -p lab stop` (per riaccenderlo: `minikube -p lab start`) |
| cancellare il cluster | `minikube delete --all --purge` |
| fermare MicroK8s | `sudo microk8s stop` |
| disinstallare MicroK8s | `sudo snap remove microk8s --purge` |
| togliere i server Ansible | `docker rm -f web1 web2 db1` |
| togliere registry, state Postgres e container della lezione 03 | `docker rm -f registry tfstate vecchio-redis` |
| togliere Argo CD, Gitea, il sito e lo stack sotto Argo | `bash argocd/99-pulizia.sh` |
| togliere i file di lavoro | `rm -rf ~/kubernetesprj/lavoro ~/.vault_pass` |

Controllo finale che non sia rimasto niente:

```bash
docker ps -a                     # solo i tuoi container (portainer, …)
minikube profile list            # nessun profilo
kubectl config get-contexts      # vuoto, o errore perché non c'è una config
```

---

## 9. Quando qualcosa non va

| Sintomo | Causa probabile | Cosa fare |
|---|---|---|
| `STOP: kubectl punta a "…", non a "lab"` | il cluster è spento, è stato cancellato, o il contesto attivo è un altro | `minikube -p lab start`, oppure rilancia la 01 |
| `kubectl top` o l'HPA dicono "metrics not available" | il metrics-server non ha ancora le metriche dei Pod nuovi | aspetta un minuto (lo script aspetta da solo) |
| Pod in `Pending` | risorse finite, o PVC non collegato a un volume | `kubectl describe pod <nome>` e guarda la sezione Events in fondo |
| Pod in `ImagePullBackOff` | tag sbagliato o problema di rete | `kubectl describe pod <nome>` e leggi il messaggio del pull |
| `port-forward` dice "address already in use" | un port-forward precedente è ancora acceso | `pkill -f "kubectl.*port-forward"` |
| Alert `TargetDown` o `etcd…` attivi nella lezione 13 | normale su minikube: etcd, scheduler e controller-manager ascoltano solo su 127.0.0.1 del nodo | ignorali e guarda gli alert `App…` |
| `ansible: command not found` | `~/.local/bin` non è nel PATH | terminale nuovo, oppure `export PATH="$HOME/.local/bin:$PATH"` |
| `terraform apply` dice "port is already allocated" | è ancora acceso un container di una prova precedente | `docker ps`, poi `terraform destroy` nella cartella in `lavoro/` |
| `microk8s` dice "insufficient permissions" | in questa sessione non sei ancora nel gruppo microk8s | `newgrp microk8s`, oppure esci e rientra |

Gli script sono stati provati per intero su questo PC il 30 ottobre 2026: Kubernetes 01–14
e lo stack su minikube, Terraform e Ansible 01–10. Non sono ancora stati provati qui la
lezione 15, lo stack su MicroK8s e l'installazione con apt della 00.

---

## 10. Il progetto vero: il Biodistretto su minikube

Ogni file in `lezioni/` ha in fondo all'intestazione un riquadro **«NEL PROGETTO VERO»**.
Il riquadro mostra dove lo stesso concetto compare in `~/biodistretto/kubernetes` (branch
`kubernetes`): lo stack docker del Biodistretto portato su un minikube a 2 nodi, con Terraform,
Ansible e HAProxy. Contiene il fatto, il perché e un `grep` da lanciare in quella cartella.
In molti c'è anche un esercizio sul cluster vero.

| Dove guardare | Cosa c'è nel progetto |
|---|---|
| Kubernetes 02, 04, 11 | probe per tipo di processo, ConfigMap da file, checksum nell'annotazione per far ripartire i Pod |
| Kubernetes 03, 15, 19 | NodePort con `externalTrafficPolicy: Local`, HAProxy fuori dal cluster con PROXY protocol, `hostAliases` verso un ClusterIP fisso |
| Kubernetes 05, 06 | quattro StatefulSet su `csi-hostpath-sc` (lo `standard` non regge con 2 nodi), `topologySpreadConstraints` |
| Kubernetes 08, 20 | guasti veri: due CNI accesi, `kubectl cp` senza tar, kubelet spento dopo il riavvio; STRIDE sulle cose trovate |
| Terraform 02, 03, 04 | `for_each` con chiavi note al plan, `terraform_remote_state`, perché due root e non due moduli |
| Terraform 07–10 | `validate` e handler, `block`/`always`, Ansible che lancia Terraform, piani in `/tmp` con dentro i segreti |

Per accenderlo (circa 10 minuti da zero, usa 2 nodi da 2 CPU e 3,5 GB: meglio con il cluster
`lab` spento):

```bash
cd ~/biodistretto/kubernetes && ./deploy.sh          # il secondo giro deve dare changed=0
kubectl --context biodistretto -n biodistretto get pods -o wide
./deploy.sh distruggi                                # toglie cluster, HAProxy e la riga @reboot
```

I `grep` dei riquadri sono stati controllati uno per uno sui file del commit `3c5a481`.

Sul sito la **lezione 24** mette insieme il progetto: il README come spiegazione, 37 file
(Ansible, i due stack Terraform, i manifest, nginx, Docker), i comandi del README e un quiz. Lo
state di Terraform, i piani, `docker/.env`, `.cache/` e il certificato restano fuori, e
l'indirizzo del laboratorio è sostituito da `IP-DEL-LAB`. Per riallinearla dopo un cambio nel
progetto: `npm run importa:progetto` nel container (vedi `site/README.md`).
