# 06 — Ansible: inventario e comandi ad-hoc

Spiegazione di `06-ansible-inventario-adhoc.sh` (questa cartella). Lezione sul sito: http://127.0.0.1:3000/terraform/6

## In una frase

Lo script accende **tre container Ubuntu 24.04 con systemd** (`web1`, `web2`, `db1`) che fanno la parte dei server,
copia l'**inventario YAML** della lezione, scrive un `ansible.cfg` e poi lancia una serie di **comandi ad-hoc**
(`ansible <gruppo> -m <modulo>`): ping, raccolta dei fatti, installazione di un pacchetto due volte per vedere
l'**idempotenza**, un `command` che è sempre CHANGED e un pattern di host.

## Questo script e la lezione

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/terraform/06-ansible-inventario-adhoc.sh` | **questo**: lo script guidato. Accende i container, copia l'inventario e lancia i comandi uno per volta, spiegando prima di eseguire (Invio / s / q) | `bash terraform/06-ansible-inventario-adhoc.sh` da `~/kubernetesprj` |
| `~/kubernetesprj/lezioni/terraform/06-ansible-inventario-adhoc.yml` | il file di lezione: **è l'inventario** (gruppi, host, variabili) con la teoria nei commenti | si **legge**; il runner lo copia come `inventory.yml` |

```bash
cd ~/kubernetesprj
bash terraform/06-ansible-inventario-adhoc.sh
```

`AUTO=1` esegue tutto senza chiedere, `DA=n` parte dal passo n (`lib/passo.sh`).

## Com'è fatto lo script

```
source ../lib/passo.sh       → titolo / passo / nota / cartella
export PATH=~/.local/bin:…   → trova ansible installato con pipx (lezione 00)
cartella ansible             → crea ed entra in ~/kubernetesprj/lavoro/ansible
12 × passo                   → collection, container, inventario, ansible.cfg, 8 comandi
nota                         → i container restano accesi per 07, 08, 09
```

Tutti i file (`inventory.yml`, `ansible.cfg`) finiscono in `~/kubernetesprj/lavoro/ansible`. La stessa cartella la
riusano le lezioni dopo.

---

## 1. La teoria nell'intestazione

Versione indicata: **ansible-core 2.21**, collection **community.docker 5**. Livello 4 — Configuration management.

### Agentless e push

Ansible gira sul **control node** (il tuo Ubuntu) e si collega ai nodi: SSH su Linux, WinRM su Windows. Per ogni
task copia sul nodo un piccolo programma Python (il **modulo**), lo esegue e legge il **JSON** di risposta. Sui nodi
servono solo **Python** e un utente con sudo: niente demoni, niente certificati.

### Idempotenza

È il concetto chiave. Un modulo descrive uno **stato** («pacchetto nginx presente», «riga X nel file») e cambia
qualcosa **solo se serve**. Alla seconda esecuzione: `changed=0`. Per questo si scrive
`apt: name=nginx state=present` e non `shell: apt-get install nginx`.

### I pezzi

| Pezzo | Cos'è | Lezione |
|---|---|---|
| inventario | **quali** host, in quali gruppi, con quali variabili | questo file |
| modulo | un'azione idempotente (apt, copy, template, service, user…) | qui |
| task | un modulo con i suoi parametri | 07 |
| play | task applicati a un gruppo di host | 07 |
| playbook | una lista di play | 07 |
| ruolo | task/handler/template/default impacchettati e riusabili | 08 |
| collection | distribuzione di moduli, plugin e ruoli (`community.docker`…) | 08 |

### Il lab: container al posto delle VM

I "server" sono **container con systemd**; Ansible ci entra con il **plugin di connessione docker** invece che con
SSH. Il resto (moduli, gruppi, variabili) è identico a un parco di VM.

### `ansible.cfg` consigliato

L'intestazione consiglia questo file nella cartella del progetto (letto **per primo**):

```ini
[defaults]
inventory = inventory.yml
forks = 20                  # host in parallelo (default 5)
callbacks_enabled = ansible.posix.profile_tasks   # tempi per task
[ssh_connection]
pipelining = True           # meno round-trip SSH (richiede no requiretty)
```

Il runner (passo 4) scrive solo la sezione `[defaults]`: qui la connessione non è SSH, quindi `pipelining` non
servirebbe.

L'intestazione nota anche: **niente `-o`** per l'output su una riga, perché è deprecato in ansible-core 2.21.

### Riquadro «NEL PROGETTO VERO»

In `~/biodistretto/kubernetes` (branch `kubernetes`; come si usa: il README della cartella) c'è un inventario di **un
solo host**, la macchina stessa, con connessione `local` e lo stesso Python di `ansible-playbook` (pipx). Le variabili
comuni stanno in `group_vars/all.yml`; la password delle statistiche la genera il lookup `password` **una volta
sola** e poi la rilegge dallo stesso file.

```bash
cd ~/biodistretto/kubernetes
cat ansible/inventory.ini
grep -n "lookup('ansible.builtin.password'" ansible/group_vars/all.yml
```

---

## 2. L'inventario, riga per riga

```yaml
all:
  vars:
    ansible_connection: community.docker.docker
    ansible_python_interpreter: /usr/bin/python3
    ambiente: lab
    ntp_server: pool.ntp.org
  children:
    web:
      hosts:
        web1:
          peso_lb: 100
        web2:
          peso_lb: 50
      vars:
        porta_http: 80
        pacchetti: [nginx, curl]
    db:
      hosts:
        db1:
      vars:
        pacchetti: [postgresql]
    ubuntu:
      children:
        web:
        db:
```

### `all.vars`: valgono per tutti gli host

| Variabile | Valore | Perché |
|---|---|---|
| `ansible_connection` | `community.docker.docker` | il plugin di connessione: entra nel container con il nome dell'host (`web1` → container `web1`), **senza SSH**. Viene dalla collection `community.docker` |
| `ansible_python_interpreter` | `/usr/bin/python3` | dice ad Ansible quale Python usare sul nodo invece di cercarlo |
| `ambiente` | `lab` | variabile nostra, usabile nei template |
| `ntp_server` | `pool.ntp.org` | variabile nostra |

Il commento accanto: in un parco vero qui starebbero `ansible_user` e `ansible_ssh_private_key_file`.

Le variabili che cominciano con `ansible_` sono **variabili speciali**: Ansible le legge per decidere *come*
collegarsi. Le altre (`ambiente`, `ntp_server`, `porta_http`…) sono dati per i task.

### `children`: i gruppi

| Gruppo | Host | Variabili di gruppo |
|---|---|---|
| `web` | `web1` (`peso_lb: 100`), `web2` (`peso_lb: 50`) | `porta_http: 80`, `pacchetti: [nginx, curl]` |
| `db` | `db1` (nessuna variabile di host) | `pacchetti: [postgresql]` |
| `ubuntu` | nessun host diretto: **contiene i gruppi** `web` e `db` | — |

- `db1:` senza niente dopo i due punti è un host senza variabili proprie: valido.
- `pacchetti` ha lo **stesso nome** in `web` e in `db` ma valori diversi: ogni host prende quello del suo gruppo.
  Un task «installa `{{ pacchetti }}`» farà cose diverse su web e db.
- `ubuntu` mostra che **un gruppo può contenere altri gruppi**: `ansible ubuntu -m …` colpisce tutti e tre.

### Dove mettere le variabili in un progetto vero

| Posto | Vale per |
|---|---|
| `group_vars/all.yml`, `group_vars/web.yml` | un gruppo |
| `host_vars/web1.yml` | un host |
| `roles/x/defaults/main.yml` | default del ruolo (priorità **minima**) |
| `-e "var=valore"` | extra vars (priorità **massima**) |

La precedenza ha **22 livelli**; quelli da ricordare, dal più debole al più forte:

```
defaults del ruolo < group_vars/all < group_vars/gruppo < host_vars
  < vars del play < vars del ruolo < set_fact/register < -e
```

### Inventario dinamico

Su un cloud l'elenco dei server cambia: un **plugin d'inventario** lo legge dall'API (`amazon.aws.aws_ec2`,
`google.cloud.gcp_compute`, `azure.azcollection`, `community.docker.docker_containers`) e crea i gruppi dai tag:

```yaml
plugin: amazon.aws.aws_ec2
keyed_groups: [{ key: tags.Ruolo, prefix: ruolo }]   # → gruppo ruolo_web
```

Così Terraform crea le VM con un tag e Ansible le trova da solo: è il tema della lezione 10.

---

## 3. I passi dello script

| Passo | Comando | Cosa vedi / perché |
|---|---|---|
| 1 | `ansible-galaxy collection install community.docker ansible.posix` | le due collection del corso. Se le hai già dalla lezione 00 non cambia niente |
| 2 | `for n in web1 web2 db1; do docker ps -a … \| grep -qx $n \|\| docker run -d --name $n --hostname $n --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw geerlingguy/docker-ubuntu2404-ansible; done; docker ps --filter name=web --filter name=db1` | crea i tre container **solo se non esistono** (`grep -qx` cerca il nome esatto fra tutti i container, anche spenti), poi li elenca |
| 3 | `cp $LEZIONI/terraform/06-ansible-inventario-adhoc.yml inventory.yml && cat inventory.yml \| grep -v '^#' \| sed '/^\$/d'` | copia il file di lezione come `inventory.yml` e lo mostra **senza** le righe che iniziano con `#` e senza righe vuote. I commenti indentati o a fine riga restano |
| 4 | `printf '[defaults]\ninventory = inventory.yml\nforks = 20\ncallbacks_enabled = ansible.posix.profile_tasks\n' > ansible.cfg && cat ansible.cfg` | scrive `ansible.cfg` nella cartella: da qui in poi `-i` non servirebbe più (il runner lo passa comunque a ogni comando) |
| 5 | `ansible-inventory -i inventory.yml --graph` | l'albero dei gruppi: `@all`, `@web`, `@db`, `@ubuntu` con i loro host |
| 6 | `ansible-inventory -i inventory.yml --host web1` | le variabili **risolte** di `web1`: quelle di `all`, di `web` e la sua `peso_lb: 100`, già con la precedenza applicata |
| 7 | `ansible all -i inventory.yml -m ansible.builtin.ping` | il modulo `ping` **non è ICMP**: verifica che Ansible entri nell'host e trovi Python. Risponde `pong` |
| 8 | `ansible web -i inventory.yml -m ansible.builtin.setup -a 'filter=ansible_distribution*'` | il modulo `setup` raccoglie i **fatti**; il filtro tiene solo quelli che iniziano con `ansible_distribution` |
| 9 | `ansible web -i inventory.yml -m ansible.builtin.apt -a 'name=tree state=present update_cache=true'` | installa `tree` (non c'è nell'immagine) su web1 e web2: **CHANGED**. `update_cache=true` fa prima un `apt-get update` |
| 10 | `ansible web -i inventory.yml -m ansible.builtin.apt -a 'name=tree state=present'` | stesso stato richiesto: ora **verde, `changed: false`**. Questa è l'idempotenza |
| 11 | `ansible db -i inventory.yml -m ansible.builtin.command -a 'uptime'` | `command` è **sempre CHANGED**: Ansible non sa cosa fa un comando. Nei playbook si corregge con `changed_when` |
| 12 | `ansible 'web:!web2' -i inventory.yml -m ansible.builtin.ping` | **pattern** di host: il gruppo `web` tranne `web2` → solo `web1` |

Nessun passo fallisce apposta.

### Il passo 2 nel dettaglio: perché quelle opzioni

| Opzione | Perché |
|---|---|
| `--name $n --hostname $n` | il nome del container è quello che usa la connessione docker; l'hostname è quello che vedi *dentro* |
| `--privileged` | systemd dentro un container ha bisogno di permessi ampi |
| `--cgroupns=host` + `-v /sys/fs/cgroup:/sys/fs/cgroup:rw` | systemd deve vedere e scrivere i cgroup |
| `geerlingguy/docker-ubuntu2404-ansible` | immagine Ubuntu 24.04 con systemd e Python, pensata per provare Ansible |

Il test `docker ps -a --format "{{.Names}}" | grep -qx $n || docker run …` rende il passo **ripetibile**: se il
container c'è già (anche spento) non lo ricrea. Nota che **non lo riaccende** se è spento: in quel caso
`docker start web1 web2 db1`.

### I comandi ad-hoc: la forma

```
ansible <pattern> -i <inventario> -m <modulo> -a '<argomenti>'
```

- `<pattern>`: un host, un gruppo, `all`, o combinazioni come `web:!web2`.
- `-m`: il modulo con il nome completo (FQCN), `ansible.builtin.ping`.
- `-a`: gli argomenti del modulo in forma `chiave=valore`.

Un ad-hoc serve per **una cosa al volo** (controllare, riavviare, installare). Quando i task diventano più d'uno, si
scrive un **playbook** (lezione 07).

---

## 4. La nota finale

```
I container web1, web2, db1 servono alle lezioni 07, 08 e 09: restano accesi.
Per toglierli:  docker rm -f web1 web2 db1
```

Non spegnerli finché non hai finito la lezione 09.

---

## Trappole

- **Il pattern con `!`**: va fra **apici singoli** (`'web:!web2'`). Senza, la shell può interpretare `!` (storia dei
  comandi).
- **Il filtro con `*`**: `filter=ansible_distribution*` sta fra apici; in zsh un `*` nudo che non trova file annulla il
  comando.
- **Container spento**: il passo 2 non lo riaccende (vedi sopra), e allora `ping` fallisce su quell'host.
- **Il `cat | grep -v '^#'` del passo 3** nasconde solo i commenti a inizio riga: per leggere la teoria apri il file
  di lezione intero.
- **`command` e `shell` non sono idempotenti da soli**: vanno dichiarati con `creates:`, `removes:` o `changed_when`.

## Domande da colloquio (dalla coda del file)

- **command, shell o un modulo?** Prima il **modulo** (idempotente, check mode, diff). `command` se non c'è un modulo:
  niente shell, quindi niente pipe, redirect, variabili d'ambiente e meno rischio di injection. `shell` solo se servono
  pipe o redirect. Con command/shell si dichiara l'idempotenza: `creates:`, `removes:` o `changed_when`.
- **Ansible vs Puppet/Chef?** Ansible: agentless, push, YAML, curva bassa, ottimo per l'**orchestrazione** (ordine fra
  host: prima il DB, poi le app, poi il LB). Puppet/Chef: agente sul nodo, pull periodico, convergenza continua sullo
  stato desiderato; più adatti a parchi enormi e stabili.
- **Cosa sono i facts?** Informazioni raccolte dal modulo `setup` all'inizio del play (OS, IP, CPU, dischi):
  `ansible_facts['distribution']`. `gather_facts: false` se non servono (più veloce); fact caching (jsonfile, redis)
  per parchi grandi.

## Dipendenze e pulizia

- **Prima**: lezione 00 (ansible-core con pipx, le collection) e Docker funzionante.
- **Dopo**: 07, 08 e 09 usano gli stessi container e la stessa cartella `~/kubernetesprj/lavoro/ansible`.
- **Pulizia** (solo quando hai finito la 09): `docker rm -f web1 web2 db1`.

## Riepilogo

- **Agentless + push**: connessione (qui docker, di solito SSH) e Python sul nodo, nient'altro.
- **Moduli idempotenti**: la seconda esecuzione non cambia niente (passi 9 e 10). `command` è sempre CHANGED (passo 11).
- **Inventario YAML**: gruppi, gruppi di gruppi (`ubuntu`), variabili per gruppo e per host.
- **Precedenza**: defaults del ruolo < group_vars < host_vars < play < `-e`.
- **Cloud**: inventario dinamico dai tag (lezione 10).

## Prova da solo

1. `ansible-inventory -i inventory.yml --host web2` e poi `--host db1`: che valore ha `pacchetti` per ognuno, e da
   quale gruppo arriva? E `peso_lb` per `db1`?
2. `ansible web1 -i inventory.yml -m ansible.builtin.debug -a 'var=porta_http' -e 'porta_http=8080'`: quale valore
   vince, e perché (guarda la scala della precedenza)?
3. `ansible db -i inventory.yml -m ansible.builtin.command -a 'mkdir /tmp/prova creates=/tmp/prova'` lanciato due
   volte: la seconda volta è ancora CHANGED? Che cosa ha cambiato `creates=`?
