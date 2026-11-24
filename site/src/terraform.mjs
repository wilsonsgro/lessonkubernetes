// Lessons 22 (Terraform) and 23 (Ansible) come from the lab files, not from corso.md: `importa` copies them verbatim into content/terraform, `caricaCapitolo` turns a range of parts into a lesson.
import { readFileSync, readdirSync, mkdirSync, copyFileSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const RADICE = join(dirname(fileURLToPath(import.meta.url)), '..');
const CONTENUTO = join(RADICE, 'content', 'terraform');
const CARTELLE = ['terraform', 'lezioni/terraform'];
const LINGUA = { md: 'markdown', sh: 'bash', tf: 'hcl', yml: 'yaml', yaml: 'yaml' };

export const CAPITOLI = {
  '22': {
    parti: ['00', '01', '02', '03', '04', '05'],
    appunti: 'appunti.md',
    titolo: 'Terraform: l\'infrastruttura come codice',
    breve: 'Terraform',
    sommario: 'Il ciclo init/plan/apply, lo state e il drift, variabili e for_each, stato remoto con lock, import e moved, moduli e ambienti, test e pipeline: sul Docker locale, senza cloud.',
  },
  '23': {
    parti: ['06', '07', '08', '09', '10'],
    appunti: 'appunti-23.md',
    titolo: 'Ansible: configurare i server, e la catena con Terraform',
    breve: 'Ansible',
    sommario: 'Inventario e comandi ad-hoc, playbook idempotenti con handler e validate, ruoli e collection, Vault e rolling update a lotti, poi Terraform che crea i nodi e scrive l\'inventario per Ansible: su container con systemd.',
  },
};
export const PARTI = Object.values(CAPITOLI).flatMap(c => c.parti);

const daCopiare = base => CARTELLE.flatMap(c => {
  const dir = join(base, c);
  return existsSync(dir) ? readdirSync(dir).filter(f => PARTI.includes(f.slice(0, 2)) && /^\d\d-[a-z0-9-]+\.[a-z]+$/.test(f)).sort().map(f => `${c}/${f}`) : [];
});

export function importaDalLaboratorio(base = resolve(RADICE, '..')) {
  const file = daCopiare(base);
  if (!file.length) throw new Error(`nessun file Terraform in ${base}/terraform`);
  for (const p of file) {
    mkdirSync(dirname(join(CONTENUTO, p)), { recursive: true });
    copyFileSync(join(base, p), join(CONTENUTO, p));
  }
  return file;
}

const fonte = (percorso, ruolo) => {
  const testo = readFileSync(join(CONTENUTO, percorso), 'utf8');
  const nome = percorso.split('/').pop();
  return { nome, percorso, lingua: LINGUA[nome.split('.').pop()] || 'plaintext', ruolo, testo, righe: testo.replace(/\n$/, '').split('\n').length };
};

export function caricaCapitolo(id) {
  const c = CAPITOLI[id];
  const file = daCopiare(CONTENUTO);
  const parti = c.parti.map(n => {
    const trova = (cartella, re) => file.find(f => f.startsWith(`${cartella}/${n}-`) && re.test(f) && f.split('/').length === cartella.split('/').length + 1);
    const spiegazione = fonte(trova('terraform', /\.md$/), 'lezione');
    const script = fonte(trova('terraform', /\.sh$/), 'passi');
    const lez = trova('lezioni/terraform', /./);
    const titolo = spiegazione.testo.match(/^# \d\d — (.+)$/m)?.[1] ?? spiegazione.nome;
    return { n, titolo, spiegazione, script, file: lez ? fonte(lez, 'manifest') : null };
  });
  return {
    id, titolo: c.titolo, breve: c.breve, sommario: c.sommario,
    spiegazione: readFileSync(join(CONTENUTO, c.appunti), 'utf8'),
    parti,
    fonti: parti.flatMap(p => [p.spiegazione, p.script, p.file].filter(Boolean)),
    traccia: '',
  };
}

if (process.argv[1] === fileURLToPath(import.meta.url) && process.argv[2] === 'importa') {
  const copiati = importaDalLaboratorio(process.argv[3] ? resolve(process.argv[3]) : undefined);
  console.log(`copiati ${copiati.length} file in content/terraform`);
}
