import {access} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

// These routes are cited by the published Convert-Pheno software paper.
const publishedRoutes = [
  '/',
  '/download-and-installation',
  '/implementation',
  '/mapping-steps',
  '/use-as-an-api',
  '/future-plans',
];

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const buildDir = path.resolve(scriptDir, '..', 'build');
const missingRoutes = [];

for (const route of publishedRoutes) {
  const relativeFile = route === '/' ? 'index.html' : `${route.slice(1)}/index.html`;

  try {
    await access(path.join(buildDir, relativeFile));
  } catch {
    missingRoutes.push(route);
  }
}

if (missingRoutes.length > 0) {
  throw new Error(
    `Published documentation routes are missing from the build: ${missingRoutes.join(', ')}`,
  );
}

console.log(`Verified ${publishedRoutes.length} publication-linked documentation routes.`);
