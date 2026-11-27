# 23 — La 21 con Ansible: HAProxy, app e Headlamp da un playbook

Spiegazione di `23-architettura-e-haproxy-ansible.yaml` (questa cartella) e dello script guidato
`kubernetes/23-architettura-e-haproxy-ansible.sh`.

## In una frase

Lo stesso laboratorio della **21** (cluster minikube da 5 nodi da 1 GiB, HAProxy come Ingress controller, le app `blu` e
`verde`, Headlamp dietro HAProxy), ma **ogni azione la fa Ansible**: un solo playbook diviso in sezioni con i tag,
che crea il cluster, installa i chart, applica i manifest, fa le prove con `assert` e smonta tutto. In più quello che
uno script bash non sa fare: **idempotenza** (la seconda corsa dice `changed=0`) e **deriva** (`--check --diff` mostra
cosa è cambiato a mano, senza toccare niente).

## I file della lezione

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/kubernetes/23-architettura-e-haproxy-ansible.sh` | lo script **guidato**: ogni passo lancia `ansible-playbook … --tags <sezione>` (Invio / s / q) | `bash kubernetes/23-architettura-e-haproxy-ansible.sh` |
| `~/kubernetesprj/lezioni/kubernetes/23-architettura-e-haproxy-ansible.yaml` | il **playbook**, con la teoria nei commenti | lo lancia lo script; a mano: `ansible-playbook 23-…-ansible.yaml --tags cluster` |
| `~/kubernetesprj/lezioni/kubernetes/21-architettura-e-haproxy.yaml` | i **manifest** delle app (della 21): il playbook li applica, non li copia | lo legge il playbook |
| `~/kubernetesprj/lezioni/kubernetes/23-architettura-e-haproxy-ansible.md` | **questo**: la spiegazione | si legge |

Qui il `.yaml` è un **playbook**, non un manifest come nella 21: anche i playbook sono YAML. I manifest restano
quelli della 21, una sola fonte: se cambi `blu` lì, cambia in tutte e due le lezioni (e nella 22).

**Prerequisiti**: `ansible-core` installato con `pipx` (sul lab c'è già, in `~/.local/bin`). Il passo 1 aggiunge la
collection `kubernetes.core` e la libreria Python `kubernetes` nel venv di Ansible, senza sudo. Il cluster è suo,
**`lab-ansible`**: spegni gli altri prima (`minikube -p lab stop; minikube -p lab-haproxy stop`), 5 GiB ciascuno.

Versioni misurate: ansible-core **2.21.5**, `kubernetes.core` **6.6.0**, libreria `kubernetes` 37.0.3, Helm **4.3.2**,
minikube 1.37.0, Kubernetes 1.34, chart `haproxytech/kubernetes-ingress` 1.57.1, `headlamp/headlamp` 0.46.0.

## Com'è fatto il playbook

Un solo play su `localhost` (`connection: local`, `gather_facts: false`): Ansible gira sull'Ubuntu e parla con
minikube, Helm e l'apiserver da lì. Le sezioni sono **tag**:

```
always           → minikube status e IP: girano a ogni lancio, servono a tutte le sezioni
versioni         → kubectl, minikube, helm, ansible-core
trappola         → minikube senza --force: accettata SOLO l'uscita 23
cluster          → minikube start --force (se spento), use-context (se serve), Calico, nodi, metrics-server
haproxy          → helm_repository, il default da 2 GiB, helm con i valori nel playbook, dove stanno i Pod
memoria          → memoria netta dei 5 nodi
app              → il manifest della 21 un oggetto per volta, poi uri+until fino a 200
verifica         → le prove della 21 con uri e assert
headlamp         → chart, utente headlamp-lettore, prove dei permessi con no_log
headlamp-token   → never: il token da 8 ore per il browser
scala            → never: blu 3 → 5 → 3, assert «reload fermi, 5 server»
deriva-crea      → never: blu a 4, come una modifica a mano
pulizia          → never: Headlamp, utente, app, HAProxy, namespace
distruggi        → never: minikube delete
```

Il tag **`never`** esclude un task da una corsa senza `--tags`: un `ansible-playbook 23-….yaml` nudo rimette il
laboratorio nello stato desiderato e **non** scala, non smonta, non stampa token.

---

## 1. Dalla 21 alla 23: chi fa cosa

| Nella 21 (bash) | Nella 23 (Ansible) | Cosa cambia |
|---|---|---|
| `minikube start …` | `ansible.builtin.command` con `when: not acceso` | gira solo se il cluster è spento |
| `kubectl config use-context` | `command` con `when: contesto.stdout != profilo` | gira solo se kubectl punta altrove |
| `kubectl rollout status daemonset/calico-node` | `kubernetes.core.k8s_info` con `until: numberReady == 5` | la condizione è scritta, non dedotta |
| `minikube addons enable metrics-server` | `command` con `when` sul JSON di `addons list -o json` | niente cambio se è già acceso |
| `helm repo add …` | `kubernetes.core.helm_repository` | |
| `helm upgrade --install … -f - <<VALORI` | `kubernetes.core.helm` con `release_values:` | i valori sono un dizionario YAML nel playbook |
| `kubectl apply -f 21-….yaml` | `kubernetes.core.k8s` con `definition: "{{ item }}"` in loop | un risultato per oggetto, con il diff |
| `curl` in un `for` fino a 200 | `ansible.builtin.uri` con `until` / `retries` / `delay` | |
| guardare l'output | `ansible.builtin.assert` | se una prova fallisce, il play si ferma con `failed=1` |
| `kubectl exec deploy/…` | `kubernetes.core.k8s_exec` sul **primo Pod** del controller | prima e dopo lo **stesso** Pod: i reload si confrontano davvero |
| `kubectl logs` + `grep` | `kubernetes.core.k8s_log` + filtro `select('search', …)` | |
| `kubectl scale` | `kubernetes.core.k8s_scale` con `wait: true` | |
| `kubectl create token` | `command` con `no_log: true` | il token non finisce nell'output |

Nella 21 `kubectl exec deploy/haproxy-kubernetes-ingress` sceglieva **uno** dei due Pod a ogni comando: il «prima» e
il «dopo» potevano venire da Pod diversi. Qui il nome del Pod si legge una volta (`k8s_info`) e si usa per tutto.

### `module_defaults`: il cluster giusto anche se kubectl punta altrove

```yaml
module_defaults:
  group/kubernetes.core.k8s: { context: "{{ profilo }}" }
  group/kubernetes.core.helm: { context: "{{ profilo }}" }
```

Ogni modulo dei due gruppi (`k8s`, `k8s_info`, `k8s_exec`, `k8s_log`, `k8s_scale` · `helm`, `helm_repository`) riceve
`context: lab-ansible`. Nella 21 la protezione era `guardia_lab` nello script; qui sta **nel playbook**: lanciato a
mano, con kubectl su un altro cluster, non tocca quel cluster. I `command` con kubectl hanno `--context` scritto.

---

## 2. Idempotenza: la seconda corsa dice `changed=0`

Un modulo (`k8s`, `helm`, `helm_repository`) confronta lo stato attuale con quello chiesto e cambia solo la differenza.
Un **`command`** no: Ansible non sa cosa fa, e lo segna sempre `changed`. L'idempotenza dei `command` la scrivi tu:

| Strumento | Dove nel playbook |
|---|---|
| `when:` — gira solo se serve | `minikube start` (`when: not acceso`), `use-context`, `addons enable` |
| `changed_when: false` — legge soltanto | `minikube status`, `addons list`, `helm show values`, `auth can-i`, `create token`, `k8s_exec` |
| `failed_when:` — decide tu cosa è un errore | la trappola (`rc != 23`), `auth can-i` (`stdout != 'no'`) |

Misurato in tre corse: il passo 13 rilancia il playbook intero (tutto tranne i `never`) sul laboratorio già montato →
**`ok=46 changed=0 failed=0 skipped=5`**. I 5 saltati sono i `when` falsi: la trappola e il suo messaggio, la
creazione del cluster, `use-context`, `addons enable`. Con `ANSIBLE_DISPLAY_OK_HOSTS=false` e
`ANSIBLE_DISPLAY_SKIPPED_HOSTS=false` l'output mostra **solo** i task che cambiano qualcosa: nessuno.

### `check_mode: false` sui task che leggono

Con `--check` Ansible **salta** i `command` (non sa se cambierebbero qualcosa) e gli `uri`. Ma se `minikube status`
non gira, `acceso` non esiste e il play si rompe. Per questo i task che **leggono** hanno `check_mode: false`: girano
anche in prova. Quelli che scrivono no.

---

## 3. Deriva: `--check --diff` la mostra, `--tags app` la corregge

Una «deriva» è il cluster che non è più come il file: qualcuno ha fatto `kubectl scale` a mano. I passi 14–16:

1. `--tags deriva-crea` porta `blu` a 4 (simula la modifica a mano).
2. `--tags app --check --diff`: Ansible confronta, **non applica**, e mostra:

```
ok: [localhost] => (item=Namespace/lab-haproxy)
--- before
+++ after
@@ -1,3 +1,3 @@
     spec:
-        replicas: 4
+        replicas: 3

changed: [localhost] => (item=Deployment/blu)
ok: [localhost] => (item=Deployment/verde)
ok: [localhost] => (item=Service/blu)
…
```

   Dopo, il cluster ha ancora `blu 4/4`: `--check` non ha toccato niente.
3. `--tags app` senza `--check`: cambia **solo** `Deployment/blu`, che torna a 3/3.

### Due trappole misurate per arrivare a questo diff

- **Con `src:` il diff non si vede.** `kubernetes.core.k8s` con `src: 21-….yaml` (7 documenti) ha detto `changed`
  ma non ha stampato nessun diff: i risultati dei 7 oggetti stanno annidati in un solo risultato, e il callback non
  li mostra. Per questo il playbook applica il file **un oggetto per volta**:
  `loop: "{{ lookup('file', manifest_21) | from_yaml_all | select | list }}"`, con `loop_control.label` =
  `Kind/nome`. Così ogni oggetto ha il suo `ok` / `changed` e il suo diff.
- **Il diff grezzo è rumore.** Senza filtri, `Deployment/blu` mostrava decine di righe di `managedFields`, `status`,
  `resourceVersion` per una sola riga vera. `hidden_fields` le toglie dal confronto:

  ```yaml
  hidden_fields:
    - metadata.managedFields
    - metadata.annotations[kubectl.kubernetes.io/last-applied-configuration]
    - metadata.generation
    - metadata.resourceVersion
    - status
  ```

  **Non** tutte le annotazioni: in questa lezione le annotazioni `haproxy.org/*` **sono** la configurazione di
  HAProxy. Si nasconde solo `last-applied-configuration` (la scrive `apply`), con le parentesi quadre perché il nome
  contiene dei punti. Misurato: con `verde` cambiato a mano (`haproxy.org/load-balance: roundrobin`), il diff mostra
  `Service/verde` con `roundrobin → leastconn`, accanto a `Deployment/blu` con `replicas: 4 → 3`, e nient'altro.

---

## 4. Le prove: `uri`, `until`, `assert`, `no_log`

**`uri` + `until`** sostituisce il `curl` in loop. «Pod pronti non vuol dire HAProxy pronto» resta vero: alla prima
corsa da cluster nuovo `/blu` ha risposto 200 al **2°–4°** tentativo (tre corse), `/verde` al 1°, Headlamp al
1°–2°.

```yaml
- ansible.builtin.uri:
    url: "http://{{ ip }}:30080/{{ item }}"
    headers: { Host: app.lab.local }
  loop: [blu, verde]
  register: pronte
  until: pronte.status == 200
  retries: 30
  delay: 1
```

**`assert`** trasforma un'osservazione in un controllo: nella 21 leggevi «reload uguali»; qui, se non lo sono, il
play si ferma. Le prove con `assert`:

| Prova | Condizione | Misurato |
|---|---|---|
| path-rewrite | `'GET /ciao' in content` | `Hostname: blu-…`, `GET /ciao` |
| rate limit | almeno un 429, al massimo 10 volte 200 su 12 | **9, 10, 10** volte 200 su 12 nelle tre corse, per esempio `200 200 200 200 200 200 429 200 200 200 429 429` |
| permessi di Headlamp | anonimo 403 con `system:anonymous`, lettore `pods` 200, `secrets` 403 | uguale alla 21 |
| scala | reload uguali prima e dopo, 5 righe nel backend `blu` | reload **4 e 4**, 5 server; nei log due `add server lab-haproxy_svc_blu_http/…` · `New server registered.` |
| ServiceAccount del pod | `auth can-i list pods -A` deve dire `no` | `no` |

Il 404 senza `Host` è un `uri` con `status_code: 404`: qualunque altro codice fa fallire il task.

**`no_log: true`** sul task che crea il token di prova e su quello che lo manda negli header: senza, Ansible
stamperebbe gli header (quindi il token) in caso di errore o con `-v`. Le prove si leggono **dopo**, dall'`assert`,
che stampa solo i codici. Il token da 8 ore per il browser sta in un tag `never` a parte (`headlamp-token`): lo stampi
solo se lo chiedi.

---

## 5. Altre trappole del laboratorio

- **`ansible: command not found` via ssh.** `ansible-core` sta in `~/.local/bin` (pipx), che è nel `PATH` della
  shell interattiva ma non di `ssh host 'comando'`. Lo script fa `export PATH="$HOME/.local/bin:$PATH"`, come
  `deploy.sh` del Biodistretto.
- **`community.general.json_query` vuole `jmespath`**, che nel venv di Ansible non c'è. Il playbook usa filtri Jinja
  (`map`, `select`, `zip`) e, dove serve, un `{% for %}`: niente dipendenze in più.
- **Avvisi di deprecazione di `kubernetes.core` 6.6** su valori di ritorno che il playbook non usa (`status.values`
  di `helm`, `return_code` di `k8s_exec`): li stampa il modulo a ogni chiamata. Lo script li spegne con
  `ANSIBLE_DEPRECATION_WARNINGS=False`.
- **Helm 4.** `kubernetes.core` 6.x lo supporta (per esempio traduce `atomic` in `--rollback-on-failure`); misurato
  con Helm 4.3.2: installazione, upgrade idempotente e disinstallazione funzionano.
- **Calico dopo minikube**: come nella 21, `minikube start` finisce prima del CNI. Il task `until` su `calico-node`
  ha ripetuto una ventina di volte (5 s l'una) prima di vedere 5 Pod pronti: l'attesa è voluta, i `FAILED -
  RETRYING` nell'output non sono errori.

Il resto delle misure è quello della 21, rifatto su `lab-ansible` (tre corse): control plane **841–891 Mi netti su 1024
(82–87%)**, worker 278–384 Mi, `oom_kill 0`; i 2 Pod HAProxy su `m02` e `m03`; Headlamp con il backend
`headlamp_svc_headlamp_http` sulla porta 4466 del Pod.

---

## 6. Lo script guidato, passo per passo

| # | Comando | Cosa vedi |
|---|---|---|
| 1 | `ansible-galaxy collection install kubernetes.core; pipx inject ansible-core kubernetes` | `ansible-core 2.21.5`, `kubernetes.core 6.6.0`, libreria `kubernetes` |
| 2 | `ansible-playbook … --list-tags` | i tag del playbook |
| 3 | `--tags versioni` | ansible-core, kubectl, minikube, Helm 4 |
| 4 | `--tags trappola` | `rc=23 · RSRC_INSUFFICIENT_REQ_MEMORY … 1800MB`, e il task è **ok**: l'errore era quello atteso |
| 5 | `--tags cluster` | 5 nodi (`lab-ansible primary=true`, `m02`–`m05`), i `RETRYING` dell'attesa di Calico, addon `ingress`, `ingress-dns`, `kong` |
| 6 | `--tags haproxy` | il default da 2048 Mi, `changed` sull'installazione, i 2 Pod su due worker |
| 7 | `--tags memoria` | memoria netta e `oom_kill` per nodo |
| 8 | `--tags app` | `changed` per ognuno dei 7 oggetti, poi `200 dopo tentativi` |
| 9 | `--tags verifica` | dove stanno i Pod, `GET /ciao`, 6 `Hostname`, 404, il backend `blu`, la sequenza 200/429, le statistiche |
| 10 | `--tags headlamp` | il default `cluster-admin`, l'installazione, il backend sulla 4466, «senza token → 403 (system:anonymous) · lettore → pods 200 · secrets 403» |
| 11 | `--tags headlamp-token` | il token da 8 ore e i comandi per il Mac |
| 12 | `--tags scala` | «reload prima 4, dopo 4 · 5 server nel backend blu», le righe `add server` dei log, poi `Server deleted.` |
| 13 | `ansible-playbook …` (tutto) | solo il riepilogo: **`changed=0`** |
| 14 | `--tags deriva-crea` | `changed=1`: blu a 4 |
| 15 | `--tags app --check --diff` | il diff `replicas: 4 → 3` solo su `Deployment/blu`; il cluster resta a 4 |
| 16 | `--tags app` | `changed` solo su `Deployment/blu`, poi `blu 3/3` |
| 17 | `--tags pulizia` | `changed=5`: Headlamp, utente e namespace, app, HAProxy, namespace del controller |

Per ripartire da un passo: `DA=8 bash kubernetes/23-architettura-e-haproxy-ansible.sh`. Tutto senza fermarsi:
`AUTO=1 bash …`. Il cluster resta acceso alla fine: `minikube -p lab-ansible stop`, oppure
`ansible-playbook … --tags distruggi` per cancellarlo.

Headlamp dal Mac si apre come nella 21 (tunnel ssh sulla 30080, `127.0.0.1 headlamp.lab.local` in `/etc/hosts`):
il passo 11 stampa il comando con l'IP giusto.

---

## 7. Domande da colloquio

- **Cosa aggiunge Ansible a uno script con kubectl e helm?** Lo stato desiderato: la seconda corsa dice `changed=0`,
  `--check --diff` mostra cosa cambierebbe, i tag scelgono le sezioni, `assert` ferma il play se una prova fallisce.
- **Un `command` è idempotente?** No, Ansible lo segna sempre `changed`. Lo rendi idempotente con `when`,
  `changed_when`, `creates`/`removes`; meglio ancora un modulo, se esiste.
- **Perché il manifest in loop invece di `src:`?** Con `src` e più documenti il risultato è uno solo e il diff non si
  vede; in loop ogni oggetto ha il suo `changed` e il suo diff.
- **Come eviti che un playbook tocchi il cluster sbagliato?** `module_defaults` con `context:` sui gruppi
  `kubernetes.core.k8s` e `kubernetes.core.helm`, e `--context` nei `command`.
- **Il token può finire nei log di Ansible?** Sì, se un task lo stampa o lo usa negli header e fallisce. `no_log: true`
  su quei task, e le prove si leggono dopo con `assert`.
- **Ansible o Terraform/Argo CD per questo?** Ansible esegue passi in ordine e verifica; non tiene uno stato suo.
  Terraform ricorda cosa ha creato (stato) e sa cancellarlo; Argo CD riconcilia di continuo dal repository. Qui
  servono ordine, attese e prove: Ansible ci sta bene.

---

## Riepilogo

- Un playbook, sezioni con i tag; `never` per scala, deriva, token, pulizia e distruzione.
- minikube con `command` + `when`/`changed_when`; Helm e manifest con `kubernetes.core`.
- Il manifest della 21 si applica in loop, un oggetto per volta: una fonte sola, diff leggibile.
- `uri` + `until` al posto dei `curl` in loop, `assert` al posto dell'occhio, `no_log` sul token.
- Seconda corsa: `changed=0`. Deriva: `--check --diff` la mostra, `--tags app` la corregge.
- `module_defaults` con `context`: il cluster giusto anche se kubectl punta altrove.

## Prova da solo

1. Cambia a mano l'annotazione `haproxy.org/load-balance` del Service `verde`
   (`kubectl --context lab-ansible -n lab-haproxy annotate svc verde haproxy.org/load-balance=roundrobin --overwrite`),
   poi `--tags app --check --diff`: quale oggetto è `changed`, e cosa dice il diff? Dopo `--tags app` (senza
   `--check`), HAProxy si ricarica? (Lezione 21: un'annotazione nuova è un cambio di struttura.)
2. Togli `changed_when: false` dal task «Addon di minikube» e rilancia il playbook intero: quanti `changed` vedi?
   È vero che è cambiato qualcosa?
3. Togli `hidden_fields` dal task che applica il manifest e ripeti la deriva: quante righe di diff per una replica?
   E se nascondi tutto `metadata.annotations`, l'esercizio 1 si vede ancora?
4. Togli `no_log: true` dal task delle prove di Headlamp e lancia `--tags headlamp -v`: dove compare il token?
5. Lancia `--tags verifica` con `kubectl config use-context lab` (o un altro contesto): quale cluster viene provato, e
   perché?
