### In una frase

Terraform descrive l'infrastruttura come **codice dichiarativo**: scrivi lo stato finale in HCL, `plan` calcola la
differenza fra codice, **state** e realtà, `apply` la esegue. Nel laboratorio il «cloud» è il **Docker locale**,
raggiunto dal provider `kreuzwerker/docker`: nessun account, nessun costo, stessi concetti.

### Dove si colloca: crea, non configura

| Famiglia | Strumenti | Come ragiona |
|---|---|---|
| dichiarativo | Terraform, OpenTofu, Pulumi, CloudFormation | descrivi lo **stato finale**; il tool calcola il diff e lo applica |
| procedurale / di configurazione | Ansible, Chef, Puppet | descrivi i **passi** idempotenti per portare un server in uno stato |

La regola pratica del materiale: **Terraform crea** l'infrastruttura (rete, VM, DNS, database gestiti, cluster),
**Ansible configura** ciò che gira dentro. È la stessa idea della lezione 01 di Kubernetes (stato desiderato e
riconciliazione), con una differenza importante: i controller di Kubernetes riconciliano **di continuo**, Terraform
solo **quando lanci** `plan` o `apply`. Una modifica fatta a mano resta lì finché qualcuno non guarda.

### Il ciclo di lavoro

`init` → `fmt` / `validate` → `plan -out=piano.tfplan` → `apply piano.tfplan` → `destroy`.

- `init` scarica i provider e scrive `.terraform.lock.hcl`: le versioni scelte restano **bloccate** per te, i
  colleghi e la CI. Il lock file va in git.
- `plan -out` **salva** il piano: l'apply esegue esattamente quello che è stato letto e approvato, non un piano
  ricalcolato nel frattempo.
- Simboli del diff: `+` crea, `~` modifica, `-/+` **ricrea** (un attributo «ForceNew», segnalato con
  `# forces replacement`), `-` distrugge. Davanti a un `-/+` su un database ci si ferma: ricreare vuol dire perdere i dati.
- Le **dipendenze nascono dai riferimenti**: `image = docker_image.nginx.image_id` basta perché l'immagine venga
  creata prima del container. Nessuno scrive l'ordine a mano.

### Lo state: la memoria di Terraform

`terraform.tfstate` collega gli **indirizzi del codice** (`docker_container.web`) agli **ID reali**. Senza state
Terraform non sa che cosa ha creato e proverebbe a ricrearlo.

- Contiene **segreti in chiaro**: `sensitive = true` nasconde un valore in plan e output, **non** lo cifra nello state.
  Lo state non va mai in git.
- In squadra lo state sta su un **backend remoto** condiviso, con **lock**, cifrato e versionato (lezione 03 del
  materiale: `pg` su un Postgres locale per il laboratorio, `s3` con `use_lockfile` in produzione).
- Prima di toccarlo a mano: `terraform state pull` come copia di sicurezza.

### Drift: la realtà cambiata fuori da Terraform

Il laboratorio ferma il container `lab-web` con `docker stop`: il `plan` successivo se ne accorge e propone di
sistemarlo. Tre risposte diverse:

| Comando | Effetto |
|---|---|
| `terraform plan` | mostra la differenza fra codice e realtà |
| `plan` / `apply -refresh-only` | mostra o **accetta** nello state ciò che è cambiato fuori, senza toccare le risorse |
| `apply -replace=indirizzo` | **ricrea** quella risorsa anche se il plan non lo chiederebbe |

In produzione il drift si cerca con un plan schedulato in CI con `-detailed-exitcode`: esce **2** se ci sono
cambiamenti, e il job diventa rosso.

### Il linguaggio: interfaccia, calcoli, risultati

- `variable` è l'interfaccia (tipo, `optional`, `validation`, `sensitive`), `locals` i valori calcolati una volta,
  `output` ciò che esce per persone, moduli e CI.
- Precedenza dei valori, l'ultima vince: `default` < `TF_VAR_nome` < `terraform.tfvars` < `*.auto.tfvars` <
  `-var-file` < `-var`.
- **`for_each` per tutto ciò che ha un'identità, `count` solo per «0 o 1»**: con `count` togliere un elemento in
  mezzo fa scalare gli indici e Terraform tocca anche gli elementi dopo; con `for_each` tocca solo quello tolto.
  Le chiavi di `for_each` devono essere **note al plan**.
- Espressioni `for` per trasformare liste in mappe, blocchi `dynamic` per i blocchi ripetuti, `terraform console`
  per provarle.

### Cambiare senza distruggere: import, moved, removed

| Blocco | A che cosa serve |
|---|---|
| `import { to = …, id = … }` | adottare una risorsa che esiste già; `-generate-config-out` scrive anche il codice |
| `moved { from = …, to = … }` | rinominare o spostare una risorsa: il plan dice «has moved to», 0 da distruggere |
| `removed { from = …, lifecycle { destroy = false } }` | togliere una risorsa dal codice senza distruggerla |

`state rm` e `force-unlock` restano comandi di emergenza: prima si verifica che nessuno stia lavorando e si salva
lo state.

### Moduli e ambienti

Un **modulo** è una cartella con `variables`, `main`, `outputs`, `versions`. Il modulo **root** configura provider e
backend, i moduli figli no. Le sorgenti dei moduli sono **versionate** (tag git o registry), mai un branch: un merge
cambierebbe i plan di tutti i progetti insieme. Gli ambienti stanno in **cartelle separate**; i workspace vanno bene
solo per copie identiche ed effimere.

### Qualità prima dell'apply

Statico (`fmt`, `validate`, tflint, trivy) → **contratti** (`validation`, `precondition`, `postcondition`) →
**test** (`terraform test`: `command = plan` con `mock_provider` per la logica, `command = apply` per l'integrazione,
`expect_failures` per provare che le validazioni scattano) → **check** (asserzioni che **avvisano** senza bloccare).
In pipeline: plan nella merge request, **apply dello stesso piano**, drift notturno con exit 2.

### Laboratorio: che cosa serve

- Docker funzionante per il tuo utente: il provider parla con `/var/run/docker.sock`. Nessun cluster Kubernetes.
- `00-installa.sh` usa **sudo** per il repository HashiCorp: va lanciato una volta, a mano, sapendo che cosa fa.
- Ogni script lavora in `~/kubernetesprj/lavoro/iac/NN`; il file di lezione resta intatto. `AUTO=1` esegue tutto
  senza chiedere, `DA=n` parte dal passo n.
- Porte usate: 8088 (nginx della 01), 5433 (il Postgres dello state remoto della 03).

### Verifica rapida (Terraform)

1. Che differenza c'è fra uno strumento dichiarativo e uno procedurale? Dove sta Terraform e dove Ansible?
2. Perché si fa `apply` di un piano salvato invece di un `apply` diretto?
3. Che cosa contiene lo state, e perché non va in git anche se gli output sono `sensitive`?
4. Il plan mostra `-/+` su una risorsa: che cosa significa e quando ti fermi?
5. Hai fermato un container a mano: che cosa fanno `plan`, `apply -refresh-only` e `apply -replace`?
6. Perché `for_each` invece di `count` per un elenco di servizi?
7. Come rinomini una risorsa senza distruggerla, e come adotti una risorsa creata a mano?
8. Perché la sorgente di un modulo non deve puntare a un branch?
9. Che differenza c'è fra `precondition`, `postcondition` e `check`?
10. Che cosa significa exit code 2 di `terraform plan -detailed-exitcode`?
