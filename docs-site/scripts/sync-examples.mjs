import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const docsSiteDir = path.resolve(path.dirname(__filename), '..');
const repoRoot = path.resolve(docsSiteDir, '..');
const examplesDir = path.join(docsSiteDir, 'static', 'examples');

const examples = [
  {
    source: path.join(repoRoot, 't', 'bff2pxf', 'in', 'individuals.json'),
    target: path.join(examplesDir, 'bff-individuals.json'),
  },
  {
    source: path.join(repoRoot, 't', 'pxf2bff', 'in', 'pxf_biosamples.json'),
    target: path.join(examplesDir, 'pxf-biosamples.json'),
  },
  ...['PERSON.csv', 'CONCEPT.csv', 'DRUG_EXPOSURE.csv'].map((filename) => ({
    source: path.join(repoRoot, 't', 'omop2bff', 'in', filename),
    target: path.join(examplesDir, 'omop', filename),
  })),
];

for (const example of examples) {
  if (!fs.existsSync(example.source)) {
    throw new Error(`Canonical example is missing: ${example.source}`);
  }

  fs.mkdirSync(path.dirname(example.target), {recursive: true});
  fs.copyFileSync(example.source, example.target);
}
