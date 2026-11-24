# 09 — Ansible Vault e rolling update

Spiegazione di `09-ansible-vault-rolling-update.sh` (questa cartella). Lezione sul sito: http://127.0.0.1:3000/terraform/9

## In una frase

Lo script prepara la password del **vault**, copia un playbook che contiene una password di DB **già cifrata**, mostra
come si cifra un valore con `encrypt_string`, e poi fa due **rolling update** sui server web: il primo va liscio, il
secondo ha un **guasto voluto su web2**, che fallisce la verifica e **resta fuori dal bilanciatore** (finto, su
`db1`), mentre web1 continua a servire.

## Questo script e la lezione

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/terraform/09-ansible-vault-rolling-update.sh` | **questo**: lo script guidato. Crea `~/.vault_pass`, copia il playbook, lancia i due rolling update e legge il bilanciatore (Invio / s / q) | `bash terraform/09-ansible-vault-rolling-update.sh` da `~/kubernetesprj` |
| `~/kubernetesprj/lezioni/terraform/09-ansible-vault-rolling-update.yml` | il file di lezione: **è il playbook** (un play con `serial`, `delegate_to`, un segreto `!vault`, verifica con `until`) con la teoria nei commenti | si **legge**; il runner lo copia come `rolling.yml` |

```bash
cd ~/kubernetesprj
bash terraform/09-ansible-vault-rolling-update.sh
```

## Com'è fatto lo script

```
source ../lib/passo.sh          → titolo / passo / nota / cartella
export PATH=~/.local/bin:…      → ansible di pipx
cartella ansible                → ~/kubernetesprj/lavoro/ansible
[[ -f inventory.yml ]] || exit  → «prima esegui la lezione 06 e la 07»
7 × passo
nota                            → come togliere i container
```

Il controllo iniziale guarda solo `inventory.yml` (lezione 06). Della 07 serve **nginx sulla porta 80** con radice
`/var/www/html`: la verifica del playbook legge `http://localhost/versione.txt`. Se non hai fatto la 07, web1 (il primo
lotto, `order: sorted`) fallisce e, con `max_fail_percentage: 0`, il play si ferma lì: gli altri host non vengono
toccati.

---

## 1. La teoria nell'intestazione

Versione: **ansible-core 2.21**. Livello 5 — Automazione su scala. Due problemi da produzione:

1. **Segreti nel repo** (password di DB, token). Ansible Vault cifra file interi o singole stringhe (**AES256**): in
   git va solo il testo cifrato.
2. **Aggiornare N server senza fermare il servizio**: a **lotti** (`serial`), un lotto alla volta fuori dal load
   balancer, aggiornato, verificato, rimesso dentro. Se troppi falliscono ci si ferma (`max_fail_percentage`).

### Vault: i comandi

| Comando / opzione | A cosa serve |
|---|---|
| `ansible-vault encrypt_string 'S3greta!' --name db_password` | cifra **un valore**: produce il blocco `!vault` da incollare nel YAML (o in `group_vars/all/vault.yml`) |
| `ansible-vault create/edit/view/rekey group_vars/all/vault.yml` | lavora su un **file intero** cifrato |
| `--ask-vault-pass` oppure `--vault-password-file ~/.vault_pass` (chmod 600) | come dare la password del vault al playbook |
| `--vault-id dev@prompt --vault-id prod@~/.vault_prod` | una password per ambiente |

**Convenzione**: nel file cifrato `vault_db_password`, e accanto, in chiaro, `db_password: "{{ vault_db_password }}"`.
Così con `grep` trovi **dove** si usa una variabile senza decifrare niente. (La lezione, per semplicità, mette il
blocco cifrato direttamente in `db_password`.)

In CI la password del vault arriva da una **variabile protetta** o da un secret manager; con HashiCorp Vault c'è il
lookup `community.hashi_vault.hashi_vault` (segreti letti a runtime, non in git).

### Riquadro «NEL PROGETTO VERO»

In `~/biodistretto/kubernetes` (branch `kubernetes`; come si usa: il README della cartella) **non si usa Vault**,
perché nessun segreto passa da git:

- l'`APP_KEY` si legge dalla `.env` dello stack docker con `slurp` e `no_log`, e si passa a Terraform come `TF_VAR_`
  (variabile d'ambiente: non si vede in `ps` né nei log);
- le altre password le genera Terraform (`random_password`).

Il rolling update lo fa **Kubernetes** (Deployment con 2 repliche, una per nodo), e HAProxy toglie il nodo senza nginx
grazie al controllo di salute e a `externalTrafficPolicy Local`.

```bash
cd ~/biodistretto/kubernetes
grep -n -E 'no_log|TF_VAR_app_key' ansible/roles/app/tasks/main.yml
kubectl --context biodistretto cordon biodistretto-m02
kubectl --context biodistretto -n biodistretto delete pod -l app=nginx --field-selector spec.nodeName=biodistretto-m02
# …nelle statistiche di HAProxy m02 va DOWN. Poi:
kubectl --context biodistretto uncordon biodistretto-m02
```

---

## 2. Il play «Rolling update dei server web»

```yaml
- name: Rolling update dei server web
  hosts: web
  become: true
  serial: 1
  max_fail_percentage: 0
  order: sorted
  vars:
    versione: "1.0"
    rompi: ""
    lb_host: db1
    db_password: !vault |
              $ANSIBLE_VAULT;1.1;AES256
              6332633063…
```

| Campo | Valore | Perché |
|---|---|---|
| `hosts` | `web` | web1 e web2 |
| `serial` | `1` | **un host per lotto**: il play intero (pre_tasks, tasks, post_tasks) gira su web1, poi su web2. Si può scrivere anche `"30%"` o `[1, 5, "50%"]` |
| `max_fail_percentage` | `0` | al primo lotto fallito, **stop**: i lotti successivi non partono |
| `order` | `sorted` | ordine alfabetico: prima web1, poi web2 |
| `versione` | `"1.0"` | la versione "pubblicata"; il passo 6 la cambia con `-e versione=2.0` |
| `rompi` | `""` | nome dell'host da rompere apposta; vuoto = nessuno |
| `lb_host` | `db1` | l'host che fa da **bilanciatore finto** |
| `db_password` | `!vault \|` + testo cifrato | il segreto: `$ANSIBLE_VAULT;1.1;AES256` è l'intestazione del formato, il resto è il cifrato. Il commento accanto dice come è stato generato e con quale password del lab (`lab-vault`) |

Il bilanciatore è un file: **`/etc/lb/backends` su db1**, una riga per ogni host "in servizio". Con un HAProxy vero si
userebbe `community.general.haproxy state=drained` (socket runtime; corso HAProxy & Traefik, lezione 03).

### `pre_tasks`: preparare e svuotare

| Task | Cosa fa | Dettagli |
|---|---|---|
| Prepara il registro del bilanciatore | `lineinfile` una riga per ogni host di `ansible_play_hosts_all` in `/etc/lb/backends` (`create: true`, `mode: "0644"`) | `delegate_to: "{{ lb_host }}"`: gira **su db1**. `run_once: true`: una volta **per lotto**. Con `serial: 1` i lotti sono di un host, quindi in pratica gira per ogni host (misurato: `run_once` con `serial: 1` su 3 host gira 3 volte). Il nome del task e il commento del file lo dicono: «una volta per lotto» |
| Togli l'host dal bilanciatore (drain) | `lineinfile` con `line: "{{ inventory_hostname }}"` e `state: absent` | `delegate_to` db1: il task gira **sul bilanciatore** ma con le variabili dell'host corrente, quindi toglie proprio la sua riga |

### `tasks`: aggiornare e verificare

| Task | Cosa fa |
|---|---|
| Pubblica la nuova versione | scrive `/var/www/html/versione.txt` con `versione {{ versione }} su {{ inventory_hostname }}` |
| Configura la connessione al DB (segreto dal vault) | scrive `/etc/app.env` con `DB_PASSWORD=…`, `mode: "0600"`. **`no_log: true`**: senza, il valore finirebbe nell'output con `-v` e nei log di AWX |
| Simula un deploy rotto su un host scelto | sovrascrive `versione.txt` con `rotto`, **solo** `when: inventory_hostname == rompi` |
| Verifica prima di rimettere in servizio | `uri` su `http://localhost/versione.txt` con `return_content: true`; `until: versione in risposta.content`, `retries: 3`, `delay: 2`: fino a **4 tentativi** (il primo più 3 ripetizioni: misurato con ansible-core 2.21.5), ogni 2 secondi, finché la pagina contiene la versione attesa |

Il segreto si **decifra al volo** durante l'esecuzione grazie a `--vault-password-file`: sul disco del control node
resta cifrato, sul server finisce in chiaro nel file `0600`.

### `post_tasks`: rimettere in servizio

```yaml
- name: Rimetti l'host nel bilanciatore
  ansible.builtin.lineinfile:
    path: /etc/lb/backends
    line: "{{ inventory_hostname }}"
  delegate_to: "{{ lb_host }}"
```

Gira **solo se l'host è arrivato fin qui**: un host che ha fallito un task esce dal play e il suo `post_tasks` non
parte. È questo che lascia fuori dal bilanciatore un host rotto.

---

## 3. I passi dello script

| Passo | Comando | Cosa vedi / perché |
|---|---|---|
| 1 | `echo 'lab-vault' > ~/.vault_pass && chmod 600 ~/.vault_pass && ls -l ~/.vault_pass` | la password del vault in un file leggibile **solo da te** (`-rw-------`). In CI arriverebbe da una variabile protetta |
| 2 | `cp $LEZIONI/terraform/09-ansible-vault-rolling-update.yml rolling.yml && grep -n -A3 'db_password' rolling.yml \| head -6` | copia il playbook. Attenzione: le prime 6 righe del `grep` cadono nei **commenti dell'intestazione** (righe 14–19 del file), non sul blocco cifrato. Per vederlo: `grep -n -A6 'db_password: !vault' rolling.yml` |
| 3 | `ansible-vault encrypt_string --vault-password-file ~/.vault_pass 'S3greta!' --name db_password` | stampa un blocco `db_password: !vault \| $ANSIBLE_VAULT;1.1;AES256 …` da incollare nel YAML. Non scrive nessun file. Il cifrato sarà diverso da quello del playbook: è normale, la cifratura usa un sale casuale |
| 4 | `ansible-playbook rolling.yml --vault-password-file ~/.vault_pass` | rolling update a `versione 1.0`: web1 tolto dal bilanciatore, aggiornato, verificato, rimesso; poi lo stesso per web2 |
| 5 | `docker exec db1 cat /etc/lb/backends` | il bilanciatore finto: dentro `web1` e `web2` |
| 6 | `ansible-playbook rolling.yml --vault-password-file ~/.vault_pass -e versione=2.0 -e rompi=web2` | **fallisce apposta**: web1 passa alla 2.0; su web2 il task "rotto" sovrascrive la pagina, la verifica non trova `2.0` dopo 4 tentativi e fallisce. web2 **resta fuori** dal bilanciatore |
| 7 | `docker exec db1 cat /etc/lb/backends` | resta solo **web1**, l'host sano: il guasto non arriva agli utenti |

### Il passo 6, lotto per lotto

```
lotto 1 (web1): prepara registro → drain web1 → versione 2.0 → app.env → (rompi ≠ web1, salta) → verifica OK → rimetti web1
lotto 2 (web2): prepara registro → drain web2 → versione 2.0 → app.env → "rotto" → verifica FALLISCE → STOP
                post_tasks non gira: web2 non torna in /etc/lb/backends
```

Qui web2 è l'ultimo host, quindi `max_fail_percentage: 0` non ha niente da fermare. Il commento del file lo dice: con
più host, **i lotti successivi non partirebbero**. Se fosse rotto web1 (`-e rompi=web1`), web2 non verrebbe nemmeno
toccato.

---

## 4. Prestazioni su centinaia di host (teoria dal file)

| Leva | Effetto |
|---|---|
| `forks = 50` | host in parallelo |
| `pipelining = True` | un solo SSH per modulo, niente file temporanei |
| `ControlPersist` (default 60s) | riusa la connessione SSH |
| `gather_facts: false` / `gather_subset: [min]` / fact caching | meno tempo nella raccolta dei fatti |
| `strategy: free` | ogni host va avanti da solo, senza aspettare gli altri |
| `async` + `poll: 0` | task lunghi in background, poi `async_status` |
| mitogen (plugin esterno) | storicamente 2-7× più veloce |
| meno task | una lista a `apt` invece di un loop di `apt` |

---

## Trappole

- **La guardia iniziale** controlla solo la 06: senza nginx della 07 la verifica fallisce anche senza `rompi`.
- **`rompi` senza `versione` nuova**: anche `-e rompi=web2` da solo fa fallire web2, perché `rotto` non contiene
  nemmeno `1.0`.
- **Il registro si riprepara a ogni giro**: il primo task rimette in `/etc/lb/backends` **tutti** gli host del play,
  compreso un web2 lasciato fuori da un guasto precedente. Rilanciando il passo 4 dopo il 6, web2 torna nel
  bilanciatore **prima** di essere verificato (finché non arriva il suo lotto e viene svuotato). In un bilanciatore
  vero sarebbe un rischio; qui serve a ripartire puliti.
- **`no_log` va su ogni task che tocca il segreto**, anche nei loop: l'item viene stampato.
- **`~/.vault_pass` sta nella tua home**, fuori dalla cartella di lavoro: non finisce in git, ma resta lì dopo la
  lezione.

## Domande da colloquio (dalla coda del file)

- **Come fai un rolling update con Ansible senza downtime?** `serial` a lotti, `pre_tasks` che tolgono l'host dal LB
  con `delegate_to`, aggiornamento, verifica (`uri` + `until`), `post_tasks` che lo rimettono; `max_fail_percentage`
  per fermarsi se un lotto fallisce. Il primo lotto piccolo (`serial: [1, "25%"]`) fa da **canary**.
- **delegate_to vs run_once vs local_action?** `delegate_to` esegue il task su un altro host ma con le variabili
  dell'host corrente (utile per LB, DNS, monitoraggio). `run_once` lo esegue una volta sola per **lotto**: senza `serial` è una volta per play, con `serial` una volta per ogni lotto.
  `local_action` = `delegate_to: localhost`.
- **Il segreto compare nei log della pipeline.** `no_log: true` sui task che lo usano (anche nei loop: l'item viene
  stampato), niente `debug` di variabili sensibili, e in AWX le credenziali come tipo dedicato, non come extra vars.

## Dipendenze e pulizia

- **Prima**: lezione 06 (container, `inventory.yml`, `ansible.cfg`) e lezione 07 (nginx sulla 80, `/var/www/html`).
- **Dopo**: è l'ultima lezione sui container; la 10 lavora con Terraform.
- **Pulizia** (dalla nota finale): `docker rm -f web1 web2 db1`. Se non ti serve più, anche `rm ~/.vault_pass`.

## Riepilogo

- Vault: `encrypt_string` per singoli valori, `--vault-id` per ambiente; password da file `0600` o da CI.
- Convenzione `vault_*` cifrato + alias in chiaro; `no_log` sui task sensibili.
- Rolling: `serial` + drain con `delegate_to` + verifica `until/retries` + `max_fail_percentage`.
- `run_once` per il lavoro comune, `post_tasks` per rimettere in servizio: un host rotto **resta fuori**.
- Scala: `forks`, `pipelining`, fact caching, `strategy: free`, `async`.

## Prova da solo

1. Salva l'output del passo 3 in un file `segreto.yml` e lancia
   `ansible localhost -m ansible.builtin.debug -a 'var=db_password' -e '@segreto.yml' --vault-password-file ~/.vault_pass`.
   Cosa stampa? E se togli `--vault-password-file`?
2. `ansible-playbook rolling.yml --vault-password-file ~/.vault_pass -e versione=3.0 -e rompi=web1`: web2 viene
   toccato? Controlla con `docker exec web2 cat /var/www/html/versione.txt` e poi `docker exec db1 cat /etc/lb/backends`.
3. Togli `no_log: true` dal task «Configura la connessione al DB» in `rolling.yml` e lancia il passo 4 con `-v`: dove
   compare la password in chiaro? Poi rimetti `no_log`.
