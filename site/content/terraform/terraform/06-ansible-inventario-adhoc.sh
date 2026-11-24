#!/usr/bin/env bash
# Lezione 06 — tre "server" in container, inventario YAML e comandi ad-hoc.
source "$(dirname "$0")/../lib/passo.sh"
export PATH="$HOME/.local/bin:$PATH"
titolo "06. Ansible: inventario e comandi ad-hoc"
cartella ansible

passo "Collection per connettersi ai container (community.docker) e per i callback (ansible.posix)" \
  'ansible-galaxy collection install community.docker ansible.posix'
passo "Tre container Ubuntu 24.04 con systemd: fanno da server web1, web2, db1 (privileged + cgroup per far girare systemd)" \
  'for n in web1 web2 db1; do docker ps -a --format "{{.Names}}" | grep -qx $n || docker run -d --name $n --hostname $n --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw geerlingguy/docker-ubuntu2404-ansible; done; docker ps --filter name=web --filter name=db1'
passo "L'inventario della lezione: gruppi web e db, variabili di gruppo, connessione docker al posto di SSH" \
  "cp $LEZIONI/terraform/06-ansible-inventario-adhoc.yml inventory.yml && cat inventory.yml | grep -v '^#' | sed '/^\$/d'"
passo "ansible.cfg nella cartella del progetto: viene letto per primo, evita di ripetere -i" \
  "printf '[defaults]\ninventory = inventory.yml\nforks = 20\ncallbacks_enabled = ansible.posix.profile_tasks\n' > ansible.cfg && cat ansible.cfg"
passo "Albero dei gruppi" \
  'ansible-inventory -i inventory.yml --graph'
passo "Le variabili RISOLTE per un host (gruppo + host + all, con la precedenza applicata)" \
  'ansible-inventory -i inventory.yml --host web1'
passo "Modulo ping: non è ICMP, verifica che Ansible entri nell'host e trovi Python" \
  'ansible all -i inventory.yml -m ansible.builtin.ping'
passo "Fatti raccolti dal modulo setup, filtrati" \
  "ansible web -i inventory.yml -m ansible.builtin.setup -a 'filter=ansible_distribution*'"
passo "Installo tree con il modulo apt (non c'è nell'immagine): la prima volta CHANGED" \
  "ansible web -i inventory.yml -m ansible.builtin.apt -a 'name=tree state=present update_cache=true'"
passo "Stesso comando: ora verde, changed=false. Questa è l'IDEMPOTENZA" \
  "ansible web -i inventory.yml -m ansible.builtin.apt -a 'name=tree state=present'"
passo "Il modulo command è sempre CHANGED: Ansible non sa cosa fa un comando (nei playbook si usa changed_when)" \
  "ansible db -i inventory.yml -m ansible.builtin.command -a 'uptime'"
passo "Pattern di host: il gruppo web tranne web2" \
  "ansible 'web:!web2' -i inventory.yml -m ansible.builtin.ping"
nota "I container web1, web2, db1 servono alle lezioni 07, 08 e 09: restano accesi." \
     "Per toglierli:  docker rm -f web1 web2 db1"
