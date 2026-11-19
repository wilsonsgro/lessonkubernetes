# 00 — Installazione di Terraform e Ansible

Spiegazione di `00-installa.sh` (questa cartella). Prerequisito di tutto il percorso Terraform & Ansible
(lezioni sul sito: http://127.0.0.1:3000/terraform/1 … /terraform/10).

## In una frase

Lo script installa gli strumenti del corso. **Terraform** viene dal repository apt ufficiale di HashiCorp, con sudo.
**Ansible** (ansible-core, due collection e ansible-lint) si installa con **pipx**, senza sudo, in virtualenv isolati.

## Questo script e la lezione

| File | Che cos'è |
|---|---|
| `~/kubernetesprj/terraform/00-installa.sh` | **questo**: lo script guidato, da lanciare |
| `~/kubernetesprj/lezioni/terraform/` | non c'è un file 00: la lezione 00 non esiste sul sito, questo script prepara solo il PC |

Si lancia dalla cartella del progetto:

```bash
cd ~/kubernetesprj
bash terraform/00-installa.sh
```

Come ogni script guidato, per ogni passo stampa la spiegazione e il comando, poi aspetta **Invio** (esegui) ·
**s** (salta) · **q** (esci). `AUTO=1` esegue tutto senza chiedere, `DA=n` parte dal passo n (`lib/passo.sh`).

## Com'è fatto il file

```
source ../lib/passo.sh   → le funzioni titolo / passo / nota
titolo "00. …"           → il riquadro viola in alto
8 × passo                → 4 per Terraform (apt), 4 per Ansible (pipx)
nota                     → il promemoria finale sul PATH
```

Non usa `guardia_lab`: non tocca nessun cluster Kubernetes.

---

## Parte 1 — Terraform dal repository di HashiCorp (passi 1–4)

Ubuntu non ha Terraform nei suoi repository. Si aggiunge quello di HashiCorp, **firmato**: apt installerà solo
pacchetti firmati con la loro chiave.

| Passo | Comando | Cosa fa |
|---|---|---|
| 1 | `sudo apt-get update && sudo apt-get install -y gnupg software-properties-common wget` | i pacchetti che servono per aggiungere un repository firmato: `gnupg` per la chiave, `wget` per scaricarla |
| 2 | `wget -O- https://apt.releases.hashicorp.com/gpg \| sudo gpg --dearmor --yes -o /usr/share/keyrings/hashicorp.gpg` | scarica la chiave pubblica di HashiCorp e la converte da testo (ASCII armor) a binario con `--dearmor`, il formato che apt legge. `--yes` sovrascrive il file se esiste già: lo script si può rilanciare |
| 3 | `echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \| sudo tee /etc/apt/sources.list.d/hashicorp.list` | aggiunge il repository. `$(lsb_release -cs)` è il nome in codice della tua Ubuntu (`noble`) |
| 4 | `sudo apt-get update && sudo apt-get install -y terraform && terraform version` | rilegge gli indici, installa Terraform e stampa la versione |

### Perché `signed-by`

`[signed-by=/usr/share/keyrings/hashicorp.gpg]` lega **questo** repository a **quella** chiave e a nessun'altra.
Il vecchio metodo (`apt-key add`) metteva la chiave fra quelle fidate per **tutti** i repository: una chiave
compromessa avrebbe potuto firmare pacchetti finti per Ubuntu stessa. Per questo `apt-key` è deprecato.

### Perché `sudo tee` e non `sudo echo … >`

In `sudo echo "…" > /etc/apt/…` la redirezione `>` la fa la **tua** shell, non sudo: fallisce per permessi.
`… | sudo tee file` scrive il file con i permessi di root. Il testo finisce anche a schermo, ed è normale.

---

## Parte 2 — Ansible con pipx (passi 5–8)

| Passo | Comando | Cosa fa |
|---|---|---|
| 5 | `pipx install --include-deps ansible-core && pipx ensurepath` | installa ansible-core in un **virtualenv suo**. `--include-deps` espone anche i comandi dei pacchetti dipendenti (`ansible-playbook`, `ansible-galaxy`, …). `ensurepath` aggiunge `~/.local/bin` al PATH nei file di avvio della shell |
| 6 | `export PATH="$HOME/.local/bin:$PATH"; ansible --version \| head -3` | mette `~/.local/bin` nel PATH **di questa esecuzione dello script**, così i passi dopo trovano `ansible`, e stampa la versione |
| 7 | `ansible-galaxy collection install community.docker ansible.posix` | le due collection del corso (sotto) |
| 8 | `pipx install ansible-lint` | il linter dei playbook, usato nella lezione 07, anche lui nel suo virtualenv |

### Perché pipx e non `pip install` o `apt install ansible`

- `pip install` nel Python di sistema su Ubuntu recente viene **rifiutato** («externally-managed-environment»), e
  comunque mescolerebbe le librerie di Ansible con quelle del sistema.
- pipx crea un virtualenv per ogni strumento e mette solo i **comandi** in `~/.local/bin`. Non serve sudo,
  e togliere uno strumento (`pipx uninstall ansible-core`) non lascia residui.
- **ansible-core** è il motore più i moduli base. Il pacchetto `ansible` completo include centinaia di collection
  che il corso non usa. Qui si aggiungono solo le due che servono.

### Le due collection

| Collection | A cosa serve nel corso |
|---|---|
| `community.docker` | la **connessione** `community.docker.docker`: Ansible entra nei container (`web1`, `web2`, `db1` della lezione 06) con `docker exec`, **senza SSH** |
| `ansible.posix` | il callback `profile_tasks`, che mostra quanto dura ogni task |

Le collection finiscono in `~/.ansible/collections`, fuori dal virtualenv di pipx.

---

## La nota finale: il PATH

```
Apri un terminale nuovo (o 'source ~/.bashrc') perché ~/.local/bin resti nel PATH.
```

L'`export` del passo 6 vale **solo dentro lo script**: quando finisce, il terminale da cui l'hai lanciato non lo
vede. `pipx ensurepath` (passo 5) l'ha scritto nei file di avvio, ma questi vengono letti solo da una shell nuova.
Per questo, se dopo lo script `ansible` dà «command not found», apri un terminale nuovo oppure:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

È anche la riga del README nella sezione «Quando qualcosa non va».

---

## Rilanciarlo è sicuro?

Sì, ogni passo è ripetibile:

- i passi apt: `install -y` di un pacchetto già presente non fa niente; la chiave si sovrascrive con `--yes`, e `tee`
  riscrive lo stesso file `hashicorp.list`;
- i passi pipx: se lo strumento c'è già, pipx scrive «already seems to be installed. Not modifying existing
  installation» ed esce con 0 (misurato con pipx 1.4.3): non cambia niente e non compare niente in rosso. Per
  aggiornare si usa `pipx upgrade ansible-core`;
- `ansible-galaxy collection install` di una collection già presente scrive «Nothing to do. All requested
  collections are already installed» (per aggiornarla: `--upgrade`).

Lo stato sul tuo Ubuntu (192.168.1.79), controllato il 19 novembre 2026: è già tutto installato.
- Terraform v1.17.2 da `/usr/bin/terraform`, con il repository `hashicorp.list` presente.
- ansible-core 2.21.5 e ansible-lint in `~/.local/bin`.
- Le collection `community.docker` 5.4.0 e `ansible.posix` 2.2.2.

## Controllo dopo l'installazione

```bash
for c in terraform ansible ansible-playbook ansible-galaxy ansible-lint; do printf '%-17s ' $c; command -v $c || echo MANCA; done
terraform version
ansible --version | head -1
ansible-galaxy collection list | grep -E 'community.docker|ansible.posix'
```

## Riepilogo

- Terraform: repository apt di HashiCorp **firmato e legato alla sua chiave** (`signed-by`), installato con sudo.
- Ansible: **pipx**, un virtualenv per strumento, comandi in `~/.local/bin`, niente sudo.
- Due collection: `community.docker` (entrare nei container senza SSH) e `ansible.posix` (`profile_tasks`).
- Alla fine: **terminale nuovo**, o il PATH non contiene `~/.local/bin`.

## Prova da solo

1. `cat /etc/apt/sources.list.d/hashicorp.list` e `apt-cache policy terraform`: da quale repository arriva la versione
   installata?
2. `pipx list`: quanti virtualenv ci sono, e quali comandi espone ognuno?
3. `ansible-doc -t connection -l | grep docker`: ne escono tre (`docker`, `docker_api`, `nsenter`). Quale usa la
   lezione 06? Cercalo in `lezioni/terraform/06-ansible-inventario-adhoc.yml`.
