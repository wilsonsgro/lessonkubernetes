# 08 — Ansible: ruoli e collection

Spiegazione di `08-ansible-ruoli-collection.sh` (questa cartella). Lezione sul sito: http://127.0.0.1:3000/terraform/8

## In una frase

Lo script fa scrivere al file di lezione un **ruolo** completo, `roles/sito_nginx` (defaults, vars, tasks, handlers,
templates, meta con **argument_specs**), più un playbook `sito.yml` che lo usa; poi ne mostra la struttura, lo esegue
sui container web, fa vedere che un parametro del tipo sbagliato viene **bloccato prima di qualsiasi task**, prova il
sito sulla porta 8080 ed elenca le collection installate.

## Questo script e la lezione

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/terraform/08-ansible-ruoli-collection.sh` | **questo**: lo script guidato. Lancia il file di lezione con `crea`, mostra il ruolo, lo esegue (Invio / s / q) | `bash terraform/08-ansible-ruoli-collection.sh` da `~/kubernetesprj` |
| `~/kubernetesprj/lezioni/terraform/08-ansible-ruoli-collection.sh` | il file di lezione: uno **script bash** con la teoria nei commenti e una funzione `crea` che scrive il ruolo e il playbook con degli heredoc | si **legge**; lo lancia il runner (`bash … crea`) |

Attenzione al nome: i due file si chiamano entrambi `08-ansible-ruoli-collection.sh`. Quello in
`~/kubernetesprj/terraform/` è il **guidato**; quello in `lezioni/terraform/` è il **generatore** del ruolo. Lanciato
senza argomenti, il generatore stampa solo `uso: … crea`.

```bash
cd ~/kubernetesprj
bash terraform/08-ansible-ruoli-collection.sh
```

## Com'è fatto lo script

```
source ../lib/passo.sh          → titolo / passo / nota / cartella
export PATH=~/.local/bin:…      → ansible di pipx
cartella ansible                → ~/kubernetesprj/lavoro/ansible (come 06 e 07)
[[ -f inventory.yml ]] || exit  → «prima esegui la lezione 06»
6 × passo
```

Il generatore ha `set -euo pipefail` e `R=roles/sito_nginx`: un percorso **relativo**, quindi il ruolo nasce nella
cartella in cui lo lanci (il runner lo lancia da `lavoro/ansible`). Rilanciarlo riscrive gli stessi file.

---

## 1. La teoria nell'intestazione

Versione: **ansible-core 2.21 · Molecule 26**. Livello 5 — Automazione su scala.

### Il ruolo: una struttura fissa che Ansible carica da sé

«Un playbook di 400 righe non si riusa.» Un **ruolo** è una cartella con nomi fissi:

```
roles/sito_nginx/
├── defaults/main.yml       valori di default — priorità MINIMA: l'utente del ruolo li sovrascrive (è l'interfaccia)
├── vars/main.yml           costanti interne — priorità ALTA: non pensate per essere cambiate
├── tasks/main.yml          i task (può includerne altri: include_tasks)
├── handlers/main.yml
├── templates/*.j2          per il modulo template
├── files/                  per il modulo copy
└── meta/
    ├── main.yml            dipendenze, piattaforme, galaxy_info
    └── argument_specs.yml  CONTRATTO: tipi e obbligatori, validati prima di eseguire il ruolo
```

Il generatore crea tutte queste cartelle tranne `files/` (il ruolo non copia file statici).

### La collection: il formato di distribuzione

Una **collection** è `namespace.nome` e contiene moduli, plugin e ruoli (`community.docker`, `amazon.aws`). Si
installa da Galaxy, da Automation Hub o da git, **a versioni fisse** in un `requirements.yml`:

```yaml
collections:
  - name: community.docker
    version: ">=5.0.0,<6.0.0"
roles:
  - name: geerlingguy.docker
    version: 7.4.1
```

```bash
ansible-galaxy install -r requirements.yml
```

### Riquadro «NEL PROGETTO VERO»

In `~/biodistretto/kubernetes` (branch `kubernetes`; come si usa: il README della cartella): **sette ruoli, un tag
per ruolo**, in ordine. Le collection sono fissate in `requirements.yml` e le installa `deploy.sh` prima del playbook;
il modulo docker vuole la sua libreria Python nel venv di pipx.

```bash
cd ~/biodistretto/kubernetes
cat ansible/site.yml
grep -n -E 'name:|version:' ansible/requirements.yml
grep -n -E 'galaxy|pipx' deploy.sh
./deploy.sh --tags haproxy,verifica      # si rilancia un solo pezzo
```

---

## 2. Il ruolo `sito_nginx`, file per file

### `defaults/main.yml` — l'interfaccia

```yaml
sito_nome: demo
sito_porta: 8080
sito_titolo: "Sito gestito da un ruolo"
sito_pacchetti_extra: []
```

Sono i **parametri** del ruolo. Priorità minima: qualunque `group_vars`, `vars` del play o `-e` li sovrascrive. Tutti
hanno il prefisso `sito_`: le variabili di Ansible sono globali per host, e un prefisso evita di pestare quelle di
altri ruoli o dell'inventario.

### `vars/main.yml` — gli interni

```yaml
sito_radice: "/var/www/{{ sito_nome }}"
sito_conf: "/etc/nginx/sites-available/{{ sito_nome }}"
```

Valori **calcolati** da un parametro. Priorità alta: non sono pensati per essere cambiati dall'esterno.

### `meta/argument_specs.yml` — il contratto

| Opzione | `type` | Altro |
|---|---|---|
| `sito_nome` | `str` | `required: true` |
| `sito_porta` | `int` | `description: Porta di ascolto` |
| `sito_titolo` | `str` | — |
| `sito_pacchetti_extra` | `list` | `elements: str` |

Sotto la chiave `main` (l'entry point `tasks/main.yml`), con `short_description: Pubblica un sito statico con nginx`.
Ansible confronta i parametri con questi tipi **prima** di eseguire i task del ruolo: un valore che non si può
convertire nel tipo dichiarato ferma tutto subito (passo 5).

### `meta/main.yml` — i metadati

`galaxy_info` con `author: lab`, `description`, `license: MIT`, `min_ansible_version: "2.17"`, `platforms` Ubuntu
`[noble]`; `dependencies: []` (nessun ruolo da eseguire prima).

### `tasks/main.yml`

| Task | Modulo | Cosa fa | `notify` |
|---|---|---|---|
| Pacchetti | `ansible.builtin.apt` | `name: "{{ ['nginx'] + sito_pacchetti_extra }}"`: nginx più gli extra (una somma di liste Jinja), `update_cache: true` con `cache_valid_time: 3600` | — |
| Cartella del sito | `ansible.builtin.file` | `{{ sito_radice }}`, `state: directory`, owner `www-data`, mode `"0755"` | — |
| Pagina | `ansible.builtin.template` | `index.html.j2` → `{{ sito_radice }}/index.html`, mode `"0644"` | — |
| Virtual host | `ansible.builtin.template` | `vhost.conf.j2` → `{{ sito_conf }}`, mode `"0644"` | `sito_nginx ricarica` |
| Virtual host abilitato | `ansible.builtin.file` | link `/etc/nginx/sites-enabled/{{ sito_nome }}` → `{{ sito_conf }}`, `state: link` | `sito_nginx ricarica` |
| Nginx attivo | `ansible.builtin.systemd_service` | `state: started`, `enabled: true` | — |

Qui si usa il modulo **`template`** con file `.j2` in `templates/`: è la forma che la lezione 07 citava nel commento
(«con un file .j2 si usa il modulo template»). `src: index.html.j2` viene cercato da solo in `templates/` del ruolo.

### `handlers/main.yml`

```yaml
- name: sito_nginx ricarica
  ansible.builtin.systemd_service:
    name: nginx
    state: reloaded
```

Anche l'handler ha il **prefisso del ruolo** nel nome: si distingue da `Ricarica nginx` della lezione 07. Lo notificano
due task: se cambiano entrambi, il reload avviene comunque **una volta sola** a fine play.

### I template

`templates/index.html.j2`:

```jinja
<!-- {{ ansible_managed }} -->
<h1>{{ sito_titolo }}</h1>
<p>{{ inventory_hostname }} · porta {{ sito_porta }}</p>
```

`templates/vhost.conf.j2`:

```jinja
# {{ ansible_managed }}
server {
    listen {{ sito_porta }};
    root {{ sito_radice }};
    index index.html;
}
```

`{{ ansible_managed }}` scrive nel file un'intestazione che avvisa: questo file lo gestisce Ansible, non modificarlo a
mano (verrebbe sovrascritto al prossimo giro).

### Il playbook `sito.yml`

```yaml
- name: Sito su tutti i web
  hosts: web
  become: true
  roles:
    - role: sito_nginx
      vars:
        sito_nome: negozio
        sito_titolo: "Negozio · {{ ambiente }}"
```

Il playbook è **corto**: tutto il lavoro sta nel ruolo. Passa due parametri: `sito_nome: negozio` (quindi
`sito_radice` diventa `/var/www/negozio` e la config `/etc/nginx/sites-available/negozio`) e un titolo che usa
`ambiente` dell'inventario 06 (`lab`). `sito_porta` resta il default **8080**.

Il sito della 07 (`sites-available/default`, porta 80) resta dov'è: su web1 e web2 nginx serve ora **due** siti, uno
sulla 80 e uno sulla 8080.

---

## 3. I passi dello script

| Passo | Comando | Cosa vedi / perché |
|---|---|---|
| 1 | `bash $LEZIONI/terraform/08-ansible-ruoli-collection.sh crea` | il generatore scrive il ruolo e `sito.yml` e stampa `ruolo scritto in roles/sito_nginx, playbook in sito.yml` |
| 2 | `find roles/sito_nginx -type f \| sort` | gli otto file del ruolo: `defaults/main.yml`, `handlers/main.yml`, `meta/argument_specs.yml`, `meta/main.yml`, `tasks/main.yml`, `templates/index.html.j2`, `templates/vhost.conf.j2`, `vars/main.yml` |
| 3 | `cat roles/sito_nginx/meta/argument_specs.yml` | il contratto: tipi e obbligatori |
| 4 | `ansible-playbook sito.yml` | il ruolo gira su `web1` e `web2`: pacchetti, cartella, pagina, vhost, link, e a fine play l'handler `sito_nginx ricarica` |
| 5 | `ansible-playbook sito.yml -e sito_porta=ottanta` | **fallisce apposta**: `ottanta` non è un `int`, argument_specs blocca il ruolo **prima di qualsiasi task**. Nessun file viene toccato |
| 6 | `docker exec web2 curl -s localhost:8080` | il sito servito dal ruolo: la pagina con `Negozio · lab`, `web2 · porta 8080` |
| 7 | `ansible-galaxy collection list 2>/dev/null \| grep -E "community.docker\|ansible.posix"` | le collection installate (namespace.nome): da lì vengono i moduli e i plugin con FQCN, come `community.docker.docker` della connessione |

---

## 4. Molecule: il test di un ruolo (solo teoria)

Lo script non lancia Molecule; il file di lezione lo descrive:

```bash
pipx inject ansible-core molecule "molecule-plugins[docker]"
cd roles/sito_nginx && molecule init scenario --driver-name docker
```

La sequenza di `molecule test`:

```
dependency → lint → create (container nuovi) → converge (applica il ruolo)
  → IDEMPOTENCE (lo riapplica: deve dare changed=0, altrimenti FALLISCE)
  → verify (asserzioni: un playbook con uri/assert, o testinfra) → destroy
```

In CI: un job per ruolo, con una matrice di piattaforme (Ubuntu 22/24, Debian 12).

Nel file di lezione `molecule-plugins[docker]` è scritto senza virgolette: in zsh le parentesi quadre vanno quotate,
come sopra.

---

## Trappole

- **Parametro in `vars/` invece che in `defaults/`**: `group_vars` non riesce più a cambiarlo (vedi domande).
- **Due file con lo stesso nome**: il guidato in `terraform/`, il generatore in `lezioni/terraform/`.
- **Il generatore usa un percorso relativo**: lanciato da un'altra cartella crea `roles/` lì.
- **Il controllo dei tipi avviene all'ingresso del ruolo**, non nel playbook: un errore di tipo blocca il ruolo intero,
  non un singolo task.

## Domande da colloquio (dalla coda del file)

- **defaults o vars in un ruolo?** defaults = parametri che l'utente può cambiare (priorità minima, quindi qualunque
  group_vars li sovrascrive). vars = valori interni calcolati o costanti, con priorità alta: metterci un parametro
  vuol dire che group_vars non riesce più a cambiarlo, «e nessuno capisce perché».
- **import_role/import_tasks o include_role/include_tasks?** import = **statico**, risolto quando il playbook viene
  letto: tag e `--list-tasks` lo vedono, ma niente loop e niente nomi da variabile. include = **dinamico**, a
  runtime: si può mettere in un loop o in un `when` calcolato, ma i tag non si propagano da soli ai task inclusi.
- **Come condividi i ruoli tra team?** In una collection versionata (o un repo git con tag), installata con
  `requirements.yml` a versione fissa. Per l'esecuzione centralizzata: AWX / Ansible Automation Platform (RBAC,
  credenziali, log, schedulazione) ed Execution Environment (immagine container con ansible-core e collection: stessa
  versione per tutti, costruita con ansible-builder).

## Dipendenze e pulizia

- **Prima**: lezione 06 (container e `inventory.yml`); la 07 non è obbligatoria, ma è lei che introduce handler e
  template.
- **Dopo**: la 09 riusa gli stessi host.
- **Pulizia**: `rm -rf roles sito.yml` in `~/kubernetesprj/lavoro/ansible` se vuoi rifare il ruolo da zero; i
  container si tolgono dopo la 09.

## Riepilogo

- Ruolo = struttura fissa: `defaults`, `vars`, `tasks`, `handlers`, `templates`, `meta`.
- `defaults` = interfaccia (priorità minima); `vars` = interni (priorità alta).
- `meta/argument_specs.yml` valida i parametri **prima** di eseguire.
- Collection + `requirements.yml` a versioni fisse; Galaxy / Automation Hub.
- Molecule: converge, **IDEMPOTENCE**, verify; AWX/AAP ed EE per i team.

## Prova da solo

1. `ansible-playbook sito.yml -e sito_porta=9090` e poi `docker exec web1 curl -s localhost:9090`: quanti task sono
   *changed* e quante volte gira l'handler? (Rilancia poi senza `-e` per tornare alla 8080.)
2. Aggiungi nel playbook `sito_pacchetti_extra: [tree, htop]` sotto `vars:` del ruolo e rilancia: cosa cambia nel
   task «Pacchetti»? E se scrivi `sito_pacchetti_extra: tree` (una stringa, non una lista)?
3. Sposta `sito_porta: 8080` da `defaults/main.yml` a `vars/main.yml` e lancia `ansible-playbook sito.yml -e
   sito_porta=9191`: vince ancora `-e`? Poi prova con una variabile di gruppo `sito_porta: 9191` nell'inventario
   (gruppo `web`): quale valore vince adesso, e perché?
