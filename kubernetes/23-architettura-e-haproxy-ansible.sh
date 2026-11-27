#!/usr/bin/env bash
# Lezione 23 — la 21 (HAProxy Ingress controller + Headlamp) su un cluster minikube "lab-ansible", con ogni azione fatta da un playbook Ansible, un tag per passo.
source "$(dirname "$0")/../lib/passo.sh"
titolo "23. Architettura con HAProxy e Headlamp, tutta con Ansible"
F="$LEZIONI/kubernetes/23-architettura-e-haproxy-ansible.yaml"
export PATH="$HOME/.local/bin:$PATH"
export ANSIBLE_CALLBACK_RESULT_FORMAT=yaml ANSIBLE_LOCALHOST_WARNING=False ANSIBLE_INVENTORY_UNPARSED_WARNING=False ANSIBLE_DEPRECATION_WARNINGS=False

passo "Ansible non installa se stesso: ansible-core sta in pipx (senza sudo). Qui si aggiungono la collection kubernetes.core e la libreria Python kubernetes nel suo venv" \
  'ansible --version | head -1; ansible-galaxy collection install kubernetes.core >/dev/null && ansible-galaxy collection list kubernetes.core | tail -1; pipx runpip ansible-core show kubernetes >/dev/null 2>&1 || pipx inject ansible-core kubernetes; pipx runpip ansible-core show kubernetes 2>/dev/null | sed -n 2p'
passo "Il playbook e i suoi tag: ogni passo da qui ne lancia uno" \
  "ansible-playbook $F --list-tags"
passo "Versioni dei client, lette da Ansible" \
  "ansible-playbook $F --tags versioni"
passo "Trappola: senza --force minikube rifiuta 1 GiB per nodo. Il task ACCETTA solo l'uscita 23 (failed_when: rc != 23)" \
  "ansible-playbook $F --tags trappola"
passo "Il cluster 'lab-ansible': minikube start --force SOLO se è spento (when), use-context solo se serve, attesa di Calico con until, metrics-server. Qualche minuto" \
  "ansible-playbook $F --tags cluster"
guardia_lab lab-ansible 23-architettura-e-haproxy-ansible.sh
passo "HAProxy con kubernetes.core.helm: i valori sono un dizionario YAML nel playbook, non un file a parte" \
  "ansible-playbook $F --tags haproxy"
passo "Memoria netta dei nodi: il control plane vicino al limite, per questo HAProxy e Headlamp stanno sui worker" \
  "ansible-playbook $F --tags memoria"
passo "Le app della 21 con kubernetes.core.k8s (src: il manifest della 21, non copiato), poi uri+until al posto del curl in loop" \
  "ansible-playbook $F --tags app"
passo "Le prove della 21 con uri e assert: path-rewrite, roundrobin, 404 senza Host, haproxy.cfg, rate limit 429, statistiche" \
  "ansible-playbook $F --tags verifica"
passo "Headlamp dietro HAProxy: pod senza permessi, utente headlamp-lettore (view), le prove dei permessi con il token tenuto fuori dai log (no_log)" \
  "ansible-playbook $F --tags headlamp"
passo "Il token per il browser (8 ore). Tag 'never': gira solo se lo chiedi" \
  "ansible-playbook $F --tags headlamp-token"
nota "Apri Headlamp ora (Workloads → Pods, namespace lab-haproxy): nel prossimo passo blu sale a 5 e torna a 3."
passo "Scala blu a 5 con k8s_scale: assert che i reload restino fermi e i server diventino 5, poi di nuovo 3" \
  "ansible-playbook $F --tags scala"
passo "Idempotenza: lo stesso playbook di nuovo, tutto tranne i tag never. Si vedono solo i task che cambiano qualcosa: nel riepilogo changed=0" \
  "ANSIBLE_DISPLAY_OK_HOSTS=false ANSIBLE_DISPLAY_SKIPPED_HOSTS=false ansible-playbook $F"
passo "Deriva: qualcuno porta blu a 4 a mano (simulato da un task con tag never)" \
  "ansible-playbook $F --tags deriva-crea"
passo "--check --diff: Ansible dice cosa cambierebbe (Deployment/blu, replicas 4 → 3) SENZA toccare il cluster" \
  "ansible-playbook $F --tags app --check --diff"
passo "Ora senza --check: lo stato desiderato torna quello del file. Cambia solo Deployment/blu, poi blu ha 3 repliche" \
  "ansible-playbook $F --tags app && kubectl --context lab-ansible -n lab-haproxy get deploy blu"
passo "Pulizia con lo stesso playbook (tag never): Headlamp, utente, app, HAProxy, namespace" \
  "ansible-playbook $F --tags pulizia"
nota "Spegnere il cluster senza perderlo:  minikube -p lab-ansible stop" \
     "Cancellarlo con Ansible:            ansible-playbook $F --tags distruggi" \
     "Tornare al cluster delle altre lezioni: kubectl config use-context lab (dopo minikube -p lab start)"
