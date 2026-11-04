#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# 08. ANSIBLE: RUOLI, ARGUMENT SPECS, COLLECTION E TEST CON MOLECULE
# Versione: ansible-core 2.21 · Molecule 26
# Livello: 5 — Automazione su scala
# ═══════════════════════════════════════════════════════════════════════════
# Un playbook di 400 righe non si riusa. Un RUOLO è una cartella con una
# struttura fissa che Ansible carica da sé:
#
#   roles/sito_nginx/
#   ├── defaults/main.yml       valori di default — priorità MINIMA: l'utente
#   │                           del ruolo li sovrascrive (è l'interfaccia)
#   ├── vars/main.yml           costanti interne — priorità ALTA: non
#   │                           pensate per essere cambiate
#   ├── tasks/main.yml          i task (può includerne altri: include_tasks)
#   ├── handlers/main.yml
#   ├── templates/*.j2          per il modulo template
#   ├── files/                  per il modulo copy
#   └── meta/
#       ├── main.yml            dipendenze, piattaforme, galaxy_info
#       └── argument_specs.yml  CONTRATTO: tipi e obbligatori, validati
#                               prima di eseguire il ruolo
#
# COLLECTION = il formato di distribuzione: namespace.nome con moduli,
# plugin e ruoli (community.docker, amazon.aws). Si installano da Galaxy,
# da Automation Hub o da git, fissate in requirements.yml:
#   collections:
#     - name: community.docker
#       version: ">=5.0.0,<6.0.0"
#   roles:
#     - name: geerlingguy.docker
#       version: 7.4.1
#   ansible-galaxy install -r requirements.yml
#
# LAB (container della lezione 06)
#   cd ~/ansible && bash 08-ansible-ruoli-collection.sh crea
#   ansible-playbook sito.yml
#   ansible-playbook sito.yml -e sito_porta=ottanta     # argument_specs lo blocca
#   docker exec web2 curl -s localhost:8080

set -euo pipefail
R=roles/sito_nginx

crea() {
  mkdir -p $R/{defaults,vars,tasks,handlers,templates,meta}

  cat > $R/defaults/main.yml <<'EOF'
sito_nome: demo
sito_porta: 8080
sito_titolo: "Sito gestito da un ruolo"
sito_pacchetti_extra: []
EOF

  cat > $R/vars/main.yml <<'EOF'
sito_radice: "/var/www/{{ sito_nome }}"
sito_conf: "/etc/nginx/sites-available/{{ sito_nome }}"
EOF

  cat > $R/meta/argument_specs.yml <<'EOF'
argument_specs:
  main:
    short_description: Pubblica un sito statico con nginx
    options:
      sito_nome:
        type: str
        required: true
      sito_porta:
        type: int
        description: Porta di ascolto
      sito_titolo:
        type: str
      sito_pacchetti_extra:
        type: list
        elements: str
EOF

  cat > $R/meta/main.yml <<'EOF'
galaxy_info:
  author: lab
  description: Sito statico con nginx
  license: MIT
  min_ansible_version: "2.17"
  platforms:
    - name: Ubuntu
      versions: [noble]
dependencies: []
EOF

  cat > $R/tasks/main.yml <<'EOF'
- name: Pacchetti
  ansible.builtin.apt:
    name: "{{ ['nginx'] + sito_pacchetti_extra }}"
    state: present
    update_cache: true
    cache_valid_time: 3600

- name: Cartella del sito
  ansible.builtin.file:
    path: "{{ sito_radice }}"
    state: directory
    owner: www-data
    mode: "0755"

- name: Pagina
  ansible.builtin.template:
    src: index.html.j2
    dest: "{{ sito_radice }}/index.html"
    mode: "0644"

- name: Virtual host
  ansible.builtin.template:
    src: vhost.conf.j2
    dest: "{{ sito_conf }}"
    mode: "0644"
  notify: sito_nginx ricarica

- name: Virtual host abilitato
  ansible.builtin.file:
    src: "{{ sito_conf }}"
    dest: "/etc/nginx/sites-enabled/{{ sito_nome }}"
    state: link
  notify: sito_nginx ricarica

- name: Nginx attivo
  ansible.builtin.systemd_service:
    name: nginx
    state: started
    enabled: true
EOF

  cat > $R/handlers/main.yml <<'EOF'
- name: sito_nginx ricarica
  ansible.builtin.systemd_service:
    name: nginx
    state: reloaded
EOF

  cat > $R/templates/index.html.j2 <<'EOF'
<!-- {{ ansible_managed }} -->
<h1>{{ sito_titolo }}</h1>
<p>{{ inventory_hostname }} · porta {{ sito_porta }}</p>
EOF

  cat > $R/templates/vhost.conf.j2 <<'EOF'
# {{ ansible_managed }}
server {
    listen {{ sito_porta }};
    root {{ sito_radice }};
    index index.html;
}
EOF

  cat > sito.yml <<'EOF'
- name: Sito su tutti i web
  hosts: web
  become: true
  roles:
    - role: sito_nginx
      vars:
        sito_nome: negozio
        sito_titolo: "Negozio · {{ ambiente }}"
EOF
  echo "ruolo scritto in $R, playbook in sito.yml"
}

case "${1:-}" in
  crea) crea ;;
  *) echo "uso: $0 crea" ;;
esac

# ── MOLECULE: TEST DI UN RUOLO ──────────────────────────────────────────────
# pipx inject ansible-core molecule molecule-plugins[docker]
# cd roles/sito_nginx && molecule init scenario --driver-name docker
# La sequenza di `molecule test`:
#   dependency → lint → create (container nuovi) → converge (applica il
#   ruolo) → IDEMPOTENCE (lo riapplica: deve dare changed=0, altrimenti
#   FALLISCE) → verify (asserzioni: un playbook con uri/assert, o testinfra)
#   → destroy
# In CI: un job per ruolo, matrice di piattaforme (Ubuntu 22/24, Debian 12).

# ── DOMANDE DA COLLOQUIO ────────────────────────────────────────────────────
# D: defaults o vars in un ruolo?
# R: defaults = parametri che l'utente può cambiare (priorità minima,
#    quindi qualunque group_vars li sovrascrive). vars = valori interni
#    calcolati o costanti, con priorità alta: metterci un parametro vuol
#    dire che group_vars non riesce più a cambiarlo, e nessuno capisce perché.
#
# D: import_role/import_tasks o include_role/include_tasks?
# R: import = statico, risolto quando il playbook viene letto: tag e
#    --list-tasks lo vedono, ma niente loop e niente nomi da variabile.
#    include = dinamico, a runtime: si può mettere in un loop o in un when
#    calcolato, ma i tag non si propagano da soli ai task inclusi.
#
# D: Come condividi i ruoli tra team?
# R: In una collection versionata (o repo git con tag), installata con
#    requirements.yml a versione fissa; per l'esecuzione centralizzata AWX
#    / Ansible Automation Platform (RBAC, credenziali, log, schedulazione)
#    e Execution Environment (immagine container con ansible-core e
#    collection: stessa versione per tutti, costruita con ansible-builder).

# ══════════════════════════════════════════════════════════════════════════
# RIEPILOGO
# • Ruolo = struttura fissa: defaults, vars, tasks, handlers, templates, meta
# • defaults = interfaccia (priorità minima); vars = interni (priorità alta)
# • meta/argument_specs.yml valida i parametri prima di eseguire
# • Collection + requirements.yml a versioni fisse; Galaxy / Automation Hub
# • Molecule: converge, IDEMPOTENCE, verify; AWX/AAP ed EE per i team
# ══════════════════════════════════════════════════════════════════════════
