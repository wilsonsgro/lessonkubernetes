# Corso Kubernetes completo — Lezioni 01–09 e 21 (HAProxy)

> **Documento unico per lo studio e per la generazione di un sito didattico mediante Codex/OpenClaw o Claude Code.**
>
> Lingua: italiano. Provenienza: file originali caricati dall'utente, più riflessioni didattiche riorganizzate a partire dal percorso di spiegazione svolto in chat.
>
> **Priorità formativa:** capire a fondo Kubernetes 01–09 e, in particolare, **sapere HAProxy** nella Lezione 21.

## Come usare questo file

Questo Markdown è progettato per essere **autosufficiente**: contiene una guida al corso, riflessioni e collegamenti concettuali, indicazioni per il sito, e infine per ogni lezione la trascrizione integrale dei sorgenti caricati (`.md`, `.yaml`, `.sh`). Non richiede ai tool di coding di accedere alla chat originale o di ricostruire comandi da screenshot.

**Legenda della provenienza**
- **Appunti e riflessioni didattiche**: sintesi e collegamenti riformulati per rendere più chiaro il percorso. Non sono trascrizioni parola per parola di tutti i messaggi della chat.
- **Fonte originale — testo Markdown**: contenuto completo e immutato del `.md` della lezione.
- **Fonte originale — manifest e script**: contenuto completo e immutato degli altri file caricati.

**Importante:** le misurazioni riportate nei file sono risultati del laboratorio di origine, **non** verifiche live compiute su questo cluster durante la preparazione del documento. I file possono far riferimento a versioni software del loro contesto temporale. Prima di eseguire i comandi su un sistema differente, verificare versione, contesto, sicurezza e risorse disponibili. Il codice di una lezione può eliminare namespace, provocare guasti intenzionali o creare cluster separati.

## Indice delle lezioni

1. **01 — Architettura e laboratorio:** spec/status, API server, etcd, scheduler, kubelet, kube-proxy, CNI, Minikube.
2. **02 — Deployment:** ReplicaSet, rollout, readiness/liveness/startup, risorse, shutdown, sicurezza.
3. **03 — Rete:** Service, DNS, Ingress, EndpointSlice e NetworkPolicy.
4. **04 — Configurazione:** ConfigMap, Secret, env, volumi, checksum e rollout.
5. **05 — Stato e storage:** StatefulSet, PVC/PV/StorageClass, PDB, drain.
6. **06 — Scheduling e autoscaling:** affinity, taint, priority, spread, HPA.
7. **07 — Sicurezza:** ServiceAccount, RBAC, PSA restricted e securityContext.
8. **08 — Troubleshooting:** stato, eventi, log, exec/debug e cinque guasti.
9. **09 — Helm:** Chart, release, template, install, upgrade e rollback.
10. **21 — HAProxy:** reverse proxy, Ingress Controller, NodePort, routing, algoritmo di bilanciamento, Runtime API, rate limit e alta disponibilità.

> La numerazione **21** è intenzionale: si preserva la numerazione del corso originale. Le lezioni 10–20 non sono incluse né inventate. Nel sito rendere la 21 accessibile direttamente dopo la 09 come approfondimento speciale, mantenendo l'etichetta «21».

## Mappa dei collegamenti che il sito deve rendere evidenti

| Concetto di origine | Ritorna in | Perché è importante |
|---|---|---|
| Riconciliazione (01) | 02, 04, 09, 21 | Controller e tool non eseguono «magia»: osservano e correggono lo stato |
| Requests e limiti (02) | 05, 06, 08, 21 | Scheduling, HPA, OOM e dimensionamento dipendono dalle risorse dichiarate |
| Readiness (02) | 03, 05, 08, 21 | Un Pod Running non è necessariamente un endpoint utilizzabile |
| EndpointSlice e Service (03) | 08, 21 | HAProxy legge le destinazioni concrete e usa i Pod IP |
| ConfigMap e env (04) | 09 | Il checksum nel template innesca rollout coerenti con nuove configurazioni |
| PVC e PDB (05) | 06, 08 | Persistenza, scheduling, disruption e guasti dei nodi sono collegati |
| Scheduler (06) | 05, 21 | Anti-affinity e nodeAffinity spiegano dove finiscono i Pod HAProxy |
| RBAC e PSA (07) | 09, 21 | Chi può leggere i Secret Helm e quali privilegi hanno i controller |
| Diagnostica (08) | 09, 21 | ImagePullBackOff, endpoint vuoti e controller non Ready vanno provati, non supposti |
| Helm (09) | 21 | Il controller HAProxy è installato/configurato tramite un Chart Helm |

---

# SPECIFICA PER L'AGENTE CHE COSTRUIRÀ IL SITO

## Obiettivo del prodotto

Crea un **sito didattico in italiano**, consultabile da browser desktop e mobile, che permetta di studiare tutte le lezioni **01–09 e 21**. Deve funzionare come manuale interattivo, non come semplice pagina con un Markdown molto lungo. Il sito deve mantenere accessibili **tutti i dettagli tecnici**, i file originali e le riflessioni, con una navigazione che aiuti lo studente ad apprendere progressivamente. La **Lezione 21 deve avere una sezione HAProxy particolarmente ricca**.

## Requisiti funzionali obbligatori

1. **Indice/curriculum**: home con percorso 01→09 e una sezione speciale 21 HAProxy; progress bar e stato di completamento per lezione.
2. **Pagine di lezione**: obiettivi, prerequisiti, spiegazione progressiva, modello mentale, diagramma, blocchi YAML/Bash, note «perché», trappole, collegamenti alle lezioni precedenti, verifica finale.
3. **Tre livelli di lettura** per ogni lezione: `Spiegazione`, `Sorgenti originali`, `Laboratorio`. Non nascondere le fonti; consentire di consultare e copiare gli script per intero.
4. **Codice**: syntax highlighting per `yaml`, `bash`, `json`, `haproxy`, comandi `kubectl` e Helm; pulsante copia; attenzione a non eseguire automaticamente comandi che modificano cluster o cancellano risorse.
5. **Diagrammi didattici**: chiari, accessibili e responsivi. Suggeriti Mermaid/SVG/HTML/CSS per rendere facilmente modificabili la catena di riconciliazione, gli endpoint, la persistenza, il calcolo HPA e il percorso HAProxy. I diagrammi devono corrispondere agli esempi dei file, senza inventare indirizzi o stati reali.
6. **Quiz e autoverifica**: almeno 5–8 domande a scelta multipla per lezione, tratte dagli argomenti e dagli esercizi originali; spiegazione dopo la risposta; punteggio e possibilità di riprovare. Distinguere domande didattiche da verifiche realmente eseguite nel cluster.
7. **Flashcard interne opzionali**: domanda/risposta sui concetti principali, ricavabili dagli esercizi e dalle domande da colloquio; non sostituire il contenuto integrale delle lezioni.
8. **Simulazioni locali** (nessun accesso cluster richiesto): calcolo HPA, valutazione RBAC elementare, confronto NetworkPolicy OR/AND, partition StatefulSet, sequenza dei rollout Helm, roundrobin/leastconn e budget rate limit per repliche HAProxy.
9. **Glossario** ricercabile: Pod, ReplicaSet, readiness, EndpointSlice, PVC, RoleBinding, taint, Chart, frontend, backend, NodePort, Runtime API, stick-table.
10. **Ricerca full-text** tra lezioni, riflessioni, manifest e blocchi sorgente.
11. **Collegamenti contestuali**: per esempio «checksum/config» deve linkare alle lezioni 04 e 09; «EndpointSlice» alle 03, 08 e 21.
12. **Tracciamento locale**: progressi, note dello studente, preferiti e quiz tramite storage locale del browser; nessuna autenticazione o backend obbligatorio per la prima versione.
13. **Accessibilità**: navigazione da tastiera, contrasto leggibile, layout responsive, `aria-label` dei controlli, niente diagrammi che dipendono esclusivamente dal colore.
14. **Esportazione**: stampa/PDF per le singole lezioni e download delle fonti in testo; se il sito usa un database o formato JSON, includere uno script deterministico di importazione da questo Markdown.
15. **Fedeltà alle fonti**: non sostituire i blocchi originali con esempi generici e non cambiare manifest o comandi senza segnalarlo. Se ci sono esempi illustrative o precisazioni editoriali, etichettarli chiaramente.

## Progetto UI consigliato (non vincolante)

- Sidebar sinistra: percorso delle lezioni, HAProxy evidenziato come «Approfondimento».
- Barra superiore: ricerca, progresso, tema chiaro/scuro, accesso al glossario.
- Corpo: spiegazione principale con titoli brevi, tabelle, codeblock copiabili, diagrammi interattivi.
- Pannello destro (desktop): indice della pagina, collegamenti trasversali e riferimenti ai file.
- Fondo lezione: esercizi guidati, quiz, «spiega con parole tue», riferimenti alla prossima lezione.
- Su mobile, sidebar a scomparsa e diagrammi ridisposti in verticale.

## Approfondimento HAProxy: sezioni richieste

Il sito deve dedicare un'esperienza forte alla Lezione 21, strutturata in questi capitoli: **(1) che cos'è un reverse proxy; (2) frontend, backend, server; (3) HAProxy esterno versus Ingress interno; (4) NodePort del controller versus Ingress delle applicazioni; (5) due repliche e High Availability; (6) route host/path e path-rewrite; (7) roundrobin versus leastconn; (8) EndpointsSlice → haproxy.cfg; (9) Runtime API e add/del server senza reload; (10) stick-table e rate limiting per replica; (11) statistiche; (12) troubleshooting e vincoli di Minikube**.

**Diagramma indispensabile:** `Client → IP_nodo:30080 → Service NodePort HAProxy → HAProxy A o B → frontend Host/path → backend → Pod IP blu/verde`. Specificare visivamente che `controller.service.nodePorts` **espone HAProxy**, mentre gli oggetti `Ingress` **decidono l'instradamento applicativo**. Evidenziare che la disponibilità di due repliche non implica stato condiviso del rate limit.

**Simulazione indispensabile:** un utente può cliccare «Guasto HAProxy A» e vedere le nuove connessioni passare a B (dopo la propagazione della readiness), e cliccare «12 richieste con limit 5/10 s» per osservare come due contatori locali possano autorizzare più di cinque richieste complessive. Dichiarare che sono simulazioni concettuali, non misure del cluster reale.

## Regole di sicurezza per il sito e per l'agente

- **Non** eseguire automaticamente `kubectl`, `helm`, `minikube`, `docker`, `ssh`, script Bash o comandi che modificano risorse dell'utente soltanto perché sono presenti nei materiali.
- I comandi sono **esempi didattici** copiabili: usare etichette di attenzione per `delete`, `drain`, `--force`, `kubectl taint`, `rollout restart`, `helm uninstall` e creazione di guasti intenzionali.
- **Non** incorporare password, token, chiavi SSH, IP privati identificativi o altri segreti reali in pagine pubbliche. Gli IP del testo originale sono esempi o dati di contesto: non usarli come configurazione valida per altri ambienti.
- Le dipendenze dal filesystem originale (`~/kubernetesprj`, `~/biodistretto`) sono **riferimenti delle fonti**, non percorsi garantiti nel runtime del sito. Il sito deve funzionare senza quei repository.
- Verificare le funzionalità dell'app in locale. Non affermare di aver eseguito le prove Kubernetes senza che siano state realmente eseguite.

## Criteri di accettazione

- Tutte le dieci lezioni sono raggiungibili dalla home nell'ordine corretto: 01,02,03,04,05,06,07,08,09,21.
- Ogni lezione possiede una spiegazione leggibile, esempi esatti, almeno cinque domande a risposta verificabile e i sorgenti originali consultabili.
- Le pagine funzionano offline/dopo una build statica, senza bisogno di un cluster Kubernetes.
- Il glossario, i link trasversali, i blocchi copia, il salvataggio del progresso e la ricerca funzionano.
- La Lezione 21 distingue correttamente **replica HAProxy**, **NodePort**, **Ingress**, **Service applicativo** e **Pod IP**.
- Nessun comando di laboratorio viene eseguito senza una richiesta esplicita dell'utente.
- Un README del progetto generato spiega come installare dipendenze, avviare il server locale, eseguire build e test, e come vengono importate le fonti.

---

# APPUNTI DIDATTICI DEL CORSO E FONTI ORIGINALI

Le sezioni seguenti sono pensate sia per essere lette direttamente, sia per essere importate nel sito. **Gli appunti precedono le fonti originali di ogni lezione**. Nel sito possono diventare la vista «Spiegazione», mentre i blocchi sorgente diventano la vista «Materiale originale».

---

<a id="lezione-01"></a>

# Lezione 01 — Architettura Kubernetes e laboratorio Minikube

## Spiegazione e riflessioni ragionate

### Modello mentale del professore
Kubernetes **non è un comando che esegue container**: è un insieme di cicli di riconciliazione. Tu dichiari una `spec`, i controller osservano lo `status` e tentano di far coincidere lo stato reale con quello desiderato. Il `kube-apiserver` è il punto d'ingresso, `etcd` conserva lo stato, scheduler e controller decidono gli interventi, il kubelet rende effettiva la configurazione sul proprio nodo. Se impari il tragitto di una richiesta `kubectl apply`, saprai localizzare i guasti nelle lezioni successive.

### Catena causa-effetto
`kubectl apply` → autenticazione / autorizzazione / admission → API object in etcd → Deployment controller crea ReplicaSet → ReplicaSet crea Pod → scheduler sceglie nodo → kubelet e runtime avviano container → CNI configura rete → kubelet riferisce condizioni. Una modifica a un YAML **non equivale** a un'operazione istantanea sul runtime: scatena una riconciliazione asincrona.

### Riflessioni e trabocchetti
- Control plane e worker sono ruoli, non sinonimi di macchine fisiche dedicate. Il profilo `lab` ha un control plane e un worker, gestiti come nodi Minikube con driver Docker e Calico.
- La CPU/memoria mostrate da Kubernetes dipendono dalla capacità pubblicata dai nodi e dal driver; il limite di un container Docker del nodo e l'`Allocatable` Kubernetes possono differire in modi sorprendenti.
- `etcd` richiede quorum per il consenso: tre membri tollerano il guasto di uno; cinque, il guasto di due. Un numero pari non dà automaticamente un vantaggio di quorum.
- Pod IP, Node IP e ClusterIP descrivono destinazioni diverse; il `ClusterIP` è una funzione di forwarding del dataplane, non un server virtuale autonomo.
- Con CNI Calico il networking dei Pod e l'enforcement delle NetworkPolicy non sono compiti di kube-proxy.

### Ragionamento guidato
**Domanda:** se un Deployment dichiara tre repliche ma ne trovi due, da dove cominci? **Risposta:** osserva Deployment, ReplicaSet e Pod; controlla eventi e scheduling. Non riavviare ciecamente il nodo: prima identifica quale anello della catena non sta convergendo.

### Verifica rapida
1. Spiega a voce `spec` versus `status` e perché un controller è un loop.
2. Descrivi nell'ordine cosa succede quando applichi un Deployment.
3. Distingui `kube-scheduler`, `kubelet`, `kube-proxy`, CNI e API server.
4. Spiega perché tre membri etcd sono più utili di due per la tolleranza ai guasti.

## Materiale originale della lezione


### Fonte originale: `01-architettura-e-lab.md`

> **Trascrizione integrale del file originale**, senza riscrittura. Questo blocco è una fonte di riferimento per il sito.

````markdown
# 01 — Architettura di Kubernetes e laboratorio su Ubuntu

Spiegazione di `01-architettura-e-lab.sh` (questa cartella). Lezione sul sito: http://127.0.0.1:3000/kubernetes/1

## In una frase

Lo script **crea il cluster minikube `lab`** (2 nodi, Calico, ingress, metrics-server), poi **lo esplora** e ti fa
vedere dal vivo l'idea su cui si regge tutto Kubernetes: **la riconciliazione**. Tu dichiari lo stato che vuoi,
i controller lo confrontano di continuo con quello reale e correggono la differenza.

## Due file con lo stesso nome: quale lanciare

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/lezioni/kubernetes/01-architettura-e-lab.sh` | **questo**: la lezione, con le spiegazioni nei commenti | `bash 01-architettura-e-lab.sh crea` · `esplora` · `spegni` |
| `~/kubernetesprj/kubernetes/01-architettura-e-lab.sh` | lo script **guidato**: fa gli stessi comandi, uno per volta, spiegando prima di eseguire (Invio / s / q) | `bash kubernetes/01-architettura-e-lab.sh` |

Per imparare conviene lo **guidato**. Questo file va **letto** mentre lo guidato gira: i commenti spiegano il perché.

## Com'è fatto il file

```
intestazione (commenti)  → la teoria: control plane, nodo, cosa succede con kubectl apply
set -euo pipefail        → lo script si ferma al primo errore
guardia_contesto()       → controlla che kubectl punti a "lab"
crea_cluster()           → minikube start + addon
esplora()                → giro guidato nel cluster + prova di auto-riparazione
spegni()                 → minikube stop
case "$1"                → sceglie la funzione dall'argomento: crea | esplora | spegni
coda (commenti)          → comandi kubectl da colloquio, domande da colloquio, riepilogo
```

`set -euo pipefail` vuol dire: `-e` esci se un comando fallisce, `-u` errore se usi una variabile non definita,
`-o pipefail` una pipe fallisce se fallisce uno qualunque dei suoi comandi (non solo l'ultimo).

---

## 1. La teoria nell'intestazione

### Control plane (il "cervello")

| Componente | Cosa fa |
|---|---|
| **kube-apiserver** | l'**unica porta d'ingresso**. Ogni richiesta (tua, dei controller, del kubelet) passa da qui: autenticazione → autorizzazione (RBAC) → admission controller → scrittura in etcd. Non ha stato, quindi se ne possono mettere più copie dietro un load balancer |
| **etcd** | il database chiave-valore dove vive **tutto** lo stato del cluster. Usa il consenso Raft: serve una maggioranza (quorum). Backup: `etcdctl snapshot save` |
| **kube-scheduler** | sceglie **su quale nodo** mettere un Pod che non ce l'ha: prima scarta i nodi che non vanno (risorse, taint, affinity), poi dà un punteggio agli altri, poi assegna (bind) |
| **controller-manager** | contiene i **loop di controllo**: Deployment → ReplicaSet → Pod, Node, Job, EndpointSlice, token dei ServiceAccount… |

### Il quorum di etcd

Quorum = `floor(N/2) + 1`.

| Membri etcd | Quorum | Guasti tollerati |
|---|---|---|
| 1 | 1 | 0 |
| 3 | 2 | 1 |
| 4 | 3 | 1 ← come con 3, ma le scritture sono più lente |
| 5 | 3 | 2 |

Per questo si usano **3 o 5** membri, mai un numero pari.

### Nodo (dove girano i container)

| Componente | Cosa fa |
|---|---|
| **kubelet** | l'agente su ogni nodo: legge i Pod assegnati **al suo nodo**, li fa partire tramite il runtime (containerd / CRI-O, attraverso l'interfaccia CRI), esegue le probe, riporta lo stato. Non si occupa dei Pod degli altri nodi |
| **kube-proxy** | traduce i Service in regole di rete (iptables / IPVS / nftables). Con Cilium può mancare: usa eBPF |
| **CNI** | il plugin di rete: dà un IP a ogni Pod. Modello "piatto": ogni Pod parla con ogni altro Pod senza NAT. **Le NetworkPolicy le applica il CNI** (Calico, Cilium), non Kubernetes |

### Cosa succede con `kubectl apply -f deploy.yaml`

1. `kubectl` manda la richiesta all'apiserver, che fa authn → authz → mutating admission → validazione dello schema →
   validating admission → scrittura in etcd.
2. Il **Deployment controller** vede l'oggetto nuovo e crea un **ReplicaSet**.
3. Il **ReplicaSet controller** crea N **Pod**, ancora senza nodo.
4. Lo **scheduler** assegna un nodo a ogni Pod.
5. Il **kubelet** di quel nodo vede il Pod e, tramite CRI, scarica l'immagine e avvia i container.
6. Il **CNI** dà l'IP. Quando la readiness probe passa, il Pod entra negli **EndpointSlice** e riceve traffico.

Il punto chiave: **nessuno chiama il componente successivo**. Ognuno osserva l'apiserver (watch) e reagisce. Per
questo, se qualcosa si rompe, il sistema si ripara da solo.

### Riquadro «NEL PROGETTO VERO»

Indica dove lo stesso concetto compare in `~/biodistretto/kubernetes`. Lì il cluster non nasce da `minikube start` ma
da una risorsa Terraform (`minikube_cluster`), con 2 nodi e CNI **kindnet** invece di Calico. Gli addon
(metrics-server, csi-hostpath-driver) sono una variabile Terraform. I `grep` del riquadro ti portano alle righe giuste.

---

## 2. `guardia_contesto()` — non sbagliare cluster

```bash
attuale="$(kubectl config current-context)"
if [[ "$attuale" != "lab" ]]; then echo "STOP…"; exit 1; fi
```

`kubectl` manda i comandi al **contesto** attivo. Sul tuo Ubuntu potrebbe essere un cluster GKE vero: un `apply` o un
`delete` nel posto sbagliato fa danni. Questa funzione blocca lo script se il contesto non è `lab`. Tutti gli script
delle lezioni successive fanno lo stesso controllo (`lib/passo.sh`).

Controllo a mano: `kubectl config current-context` → deve dire `lab`.

---

## 3. `crea` — `crea_cluster()`

```bash
minikube start -p lab --driver=docker --nodes=2 --cpus=2 --memory=4g --cni=calico
minikube -p lab addons enable ingress
minikube -p lab addons enable metrics-server
kubectl config use-context lab
```

| Opzione | Perché |
|---|---|
| `-p lab` | profilo dedicato: il cluster si chiama `lab` e anche il contesto kubectl si chiama `lab` |
| `--driver=docker` | ogni **nodo è un container Docker** (`lab`, `lab-m02`), non una VM |
| `--nodes=2` | servono due nodi per vedere affinity e distribuzione dei Pod (lezione 06) e il drain (lezione 05) |
| `--cpus=2 --memory=4g` | risorse per nodo (ma leggi la trappola sotto) |
| `--cni=calico` | il CNI di default di minikube **non applica le NetworkPolicy**: Calico sì (lezione 03) |
| addon `ingress` | installa il controller ingress-nginx (lezione 03) |
| addon `metrics-server` | abilita `kubectl top` e l'autoscaling HPA (lezione 06) |

Senza `--kubernetes-version`, minikube usa la versione che supporta meglio.

### La trappola delle risorse con il driver docker

- `--memory=4g` diventa un **limite reale** del cgroup del container-nodo: oltre i 4 GiB il kernel lo uccide.
- `--cpus=2` **non viene applicato**: `cpu.max` resta `max`.
- Il kubelet dichiara come Capacity **tutto il PC** (12 CPU, circa 16 GiB per nodo). Lo scheduler conta su risorse che
  il container non ha, e le percentuali di `kubectl top` sono calcolate su quella Capacity.

Comandi per vederlo:

```bash
kubectl get nodes -o custom-columns=NOME:.metadata.name,CPU:.status.capacity.cpu,MEM:.status.allocatable.memory
docker exec lab cat /sys/fs/cgroup/memory.max /sys/fs/cgroup/cpu.max
```

Per sapere quanto manca al limite **non basta `memory.current`**: comprende la cache dei file, che il kernel recupera.
Contano la memoria netta (totale meno `active_file` e `inactive_file`) e il contatore `oom_kill`:

```bash
docker exec lab grep -E '^(active|inactive)_file ' /sys/fs/cgroup/memory.stat
docker exec lab grep oom_kill /sys/fs/cgroup/memory.events
```

---

## 4. `esplora` — giro nel cluster

Prima chiama `guardia_contesto`, poi:

| Comando | Cosa vedi |
|---|---|
| `kubectl get nodes -o wide` | i due nodi, con IP, sistema operativo e runtime |
| `kubectl get pods -n kube-system -o wide` | il control plane: apiserver, etcd, scheduler, controller-manager, più CoreDNS, kube-proxy, Calico |
| `minikube -p lab ssh -- sudo ls /etc/kubernetes/manifests` | i file dei **Pod statici**: il kubelet avvia il control plane leggendo questa cartella **dentro il nodo**, non dall'apiserver. Sull'host Ubuntu la cartella non esiste: il nodo è un container |
| `kubectl api-resources \| head -30` | i tipi di oggetto che l'apiserver conosce: nome corto, gruppo API, se stanno in un namespace |
| `kubectl explain deployment.spec.strategy.rollingUpdate` | la documentazione di un campo, presa dallo schema del cluster |

### La riconciliazione dal vivo

```bash
kubectl create deployment eco --image=traefik/whoami:v1.12 --replicas=2
kubectl rollout status deployment/eco
kubectl get pods -l app=eco -w &          # osserva in background
kubectl delete pod -l app=eco --wait=false
sleep 10; kill "$osservatore"
kubectl get events --sort-by=.metadata.creationTimestamp | tail -12
```

1. Crea un Deployment `eco` con 2 repliche (in modo imperativo: in produzione si usa lo YAML).
2. Aspetta che le repliche siano pronte.
3. Avvia un `get -w` (watch) in background, poi **cancella i Pod**.
4. Nel watch vedi i Pod vecchi andare in `Terminating` e **due Pod nuovi** nascere: il ReplicaSet vuole 2 repliche,
   ne vede 0 e le ricrea. Nessuno gliel'ha chiesto.
5. Gli **eventi** raccontano il perché: `SuccessfulCreate` del ReplicaSet, `Scheduled`, `Pulled`, `Started`.

`kill "$osservatore"` ferma solo il watch, non i Pod.

Lo script guidato fa notare che i Pod cancellati passano da `Terminating` a `Error`: whoami esce con codice 2 quando
riceve il SIGTERM. Non è un guasto: conta che i due Pod nuovi arrivino a `Running`.

### I tre tipi di IP

```bash
kubectl expose deployment eco --port=80
kubectl get nodes,pods,svc -o wide
```

| IP | Rete | Di chi è |
|---|---|---|
| **del nodo** | 192.168.49.x (rete Docker di minikube) | del container-nodo |
| **del Pod** | 10.244.x (Calico) | del Pod, cambia quando il Pod viene ricreato |
| **del Service** (ClusterIP) | 10.96.0.0/12, cioè da 10.96 a 10.111 | **virtuale**: nessuna scheda di rete lo possiede, lo traducono le regole di kube-proxy. Resta stabile anche quando i Pod cambiano |

### Due trappole

- `kubectl get pods -A`: **senza `-n` guardi solo il namespace corrente** (`default`). «No resources found» non vuol
  dire che il cluster è vuoto.
- `kubectl -n kube-system get pod -l component=etcd`: c'è **un solo membro etcd**. Due nodi Kubernetes non vogliono
  dire due copie del database: qui il quorum tollera 0 guasti.

Alla fine `kubectl delete deployment,service eco` toglie tutto quello che la prova ha creato.

---

## 5. `spegni`

```bash
minikube -p lab stop       # ferma il cluster e conserva lo stato
# minikube delete -p lab   # (commentato) lo cancellerebbe del tutto
```

Per riaccenderlo: `minikube -p lab start`.

---

## 6. Lo script guidato `~/kubernetesprj/kubernetes/01-architettura-e-lab.sh`, passo per passo

Fa le stesse cose di `crea` + `esplora`, in 25 passi, con qualche misura in più che la lezione non ha: le risorse
vere del container-nodo, la memoria netta, `kubectl top`. Non fa `spegni`: alla fine stampa i comandi per farlo.

| Passo | Comando | Cosa vedi / perché |
|---|---|---|
| 1 | `kubectl version --client; minikube version` | le versioni dei due client: kubectl parla con l'apiserver, minikube crea il cluster |
| 2 | `kubectl config get-contexts` | i contesti noti a kubectl: il contesto dice **a quale cluster** arrivano i comandi |
| 3 | `minikube start -p lab --driver=docker --nodes=2 --cpus=2 --memory=4g --cni=calico` | crea il cluster (qualche minuto). Le opzioni sono spiegate nella sezione 3 |
| 4 | `minikube -p lab addons enable ingress` | il controller ingress-nginx (lezione 03) |
| 5 | `minikube -p lab addons enable metrics-server` | `kubectl top` e l'HPA (lezione 06) |
| 6 | `kubectl config use-context lab` | da qui in poi tutti gli script controllano che il contesto sia `lab` |
| 7 | `kubectl get nodes -o wide` | `lab` è il control plane, `lab-m02` il worker; IP, sistema operativo, runtime |
| 8 | `kubectl get pods -n kube-system -o wide` | il control plane come Pod: apiserver, etcd, scheduler, controller-manager, più CoreDNS, kube-proxy, Calico |
| 9 | `minikube -p lab ssh -- sudo ls /etc/kubernetes/manifests` | i file dei **Pod statici**, letti dal kubelet dentro il nodo |
| 10 | `ls /etc/kubernetes/manifests` | **fallisce apposta (uscita 2)**: sull'host Ubuntu la cartella non c'è, il nodo è un container con il suo filesystem |
| 11 | `kubectl -n kube-system get pod -l component=etcd -o wide` | un solo membro, `etcd-lab`, sul control plane |
| nota | — | quorum = floor(N/2)+1: 1 membro → 0 guasti tollerati · 3 → 1 · 4 → 1 · 5 → 2. Per questo 3 o 5, su macchine diverse |
| 12 | `kubectl get nodes -o custom-columns=…capacity…allocatable…` | quello che **Kubernetes crede** di avere: Capacity e Allocatable di ogni nodo |
| 13 | `docker exec lab cat /sys/fs/cgroup/memory.max /sys/fs/cgroup/cpu.max; docker exec lab nproc` | quello che il container-nodo **ha davvero**: `memory.max` = 4 GiB, `cpu.max` = `max` (il `--cpus=2` non è applicato), `nproc` vede tutte le CPU |
| 14 | ciclo su `lab` e `lab-m02` con `memory.current`, `memory.stat`, `memory.events` | per ogni nodo: totale, cache, **netto** e percentuale del limite, più il contatore `oom_kill`. La cache dei file il kernel la recupera: conta il netto |
| 15 | attesa del metrics-server (fino a 30 × 5 s), poi `kubectl top nodes` | il consumo osservato, in percentuale della Capacity del passo 12 (tutto il PC), **non** di 2 CPU / 4 GiB |
| nota | — | con il driver docker lo scheduler conta su ~16 GiB per nodo, ma il kernel uccide il container-nodo a 4 GiB. In un cluster vero Capacity = la macchina |
| 16 | `kubectl api-resources \| head -30` | i tipi di oggetto: nome corto, gruppo API, namespaced o no |
| 17 | `kubectl explain deployment.spec.strategy.rollingUpdate` | la documentazione di un campo, dallo schema del cluster |
| 18 | `kubectl create deployment eco --image=traefik/whoami:v1.12 --replicas=2` | un Deployment creato in modo imperativo, solo per vedere la riconciliazione |
| 19 | `kubectl rollout status deployment/eco` | aspetta che le 2 repliche siano pronte |
| 20 | `kubectl get pods -l app=eco -w &` + `kubectl delete pod -l app=eco --wait=false`, 15 secondi | l'**auto-riparazione**: i Pod vecchi se ne vanno, il ReplicaSet ne crea due nuovi |
| nota | — | i Pod cancellati passano da `Terminating` a `Error`: whoami esce con codice 2 al SIGTERM (misurato). Non è un guasto: conta che i nuovi arrivino a `Running` |
| 21 | `kubectl get events --sort-by=.metadata.creationTimestamp \| tail -12` | il perché: `SuccessfulCreate` del ReplicaSet, `Scheduled`, `Pulled`, `Started` |
| 22 | `kubectl expose deployment eco --port=80 && kubectl get svc eco` | un Service davanti a eco |
| 23 | tre `kubectl get … -o custom-columns` (nodi, Pod, Service) | i **tre IP** in colonna: nodo 192.168.49.x, Pod 10.244.x, Service nella 10.96.0.0/12 |
| 24 | `kubectl get pods` e il conteggio di `kubectl get pods -A` | la trappola del namespace: senza `-n` vedi solo `default` (c'è eco, il control plane no) |
| 25 | `kubectl delete deployment,service eco` | pulizia della prova |
| nota | — | spegnere: `minikube -p lab stop` · riaccendere: `minikube -p lab start` · cancellare: `minikube -p lab delete` |

Per ripartire da un passo: `DA=12 bash kubernetes/01-architettura-e-lab.sh`. Per eseguire tutto senza fermarsi:
`AUTO=1 bash kubernetes/01-architettura-e-lab.sh`. Se il cluster esiste già, il passo 3 lo riaccende invece di crearlo.

---

## 7. La coda: kubectl e domande da colloquio

### Comandi da sapere a memoria

| Comando | A cosa serve |
|---|---|
| `kubectl get pod -A -o wide --field-selector=status.phase!=Running` | tutti i Pod che **non** sono Running |
| `kubectl get events -A --sort-by=.lastTimestamp` | gli ultimi eventi del cluster, in ordine |
| `kubectl describe pod X` | eventi del Pod: scheduling, pull dell'immagine, probe |
| `kubectl logs X -c app --previous` | i log del container **prima** del crash |
| `kubectl get deploy X -o yaml \| less` | spec + status + managedFields |
| `kubectl diff -f file.yaml` | cosa cambierebbe un apply, senza farlo |
| `kubectl apply --server-side -f …` | server-side apply: il server traccia chi possiede ogni campo |
| `kubectl auth can-i create pods --as=system:serviceaccount:lab:app` | che cosa può fare un'identità (lezione 07) |
| `kubectl get --raw '/readyz?verbose'` | lo stato di salute dell'apiserver |

### Domande

- **Perché etcd con 3 o 5 nodi e non 4?** Con 4 il quorum è 3: tolleri 1 guasto come con 3, ma le scritture sono più
  lente. I numeri dispari massimizzano i guasti tollerati.
- **Se cade l'apiserver, i Pod si fermano?** No. I kubelet continuano a far girare ciò che hanno. Si ferma il resto:
  niente nuovi scheduling, niente auto-riparazione, niente aggiornamento degli endpoint. Il data plane va avanti, il
  control plane è congelato.
- **Apply client-side o server-side?** Il client-side calcola il merge con l'annotazione `last-applied`. Il
  server-side (SSA) registra in `managedFields` il "proprietario" di ogni campo: se due strumenti scrivono lo stesso
  campo, ottieni un conflitto esplicito invece di una sovrascrittura silenziosa. Helm 4 e Argo CD lo usano di default.
- **Cosa fa un admission controller?** Intercetta la richiesta dopo l'autorizzazione e prima di etcd. Quelli
  *mutating* la modificano (iniettano un sidecar, mettono dei default), quelli *validating* la accettano o la
  rifiutano (Pod Security Admission, Kyverno/Gatekeeper, ValidatingAdmissionPolicy in CEL, nativa dalla 1.30).

---

## Riepilogo

- Kubernetes = **stato desiderato** + **controller che riconciliano** osservando l'apiserver (watch).
- L'apiserver è l'unica porta, etcd l'unica fonte di verità (con un numero dispari di membri).
- Il kubelet esegue, lo scheduler sceglie il nodo, il CNI dà la rete.
- Il lab: minikube, profilo `lab`, 2 nodi, Calico, ingress, metrics-server.
- **Prima di ogni apply: `kubectl config current-context`.**

## Prova da solo

1. `kubectl get pods -n kube-system -o wide`: su quale nodo gira etcd? E i Pod di Calico?
2. Ricrea `eco` con 3 repliche, cancellane **una** sola e guarda gli eventi: chi la ricrea?
3. `kubectl explain pod.spec.containers.readinessProbe`: quali campi ha? Li userai nella lezione 02.
````

### Fonte originale: `01-architettura-e-lab.sh`

> **Trascrizione integrale del file originale**, senza riscrittura. Questo blocco è una fonte di riferimento per il sito.

````bash
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
````

### Fonte originale: `01-architettura-e-lab(1).sh`

> **Trascrizione integrale del file originale**, senza riscrittura. Questo blocco è una fonte di riferimento per il sito.

````bash
#!/usr/bin/env bash
# Lezione 01 — crea il cluster minikube "lab" (2 nodi, Calico) e guarda come è fatto.
source "$(dirname "$0")/../lib/passo.sh"
titolo "01. Architettura di Kubernetes e laboratorio minikube"

passo "Versioni dei client: kubectl parla con l'apiserver, minikube crea il cluster" \
  'kubectl version --client; minikube version'
passo "Contesti noti a kubectl: il contesto dice A QUALE cluster arrivano i comandi" \
  'kubectl config get-contexts'
passo "Crea il cluster 'lab': driver docker (ogni nodo è un container), 2 nodi per affinity/spread, Calico perché il CNI di default non applica le NetworkPolicy. Ci mette qualche minuto" \
  'minikube start -p lab --driver=docker --nodes=2 --cpus=2 --memory=4g --cni=calico'
passo "Addon ingress: installa il controller ingress-nginx (serve alla lezione 03)" \
  'minikube -p lab addons enable ingress'
passo "Addon metrics-server: abilita 'kubectl top' e l'autoscaling HPA (lezione 06)" \
  'minikube -p lab addons enable metrics-server'
passo "Punta kubectl sul cluster nuovo: da qui in poi tutti gli script controllano che il contesto sia 'lab'" \
  'kubectl config use-context lab'
passo "I nodi: lab è il control plane, lab-m02 il worker. -o wide mostra IP, OS, runtime" \
  'kubectl get nodes -o wide'
passo "Il control plane è fatto di Pod in kube-system: apiserver, etcd, scheduler, controller-manager, più CoreDNS, kube-proxy, calico" \
  'kubectl get pods -n kube-system -o wide'
passo "Quei Pod sono STATICI: il kubelet li legge da questa cartella del nodo, non dall'apiserver" \
  'minikube -p lab ssh -- sudo ls /etc/kubernetes/manifests'
passo "La stessa cartella sull'host Ubuntu NON esiste: il nodo è un container, il suo filesystem non è quello del PC (uscita 2 voluta)" \
  'ls /etc/kubernetes/manifests'
passo "etcd: un solo membro (etcd-lab), sul control plane. Due nodi Kubernetes non vogliono dire due copie del database" \
  'kubectl -n kube-system get pod -l component=etcd -o wide'
nota "Quorum etcd = floor(N/2)+1:  1 membro → 0 guasti tollerati · 3 → 1 · 4 → 1 · 5 → 2." \
     "Per questo si usano 3 o 5 membri, mai 4, e su macchine diverse."
passo "Cosa crede di avere Kubernetes: Capacity e Allocatable di ogni nodo" \
  'kubectl get nodes -o custom-columns=NOME:.metadata.name,CPU:.status.capacity.cpu,MEMORIA:.status.capacity.memory,CPU_ALLOC:.status.allocatable.cpu,MEM_ALLOC:.status.allocatable.memory'
passo "Cosa ha davvero il container-nodo: --memory=4g è un limite del cgroup, --cpus=2 non viene applicato (cpu.max = max)" \
  'docker exec lab cat /sys/fs/cgroup/memory.max /sys/fs/cgroup/cpu.max; docker exec lab nproc'
passo "Quanto è vicino al limite: memory.current comprende la cache dei file, che il kernel recupera. Contano il netto e gli OOM kill" \
  'for n in lab lab-m02; do docker exec $n sh -c "cd /sys/fs/cgroup; awk -v c=\$(cat memory.current) -v m=\$(cat memory.max) \"/^(active|inactive)_file /{f+=\\\$2} END{printf \\\"%-8s totale %5d Mi · cache %5d Mi · netto %5d Mi = %d%% di %d Mi\\\\n\\\", \\\"$n\\\", c/2^20, f/2^20, (c-f)/2^20, (c-f)*100/m, m/2^20}\" memory.stat; grep oom_kill memory.events"; done'
passo "kubectl top (aspetto il metrics-server, dopo un avvio ci mette fino a un minuto): consumo osservato, in percentuale della Capacity sopra (tutto l'host), non di 2 CPU / 4 GiB" \
  'for i in $(seq 30); do kubectl top nodes >/dev/null 2>&1 && break; sleep 5; done; kubectl top nodes'
nota "Con il driver docker ogni nodo vede tutte le CPU e la RAM del PC: lo scheduler conta su ~16 GiB per nodo," \
     "ma il container-nodo viene ucciso dal kernel a 4 GiB. In un cluster vero Capacity = la macchina."
passo "Tutti i tipi di oggetto che l'apiserver conosce (nome corto, gruppo API, namespaced o no)" \
  'kubectl api-resources | head -30'
passo "kubectl explain: la documentazione di un campo, direttamente dallo schema del cluster" \
  'kubectl explain deployment.spec.strategy.rollingUpdate'
passo "Crea un Deployment imperativo con 2 repliche (in produzione si usa YAML, qui serve a vedere la riconciliazione)" \
  'kubectl create deployment eco --image=traefik/whoami:v1.12 --replicas=2'
passo "Aspetta che il rollout sia completo: le repliche sono pronte" \
  'kubectl rollout status deployment/eco'
passo "Auto-riparazione: cancello i Pod e guardo (-w) il ReplicaSet ricrearli da solo. Dura 15 secondi" \
  'kubectl get pods -l app=eco -w & W=$!; sleep 2; kubectl delete pod -l app=eco --wait=false; sleep 13; kill $W'
nota "I Pod cancellati passano da Terminating a Error: whoami esce con codice 2 al SIGTERM (misurato)." \
     "Non è un guasto: conta che i due Pod nuovi arrivino a Running."
passo "Gli eventi raccontano il perché: SuccessfulCreate del ReplicaSet, Scheduled, Pulled, Started" \
  'kubectl get events --sort-by=.metadata.creationTimestamp | tail -12'
passo "Un Service davanti a eco, per vedere il terzo tipo di IP" \
  'kubectl expose deployment eco --port=80 && kubectl get svc eco'
passo "Tre IP diversi: del NODO (rete docker 192.168.49.x), del POD (10.244.x, rete Calico), del SERVICE (ClusterIP virtuale, rete 10.96.0.0/12: da 10.96 a 10.111)" \
  'kubectl get nodes -o custom-columns=NODO:.metadata.name,IP:.status.addresses[0].address; kubectl get pods -l app=eco -o custom-columns=POD:.metadata.name,IP:.status.podIP,NODO:.spec.nodeName; kubectl get svc eco -o custom-columns=SERVICE:.metadata.name,CLUSTER-IP:.spec.clusterIP'
passo "Trappola: senza -n, kubectl guarda solo il namespace 'default'. Qui eco c'è, il control plane no" \
  'kubectl get pods; echo "--- in tutti i namespace: $(kubectl get pods -A --no-headers | wc -l) Pod"'
passo "Pulizia del Deployment e del Service di prova" \
  'kubectl delete deployment,service eco'
nota "Per spegnere il cluster senza perderlo:  minikube -p lab stop" \
     "Per riaccenderlo:                       minikube -p lab start" \
     "Per cancellarlo del tutto:              minikube -p lab delete"
````

## Traccia per lo studio attivo

Prima di passare oltre: rileggi il manifest e lo script della lezione, individua il comando che produce l’osservazione principale, spiega perché il risultato è atteso, poi confronta la tua spiegazione con le riflessioni e le domande da colloquio del Markdown originale. Non applicare gli script a un cluster diverso dal laboratorio senza verificare i contesti.

---

<a id="lezione-02"></a>

# Lezione 02 — Deployment, rollout, probe e shutdown pulito

## Spiegazione e riflessioni ragionate

### Modello mentale del professore
Il Deployment gestisce ReplicaSet, e i ReplicaSet mantengono Pod. I Pod di un Deployment sono **repliche intercambiabili**; non hanno l'identità stabile che studieremo con StatefulSet. Il rolling update protegge la disponibilità soltanto se l'applicazione ha readiness affidabile e il processo gestisce correttamente la terminazione.

### Dalla teoria alla produzione
- `strategy.rollingUpdate.maxSurge` permette Pod temporanei in più; `maxUnavailable` fissa quante repliche possono essere non disponibili durante il rollout. Entrambi si interpretano rispetto alle repliche desiderate.
- La **readiness** decide se il Pod riceve traffico attraverso gli endpoint del Service; la **liveness** può provocare riavvii se il processo è bloccato; la **startupProbe** protegge applicazioni con avvio lento dall'interferenza precoce delle altre probe.
- `preStop`, `terminationGracePeriodSeconds` e gestione di SIGTERM contribuiscono allo shutdown: il Pod non dovrebbe troncare le connessioni prima che i client smettano di raggiungerlo.
- `requests` orienta lo scheduler, `limits` interviene a runtime; 100m CPU = 0,1 CPU. OOMKilled indica una condizione da investigare con stato e metriche, non necessariamente una richiesta di aumentare il limite.
- `securityContext` è un presidio applicativo: non-root, `allowPrivilegeEscalation: false`, capability ridotte, filesystem read-only secondo le esigenze.

### Collegamenti
La readiness qui influenzerà gli EndpointSlice nella Lezione 03; i rollout saranno provocati anche dal checksum delle ConfigMap nella Lezione 04 e dagli upgrade Helm nella Lezione 09; un image tag errato verrà riconosciuto come ImagePullBackOff nella Lezione 08.

### Verifica rapida
1. Che differenza c'è fra Deployment e ReplicaSet?
2. Perché `Running` non equivale necessariamente a `Ready`?
3. Quando usare startupProbe invece di alzare soltanto i ritardi liveness?
4. Perché un rollout può interrompere il traffico anche se è di tipo RollingUpdate?

## Materiale originale della lezione


### Fonte originale: `02-deployment-rollout-probe.md`

> **Trascrizione integrale del file originale**, senza riscrittura. Questo blocco è una fonte di riferimento per il sito.

````markdown
# 02 — Deployment: rolling update, probe, risorse e shutdown pulito

Spiegazione di `02-deployment-rollout-probe.yaml` (questa cartella). Lezione sul sito: http://127.0.0.1:3000/kubernetes/2

## In una frase

Il file crea il Namespace `lab` e un **Deployment `web`** con 3 repliche di `traefik/whoami`, configurato per
aggiornarsi **senza togliere capacità**: rolling update con `maxSurge 1` / `maxUnavailable 0`, tre probe
(startup, readiness, liveness), requests/limits, un `preStop` che ritarda lo spegnimento e un `securityContext`
restrittivo. Il runner lo applica, fa un rolling update, lo annota, guarda la storia e torna indietro con un rollback.

## Due file con lo stesso nome: quale lanciare

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/lezioni/kubernetes/02-deployment-rollout-probe.yaml` | **questo**: il manifest, con la teoria nei commenti | si **legge**; lo applica il runner (o a mano: `kubectl apply -f 02-deployment-rollout-probe.yaml`) |
| `~/kubernetesprj/kubernetes/02-deployment-rollout-probe.sh` | lo script **guidato**: applica il manifest e fa rollout, history, undo, uno per volta spiegando prima di eseguire (Invio / s / q) | `bash kubernetes/02-deployment-rollout-probe.sh` |

Un `.yaml` non si "lancia": si applica. Per imparare usa lo **guidato** e tieni aperto questo file accanto.

## Com'è fatto il file

```
intestazione (commenti)  → teoria: Deployment → ReplicaSet, i 3 ingredienti dello zero-downtime, comandi LAB,
                           riquadro NEL PROGETTO VERO
Namespace lab            → lo spazio dove vivono gli oggetti di tutte le lezioni
Deployment web           → il workload: strategia, risorse, probe, preStop, securityContext
coda (commenti)          → domande da colloquio, riepilogo
```

Versione indicata nell'intestazione: Kubernetes 1.34–1.35 (il lab minikube gira la **1.34.0**), API `apps/v1`.

---

## 1. La teoria nell'intestazione

### Un Deployment gestisce ReplicaSet, non Pod

```
Deployment web ──crea──▶ ReplicaSet (uno per ogni versione del template) ──crea──▶ Pod
```

- Ogni modifica al **pod template** (immagine, env, annotazioni *del template*) crea un **ReplicaSet nuovo**.
- Il **rollout** sposta repliche dal ReplicaSet vecchio al nuovo, rispettando `maxSurge` e `maxUnavailable`.
- I ReplicaSet vecchi **non vengono cancellati**: restano a 0 repliche. Sono la **storia** che usa
  `kubectl rollout undo`.

Cambiare invece qualcosa **fuori** dal template (per esempio `replicas`) non crea un ReplicaSet nuovo: scala quello
esistente.

### Zero-downtime non è automatico

Servono **tre cose insieme**:

| Ingrediente | Cosa garantisce |
|---|---|
| `readinessProbe` | il Pod nuovo riceve traffico solo quando è pronto |
| `maxUnavailable: 0` | non togli capacità prima di averne aggiunta |
| shutdown pulito (`preStop` + `terminationGracePeriodSeconds`) | il Pod vecchio smette di ricevere traffico **prima** di morire |

Ne manca una e durante un rollout qualche richiesta va persa.

### I comandi LAB dell'intestazione

```bash
kubectl config current-context                    # deve dire "lab"
kubectl apply -f 02-deployment-rollout-probe.yaml
kubectl -n lab rollout status deploy/web
kubectl -n lab set image deploy/web web=traefik/whoami:v1.11
kubectl -n lab annotate deploy/web kubernetes.io/change-cause="whoami v1.11" --overwrite
kubectl -n lab rollout history deploy/web
kubectl -n lab rollout undo deploy/web --to-revision=1
kubectl -n lab get rs -o wide                     # i ReplicaSet della storia
kubectl -n lab get pod -o custom-columns=NOME:.metadata.name,QOS:.status.qosClass
```

Il commento sotto `rollout history` riporta un fatto **provato**: senza l'`annotate`, anche la revisione 2 dice
"prima versione". `change-cause` si copia dal Deployment al ReplicaSet a ogni rollout, quindi se non la cambi
ti porti dietro quella vecchia.

### Riquadro «NEL PROGETTO VERO»

In `~/biodistretto/kubernetes` (branch `kubernetes`; come si usa: il README della cartella) backend, frontend e nginx
sono Deployment con `replicas: ${repliche}` (una variabile del template Terraform). Le probe cambiano secondo il
processo:

- **php-fpm non parla HTTP** → probe `tcpSocket` sulla porta **9000** (controlla solo che la porta accetti connessioni);
- **nginx** ha una porta dedicata solo alla salute: **8081**, con `path: /healthz`.

```bash
grep -n -B1 -A2 'tcpSocket' terraform/app/manifests/app.yaml.tftpl
grep -n -A3 'path: /healthz' terraform/app/manifests/app.yaml.tftpl
```

Risorse: `requests` su tutti, e `limits` **solo sulla memoria** (niente CPU throttling, come qui). Terraform aspetta la
fine del rollout prima di proseguire:

```bash
grep -n 'rollout =' terraform/app/workload.tf
```

Il rollout lì parte da solo quando cambia la configurazione: lo vedrai nella lezione 04.

---

## 2. Il Namespace `lab`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: lab
```

Un Namespace è una "cartella" logica per gli oggetti. Tutte le lezioni lavorano in `lab`: per questo ogni comando ha
`-n lab`. Sta nello stesso file del Deployment e **viene prima** (separato da `---`): `kubectl apply` crea gli oggetti
nell'ordine del file, quindi il Namespace esiste quando arriva il Deployment.

---

## 3. Il Deployment `web` — campo per campo

### `metadata`

| Campo | Valore | Perché |
|---|---|---|
| `name` / `namespace` | `web` / `lab` | il nome usato in tutti i comandi: `deploy/web` |
| `labels` | `app.kubernetes.io/name: web` | label "raccomandata" di Kubernetes; la usano i selettori |
| `annotations` | `kubernetes.io/change-cause: "prima versione"` | testo che compare nella colonna CHANGE-CAUSE di `rollout history` |

### `spec` del Deployment

| Campo | Valore | Cosa fa |
|---|---|---|
| `replicas` | `3` | quante copie del Pod vuoi |
| `revisionHistoryLimit` | `5` | quanti ReplicaSet vecchi tenere per l'undo (oltre, i più vecchi vengono cancellati) |
| `progressDeadlineSeconds` | `120` | se il rollout non avanza per 120 s, la condition `Progressing` diventa `False`: `rollout status` esce con errore e **la CI fallisce** invece di restare appesa |
| `minReadySeconds` | `5` | un Pod deve essere pronto da 5 s prima di contare come "available": filtra i Pod che passano la readiness e poi crollano subito |
| `selector.matchLabels` | `app.kubernetes.io/name: web` | quali Pod appartengono al Deployment. **Immutabile dopo la creazione**: per cambiarlo devi cancellare e ricreare |
| `strategy.type` | `RollingUpdate` | sostituzione graduale. L'alternativa `Recreate` spegne tutto e poi riaccende (downtime, ma mai due versioni insieme) |
| `rollingUpdate.maxSurge` | `1` | durante il rollout al massimo **3+1 = 4** Pod |
| `rollingUpdate.maxUnavailable` | `0` | mai sotto **3** Pod pronti |

Con `maxSurge 1` e `maxUnavailable 0` il rollout procede così: sale **un** Pod nuovo, aspetta che sia pronto (e
available dopo 5 s), poi spegne **un** Pod vecchio; ripete tre volte.

La label del `template.metadata.labels` deve combaciare con il `selector`, altrimenti l'apiserver rifiuta il Deployment.

### Il container `web`

```yaml
terminationGracePeriodSeconds: 30
containers:
  - name: web
    image: traefik/whoami:v1.12
    args: ["--port", "8080"]
    ports:
      - name: http
        containerPort: 8080
```

- `traefik/whoami` è un server HTTP minuscolo che risponde con i dati della richiesta. L'immagine è **FROM scratch**:
  dentro non c'è una shell né `/bin/sleep` (conta per il `preStop`).
- `args: ["--port", "8080"]` lo fa ascoltare sulla 8080 (sopra la 1024: un utente non root può aprirla).
- La porta ha un **nome**, `http`: le probe la richiamano per nome (`port: http`) invece che per numero.
- `terminationGracePeriodSeconds: 30`: tempo massimo fra la richiesta di spegnimento e il SIGKILL.

### Risorse e QoS

```yaml
resources:
  requests:
    cpu: 50m
    memory: 32Mi
  limits:
    memory: 64Mi
```

| Concetto | Cosa vuol dire |
|---|---|
| `requests` | quanto usa lo **scheduler** per scegliere il nodo (riserva) |
| `limits` | tetto a runtime: CPU oltre il limite → **throttling**; memoria oltre il limite → **OOMKilled** (exit 137) |
| `50m` | 50 millicore = 5% di un core |

La **classe QoS** del Pod la calcola Kubernetes dalle risorse:

| QoS | Quando | Sotto pressione di memoria |
|---|---|---|
| **Guaranteed** | request = limit per CPU **e** memoria su tutti i container | sfrattato per ultimo |
| **Burstable** | almeno una request, ma non Guaranteed | in mezzo |
| **BestEffort** | nessuna request né limit | sfrattato per primo |

Qui i Pod sono **Burstable**: c'è una request di CPU senza limit di CPU, e la memoria ha request 32Mi ≠ limit 64Mi.
Il runner lo fa vedere apposta (passi 12 e 13).

Prassi diffusa, scritta nel file: **limit di memoria sì, limit di CPU spesso no**. Il throttling CFS rallenta il
processo anche quando il nodo ha CPU libera, e la latenza sale.

### Le tre probe

```yaml
startupProbe:
  httpGet: { path: /health, port: http }
  periodSeconds: 2
  failureThreshold: 30       # fino a 60 s per partire
readinessProbe:
  httpGet: { path: /health, port: http }
  periodSeconds: 5
  failureThreshold: 2
livenessProbe:
  httpGet: { path: /health, port: http }
  periodSeconds: 10
  failureThreshold: 3
```

| Probe | Se fallisce | Qui |
|---|---|---|
| **startup** | finché non passa, le altre due **non partono**; se esaurisce il budget, il container viene riavviato | budget = `failureThreshold × period` = 30 × 2 s = **60 s** per partire |
| **readiness** | il Pod **esce dagli EndpointSlice** (niente traffico), ma **non** viene riavviato | ogni 5 s; fuori dopo 2 fallimenti (~10 s) |
| **liveness** | il kubelet **riavvia** il container | ogni 10 s; riavvio dopo 3 fallimenti (~30 s) |

Tutte e tre fanno `GET /health` sulla porta `http`: risposta 2xx/3xx = successo.

**Errore classico** (dal file): una liveness che controlla il database. Il DB rallenta, tutte le liveness falliscono,
il kubelet riavvia tutti i Pod: hai trasformato un rallentamento in un'interruzione. La liveness controlla solo che
**il processo sia vivo**; le dipendenze, se proprio, le controlla la readiness.

### Shutdown pulito: `preStop`

```yaml
lifecycle:
  preStop:
    sleep:
      seconds: 5
```

Quando un Pod viene cancellato succedono **in parallelo** due cose:

1. il kubelet esegue il `preStop` e poi manda **SIGTERM** al processo;
2. il control plane toglie il Pod dagli **Endpoint**, e kube-proxy / l'ingress aggiornano le loro regole.

Il secondo è più lento: per qualche secondo arrivano ancora richieste a un processo che sta chiudendo → **502**.
Il `preStop` con `sleep: 5` **ritarda il SIGTERM di 5 s**, il tempo perché il Pod esca dagli Endpoint.

- È l'azione **nativa** `sleep` (beta dalla 1.30, stabile nella 1.34 del lab): non chiede `/bin/sleep`
  nell'immagine. Con whoami (FROM scratch) un `exec: ["sleep","5"]` fallirebbe.
- Il tempo del `preStop` **conta dentro** i 30 s di `terminationGracePeriodSeconds`.
- Riduce i 502, **non garantisce da sola** lo zero downtime.

### `securityContext` del container

| Campo | Valore | Perché |
|---|---|---|
| `allowPrivilegeEscalation` | `false` | il processo non può guadagnare privilegi (setuid ecc.) |
| `readOnlyRootFilesystem` | `true` | il filesystem del container è in sola lettura: un attaccante non scrive binari |
| `runAsNonRoot` | `true` | il kubelet rifiuta di avviare il container se girerebbe come root |
| `runAsUser` | `65532` | UID non privilegiato esplicito (serve perché un'immagine scratch non dichiara un utente) |
| `capabilities.drop` | `["ALL"]` | toglie tutte le capability Linux |

Questi campi sono esattamente quelli che chiede il profilo **restricted** di Pod Security (lezione 07).

---

## 4. Il runner, passo per passo

Il runner (`~/kubernetesprj/kubernetes/02-deployment-rollout-probe.sh`) chiama prima `guardia_lab` (si ferma se il
contesto non è `lab`), poi esegue 13 passi:

| # | Comando | Cosa vedi |
|---|---|---|
| 1 | `kubectl config current-context` | `lab` |
| 2 | `kubectl apply -f …/02-deployment-rollout-probe.yaml` | `namespace/lab created`, `deployment.apps/web created` (o `unchanged`/`configured` se c'era già: apply è dichiarativo) |
| 3 | `kubectl -n lab rollout status deploy/web` | attende finché le 3 repliche superano la readiness: `successfully rolled out` |
| 4 | `kubectl -n lab set image deploy/web web=traefik/whoami:v1.11` | cambia l'immagine del template → **revisione 2**, nuovo ReplicaSet |
| 5 | `rollout status` + `get deploy web -o wide` | il rolling update fino alla fine; la colonna IMAGES dice `v1.11` |
| 6 | `kubectl -n lab annotate deploy/web kubernetes.io/change-cause="whoami v1.11" --overwrite` | il motivo finisce nella CHANGE-CAUSE della revisione corrente |
| 7 | `kubectl -n lab rollout history deploy/web` | due revisioni: 1 "prima versione", 2 "whoami v1.11" |
| 8 | `rollout undo deploy/web --to-revision=1` + `rollout status` | il ReplicaSet vecchio torna in scala |
| 9 | `get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}'` | `traefik/whoami:v1.12`: il rollback è avvenuto |
| 10 | `get events --sort-by=.metadata.creationTimestamp \| grep -i scaling \| tail -8` | gli eventi `ScalingReplicaSet` su e giù: il racconto del rollout |
| 11 | `kubectl -n lab get rs -o wide` | un ReplicaSet con le repliche, gli altri a 0 |
| 12 | `get pod -o custom-columns=NOME:…,QOS:.status.qosClass` | `Burstable` per tutti e tre |
| 13 | `get deploy web -o jsonpath='{…resources}'` | `{"limits":{"memory":"64Mi"},"requests":{"cpu":"50m","memory":"32Mi"}}`: il motivo del Burstable |

Nessun passo fallisce apposta in questa lezione. La `nota` finale dice: **il Deployment resta acceso**, perché la
lezione 03 ci mette davanti Service, Ingress e NetworkPolicy.

Due cose da notare:

- Dopo l'**undo** la storia non "torna indietro": la revisione 1 viene **rinumerata** come nuova revisione (3), e la 1
  sparisce dalla history. Il ReplicaSet è lo stesso di prima.
- L'`annotate` del passo 6 è sul **Deployment**: per questo, come dice l'intestazione, senza di lui la revisione 2
  avrebbe ereditato "prima versione".

---

## 5. Le trappole

| Trappola | Cosa succede | Rimedio |
|---|---|---|
| liveness che controlla una dipendenza (DB) | un rallentamento del DB riavvia tutti i Pod | liveness = solo "il processo è vivo" |
| niente startupProbe con avvio lento | la liveness uccide il container prima che sia partito | startupProbe con budget sufficiente |
| `maxUnavailable` > 0 senza readiness | i Pod nuovi ricevono traffico prima di essere pronti | readiness + `maxUnavailable: 0` |
| `preStop` con `exec sleep` su immagine scratch | il comando non esiste, il preStop fallisce | azione nativa `sleep:` |
| cambiare il `selector` | l'apiserver rifiuta: è immutabile | cancellare e ricreare il Deployment |
| dimenticare `change-cause` | la history ripete la causa vecchia | `annotate … --overwrite` a ogni rollout |
| limit di CPU basso | throttling e latenza anche con CPU libera | spesso solo request di CPU |

---

## 6. La coda: domande da colloquio

- **Il rollout è bloccato a metà. Come lo diagnostichi?** `kubectl rollout status` (scade con
  `progressDeadlineSeconds`), `kubectl get rs` (il nuovo ha Pod non pronti), `describe pod` del nuovo:
  ImagePullBackOff, readiness che fallisce, Pending per risorse. Con `maxUnavailable 0` il vecchio continua a servire:
  niente outage. Poi `kubectl rollout undo`.
- **Perché cambiare un ConfigMap non riavvia i Pod?** Il ConfigMap non fa parte del pod template: il Deployment non vede
  differenze. Soluzioni: annotazione checksum nel template (Helm, lezione 09), `configMapGenerator` con suffisso hash
  (Kustomize, lezione 11), o `kubectl rollout restart`, che aggiunge un'annotazione `restartedAt` al template.
- **Exit code 137 vs 143?** 137 = 128+9 = **SIGKILL** (OOMKilled o grace period scaduto); 143 = 128+15 = **SIGTERM**
  gestito male. Il motivo: `kubectl get pod -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}'`
  → `OOMKilled` o `Error`.
- **Blue/green e canary con un Deployment nudo?** Blue/green: due Deployment, il Service cambia selector. Canary rozzo:
  due Deployment con la stessa label del Service e repliche in proporzione. Canary vero (per percentuale, con analisi
  delle metriche): Argo Rollouts, Flagger, o pesi su Ingress/Traefik (corso HAProxy & Traefik).

### Comandi da sapere

| Comando | A cosa serve |
|---|---|
| `kubectl -n lab rollout status deploy/web` | attende la fine del rollout (esce ≠0 oltre `progressDeadlineSeconds`) |
| `kubectl -n lab rollout history deploy/web` | le revisioni con CHANGE-CAUSE |
| `kubectl -n lab rollout undo deploy/web --to-revision=1` | rollback a una revisione |
| `kubectl -n lab rollout restart deploy/web` | ricrea i Pod senza cambiare l'immagine |
| `kubectl -n lab get rs -o wide` | i ReplicaSet (la storia) |
| `kubectl -n lab get pod -o custom-columns=NOME:.metadata.name,QOS:.status.qosClass` | la QoS di ogni Pod |

---

## Riepilogo

- Deployment → ReplicaSet → Pod; ogni cambio del **template** = nuovo ReplicaSet.
- Zero-downtime = **readiness** + **maxUnavailable 0** + **preStop/grace period**.
- **startup** protegge l'avvio, **readiness** toglie traffico, **liveness** riavvia.
- **requests** per lo scheduler, **limits** a runtime; la **QoS** decide gli sfratti.
- `rollout status / history / undo`; `progressDeadlineSeconds` per la CI.

## Prova da solo

1. Cambia l'immagine in un tag che non esiste (es. `traefik/whoami:v0.0.0`) con `set image`: guarda `get rs` e
   `rollout status`. Quanti Pod vecchi restano pronti? Dopo quanto `rollout status` si arrende? Poi `rollout undo`.
2. Porta `maxUnavailable` a `1` e `maxSurge` a `0`, rifai un `set image` e confronta con `get pod -w`: quanti Pod pronti
   ci sono al minimo durante il rollout?
3. Metti `limits.cpu: 50m` (uguale alla request) e `limits.memory: 32Mi` (uguale alla request), riapplica e rileggi la
   colonna QOS: che classe ottieni adesso, e perché?
````

### Fonte originale: `02-deployment-rollout-probe.yaml`

> **Trascrizione integrale del file originale**, senza riscrittura. Questo blocco è una fonte di riferimento per il sito.

````yaml
# ═══════════════════════════════════════════════════════════════════════════
# 02. DEPLOYMENT: ROLLING UPDATE, PROBE, RISORSE E SHUTDOWN PULITO
# Versione: Kubernetes 1.34–1.35 (il lab minikube gira la 1.34.0) · apps/v1
# Livello: 1 — Workload
# ═══════════════════════════════════════════════════════════════════════════
# Un Deployment non gestisce Pod: gestisce ReplicaSet. Ogni modifica al
# pod template (immagine, env, annotazioni del template) crea un ReplicaSet
# nuovo; il rollout sposta repliche dal vecchio al nuovo rispettando
# maxSurge/maxUnavailable. I vecchi ReplicaSet restano a 0 repliche:
# sono la storia per `kubectl rollout undo`.
#
# Zero-downtime NON è automatico. Servono tre cose insieme:
#   1. readinessProbe   il Pod nuovo riceve traffico solo quando è pronto
#   2. maxUnavailable 0 non togli capacità prima di averne aggiunta
#   3. shutdown pulito  il Pod vecchio smette di ricevere traffico PRIMA
#                       di morire (preStop + terminationGracePeriodSeconds)
#
# LAB
#   kubectl config current-context                    # deve dire "lab"
#   kubectl apply -f 02-deployment-rollout-probe.yaml
#   kubectl -n lab rollout status deploy/web
#   kubectl -n lab set image deploy/web web=traefik/whoami:v1.11
#   kubectl -n lab annotate deploy/web kubernetes.io/change-cause="whoami v1.11" --overwrite
#   kubectl -n lab rollout history deploy/web
#     ↑ senza l'annotate anche la revisione 2 dice "prima versione":
#       change-cause si copia dal Deployment a ogni rollout (provato)
#   kubectl -n lab rollout undo deploy/web --to-revision=1
#   kubectl -n lab get rs -o wide                     # i ReplicaSet della storia
#   kubectl -n lab get pod -o custom-columns=NOME:.metadata.name,QOS:.status.qosClass
#
# ── NEL PROGETTO VERO: il Biodistretto su minikube ───────────────────────
#   ~/biodistretto/kubernetes (branch kubernetes). I grep partono da lì:
#   cd ~/biodistretto/kubernetes · come si usa: il README della cartella
#   backend, frontend e nginx sono Deployment con `replicas: ${repliche}`.
#   Le probe cambiano secondo il processo: php-fpm non parla HTTP, quindi
#   tcpSocket sulla 9000; nginx ha una porta solo per la salute (8081).
#     grep -n -B1 -A2 'tcpSocket' terraform/app/manifests/app.yaml.tftpl
#     grep -n -A3 'path: /healthz' terraform/app/manifests/app.yaml.tftpl
#   Risorse: requests su tutti, e limit solo sulla memoria (niente CPU
#   throttling). Terraform aspetta la fine del rollout prima di proseguire:
#     grep -n 'rollout =' terraform/app/workload.tf
#   Il rollout parte da solo quando cambia la config: vedi la lezione 04.

apiVersion: v1
kind: Namespace
metadata:
  name: lab
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: lab
  labels:
    app.kubernetes.io/name: web
  annotations:
    kubernetes.io/change-cause: "prima versione"   # compare in rollout history
spec:
  replicas: 3
  revisionHistoryLimit: 5          # quanti ReplicaSet vecchi tenere per l'undo
  progressDeadlineSeconds: 120     # oltre: condition Progressing=False → la CI fallisce
  minReadySeconds: 5               # pronto da 5 s prima di contare come "available"
  selector:
    matchLabels:                   # IMMUTABILE dopo la creazione
      app.kubernetes.io/name: web
  strategy:
    type: RollingUpdate            # l'alternativa è Recreate (tutto giù, poi su)
    rollingUpdate:
      maxSurge: 1                  # al massimo 3+1 Pod durante il rollout
      maxUnavailable: 0            # mai sotto 3 Pod pronti
  template:
    metadata:
      labels:
        app.kubernetes.io/name: web
    spec:
      terminationGracePeriodSeconds: 30
      containers:
        - name: web
          image: traefik/whoami:v1.12
          args: ["--port", "8080"]
          ports:
            - name: http
              containerPort: 8080
          # ── RISORSE E QoS ──────────────────────────────────────────────
          # requests = cosa usa lo scheduler per piazzare il Pod
          # limits   = tetto a runtime: CPU oltre il limite → throttling,
          #            memoria oltre il limite → OOMKilled (exit 137)
          # QoS: Guaranteed (req=lim su tutto) > Burstable > BestEffort:
          # sotto pressione di memoria il kubelet sfratta dal basso.
          # Prassi diffusa: limit di memoria sì, limit di CPU spesso no
          # (il throttling CFS alza la latenza anche con CPU libera).
          resources:
            requests:
              cpu: 50m
              memory: 32Mi
            limits:
              memory: 64Mi
          # ── PROBE ──────────────────────────────────────────────────────
          # startup:   protegge l'avvio lento; finché non passa, le altre
          #            due non partono. Budget = failureThreshold × period.
          # readiness: fallisce → il Pod esce dagli EndpointSlice (niente
          #            traffico) ma NON viene riavviato.
          # liveness:  fallisce → il kubelet RIAVVIA il container.
          # Errore classico: liveness che controlla il DB. Il DB rallenta,
          # tutte le liveness falliscono, si riavvia tutto: hai trasformato
          # un rallentamento in un'interruzione. La liveness controlla solo
          # che il processo sia vivo; le dipendenze, se mai, la readiness.
          startupProbe:
            httpGet: { path: /health, port: http }
            periodSeconds: 2
            failureThreshold: 30       # fino a 60 s per partire
          readinessProbe:
            httpGet: { path: /health, port: http }
            periodSeconds: 5
            failureThreshold: 2
          livenessProbe:
            httpGet: { path: /health, port: http }
            periodSeconds: 10
            failureThreshold: 3
          # ── SHUTDOWN PULITO ────────────────────────────────────────────
          # Alla cancellazione, IN PARALLELO: il kubelet manda SIGTERM e
          # il control plane toglie il Pod dagli Endpoint. Il secondo è più
          # lento: per qualche secondo kube-proxy/ingress mandano ancora
          # richieste a un processo che sta chiudendo → 502.
          # Il preStop "sleep" ritarda il SIGTERM finché il Pod è uscito
          # dagli Endpoint. L'azione nativa `sleep` (beta dalla 1.30, stabile
          # nella 1.34 del lab) non chiede /bin/sleep nell'immagine (whoami è
          # FROM scratch). Riduce i 502, non garantisce da sola zero downtime.
          lifecycle:
            preStop:
              sleep:
                seconds: 5
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            runAsNonRoot: true
            runAsUser: 65532
            capabilities: { drop: ["ALL"] }

# ── DOMANDE DA COLLOQUIO ────────────────────────────────────────────────────
# D: Il rollout è bloccato a metà. Come lo diagnostichi?
# R: `kubectl rollout status` (scade con progressDeadlineSeconds),
#    `kubectl get rs` (il nuovo ha Pod non pronti), `describe pod` del
#    nuovo: ImagePullBackOff, readiness che fallisce, Pending per risorse.
#    Con maxUnavailable 0 il vecchio continua a servire: niente outage.
#    Poi `kubectl rollout undo`.
#
# D: Perché cambiare un ConfigMap non riavvia i Pod?
# R: Il ConfigMap non fa parte del pod template: il Deployment non vede
#    differenze. Soluzioni: annotazione checksum nel template (Helm,
#    lezione 09), configMapGenerator con suffisso hash (Kustomize,
#    lezione 11), o `kubectl rollout restart` che aggiunge un'annotazione
#    restartedAt al template.
#
# D: Exit code 137 vs 143?
# R: 128+9 = SIGKILL (OOMKilled o grace period scaduto), 128+15 = SIGTERM
#    gestito male. `kubectl get pod -o jsonpath='{.status.containerStatuses
#    [0].lastState.terminated.reason}'` dice OOMKilled o Error.
#
# D: Blue/green e canary con un Deployment nudo?
# R: Blue/green: due Deployment, il Service cambia selector. Canary
#    rozzo: due Deployment con la stessa label del Service e repliche
#    in proporzione. Canary vero (per percentuale, con analisi delle
#    metriche): Argo Rollouts, Flagger, o pesi su Ingress/Traefik
#    (corso HAProxy & Traefik).

# ══════════════════════════════════════════════════════════════════════════
# RIEPILOGO
# • Deployment → ReplicaSet → Pod; ogni cambio del template = nuovo RS
# • Zero-downtime = readiness + maxUnavailable 0 + preStop/grace period
# • startup protegge l'avvio, readiness toglie traffico, liveness riavvia
# • requests per lo scheduler, limits a runtime; QoS decide gli sfratti
# • rollout status / history / undo; progressDeadlineSeconds per la CI
# ══════════════════════════════════════════════════════════════════════════
````

### Fonte originale: `02-deployment-rollout-probe.sh`

> **Trascrizione integrale del file originale**, senza riscrittura. Questo blocco è una fonte di riferimento per il sito.

````bash
#!/usr/bin/env bash
# Lezione 02 — Deployment, rollout, rollback, probe e QoS.
source "$(dirname "$0")/../lib/passo.sh"
guardia_lab
titolo "02. Deployment, rollout e probe"
F="$LEZIONI/kubernetes/02-deployment-rollout-probe.yaml"

passo "Controllo il contesto: deve essere 'lab' prima di ogni apply" \
  'kubectl config current-context'
passo "Applica il manifest: Namespace 'lab' + Deployment 'web' con probe e risorse. apply è dichiarativo: crea o aggiorna" \
  "kubectl apply -f $F"
passo "Aspetta che tutte le repliche nuove siano pronte (readiness probe superata)" \
  'kubectl -n lab rollout status deploy/web'
passo "Cambia immagine: parte un rolling update, un ReplicaSet nuovo sale mentre il vecchio scende" \
  'kubectl -n lab set image deploy/web web=traefik/whoami:v1.11'
passo "Seguo il rolling update fino alla fine: maxSurge 1 / maxUnavailable 0 = mai meno di 3 Pod pronti" \
  'kubectl -n lab rollout status deploy/web && kubectl -n lab get deploy web -o wide'
passo "Annota il motivo del rollout: finisce nella colonna CHANGE-CAUSE della history" \
  'kubectl -n lab annotate deploy/web kubernetes.io/change-cause="whoami v1.11" --overwrite'
passo "Storia dei rollout: ogni revisione è un ReplicaSet conservato" \
  'kubectl -n lab rollout history deploy/web'
passo "Rollback alla revisione 1: Kubernetes rimette in scala il ReplicaSet vecchio" \
  'kubectl -n lab rollout undo deploy/web --to-revision=1 && kubectl -n lab rollout status deploy/web'
passo "Prova che il rollback è avvenuto: l'immagine in uso è di nuovo la v1.12" \
  "kubectl -n lab get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}'; echo"
passo "Gli eventi del namespace: ScalingReplicaSet su e giù, il racconto del rollout" \
  'kubectl -n lab get events --sort-by=.metadata.creationTimestamp | grep -i scaling | tail -8'
passo "I ReplicaSet della storia: uno con le repliche, gli altri a 0 (revisionHistoryLimit decide quanti tenerne)" \
  'kubectl -n lab get rs -o wide'
passo "Classe QoS dei Pod: Guaranteed / Burstable / BestEffort, decide chi viene sfrattato per primo" \
  'kubectl -n lab get pod -o custom-columns=NOME:.metadata.name,QOS:.status.qosClass'
passo "Perché Burstable: requests cpu 50m e memoria 32Mi, limit solo sulla memoria (64Mi). Guaranteed vuole request = limit per cpu E memoria" \
  "kubectl -n lab get deploy web -o jsonpath='{.spec.template.spec.containers[0].resources}'; echo"
nota "Il Deployment resta acceso: la lezione 03 ci mette davanti Service, Ingress e NetworkPolicy."
````

## Traccia per lo studio attivo

Prima di passare oltre: rileggi il manifest e lo script della lezione, individua il comando che produce l’osservazione principale, spiega perché il risultato è atteso, poi confronta la tua spiegazione con le riflessioni e le domande da colloquio del Markdown originale. Non applicare gli script a un cluster diverso dal laboratorio senza verificare i contesti.

---

<a id="lezione-03"></a>

# Lezione 03 — Service, Ingress e NetworkPolicy

## Spiegazione e riflessioni ragionate

### Modello mentale del professore
Il Pod ha un IP effimero; il Service offre una destinazione stabile che seleziona Pod tramite **label**. L'Ingress aggiunge regole HTTP host/path ma ha bisogno di un controller che le esegua. La NetworkPolicy limita il traffico ammesso tra Pod e namespace e viene applicata dal CNI compatibile.

### Percorso di una richiesta
Client interno → DNS `web.lab.svc.cluster.local` → ClusterIP del Service `web` → dataplane kube-proxy → endpoint Pod:8080. Client esterno → controller Ingress (Host `web.lab.local`) → backend Service `web` → endpoint Pod; un controller può usare direttamente gli EndpointSlice senza passare dal ClusterIP applicativo. La porta del Service 80 e il `targetPort: http` (container 8080) non sono da confondere.

### Le due NetworkPolicy della lezione
La policy `default-deny-ingress` seleziona tutti i Pod del namespace ed elimina gli ingress consentiti per default. La policy `web-allow` riapre soltanto traffico al Pod `web` da Pod del namespace `lab` con `ruolo=client`, oppure da namespace `ingress-nginx`, sulla porta del Pod `http`. Le policy sono **additive**. Due elementi distinti nell'elenco `from` sono in OR; `namespaceSelector` e `podSelector` nello stesso elemento sono in AND.

### Trappole da capire, non da memorizzare
- Un Service può esistere senza EndpointSlice utilizzabili: selector sbagliato o readiness non soddisfatta.
- Una NetworkPolicy controlla il traffico a livello Pod: la porta da consentire è spesso la **targetPort** (8080), non la `port` del Service (80).
- Una default-deny **ingress** non blocca automaticamente l'egress. Se blocchi egress, devi considerare DNS UDP/TCP 53 e le altre dipendenze necessarie.
- `kubectl run` con `ruolo=client` accede; un Pod intruso privo della label può andare in timeout. Il test è attendibile soltanto dopo la propagazione della policy nel dataplane.

### Verifica rapida
1. Quando usi ClusterIP, NodePort, LoadBalancer e headless?
2. Perché `ping ClusterIP` non è un test affidabile di un Service TCP?
3. Qual è la differenza tra `Ingress` e Ingress Controller?
4. Qual è la differenza logica tra due elementi `from` e due selector nello stesso elemento?

## Materiale originale della lezione


### Fonte originale: `03-service-ingress-networkpolicy.md`

> **Trascrizione integrale del file originale**, senza riscrittura. Questo blocco è una fonte di riferimento per il sito.

````markdown
# 03 — Rete: Service, Ingress e NetworkPolicy

Spiegazione di `03-service-ingress-networkpolicy.yaml` (questa cartella). Lezione sul sito: http://127.0.0.1:3000/kubernetes/3

## In una frase

Il file mette **davanti al Deployment `web` della lezione 02** un **Service** (nome e IP stabili), un **Ingress**
(ingresso HTTP dall'esterno su `web.lab.local`) e **due NetworkPolicy** (tutto chiuso, poi aperto solo a chi ha la label
`ruolo=client` e al controller ingress). Il runner prova che un Pod autorizzato passa e che un Pod "intruso" no.

## Due file con lo stesso nome: quale lanciare

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/lezioni/kubernetes/03-service-ingress-networkpolicy.yaml` | **questo**: i manifest, con la teoria nei commenti | si **legge**; lo applica il runner (o a mano: `kubectl apply -f 03-service-ingress-networkpolicy.yaml`) |
| `~/kubernetesprj/kubernetes/03-service-ingress-networkpolicy.sh` | lo script **guidato**: applica e prova Service, Ingress e policy, un passo per volta (Invio / s / q) | `bash kubernetes/03-service-ingress-networkpolicy.sh` |

**Prerequisito**: la lezione 02 applicata (il Deployment `web` nel namespace `lab` deve esistere).

## Com'è fatto il file

```
intestazione (commenti)  → teoria: Service, ClusterIP, tipi di Service, DNS, comandi LAB, NEL PROGETTO VERO
Service web              → ClusterIP sulla porta 80 → porta "http" dei Pod
Ingress web              → host web.lab.local, path / → Service web
NetworkPolicy default-deny-ingress → chiude l'ingresso a tutti i Pod del namespace
NetworkPolicy web-allow  → riapre web a ruolo=client e al namespace ingress-nginx
commenti                 → la trappola dell'indentazione AND/OR, l'egress e il DNS
coda (commenti)          → domande da colloquio, riepilogo
```

Versioni: Kubernetes 1.34–1.35 (lab 1.34.0), ingress-nginx come addon minikube, Calico come CNI.

---

## 1. La teoria nell'intestazione

### Perché serve un Service

I Pod sono **effimeri** e cambiano IP a ogni ricreazione. Un **Service** dà un **nome DNS** e un **IP virtuale stabili**
davanti a un insieme di Pod, scelto per **label**:

```
Service ──selector──▶ EndpointSlice (IP dei Pod PRONTI) ◀── kube-proxy
```

- Il controller degli EndpointSlice mette dentro **solo i Pod pronti** (readiness probe superata, lezione 02).
- **kube-proxy** su ogni nodo legge gli EndpointSlice e scrive le regole di rete.

### Il ClusterIP non esiste

Il ClusterIP non è assegnato a nessuna interfaccia: è una **regola** iptables / IPVS / nftables che kube-proxy scrive su
ogni nodo e che fa **DNAT** verso un Pod a caso. Per questo **`ping` a un ClusterIP non risponde** (non c'è nessuno
che risponde all'ICMP), mentre `curl` sulla porta del Service sì.

### Tipi di Service

| Tipo | Cosa aggiunge |
|---|---|
| `ClusterIP` | solo dentro il cluster (default) |
| `NodePort` | + una porta **30000-32767** su **ogni** nodo |
| `LoadBalancer` | + un LB esterno del cloud (in locale: MetalLB, `minikube tunnel`) |
| `ExternalName` | un **CNAME** DNS, niente proxy |
| headless | `clusterIP: None` → il DNS restituisce **gli IP dei Pod** (StatefulSet, lezione 05) |

### DNS

Nome completo: `<service>.<namespace>.svc.cluster.local`. Da un Pod in `lab` basta `web`; da un altro namespace
`web.lab`. Per questo i Pod del runner fanno semplicemente `curl web/api`.

### I comandi LAB e il perché dello `sleep`

```bash
kubectl apply -f 03-service-ingress-networkpolicy.yaml
kubectl -n lab get endpointslices -l kubernetes.io/service-name=web
kubectl -n lab run curl --rm -it --image=curlimages/curl:8.23.0 \
    --labels=ruolo=client -- sh -c 'sleep 8; curl -s web/api'      # passa
kubectl -n lab run intruso --rm -it --image=curlimages/curl:8.23.0 \
    -- sh -c 'sleep 8; curl -s -m 3 web/api'                        # bloccato
curl -H 'Host: web.lab.local' http://$(minikube -p lab ip)/api
```

Lo `sleep 8` prima del `curl`: il CNI **impara l'IP di un Pod appena nato con qualche secondo di ritardo**. Senza lo
sleep anche il client **autorizzato** viene bloccato (il file dice: provato su k3s). La lezione per la produzione: un
Pod che chiama una dipendenza al primo istante deve **riprovare**, non morire al primo errore.

### Riquadro «NEL PROGETTO VERO»

In `~/biodistretto/kubernetes` (branch `kubernetes`) **non c'è Ingress**: davanti al cluster c'è **HAProxy sull'host**
(lezione 15), che entra dal Service `nginx` di tipo **NodePort** sulle porte **30080, 30443, 30081**.

```bash
grep -n -A3 'type: NodePort' terraform/app/manifests/app.yaml.tftpl
```

`externalTrafficPolicy: Local` fa sì che un nodo **senza** nginx risponda picche: così il controllo di salute di HAProxy
è davvero per singolo nodo. Senza, kube-proxy girerebbe la richiesta all'altro nodo e **ogni nodo sembrerebbe sano**.
In più conserva l'IP del client.

I servizi interni si trovano per **nome breve** (mariadb, redis…):

```bash
grep -n -E 'DB_HOST|REDIS_HOST' terraform/app/config.tf
```

**Esercizio del riquadro**: il progetto non ha NetworkPolicy. Scrivine una che lasci arrivare a mariadb solo backend e
worker, poi provala con il client "intruso". Prima controlla che **kindnet** (il CNI del progetto) la applichi davvero.

---

## 2. Il Service `web`

```yaml
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: web
  ports:
    - name: http
      port: 80
      targetPort: http
```

| Campo | Valore | Perché |
|---|---|---|
| `type` | `ClusterIP` | raggiungibile solo dall'interno; dall'esterno si passa dall'Ingress |
| `selector` | `app.kubernetes.io/name: web` | **deve combaciare** con le label del pod template della lezione 02. Se sbagli una lettera gli EndpointSlice restano vuoti |
| `ports[].port` | `80` | la porta **del Service**: chi chiama fa `web:80` (o semplicemente `web`) |
| `ports[].targetPort` | `http` | il **nome** della porta nel container (che è la 8080). Se un giorno la porta del container cambia numero ma tiene il nome, il Service non si rompe |

---

## 3. L'Ingress `web`

**Ingress = regole L7** (host, path, TLS). **Da solo non fa niente**: serve un **Ingress Controller** (ingress-nginx,
Traefik, HAProxy Ingress…) scelto con `ingressClassName`. Nel lab è l'addon `ingress` di minikube (lezione 01).

```yaml
spec:
  ingressClassName: nginx
  rules:
    - host: web.lab.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web
                port:
                  name: http
```

| Campo | Valore | Cosa fa |
|---|---|---|
| `ingressClassName` | `nginx` | quale controller deve servire questa regola |
| `host` | `web.lab.local` | il controller sceglie il backend guardando l'header **Host** della richiesta |
| `path` + `pathType` | `/` + `Prefix` | tutto ciò che comincia con `/`. Altri valori: `Exact`, `ImplementationSpecific` |
| `backend.service` | `web`, porta `http` | il Service della sezione 2, indicato per **nome di porta** del Service |

Il nome host non esiste in nessun DNS: per questo il runner fa `curl -H 'Host: web.lab.local'` verso l'IP del nodo
(`minikube -p lab ip`).

**Il successore è la Gateway API** (GatewayClass, Gateway, HTTPRoute): ruoli separati fra chi gestisce il LB e chi
l'app, pesi per il canary, header matching standard senza annotazioni del vendor. Il file avverte che il progetto
**ingress-nginx è stato ritirato** (manutenzione finita a marzo 2026): nei progetti nuovi si sceglie Gateway API o
Traefik. Nel lab lo si usa perché è l'addon pronto di minikube.

---

## 4. Le NetworkPolicy

### Le regole del gioco

- **Di default tutto parla con tutto.**
- Le policy sono **additive**: contengono solo "allow", mai "deny".
- Appena **una** policy seleziona un Pod per `Ingress`, quel Pod accetta **solo** ciò che qualche policy permette.
- Le **applica il CNI**: con un CNI che non le supporta l'`apply` riesce e **non succede niente**. Per questo il lab usa
  **Calico**.

### Policy 1 — `default-deny-ingress`

```yaml
spec:
  podSelector: {}
  policyTypes: [Ingress]
```

`podSelector: {}` = **tutti i Pod del namespace**. `policyTypes: [Ingress]` senza nessuna regola `ingress:` = nessuno
può entrare. Da qui in poi ogni Pod di `lab` è chiuso in ingresso, finché un'altra policy non apre.

### Policy 2 — `web-allow`

```yaml
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: web
  policyTypes: [Ingress]
  ingress:
    - from:
        - podSelector:
            matchLabels:
              ruolo: client
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ingress-nginx
      ports:
        - port: http
```

| Parte | Significato |
|---|---|
| `podSelector` in cima | a **chi** si applica: i Pod `web` |
| `from` con **due elementi** | **OR**: entra chi ha `ruolo=client` (nello **stesso** namespace `lab`, perché un `podSelector` da solo guarda il namespace della policy) **oppure** qualunque Pod del namespace `ingress-nginx` |
| `kubernetes.io/metadata.name` | label che Kubernetes mette da solo su ogni Namespace con il suo nome: comoda per selezionarlo |
| `ports: - port: http` | la porta **del Pod** (8080, per nome), **non** quella del Service (80). La policy vede il traffico dopo il DNAT |

Senza il ramo `ingress-nginx`, l'Ingress smetterebbe di funzionare: il controller è un Pod in un altro namespace e il
default deny lo bloccherebbe.

### La trappola dell'indentazione

```yaml
- namespaceSelector: {...}       ← UN elemento con DUE condizioni = AND
  podSelector: {...}               (quei Pod DENTRO quel namespace)

- namespaceSelector: {...}       ← DUE elementi = OR
- podSelector: {...}
```

Un trattino in più o in meno cambia completamente chi entra, e l'apply non dà errori in nessuno dei due casi.

### Egress e DNS

Se aggiungi un **default deny in uscita**, ricordati del **DNS**, altrimenti niente risolve più niente:

```yaml
egress:
  - to: [{ namespaceSelector: {}, podSelector: { matchLabels: { k8s-app: kube-dns } } }]
    ports: [{ port: 53, protocol: UDP }, { port: 53, protocol: TCP }]
```

Qui `namespaceSelector: {}` e `podSelector` stanno nello **stesso** elemento: AND = "i Pod `kube-dns` in qualunque
namespace". Questo blocco nel file è solo un commento: non viene applicato.

---

## 5. Il runner, passo per passo

`guardia_lab`, poi 6 passi:

| # | Comando | Cosa vedi |
|---|---|---|
| 1 | `kubectl apply -f …/03-service-ingress-networkpolicy.yaml` | `service/web`, `ingress.networking.k8s.io/web`, `networkpolicy…/default-deny-ingress`, `…/web-allow` creati |
| 2 | `kubectl -n lab get endpointslices -l kubernetes.io/service-name=web` | un EndpointSlice con i **3 IP** dei Pod web sulla porta 8080. Vuoto = selector sbagliato o Pod non ready |
| 3 | `kubectl -n lab run curl --rm -i --quiet --restart=Never --image=curlimages/curl:8.23.0 --labels=ruolo=client -- sh -c 'sleep 8; curl -s web/api'` | **passa**: la risposta JSON di whoami (`/api`) |
| 4 | `kubectl -n lab describe networkpolicy web-allow \| sed -n "/Allowing ingress/,/Allowing egress/p"` | la sezione "Allowing ingress traffic": porta `http`, da `ruolo=client` **oppure** dal namespace `ingress-nginx` |
| 5 | `kubectl -n lab run intruso … -- sh -c 'sleep 8; curl -s -m 3 web/api; echo uscita=\$?'` | **fallisce apposta**: niente risposta, dopo 3 s (`-m 3`) curl si arrende e stampa `uscita=28` (il codice di timeout di curl) |
| 6 | `curl -s -H 'Host: web.lab.local' http://$(minikube -p lab ip)/api` | dall'host, attraverso l'Ingress: risponde whoami. Passa perché il controller sta nel namespace `ingress-nginx` |

Note sulle opzioni di `kubectl run` usate dal runner (diverse dall'intestazione, che usa `-it`):

- `--rm` cancella il Pod alla fine; `--restart=Never` crea un Pod semplice (non riavviato);
- `-i` collega lo stdin senza TTY e `--quiet` toglie i messaggi di kubectl: l'output è solo quello del curl.

Il passo 5 è il fallimento **voluto**: dimostra la policy. Il riquadro rosso di `passo` (uscita ≠ 0) qui di solito non
compare, perché l'ultimo comando dello `sh -c` è `echo`, che esce 0: il fallimento lo leggi in `uscita=28`.

---

## 6. Le trappole

| Trappola | Cosa succede | Rimedio |
|---|---|---|
| selector del Service che non combacia | EndpointSlice vuoti, connessione rifiutata | confronta `selector` e label del template |
| `targetPort` sbagliata | il Service inoltra a una porta chiusa | usa il **nome** della porta |
| CNI senza supporto NetworkPolicy | l'apply va, ma **non blocca niente** | provare sempre con un "intruso" |
| `ports` della policy col numero del Service (80) | traffico bloccato | la porta è quella **del Pod** |
| AND/OR confusi nell'indentazione | entra chi non dovrebbe (o nessuno) | un elemento = AND, due elementi = OR |
| deny in uscita senza DNS | nessun nome risolve | regola egress verso `kube-dns` porta 53 UDP+TCP |
| default deny senza aprire al controller ingress | l'Ingress smette di rispondere | `namespaceSelector` su `ingress-nginx` |
| client che chiama subito all'avvio | bloccato finché il CNI non ha imparato l'IP | retry (nel lab: `sleep 8`) |

---

## 7. La coda: domande da colloquio

- **Un Service non risponde. Ordine dei controlli?** 1) `kubectl get endpointslices`: vuoti → selector sbagliato o Pod
  non ready. 2) `targetPort` giusta? 3) dal Pod: `curl` su `localhost:porta`. 4) DNS: `nslookup web.lab` da un Pod.
  5) NetworkPolicy che blocca.
- **`externalTrafficPolicy: Local` vs `Cluster`?** `Cluster` (default): ogni nodo inoltra a qualunque Pod, con SNAT →
  il Pod vede l'IP del nodo, non del client. `Local`: solo ai Pod del nodo, IP del client preservato, ma i nodi senza
  Pod falliscono l'health check del LB e il carico può sbilanciarsi.
- **Ingress vs Service LoadBalancer?** LoadBalancer = un LB (e un IP, e un costo) per Service, L4. Ingress = un solo LB
  L7 per molti Service, con host/path e TLS.
- **Perché un Pod pronto non riceve traffico subito dopo un rollout?** Propagazione: EndpointSlice → kube-proxy su ogni
  nodo → regole. Sono secondi, ed è lo stesso ritardo che rende necessario il `preStop` allo spegnimento (lezione 02).

### Comandi da sapere

| Comando | A cosa serve |
|---|---|
| `kubectl -n lab get endpointslices -l kubernetes.io/service-name=web` | chi c'è davvero dietro il Service |
| `kubectl -n lab describe networkpolicy web-allow` | chi può entrare, letto come lo legge Kubernetes |
| `kubectl -n lab run … --labels=ruolo=client …` | Pod di prova con una label precisa |
| `curl -H 'Host: web.lab.local' http://$(minikube -p lab ip)/api` | provare un Ingress senza DNS |

---

## Riepilogo

- **Service** = nome + IP virtuale stabile; i Pod li sceglie il **selector**.
- **EndpointSlice** contiene solo i Pod **pronti** (readiness).
- **Ingress** = regole L7, serve un **controller**; il futuro è la **Gateway API**.
- **NetworkPolicy** additive, applicate dal **CNI**; schema: default deny + allow.
- `podSelector` e `namespaceSelector`: **stesso elemento = AND, due elementi = OR**.

## Prova da solo

1. Cambia il `selector` del Service in `app.kubernetes.io/name: webx`, riapplica e guarda gli EndpointSlice. Poi
   ripeti il passo 3 del runner: che errore dà curl? Rimetti il selector giusto.
2. Togli il ramo `namespaceSelector` da `web-allow`, riapplica e ripeti il curl con `-H 'Host: web.lab.local'`
   dall'host: cosa succede all'Ingress, e perché?
3. Riscrivi il `from` di `web-allow` come **un solo elemento** con `namespaceSelector` + `podSelector` (AND) e prova
   sia il Pod `curl` con `ruolo=client` sia l'Ingress: chi passa adesso?
````

### Fonte originale: `03-service-ingress-networkpolicy.yaml`

> **Trascrizione integrale del file originale**, senza riscrittura. Questo blocco è una fonte di riferimento per il sito.

````yaml
# ═══════════════════════════════════════════════════════════════════════════
# 03. RETE: SERVICE, INGRESS E NETWORKPOLICY
# Versione: Kubernetes 1.34–1.35 (il lab minikube gira la 1.34.0) · ingress-nginx (addon minikube) · Calico
# Livello: 1 — Workload
# ═══════════════════════════════════════════════════════════════════════════
# I Pod sono effimeri e cambiano IP. Un Service dà un nome DNS e un IP
# virtuale stabili davanti a un insieme di Pod scelto per LABEL.
#
#   Service ──selector──▶ EndpointSlice (IP dei Pod PRONTI) ◀── kube-proxy
#
# Il ClusterIP non esiste su nessuna interfaccia: è una regola iptables/
# IPVS/nftables che kube-proxy scrive su ogni nodo e che fa DNAT verso un
# Pod a caso. Per questo `ping` a un ClusterIP non risponde, `curl` sì.
#
# TIPI DI SERVICE
#   ClusterIP     solo dentro il cluster (default)
#   NodePort      + una porta 30000-32767 su OGNI nodo
#   LoadBalancer  + un LB esterno del cloud (in locale: MetalLB, minikube tunnel)
#   ExternalName  un CNAME DNS, niente proxy
#   headless      clusterIP: None → il DNS restituisce gli IP dei Pod
#                 (StatefulSet, lezione 05)
#
# DNS: <service>.<namespace>.svc.cluster.local
#   da un Pod in "lab", basta "web"; da un altro namespace "web.lab".
#
# LAB (richiede la lezione 02 applicata)
#   kubectl apply -f 03-service-ingress-networkpolicy.yaml
#   kubectl -n lab get endpointslices -l kubernetes.io/service-name=web
#   kubectl -n lab run curl --rm -it --image=curlimages/curl:8.23.0 \
#       --labels=ruolo=client -- sh -c 'sleep 8; curl -s web/api'      # passa
#   kubectl -n lab run intruso --rm -it --image=curlimages/curl:8.23.0 \
#       -- sh -c 'sleep 8; curl -s -m 3 web/api'                        # bloccato
#   curl -H 'Host: web.lab.local' http://$(minikube -p lab ip)/api
#
#   Perché lo sleep: il CNI impara l'IP di un Pod appena nato con qualche
#   secondo di ritardo. Senza sleep anche il client AUTORIZZATO viene
#   bloccato (provato su k3s). In produzione: un Pod che chiama una
#   dipendenza al primo istante deve riprovare, non morire al primo errore.
#
# ── NEL PROGETTO VERO: il Biodistretto su minikube ───────────────────────
#   ~/biodistretto/kubernetes (branch kubernetes). I grep partono da lì:
#   cd ~/biodistretto/kubernetes · come si usa: il README della cartella
#   Niente Ingress: davanti al cluster c'è HAProxy sull'host (lezione 15),
#   che entra dal Service nginx di tipo NodePort (30080, 30443, 30081).
#     grep -n -A3 'type: NodePort' terraform/app/manifests/app.yaml.tftpl
#   externalTrafficPolicy: Local fa sì che un nodo senza nginx risponda
#   picche, e così il controllo di HAProxy è davvero per singolo nodo.
#   Senza, kube-proxy girerebbe la richiesta all'altro nodo e ogni nodo
#   sembrerebbe sano. In più conserva l'IP del client.
#   I servizi interni si trovano per nome breve (mariadb, redis…):
#     grep -n -E 'DB_HOST|REDIS_HOST' terraform/app/config.tf
#   ESERCIZIO: il progetto non ha NetworkPolicy. Scrivine una che lasci
#   arrivare a mariadb solo backend e worker, poi provala con il client
#   "intruso" qui sopra. Prima controlla che kindnet la applichi davvero.

apiVersion: v1
kind: Service
metadata:
  name: web
  namespace: lab
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: web     # deve combaciare con le label del pod template
  ports:
    - name: http
      port: 80                      # la porta del Service
      targetPort: http              # il NOME della porta nel container: rinominare
                                    # la porta del container non rompe il Service
---
# ── INGRESS ─────────────────────────────────────────────────────────────────
# Ingress = regole L7 (host, path, TLS). Da solo non fa niente: serve un
# Ingress Controller (ingress-nginx, Traefik, HAProxy Ingress…) scelto con
# ingressClassName. Il successore è la Gateway API (GatewayClass, Gateway,
# HTTPRoute): ruoli separati tra chi gestisce il LB e chi l'app, pesi per
# il canary, header matching standard senza annotazioni del vendor.
# Nota: il progetto ingress-nginx è stato ritirato (manutenzione finita a
# marzo 2026): nei progetti nuovi si sceglie Gateway API o Traefik.
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web
  namespace: lab
spec:
  ingressClassName: nginx
  rules:
    - host: web.lab.local
      http:
        paths:
          - path: /
            pathType: Prefix        # Prefix | Exact | ImplementationSpecific
            backend:
              service:
                name: web
                port:
                  name: http
---
# ── NETWORKPOLICY ───────────────────────────────────────────────────────────
# Di default tutto parla con tutto. Le policy sono ADDITIVE (solo "allow"):
# appena una policy seleziona un Pod per Ingress, quel Pod accetta solo ciò
# che qualche policy permette. Le applica il CNI: con un CNI che non le
# supporta l'apply riesce e NON SUCCEDE NIENTE (per questo il lab usa Calico).
#
# 1) default deny in ingresso per tutto il namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: lab
spec:
  podSelector: {}                   # {} = tutti i Pod del namespace
  policyTypes: [Ingress]
---
# 2) web accetta: dai Pod con ruolo=client dello stesso namespace,
#    e dal controller ingress (namespace ingress-nginx)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow
  namespace: lab
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: web
  policyTypes: [Ingress]
  ingress:
    - from:
        # due elementi della lista = OR
        - podSelector:
            matchLabels:
              ruolo: client
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ingress-nginx
      ports:
        - port: http                # la porta del POD (8080), non del Service
# Trappola dell'indentazione:
#   - namespaceSelector: {...}       ← un elemento con DUE condizioni = AND
#     podSelector: {...}               (quei Pod DENTRO quel namespace)
#   - namespaceSelector: {...}       ← due elementi = OR
#   - podSelector: {...}
#
# Egress: con un default deny in uscita ricordati del DNS, altrimenti
# niente risolve più niente:
#   egress:
#     - to: [{ namespaceSelector: {}, podSelector: { matchLabels: { k8s-app: kube-dns } } }]
#       ports: [{ port: 53, protocol: UDP }, { port: 53, protocol: TCP }]

# ── DOMANDE DA COLLOQUIO ────────────────────────────────────────────────────
# D: Un Service non risponde. Ordine dei controlli?
# R: 1) `kubectl get endpointslices`: vuoti → selector sbagliato o Pod non
#    ready. 2) targetPort giusta? 3) dal Pod: curl su localhost:porta.
#    4) DNS: `nslookup web.lab` da un Pod. 5) NetworkPolicy che blocca.
#
# D: externalTrafficPolicy: Local vs Cluster?
# R: Cluster (default): ogni nodo inoltra a qualunque Pod, con SNAT → il
#    Pod vede l'IP del nodo, non del client. Local: solo ai Pod del nodo,
#    IP del client preservato, ma nodi senza Pod falliscono l'health
#    check del LB e il carico può sbilanciarsi.
#
# D: Ingress vs Service LoadBalancer?
# R: LoadBalancer = un LB (e un IP, e un costo) per Service, L4.
#    Ingress = un solo LB L7 per molti Service, con host/path e TLS.
#
# D: Perché un Pod pronto non riceve traffico subito dopo un rollout?
# R: Propagazione: EndpointSlice → kube-proxy su ogni nodo → regole.
#    Sono secondi, ed è lo stesso ritardo che rende necessario il preStop
#    allo spegnimento (lezione 02).

# ══════════════════════════════════════════════════════════════════════════
# RIEPILOGO
# • Service = nome + IP virtuale stabile; i Pod li sceglie il selector
# • EndpointSlice contiene solo i Pod pronti (readiness)
# • Ingress = regole L7, serve un controller; il futuro è la Gateway API
# • NetworkPolicy additive, applicate dal CNI; default deny + allow
# • podSelector e namespaceSelector: stesso elemento = AND, due = OR
# ══════════════════════════════════════════════════════════════════════════
````

### Fonte originale: `03-service-ingress-networkpolicy.sh`

> **Trascrizione integrale del file originale**, senza riscrittura. Questo blocco è una fonte di riferimento per il sito.

````bash
#!/usr/bin/env bash
# Lezione 03 — Service, Ingress e NetworkPolicy (richiede la 02 applicata).
source "$(dirname "$0")/../lib/passo.sh"
guardia_lab
titolo "03. Service, Ingress e NetworkPolicy"
F="$LEZIONI/kubernetes/03-service-ingress-networkpolicy.yaml"

passo "Applica Service 'web', Ingress su web.lab.local e due NetworkPolicy (deny di default + allow per ruolo=client)" \
  "kubectl apply -f $F"
passo "EndpointSlice: gli IP dei Pod pronti dietro al Service. Vuoto = selector sbagliato o Pod non ready" \
  'kubectl -n lab get endpointslices -l kubernetes.io/service-name=web'
passo "Pod usa-e-getta CON label ruolo=client: la NetworkPolicy lo lascia passare. Lo sleep dà tempo al CNI di imparare l'IP del Pod" \
  "kubectl -n lab run curl --rm -i --quiet --restart=Never --image=curlimages/curl:8.23.0 --labels=ruolo=client -- sh -c 'sleep 8; curl -s web/api'"
passo "Chi può entrare in web: Pod con ruolo=client OPPURE dal namespace ingress-nginx. Le policy si sommano, il deny di default chiude il resto" \
  'kubectl -n lab describe networkpolicy web-allow | sed -n "/Allowing ingress/,/Allowing egress/p"'
passo "Pod SENZA label: la NetworkPolicy lo blocca, curl va in timeout dopo 3 secondi" \
  "kubectl -n lab run intruso --rm -i --quiet --restart=Never --image=curlimages/curl:8.23.0 -- sh -c 'sleep 8; curl -s -m 3 web/api; echo uscita=\$?'"
passo "Dall'host attraverso l'Ingress: il controller sceglie il backend in base all'header Host" \
  "curl -s -H 'Host: web.lab.local' http://\$(minikube -p lab ip)/api"
````

## Traccia per lo studio attivo

Prima di passare oltre: rileggi il manifest e lo script della lezione, individua il comando che produce l’osservazione principale, spiega perché il risultato è atteso, poi confronta la tua spiegazione con le riflessioni e le domande da colloquio del Markdown originale. Non applicare gli script a un cluster diverso dal laboratorio senza verificare i contesti.

---

<a id="lezione-04"></a>

# Lezione 04 — ConfigMap, Secret e aggiornamento della configurazione

## Spiegazione e riflessioni ragionate

### Modello mentale del professore
Una sola immagine applicativa può funzionare in più ambienti ricevendo configurazione esterna. **ConfigMap** è per configurazione non sensibile, **Secret** per credenziali; Base64 è codifica reversibile, non cifratura. Il problema più importante non è dove salvi il valore, ma **quando il processo lo legge**.

### Esperimento centrale
All'avvio il container riceve `LOG_LEVEL=info` via `env` e il file `/etc/app/app.properties` con `feature.x=false` via volume. Si fa patch della ConfigMap verso `LOG_LEVEL=debug`, `feature.x=true`. Dopo propagazione del kubelet: **env ancora `info`**, file ora `feature.x=true`. Dopo `kubectl rollout restart deploy/conf`: nuovi container con env `debug` e file aggiornato. La modifica della ConfigMap da sola non cambia il Pod template del Deployment.

### Perché accade
- Le variabili d'ambiente vengono inizializzate all'avvio del processo/container.
- I volumi ConfigMap normali possono essere aggiornati dal kubelet con sostituzione atomica dei link simbolici, per esempio `..data`, ma il processo deve riaprire/rileggere il file.
- Un file montato tramite `subPath` non riceve gli aggiornamenti automatici nel Pod esistente.
- Un checksum della ConfigMap renderizzata, inserito in `spec.template.metadata.annotations`, cambia con i dati e provoca un rollout. Helm lo userà nella Lezione 09.

### Sicurezza e applicazione reale
Il Secret `db` dimostra l'uso di `stringData` e `data` Base64. Protezione effettiva richiede RBAC, scelte di cifratura at-rest, controllo di chi può creare Pod/Deployment che montano Secret e una gestione dei segreti fuori da Git. Per Laravel, la cache di configurazione va prodotta con l'ambiente finale corretto; una variabile d'ambiente aggiornata non raggiunge da sola processi già avviati.

### Verifica rapida
1. Che cosa si aggiorna in un Pod già in esecuzione: env o file montato?
2. Perché `readOnly: true` non impedisce al kubelet di sostituire il contenuto del volume?
3. Perché `subPath` cambia il comportamento?
4. Perché Base64 non protegge una password?

## Materiale originale della lezione


### Fonte originale: `04-configmap-secret.md`

> **Trascrizione integrale del file originale**, senza riscrittura. Questo blocco è una fonte di riferimento per il sito.

````markdown
# 04 — Configurazione: ConfigMap, Secret e come si aggiornano

Spiegazione di `04-configmap-secret.yaml` (questa cartella). Lezione sul sito: http://127.0.0.1:3000/kubernetes/4

## In una frase

Il file crea una **ConfigMap** `app-config`, un **Secret** `db` e un piccolo **Deployment `conf`** (busybox) che li
consuma in **due modi**: come **variabili d'ambiente** e come **file montati**. Il runner cambia la ConfigMap a caldo e
fa vedere la lezione centrale: **il file si aggiorna da solo, la variabile d'ambiente no**; per quella serve un
container nuovo.

## Due file con lo stesso nome: quale lanciare

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/lezioni/kubernetes/04-configmap-secret.yaml` | **questo**: i manifest, con la teoria nei commenti | si **legge**; lo applica il runner (o a mano: `kubectl apply -f 04-configmap-secret.yaml`) |
| `~/kubernetesprj/kubernetes/04-configmap-secret.sh` | lo script **guidato**: applica, cambia la ConfigMap, confronta env e file, un passo per volta (Invio / s / q) | `bash kubernetes/04-configmap-secret.sh` |

Il namespace `lab` deve esistere (lo crea la lezione 02).

## Com'è fatto il file

```
intestazione (commenti)  → teoria: twelve-factor, ConfigMap vs Secret, come e quando si aggiornano,
                           comandi LAB, NEL PROGETTO VERO
ConfigMap app-config     → una chiave semplice (LOG_LEVEL) e una chiave-file (app.properties)
Secret db                → username e password, scritti con stringData
Deployment conf          → busybox che dorme; legge la config come env e come volume
commenti                 → i segreti in GitOps, il caso Laravel
coda (commenti)          → domande da colloquio, riepilogo
```

---

## 1. La teoria nell'intestazione

### Twelve-factor: la config fuori dall'immagine

La **stessa immagine** gira in ogni ambiente (dev, staging, produzione); cambia solo la configurazione, che sta fuori.
Kubernetes offre due oggetti quasi identici:

| Oggetto | Per cosa |
|---|---|
| **ConfigMap** | dati non sensibili |
| **Secret** | dati sensibili — ma solo **base64, che NON è cifratura** |

La differenza **vera** fra i due:

- **RBAC separabile**: puoi dare `get` sui ConfigMap e negarlo sui Secret;
- nei volumi un Secret sta in **tmpfs** (in memoria), **mai su disco del nodo**;
- **cifratura at-rest in etcd**, ma solo **se** l'apiserver ha una `EncryptionConfiguration` (sui cloud gestiti: KMS,
  spesso da attivare a mano).

### Come arrivano nel Pod, e quando si aggiornano

| Modo | Quando si aggiorna |
|---|---|
| `env` / `envFrom` | letti **all'avvio del container**: **mai** aggiornati |
| volume | aggiornato dal kubelet al suo **prossimo sync** (da pochi secondi a 1-2 minuti; il file dice: su k3s 5 s), con uno **swap atomico del symlink `..data`** |
| volume + `subPath` | **mai** aggiornato (trappola classica) |
| `immutable: true` | né aggiornabile né osservato: meno carico sull'apiserver; per cambiarlo lo ricrei |

E anche quando il file si aggiorna: un'app che lo legge **solo all'avvio** non vede il cambio. Serve un **reload**
(SIGHUP, watch del file) o un **rollout**.

### Riquadro «NEL PROGETTO VERO»

In `~/biodistretto/kubernetes`:

- La ConfigMap di nginx usa gli **stessi file dello stack docker**, letti con `file()` di Terraform; solo i due vhost
  sono template (`templatefile`):
  ```bash
  grep -n -E 'file\(|templatefile' terraform/app/config.tf
  ```
- Quei file sono montati con **`subPath`**, e un subPath non si aggiorna da solo. Per questo il template del Pod porta il
  **checksum della config**: cambia la ConfigMap → cambia l'annotazione → il Deployment fa il rollout.
  ```bash
  grep -n 'subPath' terraform/app/manifests/app.yaml.tftpl
  grep -n 'biodistretto/config' terraform/app/manifests/app.yaml.tftpl
  ```
- Il backend prende tutta la config con **`envFrom`**, da ConfigMap più Secret:
  ```bash
  grep -n -A4 'envFrom' terraform/app/manifests/app.yaml.tftpl
  ```
- Le password non le scrive nessuno: `random_password`, e CA e certificato dal provider `tls`. Restano però nel
  **tfstate**, che quindi è a sua volta un segreto (e sta nel `.gitignore`):
  ```bash
  grep -n '^resource' terraform/app/segreti.tf
  grep -n 'tfstate' .gitignore
  ```

---

## 2. La ConfigMap `app-config`

```yaml
data:
  LOG_LEVEL: info
  app.properties: |
    feature.x=false
```

Due chiavi, due usi:

- `LOG_LEVEL` è un **valore semplice**: il Deployment lo prende come variabile d'ambiente;
- `app.properties` è un **file intero** (il `|` di YAML conserva l'a capo): il Deployment lo monta come file.

Il nome della chiave diventa il nome del file quando la ConfigMap è montata come volume.

---

## 3. Il Secret `db`

```yaml
type: Opaque
stringData:
  username: app
  password: cambiami-subito
```

| Campo | Perché |
|---|---|
| `type: Opaque` | Secret generico, chiavi libere (altri tipi: TLS, docker-registry…) |
| `stringData` | permette di scrivere i valori **in chiaro** nel manifest; l'apiserver li converte in base64 nel campo `data`. Comodo, ma proprio per questo **questo file non va in git** |

Il runner lo legge con `get secret db -o jsonpath='{.data.password}' | base64 -d` e ottiene `cambiami-subito`:
chiunque abbia `get` sui secret del namespace lo decodifica in un comando.

---

## 4. Il Deployment `conf` — campo per campo

### Template e annotazione di checksum

```yaml
selector:
  matchLabels: { app: conf }
template:
  metadata:
    labels: { app: conf }
    annotations:
      checksum/config: "da-calcolare-in-helm"
```

Il valore qui è un **segnaposto**. In Helm (lezione 09) lo si calcola con `sha256sum` sul ConfigMap: se il contenuto
cambia, cambia l'annotazione → cambia il **pod template** → il Deployment fa un **rollout automatico** (lezione 02: ogni
cambio del template = nuovo ReplicaSet). Scritto a mano e mai cambiato, come qui, non scatena niente.

### Spec del Pod

| Campo | Valore | Perché |
|---|---|---|
| `automountServiceAccountToken` | `false` | l'app non parla con l'API di Kubernetes: niente token montato nel Pod (meno superficie d'attacco, lezione 07) |
| `image` | `busybox:1.37` | un'immagine minima **con la shell**: serve per fare `exec` e `cat` |
| `command` | `["sh", "-c", "while true; do sleep 3600; done"]` | il container non fa niente, resta vivo per farsi ispezionare |
| `resources` | requests `cpu: 10m`, `memory: 16Mi`; limits `memory: 32Mi` | stessa logica della lezione 02 (QoS Burstable) |

### Le variabili d'ambiente

```yaml
env:
  - name: LOG_LEVEL
    valueFrom:
      configMapKeyRef: { name: app-config, key: LOG_LEVEL }
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef: { name: db, key: password }
```

- `configMapKeyRef` prende **una chiave** di una ConfigMap; `secretKeyRef` una chiave di un Secret.
- Vengono risolte **quando il container parte**. Dopo, sono una fotografia.

Il commento del file avverte: **meglio il segreto come FILE, non come env**. Le env finiscono in `kubectl describe`, nei
crash dump, in `/proc/<pid>/environ` e nei log di chi le stampa. `DB_PASSWORD` qui c'è per farti vedere il modo da
evitare.

### I volumi

```yaml
volumeMounts:
  - name: config
    mountPath: /etc/app
    readOnly: true
  - name: segreti
    mountPath: /run/secrets/db
    readOnly: true
volumes:
  - name: config
    configMap:
      name: app-config
      items:
        - key: app.properties
          path: app.properties
  - name: segreti
    secret:
      secretName: db
      defaultMode: 0400
```

| Volume | Cosa finisce nel container |
|---|---|
| `config` | **solo** la chiave `app.properties` (grazie a `items`), come `/etc/app/app.properties`. Senza `items` comparirebbe anche un file `LOG_LEVEL` |
| `segreti` | ogni chiave del Secret diventa un file: `/run/secrets/db/username` e `/run/secrets/db/password` |

- `readOnly: true`: il container non può scrivere nella config.
- `defaultMode: 0400`: i file del Secret sono leggibili **solo dal proprietario** (in YAML `0400` è un numero ottale).
- Nessun `subPath`: per questo il file **si aggiorna** (la differenza col progetto vero).

Dentro `/etc/app` il kubelet crea una cartella con data e ora (`..2026_…`), un link `..data` che punta a lei, e
`app.properties` che punta a `..data/app.properties`. Per aggiornare scrive una cartella nuova e **sposta il link
`..data` in un colpo solo**: l'app non vede mai un file scritto a metà.

---

## 5. Il runner, passo per passo

`guardia_lab`, poi 10 passi. Importante: `passo` esegue i comandi con `eval` **nella stessa shell**, quindi la
variabile `P` impostata al passo 3 resta valida nei passi successivi.

| # | Comando | Cosa vedi |
|---|---|---|
| 1 | `kubectl apply -f …/04-configmap-secret.yaml` | `configmap/app-config`, `secret/db`, `deployment.apps/conf` creati |
| 2 | `kubectl -n lab rollout status deploy/conf` | il Pod è pronto |
| 3 | `P=$(kubectl -n lab get pod -l app=conf -o name \| head -1); echo $P` | il nome, es. `pod/conf-…` |
| 4 | `exec $P -- sh -c 'echo LOG_LEVEL=$LOG_LEVEL; cat /etc/app/app.properties'` | `LOG_LEVEL=info` e `feature.x=false` |
| 5 | `exec $P -- ls -la /etc/app` | i symlink: `..data -> ..2026_…`, `app.properties -> ..data/app.properties` |
| 6 | `kubectl -n lab patch cm app-config --type merge -p '{"data":{"LOG_LEVEL":"debug","app.properties":"feature.x=true\n"}}'` | `configmap/app-config patched`. Nessun Pod viene riavviato |
| 7 | `sleep 60; exec $P -- sh -c '…'` | **il punto della lezione**: `LOG_LEVEL=info` (la **variabile no**) ma `feature.x=true` (il **file sì**) |
| 8 | `get secret db -o jsonpath='{.data.password}' \| base64 -d; echo` | `cambiami-subito` in chiaro |
| 9 | `rollout restart deploy/conf && rollout status deploy/conf` | Pod nuovo, creato con la ConfigMap già aggiornata |
| 10 | nuovo `P` con `--field-selector=status.phase=Running … \| tail -1`, poi lo stesso `exec` | ora anche `LOG_LEVEL=debug` |

Nessun passo fallisce apposta. Il passo 7 è il "fallimento" concettuale: la variabile d'ambiente **resta vecchia**. Il
`sleep 60` serve ad aspettare il sync del kubelet (da pochi secondi a 1-2 minuti).

La `nota` finale: in git va il manifest del Secret **con valori finti** (`secret.example.yaml`), quello vero sta nel
`.gitignore`. Base64 non cifra; una password finita in un commit **si cambia**, perché `.gitignore` non riscrive la
storia.

Attenzione: il patch del passo 6 resta nel cluster. Se rilanci il runner, il passo 1 (`apply`) rimette `info` e
`feature.x=false`.

---

## 6. I segreti in GitOps

Il problema: in git sta tutto **tranne** i Secret. Le risposte mature:

| Strumento | Come funziona |
|---|---|
| **External Secrets Operator** | il cluster legge da Vault / AWS Secrets Manager / GCP Secret Manager e crea il Secret; in git c'è solo il riferimento (`ExternalSecret` + `SecretStore`) |
| **Sealed Secrets** | in git c'è un `SealedSecret` cifrato con la chiave pubblica del controller nel cluster |
| **SOPS** (+ age/KMS) | file YAML cifrati campo per campo, decifrati da Argo CD/Flux o helm-secrets |
| **CSI Secrets Store driver** | il segreto montato direttamente dal provider come volume, senza Secret Kubernetes |

In tutti i casi **rotazione, audit e revoca stanno nel vault**, non nel cluster.

**Minimo decente in un laboratorio senza vault**: `secret.example.yaml` in git (valori finti, mostra le chiavi
attese) e `secret.yaml` fuori da git (`.gitignore`, valori veri).

**Su EKS**: Secrets Manager + Pod Identity, poi External Secrets (→ Secret, usabile con `envFrom`) o CSI driver (→ file).
Una rotazione non tocca le env dei container già avviati: serve un rollout (esattamente ciò che vedi al passo 7).

### Il caso Laravel

ConfigMap per `APP_ENV`, `APP_URL`, `DB_HOST`…; Secret per `APP_KEY`, `DB_PASSWORD`, token. Entrambi con `envFrom`,
senza `.env` nell'immagine:

```yaml
envFrom:
  - configMapRef: { name: laravel-config }
  - secretRef:    { name: laravel-secret }
```

Con `php artisan config:cache` la cache va **rifatta all'avvio del container**, altrimenti fotografa i valori vecchi
(lo ricorda anche il passo 10 del runner).

---

## 7. Le trappole

| Trappola | Cosa succede | Rimedio |
|---|---|---|
| "Secret = cifrato" | è solo base64 | RBAC stretto, cifratura at-rest (KMS), fonte esterna |
| cambiare la ConfigMap e aspettarsi la nuova env | l'env resta quella dell'avvio | `rollout restart` o checksum nel template |
| volume con `subPath` | il file non si aggiorna **mai** | checksum nel template → rollout |
| app che legge il file solo all'avvio | il file cambia ma l'app no | reload (SIGHUP, watch) o rollout |
| segreti in env | finiscono in describe, dump, `/proc/<pid>/environ`, log | montali come file con `defaultMode` stretto |
| Secret con `stringData` in git | password in chiaro nella storia | `secret.example.yaml` + `.gitignore`; se è già committata, si **cambia** |
| `config:cache` di Laravel nell'immagine | fotografa i valori di build | rifarla all'avvio del container |

---

## 8. La coda: domande da colloquio

- **I Secret di Kubernetes sono sicuri?** Di default no: base64 in etcd e leggibili da chiunque abbia `get` sui secret
  o possa **creare un Pod** nel namespace (montandoli). Servono cifratura at-rest (KMS), RBAC stretto, niente segreti in
  env, e una fonte esterna con rotazione.
- **Ho cambiato il ConfigMap ma l'app usa ancora il valore vecchio.** Env: letta solo all'avvio. Volume con subPath: non
  si aggiorna mai. Volume normale: aggiornato al sync del kubelet, ma l'app deve rileggerlo. Soluzione robusta: config
  **versionata** (hash nel nome o checksum nel template), così ogni cambio è un rollout tracciabile e reversibile.
- **Perché un ConfigMap immutabile?** Il kubelet non lo osserva più: meno watch sull'apiserver nei cluster grandi, e
  nessuno può cambiarlo sotto i piedi a un'app in produzione.

### Comandi da sapere

| Comando | A cosa serve |
|---|---|
| `kubectl -n lab patch cm app-config --type merge -p '{"data":{…}}'` | cambiare una ConfigMap al volo |
| `kubectl -n lab get secret db -o jsonpath='{.data.password}' \| base64 -d` | leggere (e capire quanto è poco protetto) un Secret |
| `kubectl -n lab exec $P -- ls -la /etc/app` | vedere i symlink `..data` |
| `kubectl -n lab rollout restart deploy/conf` | Pod nuovi per prendere le env nuove |

---

## Riepilogo

- ConfigMap e Secret: la config **fuori dall'immagine**.
- Secret = **base64, non cifratura**: servono KMS, RBAC e una fonte esterna.
- **env mai aggiornate, volume sì** (al sync del kubelet), **subPath mai**.
- Config versionata (checksum/hash) = ogni cambio è un **rollout**.
- GitOps: External Secrets, Sealed Secrets o SOPS, **mai Secret in chiaro** in git.

## Prova da solo

1. Entra nel Pod e leggi `/run/secrets/db/password` e i permessi con `ls -la /run/secrets/db/`: che modo vedi, e da
   quale campo del manifest viene? Confrontalo con `echo $DB_PASSWORD`.
2. Aggiungi `immutable: true` alla ConfigMap, riapplica, poi rifai il `patch` del passo 6: che errore dà l'apiserver?
   Come la cambi adesso?
3. Monta `app.properties` con `subPath: app.properties` su `mountPath: /etc/app/app.properties`, riapplica, rifai il
   patch e aspetta 60 s: il file cambia? Poi cambia a mano il valore di `checksum/config` e riapplica: cosa succede ai Pod?
````

### Fonte originale: `04-configmap-secret.yaml`

> **Trascrizione integrale del file originale**, senza riscrittura. Questo blocco è una fonte di riferimento per il sito.

````yaml
# ═══════════════════════════════════════════════════════════════════════════
# 04. CONFIGURAZIONE: CONFIGMAP, SECRET E COME SI AGGIORNANO
# Versione: Kubernetes 1.34–1.35 (il lab minikube gira la 1.34.0)
# Livello: 1 — Workload
# ═══════════════════════════════════════════════════════════════════════════
# Twelve-factor: la stessa immagine in ogni ambiente, la configurazione
# fuori. Kubernetes offre due oggetti quasi identici:
#   ConfigMap  dati non sensibili
#   Secret     dati sensibili — ma solo base64, che NON è cifratura.
#              La differenza vera: RBAC separabile, tmpfs nei volumi
#              (mai su disco del nodo), cifratura at-rest in etcd SE
#              l'apiserver ha una EncryptionConfiguration (sui cloud
#              gestiti: KMS, spesso da attivare).
#
# COME ARRIVANO NEL POD, E QUANDO SI AGGIORNANO
#   env / envFrom           letti all'avvio del container: MAI aggiornati
#   volume                  aggiornati dal kubelet al suo prossimo sync
#                           (da pochi secondi a 1-2 minuti: su k3s 5 s),
#                           con uno swap atomico del symlink ..data
#   volume + subPath        MAI aggiornati (trappola classica)
#   immutable: true         né aggiornabile né osservato: meno carico
#                           sull'apiserver; per cambiarlo lo ricrei
#
# Un'app che legge il file solo all'avvio non vede comunque il cambio:
# serve un reload (SIGHUP, watch del file) o un rollout.
#
# LAB
#   kubectl apply -f 04-configmap-secret.yaml
#   kubectl -n lab rollout status deploy/conf
#   P=$(kubectl -n lab get pod -l app=conf -o name | head -1)
#   kubectl -n lab exec $P -- sh -c 'echo $LOG_LEVEL; cat /etc/app/app.properties'
#   kubectl -n lab exec $P -- ls -la /etc/app            # ..data → ..2026_…
#   kubectl -n lab patch cm app-config --type merge -p '{"data":{"LOG_LEVEL":"debug","app.properties":"feature.x=true\n"}}'
#   sleep 60; kubectl -n lab exec $P -- sh -c 'echo $LOG_LEVEL; cat /etc/app/app.properties'
#     ↑ il file è cambiato, la variabile d'ambiente no
#   kubectl -n lab get secret db -o jsonpath='{.data.password}' | base64 -d
#
# ── NEL PROGETTO VERO: il Biodistretto su minikube ───────────────────────
#   ~/biodistretto/kubernetes (branch kubernetes). I grep partono da lì:
#   cd ~/biodistretto/kubernetes · come si usa: il README della cartella
#   La ConfigMap di nginx usa gli STESSI file dello stack docker, letti con
#   file(). Cambiano solo i due vhost, che sono template:
#     grep -n -E 'file\(|templatefile' terraform/app/config.tf
#   I file sono montati con subPath, e un subPath non si aggiorna da solo.
#   Per questo il template del Pod porta il checksum della config: cambia
#   la ConfigMap, cambia l'annotazione, e il Deployment fa il rollout.
#     grep -n 'subPath' terraform/app/manifests/app.yaml.tftpl
#     grep -n 'biodistretto/config' terraform/app/manifests/app.yaml.tftpl
#   Il backend prende tutta la config con envFrom, da ConfigMap più Secret:
#     grep -n -A4 'envFrom' terraform/app/manifests/app.yaml.tftpl
#   Le password non le scrive nessuno: random_password, e CA e certificato
#   dal provider tls. Restano però nel tfstate, che quindi è un segreto:
#     grep -n '^resource' terraform/app/segreti.tf
#     grep -n 'tfstate' .gitignore

apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: lab
data:
  LOG_LEVEL: info
  app.properties: |
    feature.x=false
---
apiVersion: v1
kind: Secret
metadata:
  name: db
  namespace: lab
type: Opaque
stringData:                  # in chiaro qui, base64 in etcd: comodo, ma
  username: app              # questo file NON va in git (vedi sotto)
  password: cambiami-subito
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: conf
  namespace: lab
spec:
  replicas: 1
  selector:
    matchLabels: { app: conf }
  template:
    metadata:
      labels: { app: conf }
      annotations:
        # Helm calcola questo valore con sha256sum sul ConfigMap: se il
        # contenuto cambia, cambia il template → rollout automatico.
        checksum/config: "da-calcolare-in-helm"
    spec:
      automountServiceAccountToken: false   # non parla con l'API: niente token
      containers:
        - name: app
          image: busybox:1.37
          command: ["sh", "-c", "while true; do sleep 3600; done"]
          env:
            - name: LOG_LEVEL
              valueFrom:
                configMapKeyRef: { name: app-config, key: LOG_LEVEL }
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef: { name: db, key: password }
            # Meglio ancora: il segreto come FILE, non come env.
            # Le env finiscono in `kubectl describe`, nei crash dump,
            # in /proc/<pid>/environ e nei log di chi le stampa.
          volumeMounts:
            - name: config
              mountPath: /etc/app
              readOnly: true
            - name: segreti
              mountPath: /run/secrets/db
              readOnly: true
          resources:
            requests: { cpu: 10m, memory: 16Mi }
            limits: { memory: 32Mi }
      volumes:
        - name: config
          configMap:
            name: app-config
            items:
              - key: app.properties
                path: app.properties
        - name: segreti
          secret:
            secretName: db
            defaultMode: 0400

# ── I SEGRETI IN GITOPS ─────────────────────────────────────────────────────
# Il problema: tutto sta in git tranne i Secret. Le risposte mature:
#   • External Secrets Operator   il cluster legge da Vault / AWS Secrets
#                                 Manager / GCP Secret Manager e crea il
#                                 Secret; in git c'è solo il riferimento
#                                 (ExternalSecret + SecretStore)
#   • Sealed Secrets              in git c'è un SealedSecret cifrato con la
#                                 chiave pubblica del controller nel cluster
#   • SOPS (+ age/KMS)            file YAML cifrati campo per campo,
#                                 decifrati da Argo CD/Flux o helm-secrets
#   • CSI Secrets Store driver    il segreto montato direttamente dal
#                                 provider come volume, senza Secret k8s
# In tutti i casi: rotazione, audit e revoca stanno nel vault, non nel
# cluster.
#
# In un laboratorio senza vault, il minimo decente:
#   secret.example.yaml   in git, valori finti, mostra le chiavi attese
#   secret.yaml           fuori da git (.gitignore), valori veri
# .gitignore non cancella la storia: una password già committata si CAMBIA.
# Su EKS: Secrets Manager + Pod Identity, poi External Secrets (→ Secret,
# usabile con envFrom) o CSI driver (→ file). Una rotazione non tocca le env
# dei container già avviati: serve un rollout.
#
# Laravel: ConfigMap per APP_ENV, APP_URL, DB_HOST…; Secret per APP_KEY,
# DB_PASSWORD, token. Entrambi con envFrom, senza .env nell'immagine.
# Con `php artisan config:cache` la cache va rifatta all'avvio del container,
# altrimenti fotografa i valori vecchi.
#   envFrom:
#     - configMapRef: { name: laravel-config }
#     - secretRef:    { name: laravel-secret }

# ── DOMANDE DA COLLOQUIO ────────────────────────────────────────────────────
# D: I Secret di Kubernetes sono sicuri?
# R: Di default no: base64 in etcd e leggibili da chiunque abbia `get` sui
#    secret o possa creare un Pod nel namespace (montandoli). Servono
#    cifratura at-rest (KMS), RBAC stretto, niente segreti in env, e una
#    fonte esterna con rotazione.
#
# D: Ho cambiato il ConfigMap ma l'app usa ancora il valore vecchio.
# R: Env: letta solo all'avvio. Volume con subPath: non si aggiorna mai.
#    Volume normale: aggiornato al sync del kubelet, ma l'app deve rileggerlo.
#    Soluzione robusta: config versionata (hash nel nome o checksum nel
#    template) così ogni cambio è un rollout tracciabile e reversibile.
#
# D: Perché un ConfigMap immutabile?
# R: Il kubelet non lo osserva più: meno watch sull'apiserver nei cluster
#    grandi, e nessuno può cambiarlo sotto i piedi a un'app in produzione.

# ══════════════════════════════════════════════════════════════════════════
# RIEPILOGO
# • ConfigMap e Secret: la config fuori dall'immagine
# • Secret = base64, non cifratura: servono KMS, RBAC e una fonte esterna
# • env mai aggiornate, volume sì (al sync del kubelet), subPath mai
# • Config versionata (checksum/hash) = ogni cambio è un rollout
# • GitOps: External Secrets, Sealed Secrets o SOPS, mai Secret in chiaro
# ══════════════════════════════════════════════════════════════════════════
````

### Fonte originale: `04-configmap-secret.sh`

> **Trascrizione integrale del file originale**, senza riscrittura. Questo blocco è una fonte di riferimento per il sito.

````bash
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
````

## Traccia per lo studio attivo

Prima di passare oltre: rileggi il manifest e lo script della lezione, individua il comando che produce l’osservazione principale, spiega perché il risultato è atteso, poi confronta la tua spiegazione con le riflessioni e le domande da colloquio del Markdown originale. Non applicare gli script a un cluster diverso dal laboratorio senza verificare i contesti.

---

<a id="lezione-05"></a>

# Lezione 05 — StatefulSet, storage persistente e PodDisruptionBudget

## Spiegazione e riflessioni ragionate

### Modello mentale del professore
I Pod di un Deployment sono intercambiabili; le repliche di uno StatefulSet possiedono **identità ordinate** (`db-0`, `db-1`, `db-2`) e possono avere **PVC distinti e stabili** tramite `volumeClaimTemplates`. La stabilità del PVC non implica che il disco fisico sia portabile fra nodi.

### Relazione fra le risorse
PVC = richiesta di storage; StorageClass = provisioning e policy; PV = volume concreto. `ReadWriteOnce` significa montabile in lettura-scrittura da un nodo alla volta, non necessariamente da un solo Pod; `ReadWriteOncePod` è più restrittivo; `ReadWriteMany` richiede un backend compatibile. `WaitForFirstConsumer` coordina provisioning e collocazione del primo Pod.

### Esperimenti fondamentali
- Il Service headless `db` (`clusterIP: None`) permette DNS per singoli ordinali: `db-0.db.lab.svc.cluster.local`. `publishNotReadyAddresses: true` aiuta discovery in bootstrap quando i membri devono trovarsi prima di diventare Ready.
- BusyBox scrive `$(hostname) avviato alle ...` in append su `/data/identita`. Eliminando `db-0`, il nuovo Pod usa il PVC `dati-db-0`: la seconda riga dimostra il riutilizzo del volume nel laboratorio.
- `OrderedReady` crea in ordine; `RollingUpdate.partition` consente update degli ordinali >= soglia (per esempio partition 2, solo `db-2` su tre repliche).
- `whenScaled: Retain` e `whenDeleted: Retain` conservano i PVC nelle rispettive operazioni. La `reclaimPolicy` del PV è un controllo distinto e può decidere il destino dello storage dopo la cancellazione di un PVC.

### PDB: cosa protegge e cosa no
`maxUnavailable: 1` limita le eviction volontarie di Pod sani quando il gruppo ha disponibilità adeguata; non protegge da crash fisici, da ogni comando di delete, né crea il quorum del database. `drain` cordona e tenta eviction; `uncordon` rende di nuovo il nodo schedulabile ma **non sposta indietro** i Pod. Il backend hostpath del Minikube può impedire la ricollocazione quando i dati sono locali.

### Verifica rapida
1. Che cosa resta stabile quando elimini un Pod StatefulSet?
2. `RWO` significa un Pod oppure un nodo?
3. Cosa accade ai PVC facendo scale 3→1→3 con `Retain`?
4. Perché un PDB può bloccare un drain?

## Materiale originale della lezione


### Fonte originale: `05-statefulset-storage-pdb.md`

> **Trascrizione integrale del file originale**, senza riscrittura. Questo blocco è una fonte di riferimento per il sito.

````markdown
# 05 — Stato: StatefulSet, volumi persistenti e PodDisruptionBudget

Spiegazione di `05-statefulset-storage-pdb.yaml` (questa cartella). Lezione sul sito: http://127.0.0.1:3000/kubernetes/5

## In una frase

Il file crea un finto database a **3 repliche** come **StatefulSet `db`**: ogni Pod ha un **nome fisso** (`db-0`,
`db-1`, `db-2`), un **record DNS suo** grazie a un **Service headless** e un **disco suo** (PVC) che lo segue. Un
**PodDisruptionBudget** impedisce che un drain ne spenga più di uno alla volta. Il runner cancella un Pod e mostra che
ritrova il disco, scala giù e su, e fa il **drain** del nodo `lab-m02`.

## Due file con lo stesso nome: quale lanciare

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/lezioni/kubernetes/05-statefulset-storage-pdb.yaml` | **questo**: i manifest, con la teoria nei commenti | si **legge**; lo applica il runner (o a mano: `kubectl apply -f 05-statefulset-storage-pdb.yaml`) |
| `~/kubernetesprj/kubernetes/05-statefulset-storage-pdb.sh` | lo script **guidato**: applica, cancella, scala, fa drain e uncordon, un passo per volta (Invio / s / q) | `bash kubernetes/05-statefulset-storage-pdb.sh` |

Il namespace `lab` deve esistere (lezione 02). Il drain richiede i **2 nodi** del lab (`lab` e `lab-m02`, lezione 01).

## Com'è fatto il file

```
intestazione (commenti)  → teoria: bestiame vs identità, catena dello storage, comandi LAB, NEL PROGETTO VERO
Service db (headless)    → clusterIP: None, record DNS per ogni Pod
StatefulSet db           → 3 repliche ordinate, anti-affinity, volumeClaimTemplates, retention dei PVC
PodDisruptionBudget db   → maxUnavailable 1
coda (commenti)          → domande da colloquio, riepilogo
```

Versione: Kubernetes 1.34–1.35 (lab 1.34.0), storage class di default di minikube: `standard`.

---

## 1. La teoria nell'intestazione

### Bestiame contro identità

Un **Deployment** tratta i Pod come bestiame: nomi casuali, intercambiabili, tutti sullo stesso volume (se c'è).
Un database a 3 nodi ha bisogno di altro:

| Bisogno | Come lo dà lo StatefulSet |
|---|---|
| **identità stabile** | `db-0`, `db-1`, `db-2`: lo stesso nome dopo un restart |
| **DNS stabile** | `db-0.db.lab.svc.cluster.local`, grazie al Service headless |
| **disco per replica** | ogni Pod il suo PVC, che resta legato al nome del Pod (ma sul lab vedi la trappola dell'hostpath `standard` con 2 nodi, più sotto) |
| **ordine** | crea 0→1→2, cancella 2→1→0 (`podManagementPolicy: OrderedReady`); `Parallel` se l'ordine non serve |

### La catena dello storage

```
PVC (richiesta: 1Gi RWO) ──▶ StorageClass (provisioner: driver CSI) ──▶ PV (il disco vero: EBS, PD, local-path…)
```

- **PVC** (PersistentVolumeClaim): la **richiesta** ("voglio 1Gi in lettura-scrittura").
- **StorageClass**: **come** procurarlo (quale provisioner, quali parametri).
- **PV** (PersistentVolume): il **disco vero**, creato dal provisioner e legato al PVC.

| Impostazione | Cosa decide |
|---|---|
| `volumeBindingMode: WaitForFirstConsumer` | il PV si crea **nella zona del nodo** dove lo scheduler mette il Pod. Senza: disco in zona A, Pod costretto in zona B = **Pending per sempre** |
| `reclaimPolicy` | `Delete` (default del provisioning dinamico: cancelli il PVC, sparisce il disco) o `Retain` (dati di produzione) |
| `accessModes` | `RWO` (un nodo) · `RWOP` (un Pod) · `RWX` (più nodi: NFS/CephFS/EFS) |

### I comandi LAB dell'intestazione

```bash
kubectl apply -f 05-statefulset-storage-pdb.yaml
kubectl -n lab rollout status sts/db
kubectl -n lab get pod,pvc -l app=db
kubectl -n lab exec db-0 -- cat /data/identita        # db-0 avviato alle…
kubectl -n lab delete pod db-0 && kubectl -n lab wait --for=condition=Ready pod/db-0
kubectl -n lab exec db-0 -- cat /data/identita        # due righe: stesso disco
kubectl -n lab run dns --rm -i --quiet --restart=Never --image=busybox:1.37 -- \
    nslookup db-1.db.lab.svc.cluster.local
kubectl -n lab scale sts/db --replicas=1              # i PVC di db-1/db-2 RESTANO
kubectl drain <nodo> --ignore-daemonsets              # il PDB frena lo sfratto
```

Due fatti riportati nei commenti (il secondo è marcato «provato»):

- `kubectl run` con `-it` **senza un terminale** perde l'output: per questo si usa `-i --quiet`.
- Il `nslookup` di **busybox con il nome corto dà NXDOMAIN**: serve il nome completo
  `db-1.db.lab.svc.cluster.local`.

### Riquadro «NEL PROGETTO VERO»

In `~/biodistretto/kubernetes` **mariadb, redis, elasticsearch e minio** sono quattro StatefulSet con
`volumeClaimTemplates` sulla storage class **`csi-hostpath-sc`**:

```bash
grep -n 'storageClassName' terraform/app/manifests/dati.yaml.tftpl
grep -n -A3 'variable "storage_class"' terraform/app/variables.tf
```

- **Perché non lo `standard` di minikube**: con 2 nodi il suo hostpath crea il volume su **un nodo solo**, e il Pod
  schedulato sull'altro nodo non lo vede.
- **Elasticsearch scrive come uid 1000**: `fsGroup` rende il volume suo.
  ```bash
  grep -n -B1 'fsGroup' terraform/app/manifests/dati.yaml.tftpl
  ```
- **Differenza con questa lezione**: qui il Service è headless (`clusterIP: None`); nel progetto i Service dei dati sono
  **ClusterIP**: con 1 replica basta il nome del Service, il DNS per singolo Pod non serve.
- **Da colloquio**: lì **niente PDB**, perché con 1 replica e `minAvailable: 1` il PDB bloccherebbe ogni drain del nodo.

---

## 2. Il Service headless `db`

```yaml
spec:
  clusterIP: None
  publishNotReadyAddresses: true
  selector: { app: db }
  ports:
    - name: tcp
      port: 5432
```

| Campo | Perché |
|---|---|
| `clusterIP: None` | **headless**: niente IP virtuale né bilanciamento. Il DNS risponde con **gli IP dei Pod** e crea un record per ognuno (`db-0.db…`, `db-1.db…`) |
| `publishNotReadyAddresses: true` | i record DNS esistono **anche prima** che i Pod siano pronti: in un cluster di database i peer devono trovarsi durante l'avvio, prima di essere "pronti" |
| `port: 5432` | la porta di Postgres, solo indicativa: il container è un busybox che dorme |

---

## 3. Lo StatefulSet `db` — campo per campo

### Identità e ordine

| Campo | Valore | Cosa fa |
|---|---|---|
| `serviceName` | `db` | il Service headless che **governa i nomi DNS** dei Pod |
| `replicas` | `3` | `db-0`, `db-1`, `db-2` |
| `podManagementPolicy` | `OrderedReady` | crea uno alla volta, ognuno quando il precedente è Ready; cancella in ordine inverso |

### Aggiornamento: `partition`

```yaml
updateStrategy:
  type: RollingUpdate
  rollingUpdate:
    partition: 0
```

Il rolling update di uno StatefulSet va dall'ordinale **più alto al più basso**. Con `partition: N > 0` vengono
aggiornati **solo gli ordinali ≥ N**: è un **canary manuale**, per esempio su `db-2` prima di toccare `db-0` (spesso il
primario). Con `0`, come qui, si aggiornano tutti.

### Che fine fanno i dati: `persistentVolumeClaimRetentionPolicy`

```yaml
persistentVolumeClaimRetentionPolicy:
  whenDeleted: Retain
  whenScaled: Retain
```

| Evento | `Retain` vuol dire |
|---|---|
| `whenDeleted` | cancelli lo StatefulSet: **i PVC (e i dati) restano** |
| `whenScaled` | scali giù: i PVC delle repliche tolte restano, pronti per lo scale up |

L'alternativa è `Delete`. Il runner lo prova al passo 8.

### Il Pod

```yaml
terminationGracePeriodSeconds: 10
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          topologyKey: kubernetes.io/hostname
          labelSelector:
            matchLabels: { app: db }
```

- **podAntiAffinity**: "non mettermi su un nodo dove c'è già un Pod `app: db`". `topologyKey: kubernetes.io/hostname`
  = il dominio è il **singolo nodo**.
- **preferred** (non `required`): è una **preferenza** con peso 100. Con 3 repliche e 2 nodi una regola `required`
  lascerebbe un Pod **Pending**; con `preferred` lo scheduler li sparpaglia finché può e poi ne mette due insieme.
- `IgnoredDuringExecution`: la regola vale solo quando il Pod viene schedulato, non sposta Pod già in esecuzione.

### Il container

```yaml
image: busybox:1.37
command:
  - sh
  - -c
  - |
    echo "$(hostname) avviato alle $(date +%T)" >> /data/identita
    exec sleep 1000000
volumeMounts:
  - name: dati
    mountPath: /data
resources:
  requests: { cpu: 10m, memory: 16Mi }
  limits: { memory: 32Mi }
```

A ogni avvio il container **aggiunge** (`>>`) una riga al file `/data/identita` con il suo hostname (= il nome del Pod)
e l'ora. Il file sta sul disco persistente: se il Pod rinasce con lo stesso disco, le righe si accumulano. È la prova
visiva che "il disco segue il nome". `exec sleep` sostituisce la shell con `sleep`, che diventa il processo 1 del container. Il processo 1 non ha i
gestori di segnale di default: `sleep` ignora il SIGTERM, e il Pod muore solo con il SIGKILL dopo
`terminationGracePeriodSeconds: 10`. Per questo un `delete pod db-0` impiega circa 10 secondi.

### `volumeClaimTemplates`

```yaml
volumeClaimTemplates:
  - metadata:
      name: dati
    spec:
      accessModes: [ReadWriteOnce]
      resources:
        requests:
          storage: 1Gi
```

È uno **stampo di PVC**: lo StatefulSet crea un PVC per ogni Pod, con nome `<template>-<pod>`: **`dati-db-0`,
`dati-db-1`, `dati-db-2`**. `storageClassName` è omesso → si usa la **classe di default** del cluster (`standard` su
minikube). Un Deployment non può farlo: tutte le repliche condividerebbero lo stesso PVC.

---

## 4. Il PodDisruptionBudget `db`

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
spec:
  maxUnavailable: 1
  selector:
    matchLabels: { app: db }
  unhealthyPodEvictionPolicy: AlwaysAllow
```

Un PDB protegge dalle interruzioni **volontarie**: drain dei nodi (upgrade del cluster, autoscaler che spegne un nodo),
chiamate all'**eviction API**. **Non** protegge da un nodo che muore né da un `kubectl delete pod` (che non passa
dall'eviction).

| Campo | Perché |
|---|---|
| `maxUnavailable: 1` | con 3 repliche e quorum 2, al massimo **1 Pod giù per volta** (equivale a `minAvailable: 2`) |
| `unhealthyPodEvictionPolicy: AlwaysAllow` | un Pod **già rotto** (non Ready) si può sfrattare comunque: non blocca il drain |

---

## 5. Il runner, passo per passo

`guardia_lab`, poi 14 passi:

| # | Comando | Cosa vedi |
|---|---|---|
| 1 | `kubectl apply -f …/05-statefulset-storage-pdb.yaml` | `service/db`, `statefulset.apps/db`, `poddisruptionbudget.policy/db` creati |
| 2 | `kubectl -n lab rollout status sts/db` | i Pod nascono **in ordine**: db-0, poi db-1, poi db-2 |
| 3 | `kubectl -n lab get pod,pvc -l app=db` | 3 Pod e 3 PVC `dati-db-0/1/2`, `Bound` |
| 4 | `kubectl -n lab exec db-0 -- cat /data/identita` | una riga: `db-0 avviato alle HH:MM:SS` |
| 5 | `delete pod db-0 && wait --for=condition=Ready pod/db-0 --timeout=120s` | lo StatefulSet ricrea un Pod con **lo stesso nome** |
| 6 | `exec db-0 -- cat /data/identita` | **due righe**: il Pod nuovo ha ritrovato il disco del vecchio |
| 7 | `kubectl -n lab run dns --rm -i --quiet --restart=Never --image=busybox:1.37 -- nslookup db-1.db.lab.svc.cluster.local` | l'IP di **db-1** (il nome completo è necessario con busybox) |
| 8 | `scale sts/db --replicas=1; sleep 10; get pod,pvc -l app=db` | restano solo db-0, ma **i PVC sono ancora 3** (`whenScaled: Retain`) |
| 9 | `scale sts/db --replicas=3 && rollout status sts/db` | db-1 e db-2 tornano e **ritrovano i loro PVC** |
| 10 | `get pdb db; kubectl drain lab-m02 --ignore-daemonsets --delete-emptydir-data --timeout=90s` | il PDB (ALLOWED DISRUPTIONS 1) e lo sfratto dei Pod da `lab-m02`, uno db alla volta. Se il PDB non lo consente, il drain **aspetta e riprova** |
| 11 | `kubectl get nodes; get pods -A -o wide --field-selector spec.nodeName=lab-m02` | `lab-m02` è `Ready,SchedulingDisabled` (cordon); sopra restano solo i Pod dei DaemonSet (calico, kube-proxy) |
| 12 | `get pod -l app=db -o wide; get pdb db` | tutte le repliche db sono sul nodo `lab`; il PDB è tornato a 1 disruption permessa. **Attenzione**: con l'hostpath `standard` su 2 nodi, una replica spostata da `lab-m02` potrebbe non ritrovare i dati scritti là (vedi trappole) |
| 13 | `kubectl uncordon lab-m02 && kubectl get nodes` | il nodo torna schedulabile |
| 14 | `get pod -l app=db -o wide` | **uncordon non riporta indietro i Pod**: restano dove sono. Il nodo riceverà solo Pod **nuovi** |

Opzioni del drain:

- `--ignore-daemonsets`: i Pod dei DaemonSet non si possono spostare (ce n'è uno per nodo); senza l'opzione il drain si
  rifiuta di partire.
- `--delete-emptydir-data`: accetta di perdere i dati dei volumi `emptyDir` dei Pod sfrattati.
- `--timeout=90s`: non aspettare all'infinito se il PDB blocca.

Il drain sfratta **tutti** i Pod di `lab-m02`, non solo i db: anche le repliche di `web` (lezione 02) vengono spostate.

Nessun passo fallisce apposta. Il passo 10 è quello dove "aspettare" è normale: se due db stanno su `lab-m02`, il
secondo viene sfrattato solo quando il primo è rinato Ready altrove.

---

## 6. Le trappole

| Trappola | Cosa succede | Rimedio |
|---|---|---|
| storage class senza `WaitForFirstConsumer` in multi-zona | disco in una zona, Pod nell'altra: Pending per sempre | `volumeBindingMode: WaitForFirstConsumer` |
| hostpath `standard` di minikube con 2 nodi | il Pod sull'altro nodo non vede il volume | driver CSI (`csi-hostpath-sc` nel progetto) |
| `podAntiAffinity` **required** con più repliche che nodi | Pod Pending | `preferred`, o più nodi |
| `nslookup` di busybox col nome corto | NXDOMAIN | nome completo `…svc.cluster.local` |
| `kubectl run -it` senza terminale | output perso | `-i --quiet` |
| PDB con `minAvailable` = repliche | drain e upgrade bloccati per sempre | `maxUnavailable: 1` |
| credere che il PDB protegga dai guasti | un nodo morto non chiede permesso | repliche su nodi/zone diversi |
| aspettarsi che `uncordon` ribilanci | i Pod restano dove sono | rollout restart o descheduler |
| `reclaimPolicy: Delete` sui dati veri | cancelli il PVC, perdi il disco | `Retain` + `whenDeleted: Retain` |

---

## 7. La coda: domande da colloquio

- **Database su Kubernetes: sì o no?** Si può, con un **operator maturo** (CloudNativePG, Percona, Strimzi per Kafka)
  che gestisce failover, backup e upgrade: lo StatefulSet da solo dà identità e disco, **non la replica né il
  failover**. Se il cloud offre il gestito (RDS, Cloud SQL) e il team è piccolo, di solito si sceglie quello: il punto è
  il costo operativo, non la fattibilità.
- **Un nodo muore. Cosa succede al Pod db-1?** Il nodo va `NotReady`; dopo il timeout di eviction (default ~5 min,
  toleration not-ready/unreachable) il Pod è marcato per la cancellazione ma **resta Terminating**: lo StatefulSet **non**
  crea un nuovo db-1 finché non è sicuro che il vecchio sia morto (garanzia "**al più uno**"). Con RWO il volume è
  ancora attaccato al nodo morto. Serve cancellare il nodo, o il taint `node.kubernetes.io/out-of-service`.
- **PDB con `minAvailable` uguale alle repliche?** Il drain si blocca per sempre, e con lui l'upgrade del cluster. Su
  GKE/EKS è una causa frequente di upgrade bloccati.
- **Come allarghi un PVC?** Se la StorageClass ha `allowVolumeExpansion: true`, modifichi
  `resources.requests.storage` del PVC. Nello StatefulSet `volumeClaimTemplates` è **immutabile**: si edita ogni PVC,
  poi si ricrea lo StatefulSet con `--cascade=orphan` (i Pod restano) per allineare il template.

### Comandi da sapere

| Comando | A cosa serve |
|---|---|
| `kubectl -n lab get pod,pvc -l app=db` | Pod e dischi insieme |
| `kubectl -n lab scale sts/db --replicas=1` | scalare uno StatefulSet (in ordine inverso) |
| `kubectl -n lab get pdb db` | quante interruzioni sono permesse ora |
| `kubectl drain <nodo> --ignore-daemonsets --delete-emptydir-data` | svuotare un nodo rispettando i PDB |
| `kubectl uncordon <nodo>` | riaprirlo allo scheduling |

---

## Riepilogo

- StatefulSet = **nome, DNS e disco stabili** per ogni replica.
- **Service headless** per i record DNS di ogni Pod.
- **PVC → StorageClass → PV**; `WaitForFirstConsumer` per le zone.
- **partition** per il canary, **PVC retention** per non perdere i dati.
- Il **PDB** protegge dai drain, non dai guasti; mai `minAvailable` = repliche.

## Prova da solo

1. Cambia il PDB in `minAvailable: 3` (e togli `maxUnavailable`), riapplica e rifai il drain di `lab-m02` con
   `--timeout=60s`: cosa ripete il drain, e come finisce? Poi `kubectl uncordon lab-m02` e rimetti il PDB.
2. Imposta `partition: 2`, cambia l'immagine in `busybox:1.36` e riapplica: quali Pod vengono ricreati? Controlla con
   `kubectl -n lab get pod -l app=db -o custom-columns='NOME:.metadata.name,IMG:.spec.containers[0].image'` (le virgolette servono in zsh, per via delle `[ ]`).
3. Cancella lo StatefulSet (`kubectl -n lab delete sts db`) e guarda `get pvc`: i PVC ci sono ancora? Riapplica il file
   e leggi `/data/identita` di db-0: quante righe?
````

### Fonte originale: `05-statefulset-storage-pdb.yaml`

> **Trascrizione integrale del file originale**, senza riscrittura. Questo blocco è una fonte di riferimento per il sito.

````yaml
# ═══════════════════════════════════════════════════════════════════════════
# 05. STATO: STATEFULSET, VOLUMI PERSISTENTI E PODDISRUPTIONBUDGET
# Versione: Kubernetes 1.34–1.35 (il lab minikube gira la 1.34.0) · storage class di default (minikube "standard")
# Livello: 2 — Stato e disponibilità
# ═══════════════════════════════════════════════════════════════════════════
# Un Deployment tratta i Pod come bestiame: nomi casuali, intercambiabili,
# tutti sullo stesso volume (se c'è). Un database a 3 nodi ha bisogno di:
#   • IDENTITÀ STABILE   db-0, db-1, db-2 — lo stesso nome dopo un restart
#   • DNS STABILE        db-0.db.lab.svc.cluster.local (Service headless)
#   • DISCO PER REPLICA  ogni Pod il suo PVC, che lo segue se cambia nodo
#   • ORDINE             crea 0→1→2, cancella 2→1→0 (podManagementPolicy
#                        OrderedReady); Parallel se l'ordine non serve
#
# CATENA DELLO STORAGE
#   PVC (richiesta: 1Gi RWO) ──▶ StorageClass (provisioner: driver CSI)
#                           ──▶ PV (il disco vero: EBS, PD, local-path…)
#   volumeBindingMode: WaitForFirstConsumer → il PV si crea nella zona
#   del nodo dove lo scheduler mette il Pod (senza: disco in zona A,
#   Pod costretto in zona B = Pending per sempre).
#   reclaimPolicy: Delete (default dinamico) | Retain (dati di produzione)
#   accessModes: RWO (un nodo) · RWOP (un Pod) · RWX (NFS/CephFS/EFS)
#
# LAB
#   kubectl apply -f 05-statefulset-storage-pdb.yaml
#   kubectl -n lab rollout status sts/db
#   kubectl -n lab get pod,pvc -l app=db
#   kubectl -n lab exec db-0 -- cat /data/identita        # db-0 avviato alle…
#   kubectl -n lab delete pod db-0 && kubectl -n lab wait --for=condition=Ready pod/db-0
#   kubectl -n lab exec db-0 -- cat /data/identita        # due righe: stesso disco
#   kubectl -n lab run dns --rm -i --quiet --restart=Never --image=busybox:1.37 -- \
#       nslookup db-1.db.lab.svc.cluster.local      # -it senza terminale perde l'output
#     ↑ nome completo: il nslookup di busybox con il nome corto dà NXDOMAIN (provato)
#   kubectl -n lab scale sts/db --replicas=1              # i PVC di db-1/db-2 RESTANO
#   kubectl drain <nodo> --ignore-daemonsets              # il PDB frena lo sfratto
#
# ── NEL PROGETTO VERO: il Biodistretto su minikube ───────────────────────
#   ~/biodistretto/kubernetes (branch kubernetes). I grep partono da lì:
#   cd ~/biodistretto/kubernetes · come si usa: il README della cartella
#   mariadb, redis, elasticsearch e minio sono quattro StatefulSet con
#   volumeClaimTemplates sulla storage class csi-hostpath-sc:
#     grep -n 'storageClassName' terraform/app/manifests/dati.yaml.tftpl
#     grep -n -A3 'variable "storage_class"' terraform/app/variables.tf
#   Perché non lo `standard` di minikube: con 2 nodi il suo hostpath crea il
#   volume su un nodo solo, e il Pod schedulato sull'altro nodo non lo vede.
#   Elasticsearch scrive come uid 1000: fsGroup rende il volume suo.
#     grep -n -B1 'fsGroup' terraform/app/manifests/dati.yaml.tftpl
#   DIFFERENZA con questa lezione: lì il Service è headless (clusterIP: None).
#   Nel progetto i Service dei dati sono ClusterIP: con 1 replica basta
#   il nome del Service, e il DNS per singolo Pod non serve.
#   DA COLLOQUIO: niente PDB, perché con 1 replica e minAvailable 1 il PDB
#   bloccherebbe ogni drain del nodo.

apiVersion: v1
kind: Service
metadata:
  name: db
  namespace: lab
spec:
  clusterIP: None              # headless: niente IP virtuale, record DNS per Pod
  publishNotReadyAddresses: true   # i peer si trovano anche prima di essere pronti
  selector: { app: db }
  ports:
    - name: tcp
      port: 5432
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: db
  namespace: lab
spec:
  serviceName: db              # il Service headless che governa i nomi DNS
  replicas: 3
  podManagementPolicy: OrderedReady
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      partition: 0             # >0 = aggiorna solo gli ordinali >= partition:
                               # canary manuale su db-2 prima di toccare il primario
  persistentVolumeClaimRetentionPolicy:
    whenDeleted: Retain        # cancello lo StatefulSet: i dati restano
    whenScaled: Retain         # scalo giù: i dati restano (per lo scale up)
  selector:
    matchLabels: { app: db }
  template:
    metadata:
      labels: { app: db }
    spec:
      terminationGracePeriodSeconds: 10
      affinity:
        podAntiAffinity:       # mai due repliche sullo stesso nodo (se possibile)
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                topologyKey: kubernetes.io/hostname
                labelSelector:
                  matchLabels: { app: db }
      containers:
        - name: db
          image: busybox:1.37
          command:
            - sh
            - -c
            - |
              echo "$(hostname) avviato alle $(date +%T)" >> /data/identita
              exec sleep 1000000
          ports:
            - { name: tcp, containerPort: 5432 }
          volumeMounts:
            - name: dati
              mountPath: /data
          resources:
            requests: { cpu: 10m, memory: 16Mi }
            limits: { memory: 32Mi }
  volumeClaimTemplates:        # un PVC per Pod: dati-db-0, dati-db-1, dati-db-2
    - metadata:
        name: dati
      spec:
        accessModes: [ReadWriteOnce]
        # storageClassName omesso = la classe di default del cluster
        resources:
          requests:
            storage: 1Gi
---
# ── PODDISRUPTIONBUDGET ─────────────────────────────────────────────────────
# Protegge dalle interruzioni VOLONTARIE: drain dei nodi (upgrade del
# cluster, autoscaler che spegne un nodo), eviction API. NON protegge da
# un nodo che muore o da un `kubectl delete pod`.
# Con 3 repliche e quorum 2: al massimo 1 Pod giù per volta.
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: db
  namespace: lab
spec:
  maxUnavailable: 1            # oppure minAvailable: 2
  selector:
    matchLabels: { app: db }
  unhealthyPodEvictionPolicy: AlwaysAllow   # un Pod già rotto non blocca il drain

# ── DOMANDE DA COLLOQUIO ────────────────────────────────────────────────────
# D: Database su Kubernetes: sì o no?
# R: Si può, con un operator maturo (CloudNativePG, Percona, Strimzi per
#    Kafka) che gestisce failover, backup e upgrade: lo StatefulSet da
#    solo dà identità e disco, non la replica né il failover. Se il cloud
#    offre il gestito (RDS, Cloud SQL) e il team è piccolo, di solito si
#    sceglie quello: il costo operativo è il punto, non la fattibilità.
#
# D: Un nodo muore. Cosa succede al Pod db-1?
# R: Il nodo va NotReady; dopo il timeout di eviction (default ~5 min,
#    toleration not-ready/unreachable) il Pod è marcato per la
#    cancellazione ma resta Terminating: lo StatefulSet NON crea un nuovo
#    db-1 finché non è sicuro che il vecchio sia morto (garanzia "al più
#    uno"). Con RWO il volume è ancora attaccato al nodo morto. Serve
#    cancellare il nodo, o il taint node.kubernetes.io/out-of-service.
#
# D: PDB con minAvailable uguale alle repliche?
# R: Il drain si blocca per sempre e l'upgrade del cluster pure.
#    Su GKE/EKS è una causa frequente di upgrade bloccati.
#
# D: Come allarghi un PVC?
# R: Se la StorageClass ha allowVolumeExpansion: true, modifichi
#    resources.requests.storage del PVC. Nello StatefulSet il
#    volumeClaimTemplates è immutabile: si edita ogni PVC, poi si ricrea lo
#    StatefulSet con --cascade=orphan per allineare il template.

# ══════════════════════════════════════════════════════════════════════════
# RIEPILOGO
# • StatefulSet = nome, DNS e disco stabili per ogni replica
# • Service headless per i record DNS di ogni Pod
# • PVC → StorageClass → PV; WaitForFirstConsumer per le zone
# • partition per il canary, PVC retention per non perdere i dati
# • PDB protegge dai drain, non dai guasti; mai minAvailable = repliche
# ══════════════════════════════════════════════════════════════════════════
````

### Fonte originale: `05-statefulset-storage-pdb.sh`

> **Trascrizione integrale del file originale**, senza riscrittura. Questo blocco è una fonte di riferimento per il sito.

````bash
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
````

## Traccia per lo studio attivo

Prima di passare oltre: rileggi il manifest e lo script della lezione, individua il comando che produce l’osservazione principale, spiega perché il risultato è atteso, poi confronta la tua spiegazione con le riflessioni e le domande da colloquio del Markdown originale. Non applicare gli script a un cluster diverso dal laboratorio senza verificare i contesti.

---

<a id="lezione-06"></a>

# Lezione 06 — Scheduling, affinity, taint e autoscaling HPA

## Spiegazione e riflessioni ragionate

### Modello mentale del professore
Due domande diverse: **DOVE** eseguire i nuovi Pod? Risponde il kube-scheduler. **QUANTI** Pod desiderare? Nel laboratorio risponde l'HPA. Un HPA che chiede otto repliche non garantisce la presenza di otto Pod schedulabili o pronti.

### Lo scheduling
Il scheduler prima **filtra** i nodi che violano vincoli obbligatori, poi attribuisce punteggi ai nodi eleggibili. `nodeSelector` e `required nodeAffinity` impongono condizioni; `preferred nodeAffinity` esprime preferenze. Un taint respinge Pod non tolleranti; una toleration **non attrae** il Pod sul nodo. `NoSchedule` riguarda nuove assegnazioni, `NoExecute` può sfrattare Pod già presenti. `topologySpreadConstraints` cerca di distribuire gruppi omogenei su nodi o zone; `ScheduleAnyway` è preferenza, `DoNotSchedule` è vincolo. PriorityClass può influire sullo scheduling e sulla preemption, non assegna CPU in più.

### Il calcolo HPA
Nel Deployment `api`, `requests.cpu=20m`; con target `averageUtilization=60`, il riferimento è `12m` di CPU media per Pod. Formula concettuale: `ceil(replicheCorrenti × utilizzoAttuale / utilizzoTarget)`, soggetta a min/max, tolleranze, metriche mancanti e behavior. Nell'esempio misurato `375%/60%` con due repliche produce 13 teoriche, poi `maxReplicas=8`. Il materiale osserva 2→4→8 per la policy di scale-up.

### Behavior e dipendenze
Scale-up può essere rapido (100% in 15 s nella policy); scale-down è stabilizzato e limitato (1 Pod per 60 s e finestra 120 s nel materiale). Serve metrics-server e la CPU request; un `TARGETS <unknown>` richiede verifiche sulle metriche e sui denominatori. Il generatore di traffico ha `ruolo=client` per attraversare la NetworkPolicy della Lezione 03.

### Verifica rapida
1. Che differenza c'è fra taint e toleration?
2. `NoSchedule` espelle i Pod già presenti?
3. Perché HPA usa la request CPU, non il limit?
4. Che cosa accade se HPA vuole otto Pod ma nessun nodo ha spazio?

## Materiale originale della lezione


### Fonte originale: `06-scheduling-autoscaling.md`

> **Trascrizione integrale del file originale**, senza riscrittura. Questo blocco è una fonte di riferimento per il sito.

````markdown
# 06 — Scheduling e autoscaling: dove girano i Pod e quanti

Spiegazione di `06-scheduling-autoscaling.yaml` (questa cartella). Lezione sul sito: http://127.0.0.1:3000/kubernetes/6

## In una frase

Il file crea un Deployment **`api`** (whoami) che lo scheduler **distribuisce sui due nodi** (topology spread), con una
**priorità alta** (PriorityClass), una **toleration** per un taint e una nodeAffinity "morbida"; davanti un Service e una
NetworkPolicy; e un **HorizontalPodAutoscaler** che ne decide il numero (da 2 a 8) in base alla CPU. Il runner genera
carico, guarda l'HPA salire, poi prova un **taint** sul nodo `lab-m02`.

## Due file con lo stesso nome: quale lanciare

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/lezioni/kubernetes/06-scheduling-autoscaling.yaml` | **questo**: i manifest, con la teoria nei commenti | si **legge**; lo applica il runner (o a mano: `kubectl apply -f 06-scheduling-autoscaling.yaml`) |
| `~/kubernetesprj/kubernetes/06-scheduling-autoscaling.sh` | lo script **guidato**: applica, carica, osserva l'HPA, mette e toglie il taint, un passo per volta (Invio / s / q) | `bash kubernetes/06-scheduling-autoscaling.sh` |

Servono il namespace `lab` (lezione 02), l'addon **metrics-server** e i **2 nodi** (lezione 01).

## Com'è fatto il file

```
intestazione (commenti)        → teoria: DOVE (scheduling) e QUANTI (autoscaling), formula dell'HPA,
                                 comandi LAB, NEL PROGETTO VERO
PriorityClass lab-critico      → priorità 100000, può espellere Pod meno importanti
Service api                    → porta 80 → 8080
NetworkPolicy api-allow-client → api accetta solo da ruolo=client
Deployment api                 → senza replicas; spread, priorità, toleration, nodeAffinity, requests
HorizontalPodAutoscaler api    → 2-8 repliche al 60% della CPU, con behavior
coda (commenti)                → domande da colloquio, riepilogo
```

Versione: Kubernetes 1.34–1.35 (lab 1.34.0), `autoscaling/v2`, metrics-server.

---

## 1. La teoria nell'intestazione

### DOVE: come lo scheduler sceglie il nodo

Lo scheduler prima **filtra** i nodi (scarta quelli che non vanno), poi dà un **punteggio** agli altri. Gli strumenti,
dal più rigido al più morbido:

| Strumento | Cosa fa |
|---|---|
| `nodeSelector` | etichetta del nodo **obbligatoria** |
| `nodeAffinity` required / preferred | espressioni (`In`, `NotIn`, `Exists`…), obbligatorie o solo preferite |
| taints + tolerations | è il **nodo** che respinge chi non tollera: nodi GPU, nodi dedicati, control plane |
| `podAntiAffinity` | non accanto a un altro Pod (per label) — lezione 05 |
| `topologySpreadConstraints` | distribuzione uniforme su zone/nodi, con `maxSkew`: la scelta moderna per l'HA |
| `PriorityClass` | chi viene prima; se manca spazio, i Pod a priorità bassa vengono **espulsi** |

Differenza chiave: **affinity attrae** (il Pod sceglie il nodo), **taint respinge** (il nodo sceglie i Pod).

### QUANTI: tre autoscaler, tre domande diverse

| Autoscaler | Domanda | Note |
|---|---|---|
| **HPA** | quante **repliche** | CPU, memoria, metriche custom/esterne |
| **VPA** | quante **risorse** per replica (requests) | non mischiarlo con un HPA sulla stessa metrica CPU |
| **Cluster Autoscaler / Karpenter** | quanti **nodi** | aggiunge nodi quando ci sono Pod Pending per risorse, li toglie quando sono sottoutilizzati |
| **KEDA** | HPA guidato da **eventi** | lunghezza di una coda, lag Kafka, cron; anche fino a **zero** repliche |

### La formula dell'HPA

```
desiderate = ceil(attuali × valoreAttuale / target)
```

La percentuale di CPU è riferita alle **requests** del container: **senza requests** l'HPA mostra `<unknown>`, perché
manca il denominatore.

### I comandi LAB dell'intestazione

```bash
kubectl apply -f 06-scheduling-autoscaling.yaml
kubectl -n lab get pod -l app=api -o wide          # distribuiti sui nodi
kubectl -n lab get hpa api -w                      # TARGETS: x%/60%
kubectl -n lab run carico --rm -it --image=busybox:1.37 --labels=ruolo=client -- \
    sh -c 'while true; do wget -q -O- http://api/ >/dev/null; done'
(Ctrl+C ferma il carico; con --rm il Pod sparisce da solo)
kubectl -n lab describe hpa api                    # eventi di scala
kubectl top pod -n lab
kubectl taint nodes lab-m02 dedicato=batch:NoSchedule   # poi rimuovilo con "-"
```

Il runner fa lo stesso ma con un carico **in background e a tempo** (120 s), così non serve un secondo terminale.

### Riquadro «NEL PROGETTO VERO»

In `~/biodistretto/kubernetes`:

- backend, frontend e nginx usano **`topologySpreadConstraints` su hostname, con `maxSkew 1`**. Con 2 repliche e 2 nodi
  ne va una per nodo. Con `ScheduleAnyway`, se un nodo è giù il Pod parte comunque sull'altro.
  ```bash
  grep -n -A6 'topologySpreadConstraints' terraform/app/manifests/app.yaml.tftpl
  ```
- metrics-server è un addon del cluster, quindi un HPA funzionerebbe:
  ```bash
  grep -n 'metrics-server' terraform/cluster/variables.tf
  ```
- **TRAPPOLA**: le repliche le decide Terraform (`repliche_web`). Se aggiungi un HPA, **Terraform e HPA si contendono
  `spec.replicas`**, e ogni apply riporta il numero al valore del codice. Con l'HPA, toglilo dal template.

---

## 2. La PriorityClass `lab-critico`

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: lab-critico
value: 100000
preemptionPolicy: PreemptLowerPriority
globalDefault: false
description: "Servizi che devono restare su anche a cluster pieno"
```

| Campo | Perché |
|---|---|
| nessun `namespace` | la PriorityClass è un oggetto **di cluster**, vale per tutti i namespace |
| `value: 100000` | più alto = più importante. I Pod senza classe hanno priorità 0 |
| `preemptionPolicy: PreemptLowerPriority` | se un Pod `lab-critico` non trova posto, lo scheduler può **espellere** Pod a priorità più bassa per fargli spazio (l'altra scelta è `Never`) |
| `globalDefault: false` | non viene assegnata automaticamente ai Pod che non la chiedono |

---

## 3. Service e NetworkPolicy

```yaml
kind: Service
spec:
  selector: { app: api }
  ports:
    - port: 80
      targetPort: 8080
```

Service ClusterIP (il tipo di default) che porta `api:80` sulla 8080 dei Pod. Qui `targetPort` è un **numero**, non un
nome come nella lezione 03: funziona, ma se cambiasse la porta del container andrebbe cambiato anche qui.

```yaml
kind: NetworkPolicy
metadata:
  name: api-allow-client
spec:
  podSelector:
    matchLabels: { app: api }
  ingress:
    - from:
        - podSelector:
            matchLabels: { ruolo: client }
```

- Se la lezione 03 è applicata, nel namespace c'è già il **default deny** in ingresso: senza questa policy nessuno
  potrebbe chiamare `api`, nemmeno il generatore di carico.
- `policyTypes` è omesso: con una sezione `ingress` presente, Kubernetes la considera una policy di tipo `Ingress`.
- Nessuna `ports`: da `ruolo=client` si entra su **tutte** le porte.
- Per questo il Pod `carico` del runner ha `--labels=ruolo=client`.

---

## 4. Il Deployment `api` — campo per campo

### Niente `replicas`

```yaml
spec:
  # niente "replicas": con un HPA il numero lo decide lui
```

Se lasci `replicas` nel manifest, ogni `kubectl apply` lo riporta al valore del file e l'HPA lo rialza: **flapping**.
È la stessa trappola del riquadro Terraform. Senza il campo, il Deployment nasce con 1 replica e l'HPA la porta subito
al suo minimo (2).

### `priorityClassName: lab-critico`

Collega i Pod alla PriorityClass della sezione 2.

### `topologySpreadConstraints`

```yaml
- maxSkew: 1
  topologyKey: kubernetes.io/hostname    # in cloud: topology.kubernetes.io/zone
  whenUnsatisfiable: ScheduleAnyway      # DoNotSchedule = vincolo rigido
  labelSelector:
    matchLabels: { app: api }
```

| Campo | Significato |
|---|---|
| `topologyKey: kubernetes.io/hostname` | il "dominio" è il singolo nodo. In cloud si usa la **zona** |
| `labelSelector` | quali Pod contare: quelli `app: api` |
| `maxSkew: 1` | la differenza fra il dominio con più Pod e quello con meno non deve superare 1 (es. 4 e 4, o 5 e 4, mai 6 e 3) |
| `whenUnsatisfiable: ScheduleAnyway` | se non si riesce, il Pod parte lo stesso (lo spread diventa un punteggio). `DoNotSchedule` lo lascerebbe Pending |

A differenza della `podAntiAffinity` (lezione 05), lo spread funziona bene anche con **più repliche che nodi**: con 8
repliche e 2 nodi ne mette 4 e 4.

### `tolerations`

```yaml
- key: dedicato
  operator: Equal
  value: batch
  effect: NoSchedule
```

Il Pod **tollera** i nodi con taint `dedicato=batch:NoSchedule`, ma **non li richiede**. Il commento del file è il
punto: per **forzare** un Pod su un nodo dedicato servono **toleration + nodeAffinity insieme** (la toleration toglie il
divieto, l'affinity crea l'attrazione).

### `nodeAffinity` preferita

```yaml
nodeAffinity:
  preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 50
      preference:
        matchExpressions:
          - key: kubernetes.io/os
            operator: In
            values: [linux]
```

Una **preferenza** (peso 50) per i nodi con label `kubernetes.io/os=linux`. Nel lab tutti i nodi sono Linux, quindi non
cambia niente: è lì per mostrare la sintassi di `matchExpressions`.

### Container, risorse e probe

```yaml
image: traefik/whoami:v1.12
args: ["--port", "8080"]
resources:
  requests: { cpu: 20m, memory: 16Mi }    # base del calcolo HPA
  limits: { memory: 32Mi }
readinessProbe:
  httpGet: { path: /health, port: 8080 }
```

La **request di CPU di 20m** è il denominatore dell'HPA: il 60% di 20m = **12m** medi per Pod. Basta pochissimo carico
per superarla, ed è voluto: così nel lab l'HPA sale in fretta. La readiness fa entrare nel Service solo i Pod pronti.

---

## 5. L'HorizontalPodAutoscaler `api`

```yaml
scaleTargetRef:
  apiVersion: apps/v1
  kind: Deployment
  name: api
minReplicas: 2
maxReplicas: 8
metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 60
```

| Campo | Significato |
|---|---|
| `scaleTargetRef` | cosa scalare: il Deployment `api` (l'HPA scrive il suo `spec.replicas`) |
| `minReplicas` / `maxReplicas` | mai meno di 2, mai più di 8 |
| `type: Resource`, `cpu`, `Utilization 60` | obiettivo: CPU media **pari al 60% delle requests** |

### `behavior`: evitare le oscillazioni

```yaml
behavior:
  scaleUp:
    stabilizationWindowSeconds: 0
    policies:
      - { type: Percent, value: 100, periodSeconds: 15 }
  scaleDown:
    stabilizationWindowSeconds: 120
    policies:
      - { type: Pods, value: 1, periodSeconds: 60 }
```

| Direzione | Regola | Effetto |
|---|---|---|
| su | finestra 0, +100% ogni 15 s | sale **subito**, al massimo **raddoppiando** ogni 15 s |
| giù | finestra 120 s, 1 Pod ogni 60 s | scende solo se il calo dura **2 minuti**, e un Pod al minuto |

Salire in fretta e scendere piano: un picco breve non fa partire un ping-pong di Pod.

---

## 6. Il runner, passo per passo

`guardia_lab`, poi 10 passi e una `nota`:

| # | Comando | Cosa vedi |
|---|---|---|
| 1 | `kubectl apply -f …/06-scheduling-autoscaling.yaml` | `priorityclass…/lab-critico`, `service/api`, `networkpolicy…/api-allow-client`, `deployment.apps/api`, `horizontalpodautoscaler…/api` |
| 2 | `kubectl -n lab get pod -l app=api -o wide` | colonna NODE: i Pod distribuiti su `lab` e `lab-m02` |
| 3 | ciclo `for i in $(seq 30); do kubectl top pod … && break; sleep 5; done; kubectl top pod -n lab -l app=api` | attende fino a 150 s che metrics-server abbia le metriche (i Pod nuovi le hanno dopo **~1 minuto**; finché mancano l'HPA non decide), poi CPU e memoria per Pod |
| 4 | `kubectl -n lab run carico --restart=Never --image=busybox:1.37 --labels=ruolo=client -- sh -c '…120 s di wget su http://api/…'` | parte il Pod di carico, in background (niente `-i`): il runner va avanti |
| 5 | `timeout 90 kubectl -n lab get hpa api -w \|\| true` | per 90 s: TARGETS sale sopra `60%`, REPLICAS aumenta. `timeout` chiude il `-w`; `\|\| true` evita il rosso per l'uscita di timeout |
| 6 | `get deploy api -o jsonpath='{…requests}'; echo; top pod -l app=api` | `{"cpu":"20m","memory":"16Mi"}` e il consumo reale dei Pod |
| — | `nota` | il fatto **misurato sul lab** (sotto) |
| 7 | `kubectl -n lab describe hpa api \| tail -15` | gli eventi `SuccessfulRescale` con il motivo ("cpu resource utilization … above target") |
| 8 | `kubectl taint nodes lab-m02 dedicato=batch:NoSchedule; describe node lab-m02 \| grep -A2 Taints` | il taint sul nodo. `NoSchedule`: i Pod **già** lì restano (con `NoExecute` verrebbero espulsi) |
| 9 | `kubectl taint nodes lab-m02 dedicato=batch:NoSchedule-` | il **trattino finale** = rimuovi |
| 10 | `kubectl -n lab delete pod carico --ignore-not-found` | pulizia. L'HPA riscende da solo: dopo 120 s di calo, un Pod al minuto |

### Il fatto misurato (la `nota`)

> Esempio misurato sul lab: TARGETS **375%** = **75m per Pod** su 20m di request.
> desiderate = ceil(2 × 375 / 60) = **13** → tagliate a **maxReplicas 8**; la policy **+100% ogni 15 s** le fa salire
> **2 → 4 → 8**.

È la formula dell'intestazione applicata ai numeri veri: la formula chiederebbe 13, il `maxReplicas` taglia a 8, e il
`behavior.scaleUp` impone il ritmo (raddoppio ogni 15 s).

Nessun passo fallisce apposta. Da notare al passo 8: il Deployment `api` ha **proprio** la toleration
`dedicato=batch:NoSchedule`, quindi i **suoi** Pod nuovi possono ancora andare su `lab-m02`; il taint respinge gli
altri (per esempio i Pod di `web` della lezione 02).

---

## 7. Le trappole

| Trappola | Cosa succede | Rimedio |
|---|---|---|
| container senza requests di CPU | HPA `<unknown>/60%` | requests sempre, sono il denominatore |
| metrics-server assente o appena partito | HPA `<unknown>` | addon attivo; aspettare ~1 minuto |
| `replicas` nel manifest con un HPA | ogni apply lo riporta al valore del file (flapping) | toglierlo dal manifest (o dal template Terraform) |
| toleration pensata come "vai su quel nodo" | il Pod può andarci, non è obbligato | toleration + nodeAffinity |
| `DoNotSchedule` con un nodo giù | Pod Pending | `ScheduleAnyway` se la disponibilità conta più della simmetria |
| VPA e HPA sulla stessa metrica CPU | si combattono | VPA in modo "Off" come raccomandatore |
| default deny della lezione 03 senza policy per api | il carico non arriva, l'HPA non sale | `api-allow-client` + label `ruolo=client` |
| taint `NoSchedule` aspettandosi lo sgombero | i Pod già presenti restano | `NoExecute` o un drain |

---

## 8. La coda: domande da colloquio

- **Un Pod è Pending. Cause possibili?** `kubectl describe pod` → eventi `FailedScheduling`: "Insufficient cpu"
  (requests troppo alte o cluster pieno: lì entra l'autoscaler dei nodi), "didn't tolerate taint", "didn't match node
  affinity", "unbound PersistentVolumeClaim", vincolo di spread `DoNotSchedule`.
- **L'HPA mostra `<unknown>/60%`.** metrics-server assente o non pronto, oppure il container non ha requests di CPU (la
  percentuale non ha un denominatore).
- **Requests e limits: come le dimensioni?** Dai dati, non a occhio: p95 dell'uso reale (Prometheus, VPA in modo "Off"
  come raccomandatore) per le requests, margine per i picchi. Requests troppo basse = nodi sovraffollati e sfratti;
  troppo alte = cluster pagato e vuoto.
- **`topologySpreadConstraints` o `podAntiAffinity`?** L'anti-affinity dice "non insieme" (sì/no) e non scala bene oltre
  una replica per nodo. Lo spread dice "distribuiti con skew massimo N": funziona con più repliche che nodi ed è più
  leggero da calcolare.

### Comandi da sapere

| Comando | A cosa serve |
|---|---|
| `kubectl -n lab get hpa api -w` | TARGETS e REPLICAS in tempo reale |
| `kubectl -n lab describe hpa api` | gli eventi e il motivo di ogni scala |
| `kubectl top pod -n lab` | consumo reale (da metrics-server) |
| `kubectl taint nodes lab-m02 dedicato=batch:NoSchedule` / `…NoSchedule-` | mettere / togliere un taint |
| `kubectl describe node lab-m02 \| grep -A2 Taints` | i taint di un nodo |

---

## Riepilogo

- **Dove**: nodeSelector/affinity attraggono, taint respingono, spread distribuisce.
- **PriorityClass** decide chi resta quando manca spazio.
- **HPA** (repliche), **VPA** (risorse), **Cluster Autoscaler/Karpenter** (nodi), **KEDA** (eventi).
- HPA in **% delle requests**; `behavior` per evitare oscillazioni.
- Con un HPA, **niente `replicas`** nel manifest.

## Prova da solo

1. Rifai il conto della `nota` con i tuoi numeri: leggi TARGETS durante il carico e calcola
   `ceil(attuali × valore / 60)`. Torna con il numero di REPLICAS che l'HPA ha scelto? Se no, che cosa lo ha limitato?
2. Metti il taint `dedicato=batch:NoSchedule` su `lab-m02`, poi `kubectl -n lab rollout restart deploy/web` (lezione
   02): dove finiscono i Pod di `web`? E i Pod nuovi di `api` (`rollout restart deploy/api`)? Perché la differenza?
   Togli il taint alla fine.
3. Togli `requests.cpu` dal container `api`, riapplica e guarda `kubectl -n lab get hpa api`: che cosa mostra TARGETS?
   Rimetti la request.
````

### Fonte originale: `06-scheduling-autoscaling.yaml`

> **Trascrizione integrale del file originale**, senza riscrittura. Questo blocco è una fonte di riferimento per il sito.

````yaml
# ═══════════════════════════════════════════════════════════════════════════
# 06. SCHEDULING E AUTOSCALING: DOVE GIRANO I POD E QUANTI
# Versione: Kubernetes 1.34–1.35 (il lab minikube gira la 1.34.0) · autoscaling/v2 · metrics-server
# Livello: 2 — Stato e disponibilità
# ═══════════════════════════════════════════════════════════════════════════
# DOVE: lo scheduler filtra i nodi e poi dà un punteggio. Gli strumenti,
# dal più rigido al più morbido:
#   nodeSelector                   etichetta del nodo obbligatoria
#   nodeAffinity required/preferred  espressioni (In, NotIn, Exists…)
#   taints + tolerations           il NODO respinge chi non tollera:
#                                  nodi GPU, nodi dedicati, control plane
#   podAntiAffinity                non accanto a un altro Pod (per label)
#   topologySpreadConstraints      distribuzione uniforme su zone/nodi,
#                                  con maxSkew: la scelta moderna per l'HA
#   PriorityClass                  chi viene prima; se manca spazio, i
#                                  Pod a priorità bassa vengono espulsi
#
# QUANTI: tre autoscaler, tre domande diverse
#   HPA  quante REPLICHE (CPU, memoria, metriche custom/esterne)
#   VPA  quante RISORSE per replica (requests); non mischiarlo con un HPA
#        sulla stessa metrica CPU
#   Cluster Autoscaler / Karpenter  quanti NODI: aggiunge nodi quando ci
#        sono Pod Pending per risorse, li toglie quando sono sottoutilizzati
#   KEDA  HPA guidato da eventi (lunghezza di una coda, lag Kafka, cron),
#        anche fino a zero repliche
#
# L'HPA calcola: desiderate = ceil(attuali × valoreAttuale / target)
#   la percentuale CPU è riferita alle REQUESTS: senza requests → <unknown>
#
# LAB (minikube con l'addon metrics-server; 2 nodi)
#   kubectl apply -f 06-scheduling-autoscaling.yaml
#   kubectl -n lab get pod -l app=api -o wide          # distribuiti sui nodi
#   kubectl -n lab get hpa api -w                      # TARGETS: x%/60%
#   kubectl -n lab run carico --rm -it --image=busybox:1.37 --labels=ruolo=client -- \
#       sh -c 'while true; do wget -q -O- http://api/ >/dev/null; done'
#   (Ctrl+C ferma il carico; con --rm il Pod sparisce da solo)
#   kubectl -n lab describe hpa api                    # eventi di scala
#   kubectl top pod -n lab
#   kubectl taint nodes lab-m02 dedicato=batch:NoSchedule   # poi rimuovilo con "-"
#
# ── NEL PROGETTO VERO: il Biodistretto su minikube ───────────────────────
#   ~/biodistretto/kubernetes (branch kubernetes). I grep partono da lì:
#   cd ~/biodistretto/kubernetes · come si usa: il README della cartella
#   backend, frontend e nginx usano topologySpreadConstraints su hostname,
#   con maxSkew 1. Con 2 repliche e 2 nodi ne va una per nodo. Con
#   ScheduleAnyway, se un nodo è giù il Pod parte comunque sull'altro.
#     grep -n -A6 'topologySpreadConstraints' terraform/app/manifests/app.yaml.tftpl
#   metrics-server è un addon del cluster, quindi un HPA funzionerebbe:
#     grep -n 'metrics-server' terraform/cluster/variables.tf
#   TRAPPOLA: le repliche le decide Terraform (repliche_web). Se aggiungi un
#   HPA, Terraform e HPA si contendono spec.replicas, e ogni apply riporta
#   il numero al valore del codice. Con l'HPA, toglilo dal template.

apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: lab-critico
value: 100000
preemptionPolicy: PreemptLowerPriority
globalDefault: false
description: "Servizi che devono restare su anche a cluster pieno"
---
apiVersion: v1
kind: Service
metadata:
  name: api
  namespace: lab
spec:
  selector: { app: api }
  ports:
    - port: 80
      targetPort: 8080
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-allow-client
  namespace: lab
spec:
  podSelector:
    matchLabels: { app: api }
  ingress:
    - from:
        - podSelector:
            matchLabels: { ruolo: client }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: lab
spec:
  # niente "replicas": con un HPA il numero lo decide lui; se lo lasci,
  # ogni `kubectl apply` lo riporta al valore del file (flapping)
  selector:
    matchLabels: { app: api }
  template:
    metadata:
      labels: { app: api }
    spec:
      priorityClassName: lab-critico
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname    # in cloud: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway      # DoNotSchedule = vincolo rigido
          labelSelector:
            matchLabels: { app: api }
      tolerations:
        # tollera i nodi "dedicato=batch" ma non li richiede: per FORZARE
        # un nodo servono toleration + nodeAffinity insieme
        - key: dedicato
          operator: Equal
          value: batch
          effect: NoSchedule
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 50
              preference:
                matchExpressions:
                  - key: kubernetes.io/os
                    operator: In
                    values: [linux]
      containers:
        - name: api
          image: traefik/whoami:v1.12
          args: ["--port", "8080"]
          ports:
            - containerPort: 8080
          resources:
            requests: { cpu: 20m, memory: 16Mi }    # base del calcolo HPA
            limits: { memory: 32Mi }
          readinessProbe:
            httpGet: { path: /health, port: 8080 }
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api
  namespace: lab
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api
  minReplicas: 2
  maxReplicas: 8
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 60
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0        # sali subito
      policies:
        - { type: Percent, value: 100, periodSeconds: 15 }   # al più raddoppia
    scaleDown:
      stabilizationWindowSeconds: 120      # scendi solo se il calo dura 2 min
      policies:
        - { type: Pods, value: 1, periodSeconds: 60 }        # un Pod al minuto

# ── DOMANDE DA COLLOQUIO ────────────────────────────────────────────────────
# D: Un Pod è Pending. Cause possibili?
# R: `kubectl describe pod` → eventi FailedScheduling: "Insufficient cpu"
#    (requests troppo alte o cluster pieno: lì entra l'autoscaler dei
#    nodi), "didn't tolerate taint", "didn't match node affinity",
#    "unbound PersistentVolumeClaim", vincolo di spread DoNotSchedule.
#
# D: L'HPA mostra <unknown>/60%.
# R: metrics-server assente o non pronto, oppure il container non ha
#    requests di CPU (la percentuale non ha un denominatore).
#
# D: Requests e limits: come le dimensioni?
# R: Dai dati, non a occhio: p95 dell'uso reale (Prometheus, VPA in modo
#    "Off" come raccomandatore) per le requests, margine per i picchi.
#    Requests troppo basse = nodi sovraffollati e sfratti; troppo alte =
#    cluster pagato e vuoto.
#
# D: topologySpreadConstraints o podAntiAffinity?
# R: L'anti-affinity dice "non insieme" (sì/no), non scala bene oltre
#    una replica per nodo. Lo spread dice "distribuiti con skew massimo
#    N": funziona con più repliche che nodi ed è più leggero da calcolare.

# ══════════════════════════════════════════════════════════════════════════
# RIEPILOGO
# • Dove: nodeSelector/affinity attraggono, taint respingono, spread distribuisce
# • PriorityClass decide chi resta quando manca spazio
# • HPA (repliche), VPA (risorse), Cluster Autoscaler/Karpenter (nodi), KEDA (eventi)
# • HPA in % delle requests; behavior per evitare oscillazioni
# • Con un HPA, niente "replicas" nel manifest
# ══════════════════════════════════════════════════════════════════════════
````

### Fonte originale: `06-scheduling-autoscaling.sh`

> **Trascrizione integrale del file originale**, senza riscrittura. Questo blocco è una fonte di riferimento per il sito.

````bash
#!/usr/bin/env bash
# Lezione 06 — scheduling (spread, priorità, taint) e autoscaling HPA.
source "$(dirname "$0")/../lib/passo.sh"
guardia_lab
titolo "06. Scheduling e autoscaling"
F="$LEZIONI/kubernetes/06-scheduling-autoscaling.yaml"

passo "Applica PriorityClass, Service e NetworkPolicy, Deployment 'api' con topologySpreadConstraints, HPA al 60% di CPU" \
  "kubectl apply -f $F"
passo "Colonna NODE: i Pod sono distribuiti su lab e lab-m02 grazie allo spread" \
  'kubectl -n lab get pod -l app=api -o wide'
passo "Metriche dal metrics-server: i Pod nuovi le hanno dopo ~1 minuto (finché mancano l'HPA non può decidere). Aspetto che arrivino" \
  'for i in $(seq 30); do kubectl top pod -n lab -l app=api >/dev/null 2>&1 && break; sleep 5; done; kubectl top pod -n lab -l app=api'
passo "Genero carico in background per 120 s: un Pod con ruolo=client (ammesso dalla NetworkPolicy) che chiama api in loop" \
  "kubectl -n lab run carico --restart=Never --image=busybox:1.37 --labels=ruolo=client -- sh -c 'end=\$((\$(date +%s)+120)); while [ \$(date +%s) -lt \$end ]; do wget -q -O- http://api/ >/dev/null; done'"
passo "Guardo l'HPA per 90 s: TARGETS sale sopra il 60% e REPLICAS aumenta" \
  'timeout 90 kubectl -n lab get hpa api -w || true'
passo "Il 60% è delle REQUESTS (20m per Pod), non del nodo: la soglia è 12m medi per Pod. Confronta con il consumo" \
  "kubectl -n lab get deploy api -o jsonpath='{.spec.template.spec.containers[0].resources.requests}'; echo; kubectl -n lab top pod -l app=api"
nota "Esempio misurato sul lab: TARGETS 375% = 75m per Pod su 20m di request." \
     "desiderate = ceil(2 × 375 / 60) = 13 → tagliate a maxReplicas 8; la policy +100% ogni 15 s le fa salire 2 → 4 → 8."
passo "Gli eventi di scala: perché l'HPA ha deciso di salire" \
  'kubectl -n lab describe hpa api | tail -15'
passo "Taint sul worker: da ora nessun Pod NUOVO senza toleration va su lab-m02 (quelli già lì restano: NoSchedule, non NoExecute)" \
  'kubectl taint nodes lab-m02 dedicato=batch:NoSchedule; kubectl describe node lab-m02 | grep -A2 Taints'
passo "Tolgo il taint: il trattino finale significa 'rimuovi'" \
  'kubectl taint nodes lab-m02 dedicato=batch:NoSchedule-'
passo "Pulizia del Pod di carico (l'HPA riscende da solo: dopo 120 s di calo, un Pod al minuto)" \
  'kubectl -n lab delete pod carico --ignore-not-found'
````

## Traccia per lo studio attivo

Prima di passare oltre: rileggi il manifest e lo script della lezione, individua il comando che produce l’osservazione principale, spiega perché il risultato è atteso, poi confronta la tua spiegazione con le riflessioni e le domande da colloquio del Markdown originale. Non applicare gli script a un cluster diverso dal laboratorio senza verificare i contesti.

---

<a id="lezione-07"></a>

# Lezione 07 — RBAC, ServiceAccount e Pod Security Admission

## Spiegazione e riflessioni ragionate

### Modello mentale del professore
Tre domande consecutive su richieste di modifica: **Authentication** (chi sei?), **Authorization/RBAC** (puoi farlo?), **Admission** (la risorsa rispetta le policy?). RBAC protegge le operazioni sull'API, Pod Security Admission applica profili di sicurezza ai Pod, `securityContext` definisce concretamente i privilegi del processo Linux.

### Role, Binding e namespace
Una `Role` definisce regole di namespace; una `ClusterRole` regole riusabili anche cluster-scoped; `RoleBinding` assegna permessi in un namespace (anche da ClusterRole); `ClusterRoleBinding` lega una ClusterRole a livello cluster. Il ServiceAccount `deployer` nel namespace `lab-sicuro` riceve tramite RoleBinding lettura `pods`, `pods/log`, `services`, `configmaps` e create/update/patch dei Deployment, ma non un esplicito `get secrets` o `pods/exec`. RBAC è additivo: non basta leggere una Role per escludere altri permessi concessi da altri binding.

### Le trappole di sicurezza
- La capacità di creare o modificare Deployment può consentire la creazione indiretta di Pod che montano Secret: negare solo `get secrets` non garantisce riservatezza contro soggetti con controllo dei workload.
- `automountServiceAccountToken: false` evita credenziali API non necessarie nei Pod.
- PSA `restricted` nel namespace `lab-sicuro` respinge un Pod BusyBox senza securityContext conforme. L'admission riguarda la creazione del Pod; un Deployment può essere accettato mentre il ReplicaSet riceve errori creando i Pod.
- Nginx unprivileged usa UID/GID 101, `runAsNonRoot`, `seccompProfile: RuntimeDefault`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]` e filesystem radice read-only con `/tmp` su `emptyDir`. Il read-only root filesystem è un hardening aggiuntivo, non requisito universale del livello PSA restricted.

### Supply chain
La sicurezza non termina al Pod: tag immutabili/digest delle immagini, SBOM, scansione CVE, firma immagini, policy as code e audit completano il quadro.

### Verifica rapida
1. `kubectl auth can-i get secrets` restituisce `no`: che cosa NON dimostra?
2. Qual è la differenza tra RoleBinding e ClusterRoleBinding?
3. Perché il BusyBox non conforme viene rifiutato?
4. Che cosa cambia tra `runAsNonRoot`, capability drop e seccomp?

## Materiale originale della lezione


### Fonte originale: `07-rbac-pod-security.md`

> **Trascrizione integrale del file originale**, senza riscrittura. Questo blocco è una fonte di riferimento per il sito.

````markdown
# 07 — Sicurezza: RBAC, ServiceAccount e Pod Security Admission

Spiegazione di `07-rbac-pod-security.yaml` (questa cartella). Lezione sul sito: http://127.0.0.1:3000/kubernetes/7

## In una frase

Il file crea un namespace **`lab-sicuro`** in cui la **Pod Security Admission** applica il profilo **`restricted`**, un
**ServiceAccount `deployer`** con un **Role** di minimo privilegio (legge Pod e config, gestisce i Deployment, niente
Secret né exec né delete) e un **nginx non-root** che quel profilo lo supera. Il runner interroga l'apiserver con
`kubectl auth can-i --as` e poi prova a lanciare un Pod "qualunque", che viene **rifiutato**.

## Due file con lo stesso nome: quale lanciare

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/lezioni/kubernetes/07-rbac-pod-security.yaml` | **questo**: i manifest, con la teoria nei commenti | si **legge**; lo applica il runner (o a mano: `kubectl apply -f 07-rbac-pod-security.yaml`) |
| `~/kubernetesprj/kubernetes/07-rbac-pod-security.sh` | lo script **guidato**: applica, interroga i permessi, prova la PSA, un passo per volta (Invio / s / q) | `bash kubernetes/07-rbac-pod-security.sh` |

Questa lezione non dipende dalle precedenti: crea il suo namespace.

## Com'è fatto il file

```
intestazione (commenti)  → teoria: authn → authz → admission, RBAC in 4 oggetti, verbi che sorprendono,
                           comandi LAB, NEL PROGETTO VERO
Namespace lab-sicuro     → label PSA: enforce + warn restricted
ServiceAccount deployer  → identità senza token montato di default
Role deployer            → cosa può fare (solo allow)
RoleBinding deployer     → a chi (il SA) e dove (lab-sicuro)
Deployment nginx         → un Pod che passa "restricted"
commenti                 → oltre il cluster: la catena di fornitura
coda (commenti)          → domande da colloquio, riepilogo
```

Versione: Kubernetes 1.34–1.35 (lab 1.34.0), `rbac.authorization.k8s.io/v1`, PSA "restricted".

---

## 1. La teoria nell'intestazione

### Tre domande, sempre in quest'ordine

Ogni richiesta all'apiserver passa tre controlli:

| Fase | Domanda | Con cosa |
|---|---|---|
| **Autenticazione** | chi sei? | certificato client, token **OIDC** (persone), token del **ServiceAccount** (Pod) |
| **Autorizzazione** | puoi farlo? | **RBAC**: verbo + risorsa (+ nome) + namespace |
| **Admission** | è accettabile? | **PSA**, policy (Kyverno, ValidatingAdmissionPolicy) |

Kubernetes **non ha "utenti" come oggetti**: un utente è solo un nome dentro un certificato o un token. I
**ServiceAccount** invece sono oggetti veri, in un namespace: sono le identità dei Pod.

### RBAC in 4 oggetti

| Oggetto | Risponde a |
|---|---|
| `Role` / `ClusterRole` | **cosa** si può fare (solo allow, additivo: non esiste un "deny") |
| `RoleBinding` / `ClusterRoleBinding` | **a chi**, e **dove** |

Un **ClusterRole legato con un RoleBinding** vale **solo in quel namespace**: è il modo per riusare un ruolo standard
(`view`, `edit`) per ogni team, senza riscriverlo.

### Verbi che sorprendono

| Permesso | Che cosa dà davvero |
|---|---|
| `get` su `secrets` | leggere **tutti** i segreti (con `list`, senza nemmeno sapere il nome) |
| `create` su `pods` | leggere **ogni secret / SA del namespace**: monti il secret o il token in un Pod tuo |
| `escalate` / `bind` / `impersonate` | scalare i propri privilegi |
| `pods/exec`, `nodes/proxy` | eseguire comandi |

### I comandi LAB dell'intestazione

```bash
kubectl apply -f 07-rbac-pod-security.yaml
SA=system:serviceaccount:lab-sicuro:deployer
kubectl auth can-i get pods  -n lab-sicuro --as=$SA      # yes
kubectl auth can-i get secrets -n lab-sicuro --as=$SA    # no
kubectl auth can-i patch deployments -n lab --as=$SA     # no: altro namespace
kubectl auth can-i --list -n lab-sicuro --as=$SA
kubectl -n lab-sicuro run root --image=busybox:1.37 -- sleep 1d
  ↑ RIFIUTATO dalla PSA "restricted": il messaggio elenca cosa manca
kubectl -n lab-sicuro get pod                            # nginx Running
```

Il nome di un ServiceAccount per RBAC ha sempre la forma `system:serviceaccount:<namespace>:<nome>`. Con `--as` ti fai
**passare** per lui (impersonation): tu, admin del lab, puoi farlo.

### Riquadro «NEL PROGETTO VERO»

In `~/biodistretto/kubernetes`:

- il **worker** gira come uid/gid **1000**, Elasticsearch con **fsGroup 1000**:
  ```bash
  grep -n -A2 'runAsUser' terraform/app/manifests/app.yaml.tftpl
  ```
- il resto gira **come vuole l'immagine**. **Esercizio senza cambiare niente**:
  ```bash
  kubectl --context biodistretto label --dry-run=server --overwrite ns \
    biodistretto pod-security.kubernetes.io/enforce=restricted
  ```
  Con `--dry-run=server` l'apiserver valuta la modifica ma **non la salva**: le righe di **Warning** dicono quali Pod
  violerebbero il profilo e perché.
- **Fuori dal cluster**: il container HAProxy gira **come root in rete host**, perché senza privilegi le porte 80 e 443
  dell'host non si aprono.
  ```bash
  grep -n -E 'network_mode|user:' ansible/roles/haproxy/tasks/main.yml
  ```

---

## 2. Il Namespace `lab-sicuro` e la Pod Security Admission

```yaml
metadata:
  name: lab-sicuro
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/warn: restricted
```

La **PSA** è nativa (ha sostituito PodSecurityPolicy) e si configura **con label sul namespace**.

| Modo | Effetto |
|---|---|
| `enforce` | **rifiuta** i Pod che violano il profilo |
| `audit` | li accetta ma **annota** la violazione nel log di audit |
| `warn` | li accetta ma **avvisa** il client (le righe `Warning:` di kubectl) |

| Livello | Cosa permette |
|---|---|
| `privileged` | tutto |
| `baseline` | blocca le escalation note (privileged, hostNetwork, hostPath…) |
| `restricted` | in più: non-root, niente escalation, capabilities tolte, seccomp |

`enforce-version: latest` = usa le regole della versione di Kubernetes in esecuzione. Qui `warn` è uguale a `enforce`:
il warning serve soprattutto quando i due livelli differiscono (migrazione graduale, vedi le domande).

Attenzione: la PSA controlla i **Pod**. Un Deployment che viola il profilo viene **accettato**; è il ReplicaSet che poi
non riesce a creare i Pod (con `warn` lo vedi subito all'apply).

---

## 3. Il ServiceAccount `deployer`

```yaml
kind: ServiceAccount
metadata:
  name: deployer
  namespace: lab-sicuro
automountServiceAccountToken: false
```

Un'identità per chi deve fare deploy (una pipeline, un operatore). `automountServiceAccountToken: false`: i Pod che usano
questo SA **non ricevono il token** a meno che non lo chiedano esplicitamente. Il token si monta **solo dove serve**.

---

## 4. Il Role `deployer` — regola per regola

```yaml
rules:
  - apiGroups: [""]
    resources: [pods, pods/log, services, configmaps]
    verbs: [get, list, watch]
  - apiGroups: [apps]
    resources: [deployments]
    verbs: [get, list, watch, create, update, patch]
  - apiGroups: [apps]
    resources: [deployments/scale]
    verbs: [patch]
```

| Regola | Concede | Perché |
|---|---|---|
| core (`""`) | **leggere** Pod, log dei Pod, Service, ConfigMap | `""` è il gruppo **core** dell'API. `pods/log` è una **sottorisorsa**: va nominata a parte |
| `apps` / `deployments` | leggere, creare e modificare Deployment | il lavoro di un deployer |
| `apps` / `deployments/scale` | `patch` della sottorisorsa scale | per `kubectl scale` |

E quello che **manca** è il punto (commento del file): **niente secrets, niente pods/exec, niente delete**. Minimo
privilegio. Un `Role` vale solo nel suo namespace (`lab-sicuro`).

Nota: il deployer può **creare Deployment**, e quindi indirettamente far creare Pod nel namespace. Per la regola dei
"verbi che sorprendono", è un potere da tenere presente; qui lo limitano la PSA `restricted` e il fatto che il SA non ha
accesso ai Secret via API.

---

## 5. Il RoleBinding `deployer`

```yaml
subjects:
  - kind: ServiceAccount
    name: deployer
    namespace: lab-sicuro
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: deployer
```

- `subjects`: **a chi** — il ServiceAccount (per un SA il `namespace` va sempre indicato).
- `roleRef`: **quale** ruolo. È **immutabile**: per cambiarlo si cancella e si ricrea il binding.
- Il binding sta in `lab-sicuro`: per questo `can-i patch deployments -n lab` dà **no**.

---

## 6. Il Deployment `nginx` — un Pod che passa `restricted`

Il commento del file: è il `securityContext` che **ogni** workload dovrebbe avere, non un caso speciale.

### A livello di Pod

```yaml
automountServiceAccountToken: false
securityContext:
  runAsNonRoot: true
  runAsUser: 101
  runAsGroup: 101
  fsGroup: 101
  seccompProfile:
    type: RuntimeDefault
```

| Campo | Perché |
|---|---|
| `automountServiceAccountToken: false` | nginx non parla con l'apiserver: niente token |
| `runAsNonRoot: true` | richiesto da restricted: il kubelet non avvia il container se girerebbe come root |
| `runAsUser` / `runAsGroup: 101` | l'utente `nginx` dell'immagine unprivileged |
| `fsGroup: 101` | i volumi montati diventano del gruppo 101, così nginx può scriverci |
| `seccompProfile: RuntimeDefault` | **richiesto da restricted**: filtra le syscall con il profilo del runtime |

### A livello di container

```yaml
image: nginxinc/nginx-unprivileged:1.31-alpine
ports:
  - containerPort: 8080
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: ["ALL"]
volumeMounts:
  - { name: tmp, mountPath: /tmp }
resources:
  requests: { cpu: 10m, memory: 16Mi }
  limits: { memory: 64Mi }
volumes:
  - name: tmp
    emptyDir: {}
```

| Campo | Perché |
|---|---|
| immagine `nginx-unprivileged` | ascolta su **8080**, non su 80: un utente non root non può aprire porte sotto la 1024 |
| `allowPrivilegeEscalation: false` | richiesto da restricted |
| `capabilities.drop: ["ALL"]` | richiesto da restricted |
| `readOnlyRootFilesystem: true` | non richiesto da restricted, ma buona prassi (come nella lezione 02) |
| volume `tmp` (`emptyDir`) su `/tmp` | con la root in sola lettura, **le cartelle scrivibili si dichiarano**: nginx deve scrivere file temporanei |

---

## 7. Il runner, passo per passo

Il runner imposta `SA=system:serviceaccount:lab-sicuro:deployer`, chiama `guardia_lab`, poi 7 passi:

| # | Comando | Cosa vedi |
|---|---|---|
| 1 | `kubectl apply -f …/07-rbac-pod-security.yaml` | namespace, serviceaccount, role, rolebinding, deployment creati |
| 2 | `kubectl auth can-i get pods -n lab-sicuro --as=$SA` | `yes` |
| 3 | `kubectl auth can-i get secrets -n lab-sicuro --as=$SA` | `no` — **e la riga rossa "uscita 1"**: `can-i` esce 1 quando la risposta è no. È voluto |
| 4 | `kubectl auth can-i patch deployments -n lab --as=$SA` | `no` (uscita 1, voluto): un RoleBinding vale solo nel suo namespace |
| 5 | `kubectl auth can-i --list -n lab-sicuro --as=$SA` | la tabella Resources / Verbs: le tre regole del Role più i permessi di base che ogni utente autenticato ha (es. `selfsubjectaccessreviews`) |
| 6 | `kubectl -n lab-sicuro run root --image=busybox:1.37 -- sleep 1d` | **fallisce apposta**: `Error from server (Forbidden): … violates PodSecurity "restricted:latest"` con l'elenco di ciò che manca (allowPrivilegeEscalation, capabilities, runAsNonRoot, seccompProfile) |
| 7 | `rollout status deploy/nginx --timeout=90s && get pod` | l'nginx del manifest è `Running`: non-root, niente privilegi, seccomp RuntimeDefault, capabilities tolte |

Il passo 6 è il cuore della lezione: `kubectl run` crea **direttamente un Pod**, quindi la PSA lo blocca subito e
l'errore arriva al terminale. Il Pod `root` **non viene creato**: non c'è niente da pulire.

---

## 8. Oltre il cluster: la catena di fornitura

| Pratica | Strumenti |
|---|---|
| immagini firmate e verificate all'admission | cosign / Sigstore |
| scansione CVE in CI e SBOM | Trivy, Grype; Syft |
| immagini minime e riferimenti immutabili | distroless o FROM scratch, tag immutabili o digest `@sha256` |
| policy as code ("niente `:latest`", "requests obbligatorie", "solo registry interni") | Kyverno / OPA Gatekeeper / ValidatingAdmissionPolicy |
| sorveglianza a runtime | Falco (syscall sospette) |
| credenziali cloud senza chiavi statiche | Workload Identity / IRSA: il Pod le ottiene dal suo ServiceAccount |

---

## 9. Le trappole

| Trappola | Cosa succede | Rimedio |
|---|---|---|
| dare `create pods` pensando "non legge i secret" | monta qualunque secret in un Pod suo | trattare `create pods` come accesso ai secret |
| dare `get` (o `list`) su secrets per comodità | legge tutti i segreti del namespace | mai nei ruoli di lettura; `view` non li include |
| `roleRef` da cambiare | l'update viene rifiutato: è immutabile | cancellare e ricreare il binding |
| Deployment che viola la PSA | accettato, ma i Pod non nascono | `warn` all'apply; guardare gli eventi del ReplicaSet |
| root filesystem read-only senza volumi scrivibili | l'app crasha cercando di scrivere | `emptyDir` sulle cartelle che servono (`/tmp`) |
| immagine che ascolta su 80 come non-root | non può aprire la porta | immagine "unprivileged" su 8080 |
| passare un namespace esistente a `enforce` di colpo | i Pod nuovi vengono rifiutati | prima `warn`/`audit` (o `--dry-run=server`), poi `enforce` |
| leggere "no" come errore dello script | `can-i` esce 1 sul no | è la risposta, non un guasto |

---

## 10. La coda: domande da colloquio

- **Come dai a un team accesso in sola lettura al suo namespace?** RoleBinding nel namespace verso il ClusterRole
  predefinito **`view`**, con subject il **gruppo OIDC** del team (non i singoli utenti).
- **Perché `view` non include i secrets e `edit` sì?** Leggere un secret è un'escalation (token, password). `edit`
  include la creazione di Pod, che dà comunque accesso ai secret: per questo `edit` ≈ chi può leggere i secret del
  namespace.
- **Un Pod viene rifiutato con "violates PodSecurity restricted".** Il messaggio elenca i campi: `allowPrivilegeEscalation`,
  `capabilities`, `runAsNonRoot`, `seccompProfile`. Si corregge il `securityContext`; per migrare un namespace prima si
  mette `warn`/`audit`, si guarda cosa romperebbe, poi `enforce`.
- **Il token del ServiceAccount: com'è fatto oggi?** Token **proiettato** (BoundServiceAccountToken): JWT con audience
  e **scadenza** (1 h, rinnovato dal kubelet), legato al Pod. I vecchi Secret di tipo token senza scadenza non si creano
  più in automatico.

### Comandi da sapere

| Comando | A cosa serve |
|---|---|
| `kubectl auth can-i <verbo> <risorsa> -n <ns> --as=system:serviceaccount:<ns>:<sa>` | che cosa può fare un'identità |
| `kubectl auth can-i --list -n <ns> --as=…` | tutti i suoi permessi |
| `kubectl label --dry-run=server --overwrite ns <ns> pod-security.kubernetes.io/enforce=restricted` | chi violerebbe il profilo, senza applicarlo |
| `kubectl get ns lab-sicuro --show-labels` | le label PSA di un namespace |

---

## Riepilogo

- **Authn → Authz (RBAC) → Admission**, sempre in quest'ordine.
- **Role/ClusterRole = cosa**; **(Cluster)RoleBinding = a chi e dove**.
- **`create pods` ≈ leggere i secret**: il minimo privilegio si verifica con `can-i`.
- **PSA restricted** per namespace: non-root, no escalation, drop ALL, seccomp.
- **Supply chain**: firma, scansione, policy, identità senza chiavi statiche.

## Prova da solo

1. `kubectl auth can-i delete deployments -n lab-sicuro --as=$SA` e `kubectl auth can-i create pods/exec -n lab-sicuro
   --as=$SA`: cosa rispondono, e quale riga del Role (o la sua assenza) lo spiega?
2. Crea un RoleBinding in `lab-sicuro` che leghi il SA `deployer` al ClusterRole predefinito `view` (`kubectl create
   rolebinding …`), poi ripeti `can-i get secrets` e `can-i get pods -n lab`: cosa cambia e cosa no?
3. Togli dal Deployment `nginx` il blocco `seccompProfile` e riapplica: che `Warning` stampa kubectl? Il Deployment
   viene accettato? E i Pod nuovi (`kubectl -n lab-sicuro get rs` e `describe rs`)? Rimetti il blocco.
````

### Fonte originale: `07-rbac-pod-security.yaml`

> **Trascrizione integrale del file originale**, senza riscrittura. Questo blocco è una fonte di riferimento per il sito.

````yaml
# ═══════════════════════════════════════════════════════════════════════════
# 07. SICUREZZA: RBAC, SERVICEACCOUNT E POD SECURITY ADMISSION
# Versione: Kubernetes 1.34–1.35 (il lab minikube gira la 1.34.0) · rbac.authorization.k8s.io/v1 · PSA "restricted"
# Livello: 3 — Sicurezza e operatività
# ═══════════════════════════════════════════════════════════════════════════
# Tre domande, in quest'ordine, a ogni richiesta all'apiserver:
#   AUTENTICAZIONE  chi sei? certificato client, token OIDC (persone),
#                   token del ServiceAccount (Pod). Kubernetes non ha
#                   "utenti" come oggetti: un utente è un nome nel cert/token.
#   AUTORIZZAZIONE  puoi farlo? RBAC: verbo + risorsa (+ nome) + namespace
#   ADMISSION       è accettabile? PSA, policy (Kyverno, ValidatingAdmissionPolicy)
#
# RBAC IN 4 OGGETTI
#   Role / ClusterRole              COSA si può fare (solo allow, additivo)
#   RoleBinding / ClusterRoleBinding  A CHI, e DOVE
#   Un ClusterRole legato con un RoleBinding vale solo in quel namespace:
#   è il modo per riusare un ruolo standard ("view", "edit") per team.
#
# VERBI CHE SORPRENDONO
#   get su secrets           = leggere TUTTI i segreti (con list, senza nome)
#   create su pods           = leggere ogni secret/SA del namespace
#                              (monti il secret o il token in un Pod tuo)
#   escalate / bind / impersonate = scalare i propri privilegi
#   pods/exec, nodes/proxy   = esecuzione di comandi
#
# LAB
#   kubectl apply -f 07-rbac-pod-security.yaml
#   SA=system:serviceaccount:lab-sicuro:deployer
#   kubectl auth can-i get pods  -n lab-sicuro --as=$SA      # yes
#   kubectl auth can-i get secrets -n lab-sicuro --as=$SA    # no
#   kubectl auth can-i patch deployments -n lab --as=$SA     # no: altro namespace
#   kubectl auth can-i --list -n lab-sicuro --as=$SA
#   kubectl -n lab-sicuro run root --image=busybox:1.37 -- sleep 1d
#     ↑ RIFIUTATO dalla PSA "restricted": il messaggio elenca cosa manca
#   kubectl -n lab-sicuro get pod                            # nginx Running
#
# ── NEL PROGETTO VERO: il Biodistretto su minikube ───────────────────────
#   ~/biodistretto/kubernetes (branch kubernetes). I grep partono da lì:
#   cd ~/biodistretto/kubernetes · come si usa: il README della cartella
#   Il worker gira come uid/gid 1000, Elasticsearch con fsGroup 1000:
#     grep -n -A2 'runAsUser' terraform/app/manifests/app.yaml.tftpl
#   Il resto gira come vuole l'immagine. ESERCIZIO, senza cambiare niente:
#     kubectl --context biodistretto label --dry-run=server --overwrite ns \
#       biodistretto pod-security.kubernetes.io/enforce=restricted
#     Le righe di Warning dicono quali Pod violerebbero il profilo e perché.
#   Fuori dal cluster: il container HAProxy gira come root in rete host,
#   perché senza sudo le porte 80 e 443 dell'host non si aprono.
#     grep -n -E 'network_mode|user:' ansible/roles/haproxy/tasks/main.yml

apiVersion: v1
kind: Namespace
metadata:
  name: lab-sicuro
  labels:
    # Pod Security Admission (nativa, sostituisce PodSecurityPolicy):
    #   enforce rifiuta · audit annota · warn avvisa il client
    # livelli: privileged | baseline | restricted
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/warn: restricted
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: deployer
  namespace: lab-sicuro
automountServiceAccountToken: false   # il token si monta solo dove serve
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: deployer
  namespace: lab-sicuro
rules:
  - apiGroups: [""]                   # "" = core API (pods, services, configmaps)
    resources: [pods, pods/log, services, configmaps]
    verbs: [get, list, watch]
  - apiGroups: [apps]
    resources: [deployments]
    verbs: [get, list, watch, create, update, patch]
  - apiGroups: [apps]
    resources: [deployments/scale]
    verbs: [patch]
  # niente secrets, niente pods/exec, niente delete: minimo privilegio
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: deployer
  namespace: lab-sicuro
subjects:
  - kind: ServiceAccount
    name: deployer
    namespace: lab-sicuro
roleRef:                              # IMMUTABILE: per cambiarlo si ricrea
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: deployer
---
# Un Pod che passa la PSA "restricted": è il securityContext che ogni
# workload dovrebbe avere, non un caso speciale.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: lab-sicuro
spec:
  replicas: 1
  selector:
    matchLabels: { app: nginx }
  template:
    metadata:
      labels: { app: nginx }
    spec:
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 101                 # l'utente nginx dell'immagine unprivileged
        runAsGroup: 101
        fsGroup: 101
        seccompProfile:
          type: RuntimeDefault         # richiesto da restricted
      containers:
        - name: nginx
          image: nginxinc/nginx-unprivileged:1.31-alpine   # ascolta su 8080, non su 80
          ports:
            - containerPort: 8080
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
          volumeMounts:                # con root read-only, le cartelle
            - { name: tmp, mountPath: /tmp }    # scrivibili si dichiarano
          resources:
            requests: { cpu: 10m, memory: 16Mi }
            limits: { memory: 64Mi }
      volumes:
        - name: tmp
          emptyDir: {}

# ── OLTRE IL CLUSTER: LA CATENA DI FORNITURA ────────────────────────────────
#   • immagini firmate (cosign/Sigstore) e verificate all'admission
#   • scansione CVE in CI (Trivy, Grype) e SBOM (Syft)
#   • immagini distroless o FROM scratch, tag immutabili o digest @sha256
#   • policy as code: Kyverno / OPA Gatekeeper / ValidatingAdmissionPolicy
#     ("niente :latest", "requests obbligatorie", "solo registry interni")
#   • runtime: Falco per syscall sospette
#   • Workload Identity / IRSA: il Pod ottiene credenziali cloud dal suo
#     ServiceAccount, senza chiavi statiche nei Secret

# ── DOMANDE DA COLLOQUIO ────────────────────────────────────────────────────
# D: Come dai a un team accesso in sola lettura al suo namespace?
# R: RoleBinding nel namespace verso il ClusterRole predefinito "view",
#    con subject il gruppo OIDC del team (non i singoli utenti).
#
# D: Perché "view" non include i secrets e "edit" sì?
# R: Leggere un secret è un'escalation (token, password). "edit" include
#    la creazione di Pod, che dà comunque accesso ai secret: per questo
#    edit ≈ chi può leggere i secret del namespace.
#
# D: Un Pod viene rifiutato con "violates PodSecurity restricted".
# R: Il messaggio elenca i campi: allowPrivilegeEscalation, capabilities,
#    runAsNonRoot, seccompProfile. Si corregge il securityContext; per
#    migrare un namespace prima si mette warn/audit, si guarda cosa
#    romperebbe, poi enforce.
#
# D: Il token del ServiceAccount: com'è fatto oggi?
# R: Token proiettato (BoundServiceAccountToken): JWT con audience e
#    scadenza (1 h, rinnovato dal kubelet), legato al Pod. I vecchi
#    Secret di tipo token senza scadenza non si creano più in automatico.

# ══════════════════════════════════════════════════════════════════════════
# RIEPILOGO
# • Authn → Authz (RBAC) → Admission, sempre in quest'ordine
# • Role/ClusterRole = cosa; (Cluster)RoleBinding = a chi e dove
# • create pods ≈ leggere i secret: il minimo privilegio si verifica con can-i
# • PSA restricted per namespace: non-root, no escalation, drop ALL, seccomp
# • Supply chain: firma, scansione, policy, identità senza chiavi statiche
# ══════════════════════════════════════════════════════════════════════════
````

### Fonte originale: `07-rbac-pod-security.sh`

> **Trascrizione integrale del file originale**, senza riscrittura. Questo blocco è una fonte di riferimento per il sito.

````bash
#!/usr/bin/env bash
# Lezione 07 — RBAC con ServiceAccount e Pod Security Admission "restricted".
source "$(dirname "$0")/../lib/passo.sh"
guardia_lab
titolo "07. RBAC e Pod Security"
F="$LEZIONI/kubernetes/07-rbac-pod-security.yaml"
SA=system:serviceaccount:lab-sicuro:deployer

passo "Applica namespace lab-sicuro (PSA restricted), ServiceAccount deployer, Role, RoleBinding e un nginx non-root" \
  "kubectl apply -f $F"
passo "auth can-i --as: chiedo all'apiserver cosa può fare il ServiceAccount. Leggere i Pod: sì" \
  "kubectl auth can-i get pods -n lab-sicuro --as=$SA"
passo "Leggere i Secret: no, il Role non lo concede" \
  "kubectl auth can-i get secrets -n lab-sicuro --as=$SA"
passo "Modificare Deployment in un ALTRO namespace: no, un RoleBinding vale solo nel suo namespace" \
  "kubectl auth can-i patch deployments -n lab --as=$SA"
passo "Tutti i permessi del ServiceAccount nel namespace" \
  "kubectl auth can-i --list -n lab-sicuro --as=$SA"
passo "Un Pod busybox qualunque (root, senza securityContext) viene RIFIUTATO dalla PSA: il messaggio elenca cosa manca" \
  'kubectl -n lab-sicuro run root --image=busybox:1.37 -- sleep 1d'
passo "L'nginx del manifest invece gira: non-root, niente privilegi, seccomp RuntimeDefault, capabilities tolte" \
  'kubectl -n lab-sicuro rollout status deploy/nginx --timeout=90s && kubectl -n lab-sicuro get pod'
````

## Traccia per lo studio attivo

Prima di passare oltre: rileggi il manifest e lo script della lezione, individua il comando che produce l’osservazione principale, spiega perché il risultato è atteso, poi confronta la tua spiegazione con le riflessioni e le domande da colloquio del Markdown originale. Non applicare gli script a un cluster diverso dal laboratorio senza verificare i contesti.

---

<a id="lezione-08"></a>

# Lezione 08 — Troubleshooting: cinque guasti intenzionali

## Spiegazione e riflessioni ragionate

### Modello mentale del professore
Il troubleshooting è **un metodo**, non una raffica di riavvii. Sequenza: **STATO → EVENTI → LOG → DENTRO → INTORNO**. Lo stato suggerisce chi investigare: scheduler per Pending, kubelet/registry per ImagePull, processo e configurazione per CrashLoop, kernel/cgroup per OOM, endpoint e rete per Service apparentemente muto.

### I cinque guasti intenzionali nel namespace rotto
1. `immagine`: tag `traefik/whoami:v9.9.9` non disponibile → `ErrImagePull` / `ImagePullBackOff`; partire da `describe pod` ed eventi, non da log di un processo mai avviato.
2. `crash`: BusyBox stampa `manca DATABASE_URL` ed esce con 1 → `CrashLoopBackOff`; guardare `kubectl logs`, poi `--previous` se serve. La correzione è nella configurazione o nel comando, non automaticamente nei limiti CPU.
3. `memoria`: limit `20Mi`, pipeline che accumula dati → `OOMKilled` e generalmente exit 137. Il codice 137 indica SIGKILL, non prova da solo OOM: verificare `reason` in `state.terminated` / `lastState`.
4. `enorme`: request CPU `64` = 64 core, non `64m` → `Pending` e `FailedScheduling` / `Insufficient cpu`.
5. `eco`: Pod running ma Service selector `app=ecco` mentre i Pod hanno `app=eco` → nessun backend utile. Confrontare `svc.spec.selector`, label dei Pod ed EndpointSlice; un patch del selector può riparare il routing senza riavviare l'app.

### Quando serve kubectl debug
Le immagini minimali (per esempio senza shell) non permettono sempre `kubectl exec -- sh`. Un ephemeral container BusyBox può condividere la rete del Pod e, con runtime compatibile, osservare processi tramite `--target`; i suoi strumenti diagnosticano un'app senza modificarne l'immagine.

### Riflessione pratica
Un errore visibile nei PVC può nascere dal CSI che non comunica con API server a causa di un CNI rotto. `kubectl cp` richiede normalmente `tar` nell'immagine. Un nodo container avviato non implica kubelet funzionante. I casi reali sono nel materiale Biodistretto: impara a seguire la catena delle dipendenze, non a correggere solo l'ultimo messaggio.

### Verifica rapida
1. `Running 1/1` ma il Service è muto: quale comando viene prima di un restart?
2. `CrashLoopBackOff` e log vuoti: quali altri indizi cerchi?
3. Perché 137 non basta a diagnosticare OOM?
4. Cosa distingue un Pod Pending da uno ImagePullBackOff?

## Materiale originale della lezione


### Fonte originale: `08-troubleshooting.md`

> **Trascrizione integrale del file originale**, senza riscrittura. Questo blocco è una fonte di riferimento per il sito.

````markdown
# 08 — Troubleshooting: cinque guasti da riconoscere al primo sguardo

Spiegazione di `08-troubleshooting.sh` (questa cartella). Lezione sul sito: http://127.0.0.1:3000/kubernetes/8

## In una frase

Lo script **rompe apposta cinque workload** nel namespace `rotto` (immagine inesistente, processo che crasha, memoria
oltre il limite, CPU che nessun nodo ha, Service che non seleziona niente) e poi li **diagnostica con un metodo** in
cinque tappe: stato → eventi → log → dentro → intorno. Alla fine usa `kubectl debug` per entrare in un Pod la cui
immagine non ha nemmeno una shell.

## Due file con lo stesso nome: quale lanciare

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/lezioni/kubernetes/08-troubleshooting.sh` | **questo**: la lezione, con le spiegazioni nei commenti | `bash 08-troubleshooting.sh rompi` · `diagnosi` · `pulisci` |
| `~/kubernetesprj/kubernetes/08-troubleshooting.sh` | lo script **guidato**: rompe e diagnostica con gli stessi comandi, uno per volta, spiegando prima di eseguire (Invio / s / q) | `bash kubernetes/08-troubleshooting.sh` |

Il gioco proposto dal file: **dopo `rompi`, prima indovina tu la causa** di ogni guasto, poi lancia `diagnosi`.

```bash
bash 08-troubleshooting.sh rompi
kubectl -n rotto get pod -w          # aspetta ~1 minuto
bash 08-troubleshooting.sh diagnosi
bash 08-troubleshooting.sh pulisci
```

## Com'è fatto il file

```
intestazione (commenti)  → il metodo in 5 tappe, la tabella STATUS → dove guardare, NEL PROGETTO VERO
set -euo pipefail        → lo script si ferma al primo errore
NS=rotto                 → il namespace usa-e-getta
guardia_contesto()       → controlla che kubectl punti a "lab" (o a $CONTESTO_LAB)
rompi()                  → crea i cinque guasti
diagnosi()               → li esamina in 6 blocchi
pulisci()                → cancella il namespace
case "$1"                → rompi | diagnosi | pulisci
coda (commenti)          → altri attrezzi, domande da colloquio, riepilogo
```

L'intestazione dichiara Kubernetes 1.35 / kubectl 1.35 (il lab delle altre lezioni gira la 1.34.0).

---

## 1. La teoria nell'intestazione

### Un metodo, non un elenco di comandi

Al colloquio la domanda tipica è "il Pod non parte, cosa fai?". Convince **un metodo**:

| Tappa | Comando | Chi parla |
|---|---|---|
| 1. **STATO** | `kubectl get pod -o wide` | STATUS, RESTARTS, NODE |
| 2. **EVENTI** | `kubectl describe pod` / `get events` | scheduler, kubelet |
| 3. **LOG** | `kubectl logs [--previous]` | l'app |
| 4. **DENTRO** | `kubectl exec` / `kubectl debug` | rete, file, processi |
| 5. **INTORNO** | Service, EndpointSlice, NetworkPolicy, nodo, quota | il resto del cluster |

### STATUS → dove guardare

| STATUS | Chi è in difficoltà / causa tipica | Dove guardi |
|---|---|---|
| `Pending` | **scheduler**: risorse, taint, affinity, PVC | `describe` |
| `ContainerCreating` | **kubelet**: volume, secret mancante, CNI | `describe` |
| `ImagePullBackOff` | nome/tag sbagliato, registry privato senza `imagePullSecrets`, rate limit di Docker Hub | `describe` |
| `CrashLoopBackOff` | il **processo esce**: config, permessi, comando | `logs` |
| `OOMKilled` (137) | limite di memoria superato | `lastState` / `state.terminated` |
| `Running` ma `0/1` | readiness che fallisce | `describe` |
| `Running 1/1` ma niente traffico | Service / selector / porta / policy | `endpointslices` |

È lo schema da imparare a memoria: la colonna STATUS ti dice **già** in quale componente cercare.

### Riquadro «NEL PROGETTO VERO»: guasti veri

In `~/biodistretto/kubernetes`, quattro guasti incontrati costruendolo:

1. **Due CNI accesi.** Il provider minikube lascia attivo `87-podman-bridge.conflist` accanto a kindnet. I Pod prendono
   IP doppi, il plugin CSI va in CrashLoop con «no route to host» verso `10.96.0.1` (l'apiserver) e i PVC restano
   Pending. Si guarda **sul nodo**:
   ```bash
   minikube -p biodistretto ssh -n biodistretto-m02 -- ls /etc/cni/net.d
   grep -n -A3 '87-podman-bridge' ansible/roles/cluster/tasks/main.yml
   ```
2. **Pod che non finiscono mai di cancellarsi** su quella rete rotta: servono `--grace-period=0 --force`, e solo sui
   Pod di `kube-system`.
   ```bash
   grep -n 'grace-period=0' ansible/roles/cluster/tasks/main.yml
   ```
3. **`kubectl cp` con rc 127**: `kubectl cp` usa `tar` dentro il container, e l'immagine MinIO non ce l'ha (127 =
   comando non trovato). Ripiego: port-forward e `mc mirror`.
   ```bash
   grep -n 'port-forward' ansible/roles/dati/tasks/media.yml
   ```
4. **Dopo un riavvio del PC l'API non risponde**: i container dei nodi ripartono, ma kubelet e cri-docker no. Serve
   `minikube start`, ed è per questo che c'è un `@reboot` nel crontab:
   ```bash
   grep -n -B2 -A3 'special_time: reboot' ansible/roles/cluster/tasks/main.yml
   ```

---

## 2. `guardia_contesto()`

```bash
attuale="$(kubectl config current-context)"
[[ "$attuale" == "lab" || "${CONTESTO_LAB:-}" == "$attuale" ]] || {
  echo "STOP: contesto '$attuale' (atteso 'lab')" >&2; exit 1; }
```

Come nella lezione 01, ma con una via d'uscita: se esporti `CONTESTO_LAB=<nome>`, lo script accetta anche quel
contesto (utile per provarlo su un altro cluster di prova). Senza, accetta solo `lab`. Ogni funzione la chiama per prima.

---

## 3. `rompi` — i cinque guasti

Prima crea il namespace in modo **idempotente**:

```bash
kubectl create namespace $NS --dry-run=client -o yaml | kubectl apply -f -
```

`create --dry-run=client -o yaml` **genera** il manifest senza inviarlo; `apply` lo crea o lo lascia com'è. Un
`kubectl create namespace` diretto fallirebbe la seconda volta (già esistente) e con `set -e` fermerebbe lo script.

### Guasto 1 — `immagine`: ImagePullBackOff

```bash
kubectl -n $NS create deployment immagine --image=traefik/whoami:v9.9.9
```

Il tag `v9.9.9` non esiste. Il kubelet prova a scaricarlo, fallisce (`ErrImagePull`), poi riprova con attese sempre più
lunghe: `ImagePullBackOff`.

### Guasto 2 — `crash`: CrashLoopBackOff

```bash
kubectl -n $NS create deployment crash --image=busybox:1.37 \
  -- sh -c 'echo "manca DATABASE_URL" >&2; exit 1'
```

Il processo scrive un errore su stderr ed esce con 1. Il Deployment lo fa ripartire, lui muore di nuovo: il kubelet
allunga l'attesa fra un tentativo e l'altro (back-off) e lo stato diventa `CrashLoopBackOff`. Simula l'app a cui manca
una variabile di configurazione.

### Guasto 3 — `memoria`: OOMKilled

```yaml
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
```

- `head -c 100m /dev/zero` produce 100 MB di zeri; `tail` deve tenere in memoria l'**ultima riga**, e poiché negli zeri
  non c'è mai un a capo, l'"ultima riga" è tutto il flusso: la memoria cresce fino a sfondare il limite di **20Mi**.
- Il kernel uccide il processo (SIGKILL): reason **`OOMKilled`**, exit code **137** (128 + 9).
- `restartPolicy: Never`: è un Pod nudo e non viene riavviato, così lo stato di morte resta in
  `state.terminated` e lo si legge facilmente.

### Guasto 4 — `enorme`: Pending

```yaml
kind: Pod
metadata: { name: enorme }
spec:
  containers:
    - name: app
      image: busybox:1.37
      command: ["sleep", "3600"]
      resources:
        requests: { cpu: "64" }
```

Chiede **64 CPU**. Nessun nodo del lab ha tanto, nemmeno considerando che il kubelet dichiara come capacità tutto il PC
(lezione 01): lo scheduler non trova posto, il Pod resta **Pending** con l'evento `FailedScheduling` "Insufficient cpu".
Nessun container parte, quindi non ci sono log.

### Guasto 5 — `eco`: Service senza endpoint

```bash
kubectl -n $NS create deployment eco --image=traefik/whoami:v1.12
kubectl -n $NS create service clusterip eco --tcp=80:80 --dry-run=client -o yaml \
  | sed 's/app: eco/app: ecco/' | kubectl apply -f -
```

- `create deployment eco` mette ai Pod la label **`app: eco`**; il container si chiama `whoami` (kubectl lo ricava dal
  nome dell'immagine) e whoami, senza `--port`, ascolta sulla 80.
- `create service … --dry-run=client -o yaml` genera un Service con selector `app: eco`; `sed` lo cambia in
  **`app: ecco`** prima dell'apply.
- Risultato: tutti i Pod sono `Running 1/1`, ma il Service **non seleziona nessuno**. È il guasto più subdolo: niente
  è rosso in `get pod`.

---

## 4. `diagnosi` — il metodo applicato

### 1. STATO

```bash
kubectl -n $NS get pod -o wide
```

| Pod | STATUS atteso |
|---|---|
| `immagine-…` | `ImagePullBackOff` (o `ErrImagePull`) |
| `crash-…` | `CrashLoopBackOff` (RESTARTS che sale) |
| `memoria` | `OOMKilled` |
| `enorme` | `Pending`, colonna NODE vuota |
| `eco-…` | `Running 1/1` — il guasto qui non si vede |

### 2. EVENTI

```bash
kubectl -n $NS get events --field-selector type=Warning \
  --sort-by=.lastTimestamp -o custom-columns=OGGETTO:.involvedObject.name,MOTIVO:.reason,MESSAGGIO:.message \
  | cut -c1-160
```

- `--field-selector type=Warning`: solo gli avvisi, niente rumore dei `Normal`.
- `--sort-by=.lastTimestamp`: i più recenti **in fondo**.
- `custom-columns`: tre colonne (oggetto, motivo, messaggio); `cut -c1-160` taglia le righe lunghe.

Vedi i motivi esatti: `Failed` (pull dell'immagine), `BackOff`, `FailedScheduling` (Insufficient cpu).

### 3. LOG del container crashato

```bash
kubectl -n $NS logs deploy/crash --tail=5
kubectl -n $NS logs deploy/crash --previous --tail=5; echo
```

Il commento del file corregge un luogo comune: **durante il back-off il container "attuale" è già quello morto**, quindi
i suoi log sono già l'errore (`manca DATABASE_URL`). `--previous` è l'istanza **prima ancora**, se il runtime la
conserva; altrimenti stampa "unable to retrieve" **ed esce con 0** (provato su k3s). Quindi un `|| ripiego` dopo
`--previous` non scatterebbe mai. `logs deploy/crash` sceglie da solo un Pod del Deployment.

### 4. Perché è morto `memoria`

```bash
kubectl -n $NS get pod memoria \
  -o jsonpath='{.status.containerStatuses[0].state.terminated.reason} exit={.status.containerStatuses[0].state.terminated.exitCode}{"\n"}'
```

Stampa `OOMKilled exit=137`. Qui si legge `state.terminated` (il Pod non ripartirà); per un container che è ripartito
si guarderebbe `lastState.terminated`.

### 5. Il Service `eco` ha endpoint?

```bash
kubectl -n $NS get endpointslices -l kubernetes.io/service-name=eco
kubectl -n $NS get svc eco -o jsonpath='selector={.spec.selector}{"\n"}'
kubectl -n $NS get pod -l app=eco --show-labels
```

L'EndpointSlice **non ha indirizzi**; il selector dice `{"app":"ecco"}`; i Pod hanno `app=eco`. Il confronto delle due
righe è la diagnosi. (Lezione 03: "Service muto, prima gli EndpointSlice".)

### 6. Debug in un Pod senza shell

```bash
pod="$(kubectl -n $NS get pod -l app=eco -o name | head -1)"
kubectl -n $NS debug "$pod" -i --profile=general --image=busybox:1.37 --target=whoami -- \
  sh -c 'ps; wget -qO- localhost/api | head -c 80; echo' || true
```

L'immagine whoami è **FROM scratch**: niente `sh`, niente `ps`, `kubectl exec` non ha niente da eseguire.
`kubectl debug` aggiunge al Pod un **container effimero** (qui busybox):

| Opzione | Perché |
|---|---|
| `--image=busybox:1.37` | gli attrezzi che l'app non ha |
| `--target=whoami` | condivide il **namespace dei processi** del container `whoami`: `ps` mostra il processo dell'app |
| `--profile=general` | il profilo di permessi del container di debug |
| `-i` | serve per **vedere l'output**: senza, il comando gira e non stampa |
| `wget -qO- localhost/api` | il container effimero condivide anche la **rete** del Pod: `localhost` è whoami (porta 80). `head -c 80` tiene i primi 80 caratteri |
| `\|\| true` | con `set -e`, un fallimento del debug non deve fermare lo script |

Il container effimero resta nella spec del Pod (non si può togliere): sparisce solo ricreando il Pod.

---

## 5. `pulisci`

```bash
kubectl delete namespace $NS --wait=false
```

Cancella il namespace e **tutto ciò che contiene**. `--wait=false` restituisce subito il prompt; il namespace resta
`Terminating` ancora per un po'.

---

## 6. Il runner, passo per passo

Il runner (`~/kubernetesprj/kubernetes/08-troubleshooting.sh`) fa `guardia_lab` e poi **gli stessi comandi**, in 16 passi:

| # | Cosa | Note |
|---|---|---|
| 1 | namespace `rotto` (dry-run \| apply) | idempotente |
| 2 | guasto 1 `immagine` | tag `v9.9.9` |
| 3 | guasto 2 `crash` | |
| 4 | guasto 3 `memoria` | "alloca 100 MB con un limite di 20 MiB" |
| 5 | guasto 4 `enorme` | 64 CPU |
| 6 | guasto 5 `eco` + Service con `app: ecco` | creati con `&&`: il Service solo se il Deployment è nato |
| 7 | `sleep 30` | il tempo perché i guasti si manifestino |
| 8 | METODO 1 — `get pod -o wide` | la colonna STATUS dice già il tipo di guasto |
| 9 | METODO 2 — eventi Warning | Failed pull, BackOff, FailedScheduling… |
| 10 | METODO 3 — `logs deploy/crash --tail=5; logs … --previous --tail=5` | qui **senza** l'`echo` finale della lezione |
| 11 | jsonpath di `memoria` | `OOMKilled exit=137` (128 + SIGKILL 9) |
| 12 | `describe pod enorme \| tail -5` | gli eventi in fondo: `FailedScheduling … Insufficient cpu` |
| 13 | EndpointSlice di `eco` | vuoto… |
| 14 | selector del Service + label dei Pod | …perché `ecco` ≠ `eco` |
| 15 | `kubectl debug … --target=whoami` | qui **senza** `\|\| true`: se fallisce, `passo` mostra la riga rossa |
| 16 | `kubectl delete namespace rotto --wait=false` | pulizia |

Il passo 12 non è nella `diagnosi` della lezione: il runner aggiunge il `describe` del Pod Pending.

**Tutti i guasti sono voluti**: i passi 2-6 riescono (gli oggetti vengono creati), è il loro **stato** a essere rotto.
La riga rossa "uscita ≠ 0" può comparire al passo 10 se `--previous` non trova l'istanza precedente (secondo la
lezione su k3s esce 0; su altri runtime il codice può essere diverso).

Se rilanci il runner subito dopo la pulizia, il namespace può essere ancora `Terminating` e le creazioni falliscono:
aspetta che `kubectl get ns rotto` dica `NotFound`.

---

## 7. Altri attrezzi (coda del file)

| Comando | A cosa serve |
|---|---|
| `kubectl debug node/lab-m02 -it --image=busybox:1.37` | shell **sul nodo** (il filesystem del nodo è in `/host`) |
| `kubectl top pod --containers -n X` | CPU/memoria reali per container |
| `kubectl get pod X -o yaml \| grep -A5 lastState` | l'ultima morte |
| `kubectl events -n X --for pod/Y` | gli eventi di un solo oggetto |
| `kubectl get --raw /api/v1/nodes/N/proxy/stats/summary` | metriche del kubelet |
| `journalctl -u kubelet` | log del kubelet, sul nodo |
| `crictl ps -a` / `crictl logs` | il runtime, sotto kubectl |

**Gli eventi durano 1 ora**: per lo storico servono log e metriche (lezione 13).

---

## 8. Le trappole

| Trappola | Cosa succede | Rimedio |
|---|---|---|
| `get pod` tutto verde e "funziona" | il Service può non avere endpoint | guardare gli EndpointSlice |
| fidarsi di `logs --previous \|\| ripiego` | `--previous` può uscire 0 anche senza log | in back-off basta `logs` |
| cercare i log di un Pod Pending | il container non è mai partito | `describe` → eventi dello scheduler |
| `kubectl exec` su un'immagine scratch | niente shell da eseguire | `kubectl debug --target` |
| `kubectl debug` senza `-i` | il comando gira ma non vedi l'output | `-i` |
| `kubectl cp` su immagini senza `tar` | rc 127 | port-forward + client dedicato |
| cercare eventi vecchi | dopo 1 ora non ci sono più | log e metriche centralizzati |
| `create namespace` diretto in uno script | la seconda volta fallisce | `--dry-run=client -o yaml \| kubectl apply -f -` |

---

## 9. La coda: domande da colloquio

- **CrashLoopBackOff ma `kubectl logs` è vuoto.** Prova `--previous`; se è vuoto anche quello, il processo muore
  **prima di scrivere**: comando o entrypoint sbagliato, binario per un'altra architettura (`exec format error`),
  permessi sul file, `readOnlyRootFilesystem` che impedisce di scrivere. `describe` mostra exit code e reason.
- **L'app risponde da dentro il Pod ma non dal Service.** EndpointSlice vuoti (selector o readiness), `targetPort`
  sbagliata, l'app ascolta su `127.0.0.1` invece di `0.0.0.0`, NetworkPolicy.
- **Il nodo è NotReady.** kubelet fermo, disco pieno (DiskPressure), memoria, CNI rotto, certificati scaduti.
  `describe node` → Conditions; sul nodo `journalctl -u kubelet`.

---

## Riepilogo

- Metodo: **stato → eventi → log → dentro → intorno**.
- **Pending = scheduler**; **ImagePull/ContainerCreating = kubelet**; **Crash = app**.
- In back-off `logs` mostra **già** l'istanza morta; **exit 137 = OOM o SIGKILL**.
- **Service muto: prima gli EndpointSlice**.
- **`kubectl debug`** per immagini senza shell e per i nodi.

## Prova da solo

1. Prima di lanciare `diagnosi`, scrivi su un foglio la causa e la tappa del metodo che la rivela per ognuno dei cinque
   guasti. Poi lancia `diagnosi` e confronta: quale guasto non avresti visto con il solo `get pod`?
2. Ripara il Service `eco` senza ricrearlo: `kubectl -n rotto patch svc eco -p '{"spec":{"selector":{"app":"eco"}}}'`,
   poi ricontrolla gli EndpointSlice e chiamalo da un Pod busybox (`wget -qO- eco/api`).
3. Ripara `memoria`: portala a un limite che basti (il Pod è immutabile nelle risorse: va cancellato e ricreato) e
   guarda che stato finale ottiene. Poi prova `kubectl debug node/lab-m02 -it --image=busybox:1.37` e cerca
   `/host/etc/cni/net.d`: quanti file di configurazione CNI ci sono?
````

### Fonte originale: `08-troubleshooting.sh`

> **Trascrizione integrale del file originale**, senza riscrittura. Questo blocco è una fonte di riferimento per il sito.

````bash
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
#
# ── NEL PROGETTO VERO: il Biodistretto su minikube ───────────────────────
#   ~/biodistretto/kubernetes (branch kubernetes). I grep partono da lì:
#   cd ~/biodistretto/kubernetes · come si usa: il README della cartella
#   Guasti veri, incontrati costruendolo:
#   1) DUE CNI ACCESI. Il provider minikube lascia attivo
#      87-podman-bridge.conflist accanto a kindnet. I Pod prendono IP doppi,
#      il plugin CSI va in CrashLoop con «no route to host» verso 10.96.0.1
#      e i PVC restano Pending. Si guarda sul nodo:
#        minikube -p biodistretto ssh -n biodistretto-m02 -- ls /etc/cni/net.d
#        grep -n -A3 '87-podman-bridge' ansible/roles/cluster/tasks/main.yml
#   2) POD CHE NON FINISCONO MAI DI CANCELLARSI su quella rete rotta:
#      servono --grace-period=0 --force, e solo sui Pod di kube-system.
#        grep -n 'grace-period=0' ansible/roles/cluster/tasks/main.yml
#   3) `kubectl cp` CON rc 127: kubectl cp usa tar dentro il container, e
#      l'immagine MinIO non ce l'ha. Ripiego: port-forward e `mc mirror`.
#        grep -n 'port-forward' ansible/roles/dati/tasks/media.yml
#   4) DOPO UN RIAVVIO DEL PC l'API non risponde: i container dei nodi
#      ripartono, ma kubelet e cri-docker no. Serve `minikube start`, ed è
#      per questo che c'è un @reboot nel crontab:
#        grep -n -B2 -A3 'special_time: reboot' ansible/roles/cluster/tasks/main.yml

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
````

### Fonte originale: `08-troubleshooting(1).sh`

> **Trascrizione integrale del file originale**, senza riscrittura. Questo blocco è una fonte di riferimento per il sito.

````bash
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
````

## Traccia per lo studio attivo

Prima di passare oltre: rileggi il manifest e lo script della lezione, individua il comando che produce l’osservazione principale, spiega perché il risultato è atteso, poi confronta la tua spiegazione con le riflessioni e le domande da colloquio del Markdown originale. Non applicare gli script a un cluster diverso dal laboratorio senza verificare i contesti.

---

<a id="lezione-09"></a>

# Lezione 09 — Helm: Chart da zero, upgrade e rollback

## Spiegazione e riflessioni ragionate

### Modello mentale del professore
**Chart** = pacchetto di template, valori e metadati; **Release** = installazione del Chart con un nome e una cronologia numerata. Helm genera YAML Kubernetes, gestisce install/upgrade/rollback, ma non sostituisce controller e kubelet che rendono effettivo lo stato. Non confondere `Chart.version`, `appVersion` e la `revision` della Release.

### Chart eco
Lo script autore genera `Chart.yaml`, `values.yaml`, `values.schema.json`, `_helpers.tpl`, `configmap.yaml`, `deployment.yaml`, `service.yaml`, `ingress.yaml`, `NOTES.txt` e `.helmignore`. I valori predefiniti sono due repliche, immagine traefik/whoami con tag dalla `.Chart.AppVersion`, Service 80→container 8080, ConfigMap MESSAGGIO, Ingress opzionale. `_helpers.tpl` definisce nome e label stabili, evitando di inserire versioni nel selector immutabile del Deployment.

### Come leggere il template
`.Values` sono i parametri; `.Chart` i metadati; `.Release` identifica l'installazione. `include` restituisce il frammento riusabile, `nindent` corregge la struttura YAML, `quote` conserva i valori come stringa, `toYaml` renderizza mappe, `required` ferma la generazione quando manca un campo, `default` fornisce fallback. `values.schema.json` rifiuta per esempio `replicaCount=0` prima di toccare il cluster.

### La riflessione chiave dalle lezioni 02 e 04
Il template mette `checksum/config` nel Pod template, calcolato dall'output renderizzato della ConfigMap. Se `config.messaggio` cambia tramite upgrade Helm, cambia il checksum → nuovo Pod template → rollout. Un semplice patch diretto della ConfigMap non aggiorna da solo l'annotazione.

### Il ciclo della Release
`helm lint --strict` → `helm template` → `helm upgrade --install ... --wait` → revision 1. Upgrade del messaggio → revision 2. Upgrade con tag inesistente e `--rollback-on-failure` → revision 3 fallita e revisione di ripristino 4 se l'operazione riesce. `helm rollback eco 1` crea un'ulteriore revisione (tipicamente 5), senza cancellare la storia. `helm get values` legge i valori utente, `helm get manifest` il manifest installato. Helm salva normalmente revisioni come Secret `helm.sh/release.v1`: proteggili tramite RBAC.

### Attenzioni operative
`--reuse-values` e nuovi default del Chart hanno regole specifiche; `--reset-then-reuse-values` è una possibile alternativa. Un Helm interrotto può lasciare uno stato `pending-upgrade`: ispezionare la history prima di toccare lo storage della release. `helm template` locale non equivale a un test di admission del cluster.

### Verifica rapida
1. Chart e Release sono lo stesso oggetto?
2. Perché `helm template` è utile nelle PR?
3. Perché un cambiamento ConfigMap può provocare rollout nel nostro Chart?
4. `helm rollback` elimina le revisioni successive o aggiunge una revisione?

## Materiale originale della lezione


### Fonte originale: `09-helm-chart.md`

> **Trascrizione integrale del file originale**, senza riscrittura. Questo blocco è una fonte di riferimento per il sito.

````markdown
# 09 — Helm: un chart scritto da zero, install, upgrade e rollback

Spiegazione di `09-helm-chart.sh` (questa cartella). Lezione sul sito: http://127.0.0.1:3000/kubernetes/9

## In una frase

Lo script **scrive un chart Helm completo** (`./eco`: Chart.yaml, values.yaml, values.schema.json, template) e poi
lo porta in giro per tutto il **ciclo di vita di una release**: lint, rendering locale, install, upgrade, upgrade
fallito con rollback automatico, rollback manuale. Alla fine ti fa vedere **dove Helm tiene la storia**: nei Secret
del namespace.

## Due file con lo stesso nome: quale lanciare

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/lezioni/kubernetes/09-helm-chart.sh` | **questo**: la lezione, con le spiegazioni nei commenti | `bash 09-helm-chart.sh crea` · `prova` · `pulisci` |
| `~/kubernetesprj/kubernetes/09-helm-chart.sh` | lo script **guidato**: chiama `crea` di questo file e poi esegue i comandi Helm uno per volta, spiegando prima di eseguire (Invio / s / q) | `bash kubernetes/09-helm-chart.sh` |

Per imparare conviene lo **guidato**. Lavora nella cartella `lavoro/helm` (funzione `cartella helm` di `passo.sh`):
è lì che finisce il chart `./eco`, che servirà anche alla lezione 10 (come dipendenza) e alla 12 (deploy).

## Com'è fatto il file

```
intestazione (commenti)  → i tre problemi che Helm risolve, novità di Helm 4, NEL PROGETTO VERO
set -euo pipefail        → lo script si ferma al primo errore
CHART=./eco  NS=lab-helm → dove scrive il chart, in quale namespace installa
crea()                   → scrive tutti i file del chart con dei heredoc (cat > file <<'EOF')
prova()                  → lint, template, install, upgrade, rollback (in sequenza, senza pause)
case "$1"                → crea | prova | pulisci
coda (commenti)          → funzioni di template, precedenza dei valori, domande da colloquio, riepilogo
```

I heredoc sono scritti con `<<'EOF'` (EOF **tra apici**): la shell non tocca il testo, quindi `{{ ... }}` e `$(MESSAGGIO)`
arrivano nei file così come sono.

---

## 1. La teoria nell'intestazione

Versioni dichiarate: **Helm 4.3 · Kubernetes 1.35**, livello 4 "Packaging e delivery". Sull'Ubuntu del lab c'è
`helm v4.3.1`.

### I tre problemi che `kubectl apply` non risolve

| Problema | Come lo risolve Helm |
|---|---|
| **Parametri** | un solo set di template, valori diversi per ambiente |
| **Release** | un nome che raggruppa tutti gli oggetti installati, con una storia numerata (**revision**) salvata nel cluster come Secret di tipo `helm.sh/release.v1` |
| **Ciclo di vita** | install, upgrade, rollback, uninstall, hook, test |

### Helm 4 rispetto al 3 (uscito a novembre 2025)

| Cosa cambia | Perché conta |
|---|---|
| **server-side apply di default** per le release nuove | il server registra chi possiede ogni campo (field ownership, vedi lezione 01): conflitti espliciti invece di sovrascritture silenziose |
| `--atomic` → `--rollback-on-failure` | stesso significato, nome nuovo: se l'upgrade fallisce, torna indietro da solo |
| `--force` → `--force-replace` | il nome dice cosa fa: ricrea gli oggetti invece di aggiornarli |
| `--wait` ha **strategie**: `watcher` (kstatus, il default con `--wait`), `legacy` e `hookOnly` (il default quando `--wait` manca) | il watcher usa le regole di kstatus per decidere quando un oggetto è "pronto" |
| plugin in WebAssembly; chart **v2 invariati** | i chart scritti per Helm 3 funzionano ancora |

### Riquadro «NEL PROGETTO VERO»

In `~/biodistretto/kubernetes` (branch `kubernetes`) **Helm non c'è**. Il progetto usa YAML con `${variabili}`, resi
da `templatefile` di Terraform e spezzati in oggetti con `manifest_decode_multi`:

```bash
cd ~/biodistretto/kubernetes
grep -n 'manifest_decode_multi' terraform/app/workload.tf
grep -n -F '${repliche}' terraform/app/manifests/app.yaml.tftpl
```

Le stesse idee, a confronto:

| Helm | Progetto (Terraform) |
|---|---|
| `values.yaml` | `variables.tf` |
| release e revision | `tfstate` |
| `helm rollback` | `git revert` + `apply` |

Perché lì va bene così: i segreti e la CA li crea Terraform **nello stesso grafo**, senza doverli passare a Helm.
Esercizio proposto dal file: trasforma `app.yaml.tftpl` in un chart (`${x}` → `{{ .Values.x }}`) e confronta l'output
di `helm template` con quello che c'è nel cluster.

---

## 2. `crea()` — il chart, file per file

Alla fine `find eco -type f | sort` (passo 3 del guidato) mostra:

```
eco/.helmignore
eco/Chart.yaml
eco/templates/NOTES.txt
eco/templates/_helpers.tpl
eco/templates/configmap.yaml
eco/templates/deployment.yaml
eco/templates/ingress.yaml
eco/templates/service.yaml
eco/values.schema.json
eco/values.yaml
```

### `Chart.yaml` — la carta d'identità

| Campo | Valore | Perché |
|---|---|---|
| `apiVersion` | `v2` | formato dei chart di Helm 3 e 4 |
| `name` | `eco` | nome del chart, finisce in `.Chart.Name` |
| `type` | `application` | installabile. `library` = solo helper, non si installa |
| `version` | `0.1.0` | SemVer **del chart**: si alza a ogni modifica del chart |
| `appVersion` | `"v1.12"` | versione **dell'app**; usata come tag immagine di default |

`version` e `appVersion` sono due cose diverse: puoi cambiare un template (chart 0.1.1) senza cambiare l'app.

### `values.yaml` — l'interfaccia pubblica

```yaml
replicaCount: 2
image:
  repository: traefik/whoami
  tag: ""                # vuoto = appVersion
  pullPolicy: IfNotPresent
service:
  port: 80
config:
  messaggio: "ciao dal chart"
resources:
  requests: { cpu: 20m, memory: 16Mi }
  limits: { memory: 32Mi }
ingress:
  enabled: false
  host: eco.lab.local
```

Tutto quello che chi usa il chart può cambiare con `--set` o `-f` sta qui. Quello che non c'è, non si cambia senza
toccare i template. `tag: ""` è un trucco comune: lasciato vuoto, il template usa `appVersion`.

### `values.schema.json` — validazione prima del rendering

Uno schema JSON (draft-07): `replicaCount` e `image` sono obbligatori, `replicaCount` deve essere un **intero ≥ 1**,
`image.repository` una stringa non vuota. Helm lo applica **prima** di renderizzare: un valore sbagliato si ferma lì,
non arriva mai al cluster.

### `templates/_helpers.tpl` — i `define` riusabili

I file che cominciano con `_` **non producono YAML**: contengono solo definizioni.

| Define | Cosa restituisce |
|---|---|
| `eco.fullname` | se il nome della release **contiene** già il nome del chart, usa solo la release; altrimenti `<release>-<chart>`. Sempre tagliato a 63 caratteri (`trunc 63`) e senza `-` finale (`trimSuffix "-"`) |
| `eco.selectorLabels` | `app.kubernetes.io/name` (chart) e `app.kubernetes.io/instance` (release): le label **stabili**, usate nei selector |
| `eco.labels` | le selectorLabels + `app.kubernetes.io/version`, `app.kubernetes.io/managed-by` (`.Release.Service`, cioè Helm) e `helm.sh/chart: eco-0.1.0` |

Esempi: release `eco` → oggetti chiamati `eco`; release `prova` (usata da `helm template prova`) → `prova-eco`.
Il limite di 63 viene dai nomi DNS di Kubernetes.

Perché due insiemi di label: il `selector` di un Deployment **non si può cambiare** dopo la creazione. Se ci mettessi
la versione, ogni upgrade romperebbe il selector. Per questo nel selector vanno solo le label che non cambiano.

### `templates/configmap.yaml`

Una ConfigMap con nome `eco.fullname` e una sola chiave: `MESSAGGIO: {{ .Values.config.messaggio | quote }}`.
`quote` mette le virgolette, così un valore come `yes` o `0.1` resta una stringa.

`labels: {{- include "eco.labels" . | nindent 4 }}`: `include` restituisce il testo del define, `nindent 4` va a capo e
lo indenta di 4 spazi. Il `{{-` mangia lo spazio prima, così il blocco finisce al posto giusto sotto `labels:`.

### `templates/deployment.yaml` — il cuore

| Riga | Cosa fa |
|---|---|
| `replicas: {{ .Values.replicaCount }}` | numero di Pod dai valori |
| `matchLabels: {{- include "eco.selectorLabels" . \| nindent 6 }}` | il selector con le sole label stabili |
| `checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . \| sha256sum }}` | renderizza la ConfigMap e ne calcola l'hash. Cambia la config → cambia l'hash → cambia il template del Pod → **rollout**. Senza questo, cambiare una ConfigMap non fa ripartire i Pod |
| `image: "{{ .Values.image.repository }}:{{ .Values.image.tag \| default .Chart.AppVersion }}"` | con `tag: ""` diventa `traefik/whoami:v1.12` |
| `args: ["--port", "8080", "--name", "$(MESSAGGIO)"]` | whoami ascolta sulla 8080; `$(MESSAGGIO)` lo espande **Kubernetes** (non la shell) con la variabile d'ambiente del container |
| `envFrom: configMapRef` | tutte le chiavi della ConfigMap diventano variabili d'ambiente: da qui arriva `MESSAGGIO` |
| `ports: name: http, containerPort: 8080` | porta con nome, usata da probe e Service |
| `readinessProbe: httpGet /health, port: http` | il Pod riceve traffico solo quando `/health` risponde |
| `{{- with .Values.resources }} resources: {{- toYaml . \| nindent 12 }} {{- end }}` | se `resources` c'è, lo copia **intero** come YAML; `with` cambia il contesto `.` nel blocco |

### `templates/service.yaml`

Service con selector sulle selectorLabels, porta `{{ .Values.service.port }}` (80) verso `targetPort: http`, cioè la
porta con nome del container (8080). Cambiare il numero nel container non richiede di toccare il Service.

### `templates/ingress.yaml` — opzionale

Tutto il file è dentro `{{- if .Values.ingress.enabled }} … {{- end }}`: con il default `false` **non produce niente**.
Con `ingress.enabled=true` esce un Ingress con `ingressClassName: nginx`, path `/` di tipo `Prefix` verso il Service
sulla porta `http`. L'host usa `required`:

```
{{ required "ingress.host è obbligatorio con ingress.enabled" .Values.ingress.host }}
```

Se l'host manca, il rendering **fallisce** con quel messaggio invece di produrre un Ingress senza host.

### `templates/NOTES.txt`

Non è un manifest: è il testo che Helm stampa **dopo** install e upgrade. Qui dice nome e revision della release e il
comando `kubectl -n <ns> port-forward svc/<nome> 8080:80` per provarla.

### `.helmignore`

Come `.gitignore`: `.git/` e `*.tgz` non finiscono nel pacchetto del chart.

---

## 3. Il percorso del guidato, passo per passo

Il guidato non chiama `prova`: esegue gli stessi comandi uno alla volta (più qualche `cat`/`find`), nel namespace
`lab-helm`.

| # | Comando | Cosa vedi |
|---|---|---|
| 1 | `helm version` | la versione: sul lab è la 4, con server-side apply di default |
| 2 | `bash $LEZIONI/kubernetes/09-helm-chart.sh crea` | `chart scritto in ./eco` |
| 3 | `find eco -type f \| sort` | i file elencati sopra |
| 4 | `cat eco/values.yaml` | l'interfaccia pubblica |
| 5 | `helm lint eco --strict` | errori di struttura e di template **prima** di toccare il cluster. `--strict` tratta anche gli avvisi come errori |
| 6 | `helm template prova eco --set ingress.enabled=true \| grep ^kind:; helm template prova eco --set ingress.enabled=true --show-only templates/ingress.yaml` | i manifest renderizzati **in locale, senza cluster**: è quello che finirebbe nell'apply. Gli oggetti si chiamano `prova-eco`. Prima l'elenco dei tipi (ConfigMap, Service, Deployment, Ingress), poi solo l'Ingress acceso con `--set`: `--show-only` rende un template solo. Tutto intero è lungo: l'Ingress comincia alla riga 87 |
| 7 | `helm template prova eco --set replicaCount=0` | **fallisce apposta**: lo schema JSON rifiuta `replicaCount=0` (minimo 1) **prima** del rendering. Il guidato stampa l'uscita ≠ 0 in rosso: è voluto |
| 8 | `helm upgrade --install eco eco -n lab-helm --create-namespace --wait --timeout 2m` | installa (la release non c'è ancora), crea il namespace, aspetta che i Pod siano pronti. Stampa le NOTES |
| 9 | `helm -n lab-helm history eco` | revision 1, `deployed` |
| 10 | `helm upgrade eco eco -n lab-helm --reuse-values --set config.messaggio='seconda versione' --wait --timeout 2m` | cambia solo il messaggio. Cambia la ConfigMap → cambia il checksum → i Pod ripartono. Revision 2 |
| 11 | `helm upgrade eco eco -n lab-helm --reuse-values --set image.tag=v9.9.9 --rollback-on-failure --timeout 60s` | **fallisce apposta**: l'immagine `traefik/whoami:v9.9.9` non esiste, i Pod nuovi non diventano mai pronti. Dopo 60 s Helm dichiara il fallimento e **torna da solo** alla versione buona |
| 12 | `helm -n lab-helm history eco` | revision 3 `failed`, revision 4 = rollback automatico alla 2 |
| 13 | `helm -n lab-helm get values eco` | solo i valori **passati dall'utente** (qui `config.messaggio`), non i default del chart |
| 14 | `helm -n lab-helm get manifest eco \| grep -m1 'image:'` | il manifest effettivamente installato: l'immagine in uso è di nuovo quella buona, non la `v9.9.9` |
| 15 | `helm -n lab-helm rollback eco 1 --wait` | rollback manuale alla revision 1. Un rollback **non cancella** la storia: aggiunge una revision nuova con il contenuto della 1 |
| 16 | `kubectl -n lab-helm get secret -l owner=helm` | un Secret per revision, tipo `helm.sh/release.v1`: è la storia della release |

Nota finale del guidato: il chart `./eco` serve alla lezione 10 (dipendenza) e alla 12 (deploy). Pulizia:
`helm uninstall eco -n lab-helm && kubectl delete ns lab-helm`.

### `prova()` nella lezione: le stesse cose in un colpo

`prova` fa la stessa sequenza (dal lint al `get secret`) ma senza pause e con due accorgimenti per non fermarsi con
`set -e` sui passi che falliscono apposta:

```bash
helm template prova $CHART --set replicaCount=0 && exit 1 || echo "OK: replicaCount=0 rifiutato"
helm upgrade … --set image.tag=v9.9.9 --rollback-on-failure --timeout 60s || echo "OK: upgrade fallito e annullato"
```

Il primo si legge così: se il template **riesce**, è un errore (lo schema non funziona) ed esce con 1; se fallisce,
stampa OK. Prima di tutto controlla a mano che il contesto sia `lab`, come la guardia della lezione 01.
`pulisci` fa `helm uninstall eco -n lab-helm; kubectl delete ns lab-helm`.

---

## 4. Le trappole

- **L'indentazione.** `{{-` e `-}}` tolgono spazi e a capo prima/dopo. Un `nindent` sbagliato o un trattino in più
  producono YAML valido ma sbagliato (o non valido). È il bug Helm più comune: per questo `helm template` prima di
  tutto.
- **`--reuse-values` ignora i nuovi default del chart.** Riusa i valori della release precedente; se il chart nuovo
  aggiunge un valore con un default, quel default non arriva. `--reset-then-reuse-values` unisce correttamente.
- **`lookup` in `helm template` è vuoto**: legge il cluster, ma il rendering locale il cluster non lo vede.
- **Il selector non si cambia**: mettici solo label stabili (name + instance), mai la versione.
- **Cambiare una ConfigMap non fa ripartire i Pod** se non c'è un `checksum/config` (o qualcosa di simile) nel
  template del Pod.
- **Helm interrotto a metà** lascia la release in `pending-*` e blocca ogni operazione successiva (vedi domande).

---

## 5. La coda: template e precedenza dei valori

### Le cose dei template che ti chiedono

| Costrutto | A cosa serve |
|---|---|
| `{{-  -}}` | tolgono spazi/a capo prima/dopo |
| `include` vs `template` | `include` restituisce una **stringa**, quindi puoi metterlo in pipe (`\| nindent`); `template` no |
| `toYaml . \| nindent N` | per blocchi interi (resources, tolerations) |
| `required "msg" .X` | fa fallire il rendering se manca un valore |
| `default`, `quote`, `tpl`, `lookup` | valore di ripiego, virgolette, rendering di una stringa come template, lettura dal cluster (vuoto in `helm template`) |
| `.Release .Chart .Values .Capabilities .Template .Files` | gli oggetti disponibili nei template |

### Precedenza dei valori (l'ultimo vince)

```
values.yaml del chart  <  values del chart padre  <  -f file1  <  -f file2  <  --set
```

---

## 6. Comandi e domande da colloquio

### Comandi da sapere

| Comando | A cosa serve |
|---|---|
| `helm lint eco --strict` | controllo statico del chart |
| `helm template <rel> eco --set …` | rendering locale |
| `helm upgrade --install … --wait --timeout 2m` | install idempotente, la forma da usare in CI |
| `helm upgrade … --rollback-on-failure` | upgrade che si annulla da solo se fallisce |
| `helm -n NS history eco` | la storia delle revision |
| `helm -n NS get values eco` / `get manifest eco` | valori dell'utente / manifest installato |
| `helm -n NS rollback eco 1 --wait` | torna a una revision |
| `kubectl -n NS get secret -l owner=helm` | i Secret della storia |

### Domande

- **Dove salva Helm lo stato? Cosa succede se cancello quel Secret?** Un Secret per revision, nel namespace della
  release. Cancellandoli Helm "dimentica" la release, ma gli oggetti restano nel cluster: un install successivo
  fallisce per conflitto di ownership (oppure serve `--take-ownership`).
- **Un upgrade è rimasto in `pending-upgrade` e ogni nuovo upgrade fallisce.** Un processo Helm è morto a metà (per
  esempio una CI cancellata). `helm history` mostra lo stato; si fa `helm rollback` all'ultima `deployed`. Se è
  `pending-install` non c'è una revision a cui tornare: `helm uninstall` e si reinstalla. È successo davvero
  preparando la lezione 13: Helm interrotto a metà → `another operation (install/upgrade/rollback) is in progress`.
  Per prevenirlo: `--rollback-on-failure` e timeout in CI.
- **Come rivedi cosa cambierà prima di un upgrade?** `helm template` + diff in PR, oppure il plugin helm-diff
  (`helm diff upgrade`), oppure `--dry-run=server`, che passa anche dall'admission del cluster.
- **Differenza fra `version` e `appVersion`?** La prima è la versione del chart (SemVer, cambia a ogni modifica del
  chart), la seconda dell'applicazione (qui il tag di default dell'immagine).

---

## Riepilogo

- Chart = template + values + Chart.yaml; release = un'installazione con storia.
- `_helpers.tpl` per nomi e label; `checksum/config` per i rollout quando cambia la config.
- `values.schema.json` e `required`: errori **prima** del cluster.
- In CI: `upgrade --install`, `--wait`, `--rollback-on-failure` (Helm 4).
- `history` / `rollback` / `get values` / `get manifest`; la storia sta nei Secret `owner=helm`.

## Prova da solo

1. `helm template prova eco --set ingress.enabled=true --set ingress.host=` : che errore ti dà? Da quale riga del
   chart arriva?
2. Fai un upgrade con `--set replicaCount=3`, poi `helm -n lab-helm history eco` e
   `kubectl -n lab-helm get secret -l owner=helm`: quante revision e quanti Secret vedi adesso?
3. Cambia `config.messaggio` con un upgrade **senza** toccare altro e confronta l'annotazione `checksum/config` del
   Deployment prima e dopo (`kubectl -n lab-helm get deploy eco -o yaml | grep checksum`). Poi rifai l'upgrade con lo
   stesso messaggio: i Pod ripartono?
````

### Fonte originale: `09-helm-chart(1).sh`

> **Trascrizione integrale del file originale**, senza riscrittura. Questo blocco è una fonte di riferimento per il sito.

````bash
#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# 09. HELM: UN CHART SCRITTO DA ZERO, INSTALL, UPGRADE E ROLLBACK
# Versione: Helm 4.3 · Kubernetes 1.35
# Livello: 4 — Packaging e delivery
# ═══════════════════════════════════════════════════════════════════════════
# Helm risolve tre problemi che kubectl apply non risolve:
#   1. PARAMETRI     un solo set di template, valori diversi per ambiente
#   2. RELEASE       un nome che raggruppa tutti gli oggetti installati,
#                    con una storia numerata (revision) salvata nel cluster
#                    come Secret di tipo helm.sh/release.v1
#   3. CICLO DI VITA install, upgrade, rollback, uninstall, hook, test
#
# HELM 4 (novembre 2025) rispetto al 3, da sapere al colloquio:
#   • server-side apply di default per le release nuove (field ownership)
#   • --atomic → --rollback-on-failure, --force → --force-replace
#   • --wait ha strategie: watcher (kstatus, default con --wait), legacy
#   • plugin in WebAssembly, chart v2 invariati (i chart Helm 3 funzionano)
#
# LAB (sul tuo Ubuntu c'è helm v4.3.1)
#   bash 09-helm-chart.sh crea       # scrive ./eco
#   bash 09-helm-chart.sh prova      # lint, template, install, upgrade, rollback
#
# ── NEL PROGETTO VERO: il Biodistretto su minikube ───────────────────────
#   ~/biodistretto/kubernetes (branch kubernetes). I grep partono da lì:
#   cd ~/biodistretto/kubernetes · come si usa: il README della cartella
#   Il progetto NON usa Helm. Usa YAML con ${variabili}, resi da
#   templatefile e separati in oggetti con manifest_decode_multi:
#     grep -n 'manifest_decode_multi' terraform/app/workload.tf
#     grep -n -F '${repliche}' terraform/app/manifests/app.yaml.tftpl
#   Le stesse cose, a confronto: values.yaml ↔ variables.tf;
#   release e revision ↔ tfstate; rollback ↔ git revert e apply.
#   Perché qui va bene così: i segreti e la CA li crea Terraform nello
#   stesso grafo, senza passarli a Helm.
#   ESERCIZIO: trasforma app.yaml.tftpl in un chart (${x} → {{ .Values.x }}),
#   poi confronta l'output di `helm template` con quello che c'è nel cluster.

set -euo pipefail
CHART=./eco
NS=lab-helm

crea() {
  mkdir -p $CHART/templates

  # ── Chart.yaml: version = versione del CHART, appVersion = dell'APP ─────
  cat > $CHART/Chart.yaml <<'EOF'
apiVersion: v2
name: eco
description: Un servizio HTTP di esempio
type: application        # "library" = solo helper, non installabile
version: 0.1.0           # SemVer del chart: si alza a ogni modifica del chart
appVersion: "v1.12"      # versione dell'app, usata come tag di default
EOF

  # ── values.yaml: l'interfaccia pubblica del chart ───────────────────────
  cat > $CHART/values.yaml <<'EOF'
replicaCount: 2
image:
  repository: traefik/whoami
  tag: ""                # vuoto = appVersion
  pullPolicy: IfNotPresent
service:
  port: 80
config:
  messaggio: "ciao dal chart"
resources:
  requests: { cpu: 20m, memory: 16Mi }
  limits: { memory: 32Mi }
ingress:
  enabled: false
  host: eco.lab.local
EOF

  # ── values.schema.json: valida i valori PRIMA di renderizzare ───────────
  cat > $CHART/values.schema.json <<'EOF'
{
  "$schema": "https://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["replicaCount", "image"],
  "properties": {
    "replicaCount": { "type": "integer", "minimum": 1 },
    "image": {
      "type": "object",
      "required": ["repository"],
      "properties": { "repository": { "type": "string", "minLength": 1 } }
    }
  }
}
EOF

  # ── _helpers.tpl: i "define" riusabili; i file con _ non producono YAML ─
  cat > $CHART/templates/_helpers.tpl <<'EOF'
{{- define "eco.fullname" -}}
{{- if contains .Chart.Name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "eco.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "eco.labels" -}}
{{ include "eco.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}
EOF

  cat > $CHART/templates/configmap.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "eco.fullname" . }}
  labels: {{- include "eco.labels" . | nindent 4 }}
data:
  MESSAGGIO: {{ .Values.config.messaggio | quote }}
EOF

  cat > $CHART/templates/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "eco.fullname" . }}
  labels: {{- include "eco.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels: {{- include "eco.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels: {{- include "eco.selectorLabels" . | nindent 8 }}
      annotations:
        # cambia il ConfigMap → cambia l'hash → cambia il template → rollout
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
    spec:
      containers:
        - name: eco
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          args: ["--port", "8080", "--name", "$(MESSAGGIO)"]
          envFrom:
            - configMapRef:
                name: {{ include "eco.fullname" . }}
          ports:
            - name: http
              containerPort: 8080
          readinessProbe:
            httpGet: { path: /health, port: http }
          {{- with .Values.resources }}
          resources: {{- toYaml . | nindent 12 }}
          {{- end }}
EOF

  cat > $CHART/templates/service.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: {{ include "eco.fullname" . }}
  labels: {{- include "eco.labels" . | nindent 4 }}
spec:
  selector: {{- include "eco.selectorLabels" . | nindent 4 }}
  ports:
    - name: http
      port: {{ .Values.service.port }}
      targetPort: http
EOF

  cat > $CHART/templates/ingress.yaml <<'EOF'
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "eco.fullname" . }}
  labels: {{- include "eco.labels" . | nindent 4 }}
spec:
  ingressClassName: nginx
  rules:
    - host: {{ required "ingress.host è obbligatorio con ingress.enabled" .Values.ingress.host }}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: {{ include "eco.fullname" . }}
                port: { name: http }
{{- end }}
EOF

  cat > $CHART/templates/NOTES.txt <<'EOF'
{{ .Release.Name }} installato (revision {{ .Release.Revision }}).
  kubectl -n {{ .Release.Namespace }} port-forward svc/{{ include "eco.fullname" . }} 8080:{{ .Values.service.port }}
EOF

  cat > $CHART/.helmignore <<'EOF'
.git/
*.tgz
EOF
  echo "chart scritto in $CHART"
}

prova() {
  [[ "$(kubectl config current-context)" == "lab" ]] || { echo "STOP: contesto non 'lab'" >&2; exit 1; }

  helm lint $CHART --strict
  # template = rendering locale, senza cluster: è ciò che si rivede in PR
  helm template prova $CHART --set ingress.enabled=true | grep '^kind:'
  helm template prova $CHART --set ingress.enabled=true --show-only templates/ingress.yaml
  # lo schema blocca i valori sbagliati prima di toccare il cluster
  helm template prova $CHART --set replicaCount=0 && exit 1 || echo "OK: replicaCount=0 rifiutato"

  # install idempotente: upgrade --install è la forma da usare in CI
  helm upgrade --install eco $CHART -n $NS --create-namespace \
    --wait --timeout 2m
  helm -n $NS history eco

  # upgrade con un valore diverso: il checksum fa ripartire i Pod
  helm upgrade eco $CHART -n $NS --reuse-values \
    --set config.messaggio="seconda versione" --wait --timeout 2m

  # upgrade che fallisce: immagine inesistente → rollback automatico
  helm upgrade eco $CHART -n $NS --reuse-values \
    --set image.tag=v9.9.9 --rollback-on-failure --timeout 60s \
    || echo "OK: upgrade fallito e annullato"
  helm -n $NS history eco             # revision 3 failed, 4 = rollback alla 2

  helm -n $NS get values eco          # i valori forniti dall'utente
  helm -n $NS get manifest eco | grep -m1 'image:'
  helm -n $NS rollback eco 1 --wait   # torna alla prima revision
  kubectl -n $NS get secret -l owner=helm   # dove Helm salva la storia
}

case "${1:-}" in
  crea) crea ;;
  prova) prova ;;
  pulisci) helm uninstall eco -n lab-helm; kubectl delete ns lab-helm ;;
  *) echo "uso: $0 crea|prova|pulisci" ;;
esac

# ── TEMPLATE: LE COSE CHE TI CHIEDONO ───────────────────────────────────────
#   {{-  -}}           tolgono gli spazi/a capo prima/dopo: l'indentazione
#                      sbagliata è il bug Helm più comune
#   include vs template  include restituisce una stringa → si può fare
#                      | nindent; template no
#   toYaml . | nindent N  per blocchi interi (resources, tolerations)
#   required "msg" .X  fallisce il rendering se manca un valore
#   default, quote, tpl, lookup (legge il cluster: vuoto in `helm template`)
#   .Release .Chart .Values .Capabilities .Template .Files
#
# PRECEDENZA DEI VALORI (l'ultimo vince)
#   values.yaml del chart < values del chart padre < -f file1 < -f file2 < --set
#   --reuse-values riusa i valori della release ma IGNORA i nuovi default
#   del chart; --reset-then-reuse-values li unisce correttamente.

# ── DOMANDE DA COLLOQUIO ────────────────────────────────────────────────────
# D: Dove salva Helm lo stato? Cosa succede se cancello quel Secret?
# R: Un Secret per revision nel namespace della release. Cancellandoli
#    Helm "dimentica" la release ma gli oggetti restano nel cluster: un
#    install successivo fallisce per conflitto di ownership (o serve
#    --take-ownership).
#
# D: Un upgrade è rimasto in "pending-upgrade" e ogni nuovo upgrade fallisce.
# R: Un processo Helm è morto a metà (CI cancellata). `helm history`
#    mostra lo stato; si fa `helm rollback` all'ultima deployed. Se è
#    "pending-install" non c'è una revision a cui tornare: `helm uninstall`
#    e si reinstalla (successo davvero preparando la lezione 13: helm
#    interrotto a metà → "another operation (install/upgrade/rollback) is
#    in progress"). Per prevenirlo: --rollback-on-failure e timeout in CI.
#
# D: Come rivedi cosa cambierà prima di un upgrade?
# R: helm template + diff in PR, oppure il plugin helm-diff
#    (`helm diff upgrade`), oppure `--dry-run=server` che passa
#    dall'admission del cluster.

# ══════════════════════════════════════════════════════════════════════════
# RIEPILOGO
# • Chart = template + values + Chart.yaml; release = installazione con storia
# • _helpers.tpl per nomi e label; checksum/config per i rollout da config
# • values.schema.json e required: errori prima del cluster
# • upgrade --install, --wait, --rollback-on-failure (Helm 4) in CI
# • history / rollback / get values / get manifest
# ══════════════════════════════════════════════════════════════════════════
````

### Fonte originale: `09-helm-chart.sh`

> **Trascrizione integrale del file originale**, senza riscrittura. Questo blocco è una fonte di riferimento per il sito.

````bash
#!/usr/bin/env bash
# Lezione 09 — un chart Helm scritto da zero: lint, template, install, upgrade, rollback.
source "$(dirname "$0")/../lib/passo.sh"
guardia_lab
titolo "09. Helm: chart da zero"
cartella helm
NS=lab-helm

passo "Versione di Helm (sul tuo Ubuntu è la 4: server-side apply di default)" \
  'helm version'
passo "Scrivo il chart ./eco con lo script della lezione: Chart.yaml, values.yaml, values.schema.json, template" \
  "bash $LEZIONI/kubernetes/09-helm-chart.sh crea"
passo "Com'è fatto un chart" \
  'find eco -type f | sort'
passo "values.yaml è l'interfaccia pubblica del chart: tutto quello che si può cambiare con --set o -f" \
  'cat eco/values.yaml'
passo "helm lint --strict: errori di struttura e di template prima di toccare il cluster" \
  'helm lint eco --strict'
passo "helm template: renderizza i manifest IN LOCALE, senza cluster. È quello che finirebbe nell'apply. Prima i tipi di oggetto, poi solo l'Ingress con --show-only" \
  'helm template prova eco --set ingress.enabled=true | grep ^kind:; helm template prova eco --set ingress.enabled=true --show-only templates/ingress.yaml'
passo "Lo schema JSON rifiuta replicaCount=0 PRIMA del rendering: errore atteso" \
  'helm template prova eco --set replicaCount=0'
passo "upgrade --install: installa se non c'è, aggiorna se c'è. --wait aspetta che i Pod siano pronti" \
  "helm upgrade --install eco eco -n $NS --create-namespace --wait --timeout 2m"
passo "La storia della release: revision 1, deployed" \
  "helm -n $NS history eco"
passo "Upgrade che cambia solo un valore: --reuse-values tiene gli altri. Il checksum della ConfigMap fa ripartire i Pod" \
  "helm upgrade eco eco -n $NS --reuse-values --set config.messaggio='seconda versione' --wait --timeout 2m"
passo "Upgrade con un'immagine inesistente e --rollback-on-failure: fallisce dopo 60 s e Helm torna da solo alla versione buona" \
  "helm upgrade eco eco -n $NS --reuse-values --set image.tag=v9.9.9 --rollback-on-failure --timeout 60s"
passo "History: revision 3 failed, revision 4 = rollback automatico alla 2" \
  "helm -n $NS history eco"
passo "I valori che l'utente ha passato (non i default)" \
  "helm -n $NS get values eco"
passo "Il manifest effettivamente installato: qui l'immagine in uso" \
  "helm -n $NS get manifest eco | grep -m1 'image:'"
passo "Rollback manuale alla revision 1" \
  "helm -n $NS rollback eco 1 --wait"
passo "Dove Helm salva la storia: un Secret per revision, tipo helm.sh/release.v1" \
  "kubectl -n $NS get secret -l owner=helm"
nota "Il chart ./eco serve alla lezione 10 (dipendenza) e alla 12 (deploy)." \
     "Pulizia:  helm uninstall eco -n $NS && kubectl delete ns $NS"
````

## Traccia per lo studio attivo

Prima di passare oltre: rileggi il manifest e lo script della lezione, individua il comando che produce l’osservazione principale, spiega perché il risultato è atteso, poi confronta la tua spiegazione con le riflessioni e le domande da colloquio del Markdown originale. Non applicare gli script a un cluster diverso dal laboratorio senza verificare i contesti.

---

<a id="lezione-21"></a>

# Lezione 21 — HAProxy: architettura e Ingress Controller Kubernetes

## Spiegazione e riflessioni ragionate

### Obiettivo privilegiato: sapere HAProxy, non soltanto Kubernetes
HAProxy è un reverse proxy e load balancer per connessioni TCP e HTTP. La triade è: **frontend** riceve connessioni e applica regole; **backend** identifica un gruppo di destinazioni e un algoritmo; **server** è una destinazione concreta `IP:porta`. Nel laboratorio Kubernetes due Pod HAProxy rappresentano **due repliche di una stessa installazione logica**, non due ingressClass distinte. L'obiettivo principale delle repliche è ridondanza del proxy e continuità in caso di perdita di un Pod o worker, purché il dataplane e gli altri nodi siano disponibili.

### Il percorso esatto del traffico
Client → `IP_NODO:30080` → Service NodePort del controller → dataplane kube-proxy seleziona **uno dei due HAProxy** → frontend HAProxy interpreta `Host: app.lab.local` e path `/blu` o `/verde` → backend HAProxy → **IP del Pod applicativo**. Nell'installazione di questa lezione, HAProxy **non passa dal ClusterIP del Service applicativo**: il Service è un indice che il controller usa per ottenere EndpointSlice. Questa differenza spiega perché HAProxy, non kube-proxy, applica `roundrobin`, `leastconn`, controlli health e logica del backend.

### La riflessione nata dalla domanda sui due controller
Perché `controller.replicaCount: 2`? Per evitare che il guasto di un solo Pod HAProxy renda indisponibile l'ingresso; la podAntiAffinity obbligatoria li colloca su worker distinti, così il guasto completo di un worker non spegne entrambi. **Le due repliche non condividono automaticamente contatori e connessioni**. Il NodePort può inoltrare nuove connessioni alla replica rimasta Ready dopo la propagazione; connessioni già attive sull'istanza guasta possono interrompersi. La ridondanza dei Pod non elimina punti di guasto a monte o nel control plane.

### La riflessione nata dalla domanda sulle NodePort
Il comando Helm `controller.service.nodePorts: { http: 30080, https: 30443, stat: 30024 }` configura nel Chart il Service **di ingresso per raggiungere HAProxy**. NodePort risponde a «come entro fino al proxy?»; l'Ingress risponde a «quale Service applicativo è la destinazione?»; il backend HAProxy risponde a «quale Pod concreto serve la richiesta?». `30080` è HTTP, `30443` HTTPS, `30024` statistiche. **NodePort non significa automaticamente accessibile da Internet**: servono routing, NAT/firewall o un LB esterno quando il client non raggiunge direttamente gli IP dei nodi. Non esporre la porta statistiche pubblicamente senza protezioni.

### Il controllo automatico delle destinazioni
Il controller HAProxy Technologies osserva Ingress, Service ed EndpointSlice via API server, genera `haproxy.cfg` e usa la Runtime API per cambi di membership dei backend. Scalandone uno da tre a cinque Pod, il materiale ha osservato due `add server` e contatore reload invariato. Cambiamenti strutturali possono invece richiedere reload. Verifica sullo **stesso Pod HAProxy** prima e dopo: `kubectl exec deploy/...` sceglie una replica implicitamente e può confondere il confronto.

### Algoritmi e stato locale
`haproxy.org/load-balance: roundrobin` sul Service blu dà una distribuzione a turno; `leastconn` sul verde privilegia destinazioni con meno connessioni attive. Con due HAProxy indipendenti la sequenza roundrobin globale non appare necessariamente perfetta. L'Ingress `app` instrada `app.lab.local/blu` verso blu e `/verde` verso verde, con `path-rewrite` che elimina il prefisso. Il secondo Ingress `limitato` usa cinque richieste in dieci secondi per IP, risposta `429` oltre il limite. **Ogni HAProxy mantiene la propria stick-table**: con due repliche non ottieni automaticamente cinque richieste globali; nel laboratorio sono state osservate 9 o 10 risposte 200 su 12 richieste consecutive. Per rate limit globale occorrono coordinamento/stato condiviso o un punto unico di enforcement.

### Architetture a confronto
Nel Biodistretto descritto dalle fonti HAProxy gira **fuori** Kubernetes sull'host e bilancia verso NodePort nginx sui nodi (30080, 30443, 30081); in questa lezione HAProxy gira **dentro** come Pod e conosce gli IP dei Pod applicativi. `externalTrafficPolicy: Local` può far sì che un health check NodePort rifletta la presenza di endpoint locali al nodo, evitando che un nodo apparentemente sano inoltri soltanto altrove. Un load balancer esterno e un Ingress Controller interno possono coesistere.

### Laboratorio: concentrazione sui fatti osservabili
Cluster separato `lab-haproxy` (cinque nodi da 1 GiB, Calico), vecchio `lab` preferibilmente fermo, attesa Calico prima dei workload, due controller su worker distinti, Chart `haproxytech/kubernetes-ingress` versione 1.57.1. Non usare `minikube addons enable ingress`, perché in questo materiale installerebbe ingress-nginx. Test `curl -H 'Host: app.lab.local' http://$IP:30080/blu/ciao` mostra Hostname del Pod e path `/ciao`; senza Host corrispondente si ottiene 404. Testare `show proc`, le righe `server` e statistiche `:30024/stats;csv` prima/dopo scaling.

### Verifica rapida (HAProxy)
1. Che cos'è HAProxy? Definisci frontend, backend e server senza nominare Kubernetes.
2. Perché due Pod HAProxy, e perché su worker differenti?
3. Le NodePort 30080/30443 sono le porte dei Pod blu o il punto di ingresso per HAProxy?
4. In che cosa differiscono NodePort, Ingress e backend HAProxy?
5. Perché la lista server contiene IP Pod invece del ClusterIP applicativo?
6. In che senso HAProxy può aggiungere server senza un reload?
7. Perché con due repliche un limite di cinque richieste non è globale?
8. Quando preferisci `roundrobin` a `leastconn`?
9. Perché un HAProxy esterno che bilancia nodi richiede un ragionamento su `externalTrafficPolicy`?
10. Che cosa succede alle connessioni esistenti quando una replica HAProxy muore, anche se ce n'è una seconda?

## Materiale originale della lezione


### Fonte originale: `21-architettura-e-haproxy.md`

> **Trascrizione integrale del file originale**, senza riscrittura. Questo blocco è una fonte di riferimento per il sito.

````markdown
# 21 — Architettura con HAProxy come Ingress controller

Spiegazione di `21-architettura-e-haproxy.yaml` (questa cartella) e dello script guidato
`kubernetes/21-architettura-e-haproxy.sh`.

## In una frase

Lo script crea un **cluster minikube nuovo, `lab-haproxy`** (5 nodi da 1 GiB, Calico), ci installa **HAProxy come
Ingress controller** al posto di ingress-nginx, e ti fa vedere che HAProxy **parla direttamente con i Pod**: legge gli
Ingress e gli EndpointSlice dall'apiserver, scrive da sé la propria configurazione e aggiunge o toglie i server **senza
ricaricarsi**.

## I file della lezione

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/kubernetes/21-architettura-e-haproxy.sh` | lo script **guidato**: crea il cluster, installa HAProxy con Helm, applica il manifest e lo prova, un passo per volta (Invio / s / q) | `bash kubernetes/21-architettura-e-haproxy.sh` |
| `~/kubernetesprj/lezioni/kubernetes/21-architettura-e-haproxy.yaml` | i **manifest** con la teoria nei commenti: namespace, app `blu` e `verde`, Service e Ingress con le annotazioni `haproxy.org/*` | si **legge** mentre lo script gira; lo applica lo script (o a mano: `kubectl apply -f …`) |
| `~/kubernetesprj/lezioni/kubernetes/21-architettura-e-haproxy.md` | **questo**: la spiegazione | si legge |

Il file della lezione è uno `.yaml` (come la 03), non uno `.sh` (come la 01): qui c'è qualcosa da **applicare**, i
manifest, e i comandi stanno già nello script guidato.

**Prerequisito**: nessuno. Il cluster è suo, separato da `lab`. **Non tenerli accesi insieme**: `lab` usa 8 GiB
(2 × 4), `lab-haproxy` 5 GiB, il PC ne ha 15. Prima di cominciare: `minikube -p lab stop`.

## Com'è fatto il manifest

```
intestazione (commenti)  → teoria: il percorso del traffico, Runtime API, il cluster da 1 GiB, LAB, NEL PROGETTO VERO
Namespace lab-haproxy
Deployment blu (3)       → whoami, sparsi sui nodi, request piccole
Deployment verde (2)     → uguale
Service blu              → haproxy.org/load-balance: roundrobin
Service verde            → haproxy.org/load-balance: leastconn
Ingress app              → classe haproxy, host app.lab.local, /blu e /verde, path-rewrite
Ingress limitato         → host limitato.lab.local, rate limit 5 ogni 10 s, poi 429
coda (commenti)          → domande da colloquio, riepilogo
```

Versioni misurate: Kubernetes 1.34.0, minikube 1.37.0, chart `haproxytech/kubernetes-ingress` **1.57.1**
(HAProxy 3.4), Calico.

---

## 1. L'architettura: cosa cambia rispetto alla 01 e alla 03

| | Lezione 01/03 (`lab`) | Lezione 21 (`lab-haproxy`) |
|---|---|---|
| Nodi | 2 da 4 GiB | **5 da 1 GiB** |
| Ingress controller | ingress-nginx, `minikube addons enable ingress` | **HAProxy**, `helm upgrade --install` |
| `ingressClassName` | `nginx` | `haproxy` |
| Come si entra dall'host | porta 80 dell'IP di minikube | **NodePort 30080** (http), 30443 (https), 30024 (stats) |
| Namespace delle prove | `lab` | `lab-haproxy` |
| Namespace del controller | `ingress-nginx` | `haproxy-controller` |

### Perché non `minikube addons enable ingress`

L'addon `ingress` di minikube installa **sempre ingress-nginx**. minikube 1.37 non ha un addon HAProxy (lo script lo
mostra con `minikube addons list`: ci sono solo `ingress`, `ingress-dns` e `kong`). HAProxy si installa con il **chart
ufficiale di HAProxy Technologies**:

```bash
helm repo add haproxytech https://haproxytech.github.io/helm-charts
helm upgrade --install haproxy haproxytech/kubernetes-ingress --version 1.57.1 \
  -n haproxy-controller --create-namespace -f valori.yaml
```

Il chart crea anche l'**IngressClass `haproxy`**: un Ingress con un'altra classe viene ignorato.

### Il percorso di una richiesta

```
curl -H 'Host: app.lab.local' http://192.168.49.2:30080/blu/ciao
  │
  ▼ NodePort 30080 su un nodo qualunque (anche il control plane)
  │ kube-proxy fa DNAT verso UNO dei 2 Pod HAProxy
  ▼
Pod HAProxy ── frontend: Host app.lab.local + path /blu → backend lab-haproxy_svc_blu_http
  │            path-rewrite: /blu/ciao → /ciao
  ▼ roundrobin fra le righe "server" del backend = gli IP dei Pod blu pronti
Pod blu (10.244.x.x:80) → risponde "Hostname: blu-…", "GET /ciao"
```

Il punto chiave: **HAProxy non usa il ClusterIP del Service**. Il Service serve da *indice*: il controller guarda i
suoi EndpointSlice e mette ogni IP di Pod pronto in una riga `server`. Per questo l'algoritmo di bilanciamento, gli
health check e le sticky session sono di HAProxy, non il DNAT casuale di kube-proxy.

### Configurazione scritta da un controller

Il Pod HAProxy contiene due cose: il **controller** (un programma Go che fa watch sull'apiserver) e **HAProxy**. Il
controller traduce Ingress, Service ed EndpointSlice in `/etc/haproxy/haproxy.cfg`:

```
backend lab-haproxy_svc_blu_http from haproxytech
  mode http
  balance roundrobin
  default-server check
  server s8b6ace539ea1bc2ba7edfc18 10.244.121.3:80 enabled
  server sd091f11bb8ebabf2e073452b 10.244.69.132:80 enabled
  server sd757b298bf4fc36cf98b1eda 10.244.205.66:80 enabled
```

Un backend per porta di Service (`<namespace>_svc_<service>_<porta>`), una riga per Pod.

### Senza reload: la Runtime API

Quando i Pod cambiano, il controller **non ricarica HAProxy**: gli manda `add server` / `del server` sul socket
`/run/haproxy-runtime-api.sock`. Misurato sul lab: `blu` da 3 a 5 repliche → nei log due `add server … New server
registered`, e il contatore `reloads` del processo master (`show proc` sul socket master) **resta uguale**. Un reload
lo provoca solo un cambio di struttura: un backend nuovo, un'annotazione nuova.

Le versioni vecchie del controller facevano diversamente: pre-allocavano degli «slot» `server` spenti (in `maint`) da
accendere. In HAProxy 3.x i server sono dinamici e gli slot non ci sono più: se leggi una guida che li nomina, è vecchia.

### Le annotazioni: Service = backend, Ingress = frontend

| Dove | Annotazione | Cosa fa |
|---|---|---|
| Service `blu` | `haproxy.org/load-balance: roundrobin` | a turno (è anche il default) |
| Service `verde` | `haproxy.org/load-balance: leastconn` | al Pod con meno connessioni aperte: per connessioni lunghe |
| Ingress `app` | `haproxy.org/path-rewrite: /(blu\|verde)/?(.*) /\2` | toglie il prefisso prima di passare al Pod |
| Ingress `limitato` | `haproxy.org/rate-limit-requests: "5"`, `rate-limit-period: "10s"`, `rate-limit-status-code: "429"` | 5 richieste ogni 10 s per IP, poi 429 (il default è 403) |

Le annotazioni di un Ingress valgono per **tutte** le sue regole: per questo il rate limit sta in un Ingress a parte,
su un host a parte.

---

## 2. Il cluster da 1 GiB per nodo: tre trappole misurate

### minikube rifiuta 1 GiB

```
X Exiting due to RSRC_INSUFFICIENT_REQ_MEMORY: Requested memory allocation 1024MiB is less than the usable minimum of 1800MB
```

Il passo 2 dello script lo fa vedere apposta (uscita 23). Il passo 3 aggiunge `--force`, che scavalca il controllo.

### `minikube start` finisce prima di Calico

Con 5 nodi, `minikube start` dice «Done!» quando i nodi sono `Ready`, ma `calico-node` sui worker può essere ancora in
avvio. Un Pod schedulato in quel momento fallisce la creazione della rete:

```
plugin type="calico" failed (add): stat /var/lib/calico/nodename: no such file or directory
```

Il kubelet ricrea il sandbox (`SandboxChanged`) e il container riparte: `RESTARTS 1` su entrambi i Pod HAProxy, senza
nessun guasto vero. Il passo 5 aspetta `kubectl -n kube-system rollout status daemonset/calico-node` prima di installare
qualunque cosa. Regola generale: dopo aver creato un cluster, aspetta il CNI, non solo i nodi.

### Il control plane sta al limite

Memoria netta (senza la cache dei file, come nella lezione 01) misurata dopo l'installazione di HAProxy:

| Nodo | Netto | Su | OOM kill |
|---|---|---|---|
| `lab-haproxy` (control plane) | 840–860 Mi (82–84%) | 1024 Mi | 0 |
| `lab-haproxy-m02` … `m05` | 320–375 Mi | 1024 Mi | 0 |

Apiserver, etcd, scheduler, controller-manager e Calico stanno tutti sul control plane: con 1 GiB resta poco. Per
questo i valori Helm hanno una **nodeAffinity** che tiene HAProxy fuori dal nodo con label
`minikube.k8s.io/primary=true`, e una **podAntiAffinity** che mette le 2 repliche su worker diversi. Se vedi
`oom_kill` maggiore di 0 sul control plane, il cluster è troppo stretto: rifallo con `--memory=2g`.

### Il chart chiede 2 GiB e lo scheduler dice sì

Di default il chart mette `requests.memory: 2048Mi` per replica. Su nodi da 1 GiB **lo scheduler le accetta lo stesso**:
con il driver docker il kubelet dichiara come Capacity **tutta la RAM del PC** (~16 GiB per nodo, la trappola della
lezione 01). Lo script la abbassa a 64 Mi, con un limite di 256 Mi. Le app `blu` e `verde` hanno request da 16 Mi.

---

## 3. Lo script guidato, passo per passo

| # | Comando | Cosa vedi |
|---|---|---|
| 1 | `kubectl version --client; minikube version; helm version` | le versioni dei client |
| 2 | `minikube start -p lab-haproxy … --memory=1g` | **rifiutato** (uscita 23 voluta): sotto i 1800 MB |
| 3 | lo stesso con `--force` | 5 nodi `lab-haproxy`, `-m02` … `-m05`. Qualche minuto |
| 4 | `kubectl config use-context lab-haproxy` | da qui la guardia controlla il contesto `lab-haproxy` |
| 5 | `kubectl -n kube-system rollout status daemonset/calico-node` | Calico pronto sui 5 nodi. Senza questa attesa i Pod HAProxy fallivano il sandbox (`/var/lib/calico/nodename: no such file`) e ripartivano una volta |
| 6 | `kubectl get nodes -L minikube.k8s.io/primary -o wide` | il control plane ha `primary=true` |
| 7 | `minikube … addons enable metrics-server` | `kubectl top`; **non** si abilita `ingress` |
| 8 | `minikube … addons list \| grep …` | nessun addon HAProxy |
| 9 | `helm repo add haproxytech …; helm search repo …` | il chart 1.57.1, HAProxy 3.4 |
| 10 | `helm show values … \| sed -n '/resources/…'` | le request da 2 GiB del chart |
| 11 | `helm upgrade --install haproxy … -f - <<VALORI` | i valori sono nel comando stesso: repliche, risorse, NodePort, affinity |
| 12 | `kubectl -n haproxy-controller get pods,svc; get ingressclass` | 2 Pod su worker diversi, NodePort 30080/30443/30024, classe `haproxy` |
| 13 | memoria netta e `oom_kill` di ogni nodo | il control plane vicino al limite |
| 14 | `kubectl apply -f 21-…yaml` + `rollout status` | namespace, app, Service, Ingress |
| 15 | un `curl` ripetuto fino a 200 su `/blu` e `/verde` | Pod pronti non vuol dire HAProxy pronto: il controller deve ancora scrivere i backend (alla prima corsa `/verde` rispondeva vuoto) |
| 16 | `kubectl -n lab-haproxy get pods -o wide` | blu e verde sparsi sui worker |
| 17 | `curl -H 'Host: app.lab.local' …/blu/ciao` e `…/verde` | `GET /ciao`: il prefisso è stato tolto |
| 18 | sei `curl` a `/blu` | roundrobin; la sequenza non è perfetta perché le 2 repliche di HAProxy girano ognuna per conto suo |
| 19 | `curl` senza `Host` | 404: nessuna regola combacia |
| 20 | `sed` su `/etc/haproxy/haproxy.cfg` + `get endpointslices` | una riga `server` per IP di Pod, gli stessi IP dell'EndpointSlice |
| 21 | `show proc` sul socket master | il numero di reload, prima |
| 22 | `scale deploy/blu --replicas=5` + log | `add server … New server registered` |
| 23 | `show proc` e `show servers state` | reload invariati, 5 server (stato 2 = UP) |
| 24 | 12 `curl` su `limitato.lab.local` | 200 e poi 429; misurato in due corse **10 e 9 volte 200** su 12: fino a 5 per replica |
| 25 | `curl …:30024/stats;csv` | la pagina statistiche in CSV: backend, server, `UP` |
| 26 | `scale deploy/blu --replicas=3` + log | `Server deleted.` due volte: i server in più escono a caldo |
| 27 | `kubectl delete -f …; helm uninstall …` | pulizia |

`kubectl exec deploy/haproxy-kubernetes-ingress` sceglie **uno** dei due Pod: l'altro ha la sua configurazione e i suoi
contatori.

Per ripartire da un passo: `DA=14 bash kubernetes/21-architettura-e-haproxy.sh`. Tutto senza fermarsi:
`AUTO=1 bash kubernetes/21-architettura-e-haproxy.sh`.

### La pagina statistiche dal Mac

I nodi minikube (`192.168.49.x`) si vedono solo dall'Ubuntu. Dal Mac, un tunnel ssh:

```bash
ssh -N -L 30024:192.168.49.2:30024 wilsonsgro@192.168.1.79
# nel browser del Mac: http://localhost:30024/stats
```

`192.168.49.2` è `minikube -p lab-haproxy ip`: se è diverso, usa quello.

---

## 4. Dentro o fuori dal cluster

Nel Biodistretto (`~/biodistretto/kubernetes`) HAProxy sta **fuori**, sull'host, ed entra dai NodePort di nginx:

| | HAProxy fuori (Biodistretto) | HAProxy dentro (questa lezione) |
|---|---|---|
| Vede | i **nodi** | i **Pod** |
| Si configura | a mano, `haproxy.cfg` sull'host | da sé, dagli Ingress |
| Health check | per nodo; serve `externalTrafficPolicy: Local` perché non menta | per Pod |
| Davanti serve ancora | niente | qualcosa che arrivi ai nodi: NodePort, un LB, o l'HAProxy esterno |

Le due cose si sommano: in produzione spesso c'è un bilanciatore esterno (HAProxy, un LB del cloud) che manda ai nodi,
e un Ingress controller dentro che manda ai Pod.

---

## 5. Domande da colloquio

- **Un Ingress controller manda il traffico al ClusterIP?** Di solito no: HAProxy e ingress-nginx leggono gli
  EndpointSlice e parlano con gli IP dei Pod.
- **Scalo da 3 a 6 repliche: HAProxy si ricarica?** No: `add server` sulla Runtime API. Si ricarica solo per un
  cambio di struttura.
- **Rate limit con più repliche del controller: è esatto?** No: ogni replica ha la sua stick-table, il limite si
  moltiplica per le repliche raggiunte. Per un limite globale servono i `peers` fra le repliche, o un limite a monte.
- **roundrobin o leastconn?** roundrobin per richieste brevi e simili; leastconn per connessioni lunghe o di durata
  diversa (websocket, upload, query lente).
- **Perché due IngressClass nello stesso cluster?** Per avere due controller (uno pubblico e uno interno, o nginx e
  HAProxy durante una migrazione): ogni Ingress sceglie il suo con `ingressClassName`.

---

## Riepilogo

- minikube non ha l'addon HAProxy: si installa con Helm, e porta l'IngressClass `haproxy`.
- HAProxy legge Ingress ed EndpointSlice e scrive `haproxy.cfg` da sé; il traffico va ai **Pod**, non al ClusterIP.
- I Pod nuovi entrano con la Runtime API, **senza reload**.
- Annotazioni: sul Service il backend, sull'Ingress il frontend.
- Il rate limit è **per replica**.
- 5 nodi da 1 GiB: serve `--force`, le request vanno abbassate, il controller sta lontano dal control plane.

## Prova da solo

1. Cancella un Pod `blu` e guarda i log del controller: quale comando della Runtime API vedi? Il numero di reload cambia?
2. Aggiungi a `Service blu` l'annotazione `haproxy.org/load-balance: leastconn` con `kubectl annotate --overwrite`:
   cambia il `balance` in `haproxy.cfg`? Questa volta il reload c'è?
3. Porta `rate-limit-requests` a `"2"` e ripeti i 12 `curl`: quanti 200 ti aspetti con 2 repliche? E se scali il
   controller a 1 (`helm upgrade … --reuse-values --set controller.replicaCount=1`)?
4. Spegni un worker con un Pod HAProxy (`docker stop lab-haproxy-m02`, poi `docker start`): i `curl` continuano a
   passare? Quanto ci mette Kubernetes ad accorgersene?
````

### Fonte originale: `21-architettura-e-haproxy.yaml`

> **Trascrizione integrale del file originale**, senza riscrittura. Questo blocco è una fonte di riferimento per il sito.

````yaml
# ═══════════════════════════════════════════════════════════════════════════
# 21. ARCHITETTURA CON HAPROXY COME INGRESS CONTROLLER
# Versione: Kubernetes 1.34 · minikube 1.37 · chart haproxytech/kubernetes-ingress 1.57.1 (HAProxy 3.4) · Calico
# Livello: 1 — Workload
# ═══════════════════════════════════════════════════════════════════════════
# Un Ingress è solo una REGOLA (host, path → Service). La esegue un
# controller: nella 03 era ingress-nginx (addon di minikube), qui è HAProxy.
# minikube non ha un addon HAProxy: lo installa Helm (lo script guidato).
#
#   client ──▶ NodePort 30080 su UN nodo qualunque
#                 │ kube-proxy (DNAT)
#                 ▼
#          Pod HAProxy (2 repliche, su worker diversi)
#                 │ legge Ingress + EndpointSlice dall'apiserver (watch)
#                 │ e scrive /etc/haproxy/haproxy.cfg
#                 ▼
#          IP dei Pod blu/verde, DIRETTAMENTE: il ClusterIP non si usa
#
# Il punto chiave: HAProxy NON passa dal ClusterIP del Service. Ogni Pod
# pronto diventa una riga "server" nel backend. Così l'algoritmo di
# bilanciamento (roundrobin, leastconn…) e i controlli di salute sono di
# HAProxy, non il DNAT a caso di kube-proxy.
# Quando i Pod cambiano, il controller aggiunge o toglie i server con la
# Runtime API (socket, comando "add server"), SENZA ricaricare HAProxy.
# Misurato: blu da 3 a 5 repliche → 2 "add server", reload fermi a 3.
# Le versioni vecchie del controller pre-allocavano invece degli slot
# "server" spenti (maint): in HAProxy 3.x i server sono dinamici.
#
# CLUSTER (profilo lab-haproxy)
#   5 nodi da 1 GiB, Calico. minikube rifiuta meno di 1800 MB:
#   serve --force. Misurato: control plane ~840 MiB netti su 1024
#   (al limite), worker ~350 MiB. Per questo HAProxy sta solo sui worker
#   (nodeAffinity) e le request del chart scendono da 2 GiB a 64 MiB.
#
# LAB
#   kubectl apply -f 21-architettura-e-haproxy.yaml
#   IP=$(minikube -p lab-haproxy ip)
#   curl -H 'Host: app.lab.local' http://$IP:30080/blu       # → un Pod blu
#   curl -H 'Host: app.lab.local' http://$IP:30080/verde     # → un Pod verde
#   for i in $(seq 8); do curl -s -o /dev/null -w '%{http_code} ' \
#       -H 'Host: limitato.lab.local' http://$IP:30080/; done   # 200… poi 429
#   statistiche: http://$IP:30024/stats   (dal Mac: tunnel ssh, vedi .md)
#
# ── NEL PROGETTO VERO: il Biodistretto su minikube ───────────────────────
#   ~/biodistretto/kubernetes (branch kubernetes). I grep partono da lì:
#   cd ~/biodistretto/kubernetes · come si usa: il README della cartella
#   Lì HAProxy sta FUORI dal cluster, sull'host: entra dai NodePort di
#   nginx (30080, 30443, 30081) e controlla ogni nodo per conto suo.
#     grep -n -A3 'type: NodePort' terraform/app/manifests/app.yaml.tftpl
#   Qui HAProxy sta DENTRO: è un Pod, legge l'apiserver e conosce i Pod.
#   Fuori: un HAProxy per tutto, ma vede solo nodi (e serve
#   externalTrafficPolicy: Local per non mentire). Dentro: vede i Pod, ma
#   davanti serve ancora qualcosa che arrivi ai nodi (NodePort o LB).

apiVersion: v1
kind: Namespace
metadata:
  name: lab-haproxy
---
# ── LE DUE APP ──────────────────────────────────────────────────────────────
# whoami risponde con il nome del Pod (Hostname): si vede chi ha servito.
# 3 repliche blu, 2 verdi, sparse sui nodi (maxSkew 1).
apiVersion: apps/v1
kind: Deployment
metadata:
  name: blu
  namespace: lab-haproxy
spec:
  replicas: 3
  selector:
    matchLabels: { app: blu }
  template:
    metadata:
      labels: { app: blu }
    spec:
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels: { app: blu }
      containers:
        - name: whoami
          image: traefik/whoami:v1.12
          ports:
            - { name: http, containerPort: 80 }
          readinessProbe:
            httpGet: { path: /health, port: http }
          resources:                       # nodi da 1 GiB: request piccole e vere
            requests: { cpu: 10m, memory: 16Mi }
            limits: { memory: 32Mi }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: verde
  namespace: lab-haproxy
spec:
  replicas: 2
  selector:
    matchLabels: { app: verde }
  template:
    metadata:
      labels: { app: verde }
    spec:
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels: { app: verde }
      containers:
        - name: whoami
          image: traefik/whoami:v1.12
          ports:
            - { name: http, containerPort: 80 }
          readinessProbe:
            httpGet: { path: /health, port: http }
          resources:
            requests: { cpu: 10m, memory: 16Mi }
            limits: { memory: 32Mi }
---
# ── SERVICE: le annotazioni haproxy.org/* configurano il BACKEND ────────────
# Il Service qui serve a HAProxy per trovare gli EndpointSlice: il suo
# ClusterIP resta per il traffico interno, HAProxy non lo usa.
apiVersion: v1
kind: Service
metadata:
  name: blu
  namespace: lab-haproxy
  annotations:
    haproxy.org/load-balance: roundrobin   # a turno (il default)
spec:
  selector: { app: blu }
  ports:
    - { name: http, port: 80, targetPort: http }
---
apiVersion: v1
kind: Service
metadata:
  name: verde
  namespace: lab-haproxy
  annotations:
    haproxy.org/load-balance: leastconn    # al Pod con meno connessioni aperte
spec:
  selector: { app: verde }
  ports:
    - { name: http, port: 80, targetPort: http }
---
# ── INGRESS: le annotazioni haproxy.org/* configurano il FRONTEND ───────────
# ingressClassName: haproxy (non nginx come nella 03): un controller
# ignora gli Ingress delle altre classi.
# path-rewrite toglie il prefisso: /blu/qualcosa arriva al Pod come
# /qualcosa. Senza, whoami riceverebbe /blu e risponderebbe lo stesso
# (whoami risponde a tutto), ma un'app vera darebbe 404.
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app
  namespace: lab-haproxy
  annotations:
    haproxy.org/path-rewrite: /(blu|verde)/?(.*) /\2
spec:
  ingressClassName: haproxy
  rules:
    - host: app.lab.local
      http:
        paths:
          - path: /blu
            pathType: Prefix
            backend:
              service: { name: blu, port: { name: http } }
          - path: /verde
            pathType: Prefix
            backend:
              service: { name: verde, port: { name: http } }
---
# Un secondo Ingress, solo per il rate limit: le annotazioni valgono per
# tutto l'Ingress, quindi un host a parte non tocca app.lab.local.
# 5 richieste ogni 10 secondi per IP; oltre, 429 (il default è 403).
# Il conteggio sta in una stick-table DI OGNI replica: con 2 repliche e
# kube-proxy che sceglie a caso, il limite reale è fra 5 e 10.
# Misurato: 12 richieste di fila → 10 (poi 9) volte 200, il resto 429.
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: limitato
  namespace: lab-haproxy
  annotations:
    haproxy.org/rate-limit-requests: "5"
    haproxy.org/rate-limit-period: "10s"
    haproxy.org/rate-limit-status-code: "429"
spec:
  ingressClassName: haproxy
  rules:
    - host: limitato.lab.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service: { name: blu, port: { name: http } }

# ── DOMANDE DA COLLOQUIO ────────────────────────────────────────────────────
# D: Un Ingress controller manda il traffico al ClusterIP del Service?
# R: Di solito no: HAProxy e ingress-nginx leggono gli EndpointSlice e
#    parlano con gli IP dei Pod. Così bilanciamento, sticky session e
#    health check li decide il controller. Il Service serve da "indice".
#
# D: Scalo un Deployment da 3 a 6: HAProxy si ricarica?
# R: No: il controller aggiunge i server con la Runtime API ("add
#    server"). Ricarica solo se cambia la struttura (nuovo backend, nuova
#    annotazione). Si vede con: echo "show proc" | socat stdio
#    /run/haproxy-master.sock → colonna reloads.
#
# D: Rate limit con più repliche del controller: è esatto?
# R: No. Ogni replica ha la sua stick-table: il limite si moltiplica per
#    il numero di repliche raggiunte. Per un limite globale servono
#    peers fra le repliche o un limite a monte (nel LB, nell'app).
#
# D: roundrobin o leastconn?
# R: roundrobin per richieste brevi e simili; leastconn per connessioni
#    lunghe o di durata diversa (websocket, upload, query lente).

# ══════════════════════════════════════════════════════════════════════════
# RIEPILOGO
# • minikube non ha l'addon HAProxy: si installa con Helm, classe "haproxy"
# • HAProxy legge Ingress ed EndpointSlice e scrive haproxy.cfg da sé
# • Il traffico va ai Pod, non al ClusterIP: bilancia HAProxy
# • Annotazioni: sul Service il backend, sull'Ingress il frontend
# • Rate limit per replica, non globale
# • 5 nodi da 1 GiB: --force, request piccole, niente controller sul control plane
# ══════════════════════════════════════════════════════════════════════════
````

### Fonte originale: `21-architettura-e-haproxy.sh`

> **Trascrizione integrale del file originale**, senza riscrittura. Questo blocco è una fonte di riferimento per il sito.

````bash
#!/usr/bin/env bash
# Lezione 21 — cluster minikube "lab-haproxy" (5 nodi da 1 GiB, Calico) con HAProxy come Ingress controller al posto di ingress-nginx.
source "$(dirname "$0")/../lib/passo.sh"
titolo "21. Architettura con HAProxy come Ingress controller"
F="$LEZIONI/kubernetes/21-architettura-e-haproxy.yaml"
CHART_VER=1.57.1

passo "Versioni dei client: kubectl, minikube, helm (HAProxy si installa con Helm)" \
  'kubectl version --client; minikube version --short; helm version --short'
passo "Prima prova SENZA --force: minikube rifiuta 1 GiB per nodo (minimo 1800 MB). Uscita 23 voluta" \
  'minikube start -p lab-haproxy --driver=docker --nodes=5 --cpus=2 --memory=1g --cni=calico'
passo "Crea il cluster 'lab-haproxy': 5 nodi (container docker) da 1 GiB, Calico. --force scavalca il minimo. Qualche minuto" \
  'minikube start -p lab-haproxy --driver=docker --nodes=5 --cpus=2 --memory=1g --cni=calico --force'
passo "Punta kubectl sul cluster nuovo: da qui lo script controlla che il contesto sia 'lab-haproxy'" \
  'kubectl config use-context lab-haproxy'
guardia_lab lab-haproxy 21-architettura-e-haproxy.sh
passo "minikube start torna prima che Calico sia su in tutti i nodi: un Pod schedulato adesso fallisce il sandbox (/var/lib/calico/nodename assente) e riparte una volta. Aspetto calico-node pronto sui 5 nodi" \
  'kubectl -n kube-system rollout status daemonset/calico-node --timeout=5m && kubectl -n kube-system get pods -l k8s-app=calico-node -o wide'
passo "I 5 nodi: lab-haproxy è il control plane (label minikube.k8s.io/primary=true), m02–m05 i worker" \
  'kubectl get nodes -L minikube.k8s.io/primary -o wide'
passo "Addon metrics-server per kubectl top. NON si abilita 'ingress': installerebbe ingress-nginx" \
  'minikube -p lab-haproxy addons enable metrics-server'
passo "Gli addon di ingress di minikube: ingress (nginx), ingress-dns, kong. HAProxy non c'è: serve Helm" \
  'minikube -p lab-haproxy addons list | grep -iE "ingress|kong|haproxy"'
passo "Repo Helm di HAProxy Technologies e versione del chart" \
  "helm repo add haproxytech https://haproxytech.github.io/helm-charts >/dev/null 2>&1; helm repo update haproxytech >/dev/null; helm search repo haproxytech/kubernetes-ingress --version $CHART_VER"
passo "Trappola: il chart chiede 2 GiB di request per replica. Su nodi da 1 GiB lo scheduler le accetta lo stesso (Capacity = tutto il PC, lezione 01)" \
  "helm show values haproxytech/kubernetes-ingress --version $CHART_VER | sed -n '/^  resources:/,/^\$/p' | head -7"
passo "Installa HAProxy: 2 repliche su worker diversi (mai sul control plane, già al limite), request da 64 Mi, NodePort fissi 30080 http, 30443 https, 30024 stats" \
  "helm upgrade --install haproxy haproxytech/kubernetes-ingress --version $CHART_VER -n haproxy-controller --create-namespace --wait --timeout 5m -f - <<'VALORI'
controller:
  replicaCount: 2
  resources:
    requests: { cpu: 50m, memory: 64Mi }
    limits: { memory: 256Mi }
  service:
    nodePorts: { http: 30080, https: 30443, stat: 30024 }
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - { key: minikube.k8s.io/primary, operator: NotIn, values: ['true'] }
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - topologyKey: kubernetes.io/hostname
          labelSelector:
            matchLabels: { app.kubernetes.io/name: kubernetes-ingress }
VALORI"
passo "Il controller: 2 Pod su due worker, un Service NodePort, l'IngressClass 'haproxy'" \
  'kubectl -n haproxy-controller get pods -o wide; kubectl -n haproxy-controller get svc; kubectl get ingressclass'
passo "Quanto è vicino al limite ogni nodo: memoria netta (senza cache dei file) su 1024 Mi, e gli OOM kill" \
  'for n in $(kubectl get nodes -o name | cut -d/ -f2); do docker exec $n sh -c "cd /sys/fs/cgroup; awk -v c=\$(cat memory.current) -v m=\$(cat memory.max) \"/^(active|inactive)_file /{f+=\\\$2} END{printf \\\"%-16s netto %4d Mi = %3d%% di %d Mi · \\\", \\\"$n\\\", (c-f)/2^20, (c-f)*100/m, m/2^20}\" memory.stat; grep oom_kill memory.events"; done'
nota "Il control plane sta intorno all'80% netto (misurato 839 Mi su 1024): per questo HAProxy e le app" \
     "vanno sui worker. Se vedi oom_kill > 0 sul control plane, il cluster è troppo stretto: --memory=2g."
passo "Applica namespace lab-haproxy, le app blu (3) e verde (2), i Service e i due Ingress di classe haproxy" \
  "kubectl apply -f $F && kubectl -n lab-haproxy rollout status deploy/blu && kubectl -n lab-haproxy rollout status deploy/verde"
passo "Pod pronti non vuol dire HAProxy pronto: il controller deve vedere Ingress ed EndpointSlice e scrivere i backend. Aspetto che /blu e /verde rispondano 200" \
  "IP=\$(minikube -p lab-haproxy ip); for p in blu verde; do for i in \$(seq 30); do c=\$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: app.lab.local' http://\$IP:30080/\$p); [ \"\$c\" = 200 ] && break; sleep 1; done; echo \"/\$p → \$c dopo \$i tentativi\"; done"
passo "Dove sono finiti i Pod: sparsi sui worker dal topologySpreadConstraints" \
  'kubectl -n lab-haproxy get pods -o wide'
passo "Dall'host attraverso HAProxy: /blu/ciao arriva al Pod come /ciao (path-rewrite). Hostname dice chi ha risposto" \
  "curl -s -H 'Host: app.lab.local' http://\$(minikube -p lab-haproxy ip):30080/blu/ciao | grep -E 'Hostname|GET'; curl -s -H 'Host: app.lab.local' http://\$(minikube -p lab-haproxy ip):30080/verde | grep -E 'Hostname|GET'"
passo "Sei richieste a /blu: roundrobin. Le 2 repliche di HAProxy girano ognuna per conto suo, quindi la sequenza non è perfetta" \
  "IP=\$(minikube -p lab-haproxy ip); for i in 1 2 3 4 5 6; do curl -s -H 'Host: app.lab.local' http://\$IP:30080/blu | grep Hostname; done"
passo "Senza header Host nessuna regola combacia: 404 di HAProxy (il backend di default)" \
  "curl -s -o /dev/null -w '%{http_code}\n' http://\$(minikube -p lab-haproxy ip):30080/"
passo "La config che il controller ha SCRITTO da sé: un backend per Service, una riga server per IP di Pod (non il ClusterIP)" \
  'kubectl -n haproxy-controller exec deploy/haproxy-kubernetes-ingress -- sed -n "/^backend lab-haproxy_svc_blu/,/^\$/p;/^backend lab-haproxy_svc_verde/,/^\$/p" /etc/haproxy/haproxy.cfg; kubectl -n lab-haproxy get endpointslices'
passo "Reload contati prima di scalare: colonna reloads del processo master" \
  'kubectl -n haproxy-controller exec deploy/haproxy-kubernetes-ingress -- sh -c "echo show proc | socat stdio /run/haproxy-master.sock | head -2"'
passo "Scalo blu a 5: il controller aggiunge i server con la Runtime API ('add server'), senza ricaricare" \
  'kubectl -n lab-haproxy scale deploy/blu --replicas=5 && kubectl -n lab-haproxy rollout status deploy/blu && sleep 5; kubectl -n haproxy-controller logs deploy/haproxy-kubernetes-ingress --since=60s | grep -E "add server|New server" | tail -4'
passo "Reload di nuovo: lo stesso numero di prima. I 5 server ci sono, visti dal socket runtime (srv_op_state 2 = UP)" \
  'kubectl -n haproxy-controller exec deploy/haproxy-kubernetes-ingress -- sh -c "echo show proc | socat stdio /run/haproxy-master.sock | head -2; echo show servers state lab-haproxy_svc_blu_http | socat stdio /run/haproxy-runtime-api.sock | cut -d\" \" -f4-6"'
nota "kubectl exec deploy/… sceglie UNO dei due Pod: l'altro ha la sua config e i suoi contatori."
passo "Rate limit su limitato.lab.local: 5 richieste ogni 10 s, poi 429. Con 2 repliche ne passano fino a 10" \
  "IP=\$(minikube -p lab-haproxy ip); for i in \$(seq 12); do curl -s -o /dev/null -w '%{http_code} ' -H 'Host: limitato.lab.local' http://\$IP:30080/; done; echo"
passo "La pagina statistiche di HAProxy in CSV: backend, server, stato. Nel browser è http://IP:30024/stats" \
  "curl -s \"http://\$(minikube -p lab-haproxy ip):30024/stats;csv\" | cut -d, -f1,2,18 | grep -E '^(# pxname|lab-haproxy_svc)'"
passo "Riporto blu a 3: i server in più escono a caldo come sono entrati" \
  'kubectl -n lab-haproxy scale deploy/blu --replicas=3 && sleep 10; kubectl -n haproxy-controller logs deploy/haproxy-kubernetes-ingress --since=30s | grep -iE "delete|del server" | tail -2'
passo "Pulizia: le app e il namespace lab-haproxy, poi il controller HAProxy" \
  "kubectl delete -f $F --ignore-not-found; helm uninstall haproxy -n haproxy-controller; kubectl delete namespace haproxy-controller --ignore-not-found"
nota "Spegnere il cluster senza perderlo:  minikube -p lab-haproxy stop" \
     "Cancellarlo del tutto:              minikube -p lab-haproxy delete" \
     "Tornare al cluster delle altre lezioni: kubectl config use-context lab (dopo minikube -p lab start)"
````

## Traccia per lo studio attivo

Prima di passare oltre: rileggi il manifest e lo script della lezione, individua il comando che produce l’osservazione principale, spiega perché il risultato è atteso, poi confronta la tua spiegazione con le riflessioni e le domande da colloquio del Markdown originale. Non applicare gli script a un cluster diverso dal laboratorio senza verificare i contesti.

---

# Appendice — Inventario delle fonti incorporate

I seguenti file sono incorporati integralmente in questo documento. SHA-256 calcolato sui byte UTF-8 dei rispettivi file disponibili al momento della creazione.

| File | Byte UTF-8 | SHA-256 |
|---|---:|---|
| `01-architettura-e-lab.md` | 18275 | `324dc1e90be9eb99fea66d45c06406d386a6e49721ef4a2dc628465046f267c2` |
| `01-architettura-e-lab.sh` | 10756 | `ed3a27c337dd796e4c91e0521553d5bd97411484ffc4f56f1d92f8745537936f` |
| `01-architettura-e-lab(1).sh` | 5940 | `477d284b364080bba0b5489680015ccf79534ece1b031d9cebdd62f81ae5293c` |
| `02-deployment-rollout-probe.md` | 18032 | `b460e53997ce16590a0055c250fb848b0908822d8a3d651e4098a354ac30460c` |
| `02-deployment-rollout-probe.yaml` | 9745 | `a2d07e7bf0ce25e6f0ae7277dea521f18550f67cc6d5e8e1989ccb075e189e0e` |
| `02-deployment-rollout-probe.sh` | 2523 | `e60afb6fd9b4bce10423e6bba4286b6d67feaf62d6088e9421bcc94196e23cd7` |
| `03-service-ingress-networkpolicy.md` | 15644 | `bcfab47653bf6f2cfc4bbbfb72de451f167fb0b5bdcb5076cd76d926449711e6` |
| `03-service-ingress-networkpolicy.yaml` | 9105 | `6a7c6d2d845605c73e1bfd7b605539210fa056c19e34f09a318f4ea6ba801a11` |
| `03-service-ingress-networkpolicy.sh` | 1533 | `08d237b9c059da6b7f21cb1f3eef7b8ee83efbdbe7823bbf5effff1d772a1090` |
| `04-configmap-secret.md` | 15263 | `f45846b9181fb82e122ad72811a5ebcd1c17d12c71781be0efc06b089e85b13f` |
| `04-configmap-secret.yaml` | 9511 | `33bfad45c6b76391d5942e17340255815387bd6fcf3dca37fd66dee2896a1368` |
| `04-configmap-secret.sh` | 2290 | `25760fd84ad010cf3e3dfc7e02c58252ce2df8eed41f486a881ace6a92c101b2` |
| `05-statefulset-storage-pdb.md` | 16994 | `ad303ad32967288c2ecdc3fc92c4dbde1a53f6be6f77d96eebb8ddf2446aad4c` |
| `05-statefulset-storage-pdb.yaml` | 9014 | `844368f1a834dde9b1bed422db7cefa1d5868876c3fb64a383fb0f7db2e89f37` |
| `05-statefulset-storage-pdb.sh` | 2550 | `b3fb527d8996421a1994c0c3609119db8111e0153e15b21bee53dd2021fb2720` |
| `06-scheduling-autoscaling.md` | 17121 | `798dc42ed0d66cd46cee725d5f6499308f540f477de384ce6f4dacae7d9fc222` |
| `06-scheduling-autoscaling.yaml` | 8620 | `3d96cf0789879be7e25ed638abea488e0f3fc08617849cf74a646ae8dfdd4aba` |
| `06-scheduling-autoscaling.sh` | 2364 | `3b020a303fff64b4598c706b5de3392971cf32a4dcf26f0266d097e73afe1cdf` |
| `07-rbac-pod-security.md` | 16103 | `c5eb944cf031881346dd19dcda984cbce7c6d29ecc1e0715fededbca6d1e1d00` |
| `07-rbac-pod-security.yaml` | 8798 | `c89865ece96256457ed8a6143c25eba7808caa0a44495c2ff6ecc50adf276f61` |
| `07-rbac-pod-security.sh` | 1374 | `34a6b6589bfdd0009bb5f8194dcc9060ea1e1e9e6a5a106fb8e9457306d38c40` |
| `08-troubleshooting.md` | 17604 | `87fba3e13f5d6229d378fb0a1d4dd9febb6cefa39805de74ad16343a400a1db1` |
| `08-troubleshooting.sh` | 9596 | `71b7798d248bb69912b1425afa9ec160c633d7147f144c9a5ffb3310edfb88f9` |
| `08-troubleshooting(1).sh` | 3483 | `e48251abec0d9b52007b25aae231b513e0cfdc702cfc9251742b22d0c82ad11c` |
| `09-helm-chart.md` | 18779 | `6ecfcb05425db3c98557dbf1a7497c52cf3eef0e3ac1b0d672dbc1327165ff53` |
| `09-helm-chart(1).sh` | 12147 | `f5a5fb07cce421979e4f75038772f8f313138d476ed03639bc126d18864eb26a` |
| `09-helm-chart.sh` | 2677 | `e43078306f4f2f43ae70c60553447ae08d3c274bdd47550e22e534aff5489ba9` |
| `21-architettura-e-haproxy.md` | 15219 | `6384bc1f8f571eb0f9b29ceaf5aa9db5e3cefd82a721f14846f09b59e3911133` |
| `21-architettura-e-haproxy.yaml` | 10104 | `933213998670961cd65a37bff8adee9f3e6b0539a90648ab81e05180d3ceb01d` |
| `21-architettura-e-haproxy.sh` | 8681 | `514c06462778cc6a1f66ff0ba8515e0e7f1381edafe22e65cefd2700768398ad` |

# Appendice — Risposte rapide alle due domande su HAProxy emerse in chat

**Perché due controller HAProxy?** Nel linguaggio corrente della lezione si dice «due controller», ma tecnicamente sono **due repliche Pod di un’unica installazione logica del controller**. Sono distribuite su worker diversi mediante `podAntiAffinity`, così il guasto di un singolo Pod o worker non interrompe necessariamente tutto il punto d’ingresso. Le repliche mantengono però stato locale (connessioni, contatori di rate limiting) non condiviso per impostazione predefinita. La continuità richiede che il Service rimuova gli endpoint non Ready e che esista un percorso di rete funzionante verso una replica rimasta.

**Dove si definisce il punto di ingresso esterno?** Durante l’installazione del Chart HAProxy, `controller.service.nodePorts: { http: 30080, https: 30443, stat: 30024 }` stabilisce le **porte NodePort del Service del controller**. Un client capace di raggiungere l’IP di un nodo e quella porta può entrare fino a HAProxy. Le regole `Ingress` con `ingressClassName: haproxy` stabiliscono poi come HAProxy instrada le richieste in base a Host e path. **NodePort ≠ Ingress ≠ endpoint del Pod applicativo**. NodePort non implica, da solo, accessibilità pubblica da Internet.

**Frase conclusiva:** «NodePort porta il traffico fino a HAProxy. L’Ingress dice ad HAProxy quale backend utilizzare. HAProxy sceglie il Pod applicativo concreto. Due repliche migliorano la disponibilità, ma non condividono automaticamente lo stato».
