# 07 — Ansible: playbook

Spiegazione di `07-ansible-playbook.sh` (questa cartella). Lezione sul sito: http://127.0.0.1:3000/terraform/7

## In una frase

Lo script copia il playbook della lezione come `site.yml` e lo fa girare sui container `web1` e `web2` della lezione
06 in tutti i modi che contano: controllo di sintassi, **dry-run** `--check --diff` (che fallisce apposta), prima e
seconda esecuzione (**changed=0**), una variabile cambiata da riga di comando, `--tags` e `--limit`, una porta non
valida che **`validate` rifiuta** senza rompere nginx, e infine `ansible-lint`.

## Questo script e la lezione

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/terraform/07-ansible-playbook.sh` | **questo**: lo script guidato. Copia il playbook e lo lancia con opzioni diverse, un passo per volta (Invio / s / q) | `bash terraform/07-ansible-playbook.sh` da `~/kubernetesprj` |
| `~/kubernetesprj/lezioni/terraform/07-ansible-playbook.yml` | il file di lezione: **è il playbook** (due play, handler, template, loop, block/rescue) con la teoria nei commenti | si **legge**; il runner lo copia come `site.yml` |

```bash
cd ~/kubernetesprj
bash terraform/07-ansible-playbook.sh
```

## Com'è fatto lo script

```
source ../lib/passo.sh          → titolo / passo / nota / cartella
export PATH=~/.local/bin:…      → ansible-playbook e ansible-lint di pipx
cartella ansible                → ~/kubernetesprj/lavoro/ansible, la stessa della 06
[[ -f inventory.yml ]] || exit  → «prima esegui la lezione 06»
10 × passo
```

Non passa `-i`: l'inventario lo prende dall'`ansible.cfg` scritto dalla lezione 06 (`inventory = inventory.yml`), che
attiva anche il callback `profile_tasks` (i tempi di ogni task).

---

## 1. La teoria nell'intestazione

Versione: **ansible-core 2.21**. Livello 4 — Configuration management.

Un playbook si legge **dall'alto in basso**: play → task, in ordine, su tutti gli host del play **in parallelo**. La
strategia di default è `linear`: il task N parte su tutti gli host solo quando il task N-1 è finito su tutti.

### Concetti da saper spiegare

| Concetto | Cosa fa |
|---|---|
| `handler` | task eseguito **una volta a fine play**, solo se **notificato** da un task "changed" (es. reload di nginx dopo la config) |
| `template` | file Jinja2 renderizzato con le variabili dell'host |
| `register` | salva il risultato di un task in una variabile |
| `when` | condizione: espressione Jinja **senza** `{{ }}` |
| `loop` | ripete un task su una lista (`with_items` è il vecchio modo) |
| `block` / `rescue` / `always` | try / catch / finally |
| `tags` | eseguire solo una parte: `--tags config` |
| `--check --diff` | dry-run che mostra le differenze |

### Riquadro «NEL PROGETTO VERO»

In `~/biodistretto/kubernetes` (branch `kubernetes`; come si usa: il README della cartella) ci sono tutti i pezzi di
questa lezione in un playbook vero:

```bash
cd ~/biodistretto/kubernetes
grep -n -E 'validate|Riavvia' ansible/roles/haproxy/tasks/main.yml        # validate prima di sostituire + handler
grep -n -A3 'always:' ansible/roles/cluster/tasks/main.yml               # pulire anche se terraform fallisce
grep -n -E 'label|failed_when' ansible/roles/verifica/tasks/main.yml      # loop con label, failed_when
grep -n -A3 'until:' ansible/roles/verifica/tasks/main.yml                # until/retries invece di sleep fissi
```

Il secondo giro di `./deploy.sh` deve dare `changed=0`: per questo ogni `command` ha il suo `changed_when`.

---

## 2. Il primo play: «Configura i server web»

```yaml
- name: Configura i server web
  hosts: web
  become: true
  vars:
    messaggio: "Servito da Ansible"
    utenti:
      - { nome: deploy, gruppi: [www-data] }
      - { nome: monitor, gruppi: [] }
```

| Campo | Valore | Perché |
|---|---|---|
| `hosts` | `web` | il gruppo dell'inventario 06: `web1` e `web2` (non `db1`) |
| `become` | `true` | sudo. Nei container sei già root; sulle VM serve |
| `vars.messaggio` | `"Servito da Ansible"` | finisce nella pagina; il passo 6 lo sovrascrive con `-e` |
| `vars.utenti` | lista di due dizionari | l'ingresso del `loop` più sotto |

Le altre variabili usate (`pacchetti`, `porta_http`, `ambiente`, `peso_lb`) arrivano dall'**inventario** della 06.

### `pre_tasks`: la cache di apt

```yaml
- name: Aggiorna la cache di apt solo se più vecchia di un'ora
  ansible.builtin.apt:
    update_cache: true
    cache_valid_time: 3600
```

`pre_tasks` girano prima dei `tasks`. `cache_valid_time: 3600` fa l'`apt-get update` solo se la cache ha più di
un'ora: così la seconda esecuzione non lo rifà e resta `changed=0`.

### I task, uno per uno

| Task | Modulo | Cosa fa e perché | Tag |
|---|---|---|---|
| Installa i pacchetti del gruppo | `ansible.builtin.apt` | `name: "{{ pacchetti }}"` = `[nginx, curl]` per il gruppo web. Una lista in un colpo: più veloce di un loop | `pacchetti` |
| Crea gli utenti applicativi | `ansible.builtin.user` | `loop: "{{ utenti }}"` crea `deploy` (nel gruppo `www-data`) e `monitor`. `append: true` aggiunge ai gruppi senza togliere quelli esistenti; `loop_control.label` mostra nell'output solo il nome, non tutto il dizionario | — |
| Pagina iniziale da template | `ansible.builtin.copy` con `content` | scrive `/var/www/html/index.html` (owner `www-data`, mode `"0644"`). Il `content` è Jinja: `inventory_hostname`, `messaggio`, `ambiente`, `peso_lb \| default(1)` e un `{% if %}` sui fatti | `config` |
| Configurazione di nginx | `ansible.builtin.copy` con `validate` | scrive `/etc/nginx/sites-available/default` con `listen {{ porta_http }}` e una `location /salute` che risponde `ok`. **Notifica** l'handler | `config` |
| Nginx avviato e abilitato al boot | `ansible.builtin.systemd_service` | `state: started`, `enabled: true` | — |
| Versione di nginx | `ansible.builtin.command: nginx -v` | `register: versione` e **`changed_when: false`**: un comando di sola lettura non cambia niente | — |
| Mostra la versione | `ansible.builtin.debug` | `msg: "{{ versione.stderr }}"`: `nginx -v` scrive su **stderr** | — |
| Deploy con ripristino | `block` / `rescue` / `always` | vedi sotto | — |

### La pagina: Jinja nel `content`

```jinja
<h1>{{ inventory_hostname }}</h1>
<p>{{ messaggio }} · ambiente {{ ambiente }} · peso {{ peso_lb | default(1) }}</p>
{% if ansible_facts['distribution'] == 'Ubuntu' %}
<p>Ubuntu {{ ansible_facts['distribution_version'] }}</p>
{% endif %}
```

- `inventory_hostname` = il nome dell'host nell'inventario (`web1`, `web2`).
- `peso_lb | default(1)`: il filtro `default` evita l'errore se un host non ha la variabile.
- Il commento del file: con un file `.j2` si userebbe il modulo `template` (`src: index.html.j2`), stesso risultato.

### `validate`: la config rotta non arriva sul server

```yaml
validate: "bash -c 'echo \"events {} http { include %s; }\" > /tmp/v.conf && nginx -t -c /tmp/v.conf'"
```

- `%s` è il **file nuovo, ancora temporaneo**.
- Un frammento `server { … }` non si valida da solo: lo si include in una config minima (`events {} http { include …; }`)
  e si lancia `nginx -t` su quella.
- Il commento spiega perché non basta `nginx -t` normale: controllerebbe il `nginx.conf` installato, cioè il file
  **vecchio**.
- Se la validazione fallisce, il task fallisce e il file sul server **resta quello di prima** (passo 8).

### `block` / `rescue` / `always`

```yaml
block:
  - test -f /etc/nginx/nginx.conf        (command, changed_when: false)
  - uri http://localhost:{{ porta_http }}/salute   status_code: 200
rescue:
  - debug "qui un rollback: copia del file precedente, reload"
always:
  - debug "deploy su {{ inventory_hostname }} terminato"
```

Se un task del `block` fallisce, girano i task di `rescue` (qui solo un messaggio: in un deploy vero copierebbe il file
precedente e ricaricherebbe). `always` gira **comunque**.

### L'handler

```yaml
handlers:
  - name: Ricarica nginx
    ansible.builtin.systemd_service:
      name: nginx
      state: reloaded
```

Il `notify: Ricarica nginx` del task di config deve combaciare **esattamente** con questo `name`. Parte una volta sola,
a fine play, e solo se il task che lo notifica era *changed*.

---

## 3. Il secondo play: «Verifica dal punto di vista di un client»

```yaml
- name: Verifica dal punto di vista di un client
  hosts: web
  gather_facts: false
  tasks:
    - name: La pagina contiene il nome dell'host
      ansible.builtin.uri:
        url: "http://localhost:{{ porta_http }}/"
        return_content: true
      register: pagina
      failed_when: inventory_hostname not in pagina.content
```

- `gather_facts: false`: i fatti non servono, il play è più veloce.
- `failed_when` ridefinisce il fallimento: non basta il 200, la pagina deve contenere il nome dell'host (lo mette
  l'`<h1>` del template).

---

## 4. I passi dello script

| Passo | Comando | Cosa vedi / perché |
|---|---|---|
| 1 | `cp $LEZIONI/terraform/07-ansible-playbook.yml site.yml && grep -n 'name:\|tags:\|notify\|handlers' site.yml \| head -30` | copia il playbook e ne mostra lo scheletro: nomi, tag, notify, handler (con il numero di riga; compaiono anche righe di commento che contengono quelle parole) |
| 2 | `ansible-playbook site.yml --syntax-check` | solo la sintassi, senza collegarsi agli host |
| 3 | `ansible-playbook site.yml --check --diff` | **fallisce apposta** su host vergini: in check il pacchetto nginx non viene installato davvero, quindi il task `systemd_service` non trova il servizio. Il file di lezione riporta il messaggio provato: «Could not find the requested service nginx» |
| 4 | `ansible-playbook site.yml` | prima esecuzione: i task sono **changed** |
| 5 | `ansible-playbook site.yml` | seconda esecuzione: **changed=0**. Un playbook ben scritto è idempotente |
| 6 | `ansible-playbook site.yml -e messaggio="ciao" --diff` | `-e` ha la priorità massima: la pagina cambia e `--diff` mostra la riga nuova. Vedi l'incongruenza sull'handler sotto |
| 7 | `ansible-playbook site.yml --tags config --limit web1` | solo i due task con tag `config` (pagina e config di nginx), solo su `web1`. Senza `-e`, `messaggio` torna `"Servito da Ansible"`: la pagina di web1 viene riscritta |
| 8 | `ansible-playbook site.yml --limit web1 -e porta_http=abc` | **fallisce apposta**: `listen abc` non è valido, `validate` lo rifiuta («failed to validate», dal file di lezione) e il file buono resta sul server |
| 9 | `docker exec web1 curl -s localhost` | la prova: nginx su web1 **risponde ancora** con la pagina |
| 10 | `ansible-lint site.yml` | buone pratiche: FQCN dei moduli, nomi dei task, permessi dei file… Se segnala qualcosa lo vedi in rosso con il nome della regola |

### Il passo 6 e l'handler: attenzione

La spiegazione del passo 6 (e l'intestazione del file: «cambia il template → handler») dice che scatta l'handler che
ricarica nginx. Leggendo il playbook, però, `-e messaggio=…` cambia **solo la pagina** (`index.html`), e il task della
pagina **non ha `notify`**: il `notify: Ricarica nginx` sta solo sul task della **config** di nginx, il cui contenuto
non dipende da `messaggio`. Guarda l'output del passo 6: se in fondo non compare `RUNNING HANDLER [Ricarica nginx]`,
è per questo. Per far partire davvero l'handler serve cambiare la config, per esempio `-e porta_http=8080` (ma poi
ricordati di rilanciare senza `-e` per tornare alla 80).

Nel passo 8, invece, l'handler non parte perché il task notificante **fallisce**: i handler girano a fine play e
l'host è già uscito.

---

## Trappole

- **`--check` non è una garanzia**: i moduli che dipendono da qualcosa che in check non è successo falliscono (passo 3).
- **`command` senza `changed_when`** rende impossibile `changed=0`: qui `nginx -v` ce l'ha.
- **`when` vuole l'espressione senza `{{ }}`**, al contrario di quasi tutto il resto.
- **Il nome nel `notify`** deve combaciare con quello dell'handler (o con un suo `listen`).
- **`-e` vince su tutto**: se lo dimentichi in un comando, il valore torna quello del playbook o dell'inventario
  (passo 7).

## Domande da colloquio (dalla coda del file)

- **L'handler non è partito anche se ho cambiato la config. Perché?** 1) Il task che notifica non era *changed*
  (contenuto identico); 2) il play è fallito prima della fine: i handler girano a fine play (`--force-handlers` per
  eseguirli comunque, `meta: flush_handlers` per eseguirli subito); 3) il nome nel `notify` non coincide (o si usa
  `listen`).
- **Come rendi idempotente un task shell?** `creates:`/`removes:` (salta se il file esiste/non esiste), `changed_when`
  basato sull'output, oppure un controllo registrato + `when`. Meglio ancora: un modulo.
- **`--check` è affidabile?** Solo per i moduli che lo supportano; command/shell vengono saltati (o eseguiti con
  `check_mode: false`), e i task che dipendono da un `register` di un task saltato possono fallire. È un'anteprima,
  non una garanzia: per questo si testa con Molecule (lezione 08).
- **Perché `validate:` nel copy della config?** Il file viene scritto in un temporaneo, validato (`nginx -t`,
  `visudo -cf`, `sshd -t`) e copiato solo se valido: una config rotta non arriva mai sul server, quindi il reload non
  può rompere il servizio.

## Dipendenze e pulizia

- **Prima**: lezione 06 (container `web1`, `web2`, `db1` accesi, `inventory.yml` e `ansible.cfg` in
  `~/kubernetesprj/lavoro/ansible`). Senza `inventory.yml` lo script si ferma subito.
- **Dopo**: la 08 trasforma questo playbook in un ruolo; la 09 riusa gli stessi host.
- **Pulizia**: niente da togliere ora; i container si tolgono dopo la 09 (`docker rm -f web1 web2 db1`).

## Riepilogo

- Play → task **in ordine**, host **in parallelo**; la seconda esecuzione dà `changed=0`.
- `notify` + handler = reload **una volta sola, solo se serve**.
- `register` / `when` / `loop` / `changed_when` / `failed_when`.
- `block` / `rescue` / `always` per un deploy con ripristino.
- `--check --diff` per l'anteprima, `validate:` per le config, `ansible-lint` per le buone pratiche.

## Prova da solo

1. `ansible-playbook site.yml --limit web1 -e porta_http=8080 --diff`: compare `RUNNING HANDLER [Ricarica nginx]`? Poi
   `docker exec web1 curl -s localhost:8080/salute`. Alla fine rilancia `ansible-playbook site.yml` per tornare alla 80.
2. Togli `changed_when: false` dal task «Versione di nginx» in `site.yml` e lancia due volte il playbook: la seconda
   volta il riepilogo è ancora `changed=0`?
3. `ansible-playbook site.yml --list-tasks` e `ansible-playbook site.yml --list-tags`: quali task salterebbe
   `--tags config`?
