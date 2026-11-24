import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { leggiPassi } from '../src/passi.mjs';
import { importa } from '../src/importa.mjs';
import { evidenzia, pericoliDi, linguaggio } from '../src/evidenzia.mjs';

test('quoting: apici, virgolette con escape, continuazioni', () => {
  const s = `titolo "21. HAProxy"\npasso "Uno \\"due\\"" \\\n  'kubectl get pod; echo $X'\npasso "IP=\\$(minikube ip)" \\\n  "curl http://\\$IP:30080/\\$p"\nnota "a" \\\n     "b"\n`;
  const v = leggiPassi(s);
  assert.deepEqual(v.map(x => x.tipo), ['titolo', 'passo', 'passo', 'nota']);
  assert.equal(v[1].perche, 'Uno "due"');
  assert.equal(v[1].comando, 'kubectl get pod; echo $X');
  assert.equal(v[2].perche, 'IP=$(minikube ip)');
  assert.equal(v[2].comando, 'curl http://$IP:30080/$p');
  assert.equal(v[3].testo, 'a\nb');
});

test('ogni script guidato del corso: un passo per ogni riga "passo", mai un comando vuoto', () => {
  const { lezioni } = importa(readFileSync(new URL('../content/corso.md', import.meta.url), 'utf8'));
  for (const l of lezioni) {
    const f = l.fonti.find(x => x.ruolo === 'passi');
    const attesi = (f.testo.match(/^passo /gm) || []).length;
    const passi = leggiPassi(f.testo).filter(v => v.tipo === 'passo');
    assert.equal(passi.length, attesi, l.id);
    for (const p of passi) assert.ok(p.perche && p.comando, `${l.id} passo ${p.n}`);
  }
});

test('evidenzia: una stringa su più righe resta bilanciata riga per riga', () => {
  const { html, righe } = evidenzia('a: "uno\ndue"\nb: 3\n', 'yaml');
  assert.equal(righe, 3);
  for (const r of html.split('\n')) assert.equal((r.match(/<span/g) || []).length, (r.match(/<\/span>/g) || []).length, r);
});

test('pericoli: segnala i comandi distruttivi, non i commenti', () => {
  assert.deepEqual(pericoliDi('kubectl -n lab delete pod web-1'), ['delete']);
  assert.deepEqual(pericoliDi('kubectl drain lab-m02 --ignore-daemonsets --force'), ['drain', '--force']);
  assert.deepEqual(pericoliDi('# kubectl delete ns lab'), []);
  assert.deepEqual(pericoliDi('kubectl get pods'), []);
  const e = evidenzia('kubectl get pod\nhelm uninstall eco\n', 'bash');
  assert.deepEqual(e.pericoli, { 'helm uninstall': 1 });
  assert.match(e.html.split('\n')[1], /class="riga pericolo"/);
});

test('passi: «cartella» diventa una voce con la cartella di lavoro', () => {
  const v = leggiPassi('titolo "01. Workflow"\ncartella iac/01\npasso "init" \\\n  \'terraform init\'\n');
  assert.deepEqual(v[1], { tipo: 'cartella', testo: 'iac/01' });
  assert.equal(v[2].comando, 'terraform init');
});

test('HCL: tf e terraform usano la grammatica hcl e colorano i blocchi', () => {
  const e = evidenzia('resource "docker_container" "web" {\n  name = "lab-web" # commento\n}\n', 'tf');
  assert.equal(e.lingua, 'hcl');
  assert.match(e.html, /hljs-keyword">resource</);
  assert.match(e.html, /hljs-comment"># commento/);
});

test('pericoli Terraform: -replace, state rm, force-unlock', () => {
  assert.deepEqual(pericoliDi('terraform apply -replace=docker_container.web -auto-approve'), ['terraform -replace']);
  assert.deepEqual(pericoliDi('terraform state rm docker_container.web'), ['terraform state rm']);
  assert.deepEqual(pericoliDi('terraform force-unlock 1234'), ['terraform force-unlock']);
  assert.deepEqual(pericoliDi('terraform plan -out=piano.tfplan'), []);
});

test('progetto reale: deploy.sh distruggi è pericoloso, deploy.sh e minikube stop no; nginx e Dockerfile colorati', () => {
  assert.deepEqual(pericoliDi('./deploy.sh distruggi'), ['deploy.sh distruggi']);
  assert.deepEqual(pericoliDi('./deploy.sh --tags immagini,app'), []);
  assert.deepEqual(pericoliDi('minikube -p biodistretto stop'), []);
  assert.equal(linguaggio('nginx'), 'nginx');
  assert.equal(linguaggio('dockerfile'), 'dockerfile');
});
