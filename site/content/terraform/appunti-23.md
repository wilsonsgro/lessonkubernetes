### In una frase

Ansible porta dei server già esistenti in uno **stato descritto**: dal **control node** entra nei nodi (di solito
SSH, nel laboratorio il plugin `community.docker.docker`), copia un **modulo** Python, lo esegue e legge il JSON di
risposta. Ogni modulo cambia qualcosa **solo se serve**: la seconda esecuzione dà `changed=0`. Terraform **crea** le
macchine, Ansible **configura** quello che gira dentro.

### Il laboratorio: container al posto delle VM

- Tre container Ubuntu 24.04 **con systemd** (`web1`, `web2`, `db1`, immagine `geerlingguy/docker-ubuntu2404-ansible`)
  fanno da server. Girano `--privileged` con il cgroup dell'host: **solo per il laboratorio**.
- Le parti 06–09 lavorano in `~/kubernetesprj/lavoro/ansible` e riusano gli stessi container: si tolgono solo alla
  fine della 09 (`docker rm -f web1 web2 db1`). La 10 crea i suoi nodi in `~/kubernetesprj/lavoro/iac/10`.
- `ansible-core` arriva con **pipx** (parte 00): gli script aggiungono `~/.local/bin` al `PATH`.

### Agentless, push, idempotente

| Idea | Che cosa vuol dire |
|---|---|
| agentless | sui nodi bastano Python e un utente con sudo: niente demoni, niente certificati |
| push | è il control node a collegarsi e a spingere i task, quando lo lanci |
| idempotenza | un modulo descrive uno **stato** (`apt: name=nginx state=present`), non un comando: rilanciato non cambia niente |

`command` e `shell` non sanno cosa fanno: sono **sempre CHANGED**, finché non dichiari tu l'idempotenza con
`creates:`, `removes:` o `changed_when`. Prima si cerca un modulo, poi `command`, `shell` solo per pipe e redirect.

### Inventario e variabili

L'inventario dice **quali host**, in **quali gruppi**, con **quali variabili**. Un gruppo può contenere altri gruppi
(`ubuntu` contiene `web` e `db`), e la stessa variabile (`pacchetti`) può valere cose diverse in gruppi diversi. Le
variabili che cominciano con `ansible_` dicono **come collegarsi**; le altre sono dati per i task.

La precedenza ha 22 livelli; quelli da ricordare, dal più debole al più forte:

```
defaults del ruolo < group_vars/all < group_vars/gruppo < host_vars
  < vars del play < vars del ruolo < set_fact/register < -e
```

Su un cloud l'elenco cambia di continuo: un **inventario dinamico** (`amazon.aws.aws_ec2`,
`community.docker.docker_containers`…) legge i server dall'API e crea i gruppi dai tag.

### Playbook: play, task, handler

Un playbook è una lista di **play**; un play applica dei **task** a un gruppo di host. I task vanno **in ordine**, gli
host **in parallelo** (strategia `linear`: il task N parte solo quando il N-1 è finito su tutti).

- **handler**: un task che gira **una volta a fine play**, solo se un task *changed* lo ha notificato. Se la config non
  cambia, nginx non viene ricaricato.
- `register`, `when` (senza `{{ }}`), `loop`, `changed_when`, `failed_when`; `block` / `rescue` / `always` come
  try / catch / finally.
- **`validate:`** scrive il file nuovo in un temporaneo, lo controlla (`nginx -t`, `visudo -cf`, `sshd -t`) e lo
  installa solo se è valido: una porta sbagliata viene rifiutata e nginx resta in piedi.
- `--check --diff` è un'**anteprima**, non una garanzia: i task che dipendono da qualcosa che in check non è successo
  falliscono (nel laboratorio il `service nginx` su host vergini).

### Ruoli e collection

Un **ruolo** è una cartella con nomi fissi: `defaults/` (i **parametri**, priorità minima), `vars/` (gli interni,
priorità alta), `tasks/`, `handlers/`, `templates/`, `meta/`. In `meta/argument_specs.yml` c'è il **contratto**: tipi e
obbligatori, controllati **prima di qualsiasi task**: `-e sito_porta=ottanta` ferma il ruolo senza toccare un file.

Un parametro messo in `vars/` invece che in `defaults/` non lo cambia più nessun `group_vars`. Le variabili di un
ruolo hanno un prefisso (`sito_`) perché in Ansible sono globali per host.

Una **collection** (`namespace.nome`, per esempio `community.docker`) distribuisce moduli, plugin e ruoli; si fissa a
versione in `requirements.yml`. Molecule prova un ruolo: converge, **idempotence** (deve dare `changed=0`), verify.

### Segreti e rolling update

- **Ansible Vault** cifra file interi o singoli valori (`encrypt_string`, AES256): in git va solo il cifrato. La
  password arriva da `--vault-password-file` (file `0600`) o dalla CI. Convenzione: `vault_db_password` cifrato,
  `db_password: "{{ vault_db_password }}"` in chiaro accanto.
- **`no_log: true`** su ogni task che tocca un segreto, anche nei loop: altrimenti il valore finisce nell'output e nei
  log.
- Rolling update a **lotti**: `serial` (anche `"30%"` o `[1, "25%"]`, dove il primo lotto fa da canary), `pre_tasks`
  che tolgono l'host dal bilanciatore con **`delegate_to`**, aggiornamento, verifica `uri` + `until` / `retries`,
  `post_tasks` che lo rimettono. Un host che fallisce esce dal play: il suo `post_tasks` non parte e **resta fuori**.
- `max_fail_percentage` vale **per lotto** e va **superato**, non eguagliato: con `0` il primo errore ferma i lotti
  successivi.

### La catena Terraform + Ansible

```
terraform apply ──▶ container + inventory.yml (local_file + templatefile)
                └──▶ ansible-playbook -i inventory.yml site.yml
```

Terraform crea i nodi con `for_each` su un insieme di nomi (`app01`, `app02`…) e **scrive l'inventario** con gli IP
che solo lui conosce. Con `-var repliche=3` crea **solo** `app03`; lo stesso playbook lo configura e gli altri due
restano verdi. Il confine resta netto: Terraform il **ciclo di vita delle risorse**, Ansible lo **stato dentro il
sistema operativo**. Due strumenti sulla stessa cosa portano drift e lotte fra tool; i provisioner di Terraform
(`remote-exec`) sono l'ultima risorsa.

**Mutabile o immutabile?** Server che vivono a lungo e che Ansible aggiorna, con il rischio dei «snowflake server»;
oppure immagini costruite (Packer + Ansible) e VM sostituite da Terraform. In Kubernetes l'immutabile è il default:
l'immagine container è l'artefatto, Ansible resta per i nodi e quello che sta fuori dal cluster.

### Verifica rapida (Ansible)

1. Che cosa serve sui nodi perché Ansible li possa gestire, e perché si dice «agentless»?
2. Perché `apt: name=nginx state=present` invece di `shell: apt-get install nginx`? Come rendi idempotente un `command`?
3. La stessa variabile è in `group_vars/web` e passata con `-e`: quale vince? E fra `defaults` e `vars` di un ruolo?
4. Hai cambiato un file ma l'handler non è partito: quali sono le tre cause possibili?
5. A che cosa serve `validate:` nel task che scrive la config di nginx?
6. Perché `--check --diff` non è una garanzia?
7. Che cosa controlla `meta/argument_specs.yml`, e quando?
8. Come tieni una password di DB in git senza metterla in chiaro, e come eviti che compaia nei log?
9. Nel rolling update della parte 09 web2 si rompe: perché resta fuori dal bilanciatore mentre web1 continua a servire?
10. Nella catena della parte 10, chi conosce gli IP dei nodi e come arrivano ad Ansible?
