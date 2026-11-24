// Lesson 24: the real Biodistretto project (~/biodistretto/kubernetes). `importa` copies a fixed list of files, never state, plans, .env or caches, and masks LAN addresses; the fidelity test compares against the same mask.
import { readFileSync, mkdirSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const RADICE = join(dirname(fileURLToPath(import.meta.url)), '..');
const CONTENUTO = join(RADICE, 'content', 'progetto');
export const SORGENTE = process.env.PROGETTO || resolve(RADICE, '../../biodistretto/kubernetes');
const LINGUA = { md: 'markdown', sh: 'bash', tf: 'hcl', yml: 'yaml', yaml: 'yaml', j2: 'haproxy', conf: 'nginx', ini: 'ini', cfg: 'ini' };

export const VIETATI = [/\.tfstate/, /\.tfplan$/, /(^|\/)\.env$/, /(^|\/)\.cache\//, /\.crt$/, /(^|\/)\.terraform\//, /lock\.info$/];

export const FILE = [
  'README.md', 'deploy.sh', '.gitignore',
  'ansible/site.yml', 'ansible/ansible.cfg', 'ansible/inventory.ini', 'ansible/requirements.yml', 'ansible/group_vars/all.yml',
  'ansible/roles/prerequisiti/tasks/main.yml', 'ansible/roles/cluster/tasks/main.yml', 'ansible/roles/immagini/tasks/main.yml',
  'ansible/roles/app/tasks/main.yml', 'ansible/roles/dati/tasks/main.yml', 'ansible/roles/dati/tasks/media.yml',
  'ansible/roles/haproxy/tasks/main.yml', 'ansible/roles/haproxy/handlers/main.yml', 'ansible/roles/haproxy/templates/haproxy.cfg.j2',
  'ansible/roles/verifica/tasks/main.yml', 'ansible/distruggi.yml',
  'terraform/cluster/main.tf', 'terraform/cluster/variables.tf', 'terraform/cluster/outputs.tf',
  'terraform/app/versions.tf', 'terraform/app/variables.tf', 'terraform/app/segreti.tf', 'terraform/app/config.tf',
  'terraform/app/workload.tf', 'terraform/app/outputs.tf',
  'terraform/app/manifests/dati.yaml.tftpl', 'terraform/app/manifests/minio-init.yaml.tftpl', 'terraform/app/manifests/app.yaml.tftpl',
  'terraform/app/nginx/www.conf.tftpl', 'terraform/app/nginx/backend.conf.tftpl', 'terraform/app/nginx/bordo.conf',
  'docker/build.sh', 'docker/frontend/Dockerfile', 'docker/frontend/nginx-k8s.conf',
];

export const maschera = t => t.replace(/(?<![\d.])192\.168\.\d{1,3}\.\d{1,3}(?![\d.])/g, 'IP-DEL-LAB');

const lingua = nome => {
  if (nome === 'Dockerfile') return 'dockerfile';
  const parti = nome.split('.');
  const est = parti.pop();
  if (est === 'tftpl') return { tf: 'hcl', yaml: 'yaml', conf: 'nginx' }[parti.pop()] || 'plaintext';
  return LINGUA[est] || 'plaintext';
};

export function importaDalProgetto(base = SORGENTE) {
  for (const p of FILE) if (VIETATI.some(re => re.test(p))) throw new Error(`file vietato: ${p}`);
  const mancanti = FILE.filter(p => !existsSync(join(base, p)));
  if (mancanti.length) throw new Error(`mancano in ${base}: ${mancanti.join(', ')}`);
  const testi = FILE.map(p => [p, maschera(readFileSync(join(base, p), 'utf8'))]);
  for (const [p, t] of testi) if (/192\.168\.\d+\.\d+/.test(t)) throw new Error(`IP non mascherato in ${p}`);
  for (const [p, t] of testi) {
    mkdirSync(dirname(join(CONTENUTO, 'file', p)), { recursive: true });
    writeFileSync(join(CONTENUTO, 'file', p), t);
  }
  return FILE;
}

export function caricaProgetto() {
  const fonti = FILE.map((percorso, n) => {
    const testo = readFileSync(join(CONTENUTO, 'file', percorso), 'utf8');
    const nome = percorso.split('/').pop();
    return { nome: percorso, percorso, scarica: `biodistretto/${percorso}`, lingua: lingua(nome), ruolo: n ? 'progetto' : 'lezione', testo, righe: testo.replace(/\n$/, '').split('\n').length };
  });
  return {
    id: '24',
    titolo: 'Progetto reale: Biodistretto su Kubernetes',
    breve: 'Progetto reale',
    sommario: 'Un sito vero su minikube: Ansible fa da regista, Terraform crea il cluster e i workload, HAProxy porta il traffico ai NodePort. Gli stessi pezzi delle lezioni 21, 22 e 23, messi insieme.',
    radice: '~/biodistretto/kubernetes/',
    introFonti: `I ${FILE.length} file del progetto che contano, così come sono nel repository (branch <code>kubernetes</code>). Restano fuori lo state di Terraform, i piani, <code>.env</code>, <code>.cache/</code> e il certificato: contengono segreti o sono generati. Nel README l'indirizzo del laboratorio è sostituito da <code>IP-DEL-LAB</code>. Nessun comando viene eseguito dal sito.`,
    titoloPassi: 'I comandi del README',
    passi: { percorso: 'comandi.passi', testo: readFileSync(join(CONTENUTO, 'comandi.passi'), 'utf8') },
    introPassi: 'Raccolti dal README del progetto, non da uno script guidato: si lanciano a mano dal PC del laboratorio, in <code>~/biodistretto/kubernetes</code>.',
    spiegazione: readFileSync(join(CONTENUTO, 'appunti-24.md'), 'utf8'),
    fonti,
    traccia: '',
  };
}

if (process.argv[1] === fileURLToPath(import.meta.url) && process.argv[2] === 'importa') {
  const copiati = importaDalProgetto(process.argv[3] ? resolve(process.argv[3]) : undefined);
  console.log(`copiati ${copiati.length} file in content/progetto/file`);
}
