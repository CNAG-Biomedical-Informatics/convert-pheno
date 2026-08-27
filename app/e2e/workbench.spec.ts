import { expect, test } from '@playwright/test'
import { readFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { strFromU8, unzipSync } from 'fflate'

async function fixture(relativePath: string) {
  return readFile(new URL(`../../${relativePath}`, import.meta.url), 'utf8')
}

function fixturePath(relativePath: string) {
  return fileURLToPath(new URL(`../../${relativePath}`, import.meta.url))
}

test('starts with a bundled example that converts to a table preview', async ({ page }) => {
  await page.goto('/')
  await expect(page.getByText('beacon-individuals-example.json')).toBeVisible()
  await expect(page.getByLabel('JSON input')).toHaveValue(/HG00096/)
  await page.getByRole('button', { name: 'Run conversion' }).click()
  await expect(page.getByText('1 output file ready')).toBeVisible()
  await expect(page.getByRole('region', { name: /table preview/ })).toBeVisible()
  await expect(page.getByText(/of \d+ visible/)).toBeVisible()
})

test('downloads a PXF to BFF artifact from the real Perl service', async ({ page }) => {
  await page.goto('/')
  await page.getByLabel('Source format').selectOption('pxf')
  await page.getByLabel('Target format').selectOption('pxf2bff')
  await page.getByLabel('Choose JSON file').setInputFiles(fixturePath('t/pxf2bff/in/pxf.json'))
  await page.getByRole('button', { name: 'Run conversion' }).click()
  await expect(page.getByText('individuals.json')).toBeVisible()

  const downloadPromise = page.waitForEvent('download')
  await page.getByRole('button', { name: 'Download file' }).click()
  const download = await downloadPromise
  const generated = JSON.parse(await readFile(await download.path(), 'utf8'))
  const expected = JSON.parse(await fixture('t/pxf2bff/out/individuals.json'))
  generated.forEach((individual: { info?: { convertPheno?: unknown } }) => {
    delete individual.info?.convertPheno
  })
  expect(generated).toEqual(expected)
})

test('downloads all FHIR-derived BFF entities as a ZIP', async ({ page }) => {
  await page.goto('/')
  await page.getByLabel('Source format').selectOption('fhir')
  await page.getByLabel('Target format').selectOption('fhir2bff')
  for (const entity of ['biosamples', 'datasets', 'cohorts']) {
    await page.getByRole('checkbox', { name: entity }).check()
  }
  await page.getByLabel('JSON input').fill(await fixture('t/fhir2bff/in/patient-bundle.json'))
  await page.getByRole('button', { name: 'Run conversion' }).click()
  await expect(page.getByText('4 output files ready')).toBeVisible()

  const downloadPromise = page.waitForEvent('download')
  await page.getByRole('button', { name: 'Download ZIP' }).click()
  const download = await downloadPromise
  const archive = unzipSync(await readFile(await download.path()))
  expect(Object.keys(archive).sort()).toEqual([
    'biosamples.json', 'cohorts.json', 'datasets.json', 'individuals.json',
  ])
  const individuals = JSON.parse(strFromU8(archive['individuals.json']))
  const expected = JSON.parse(await fixture('t/fhir2bff/out/individuals.json'))
  for (let index = 0; index < individuals.length; index += 1) {
    delete individuals[index]?.info?.convertPheno
    const bundles = individuals[index]?.info?.fhir?.bundles
    if (bundles) {
      bundles.forEach((bundle: { source: string }, bundleIndex: number) => {
        expected[index].info.fhir.bundles[bundleIndex].source = bundle.source
      })
    }
  }
  expect(individuals).toEqual(expected)
})

test('converts CSV plus its mapping through multipart upload', async ({ page }) => {
  await page.goto('/')
  await page.getByLabel('Source format').selectOption('csv')
  await page.getByLabel('CSV data').setInputFiles(fixturePath('t/csv2bff/in/csv_data.csv'))
  await page.getByLabel('Mapping file').setInputFiles(fixturePath('t/csv2bff/in/csv_mapping.yaml'))
  await page.getByText('Advanced settings').click()
  await page.getByLabel('Column separator').fill(',')
  await page.getByRole('button', { name: 'Run conversion' }).click()
  await expect(page.getByText('individuals.json')).toBeVisible()
  await expect(page.getByRole('region', { name: 'individuals.json table preview' })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Review mapped terms before using the output' })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Download full XLSX' })).toBeVisible()
  await expect(page.getByRole('region', { name: 'Terminology review decisions' })).toBeVisible()
  await expect(page.getByRole('button', { name: /All preview/ })).toHaveAttribute('aria-pressed', 'true')
})
