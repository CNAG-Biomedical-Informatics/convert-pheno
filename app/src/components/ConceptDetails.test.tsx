import { render, screen, cleanup } from '@testing-library/react'
import { afterEach, expect, it, vi } from 'vitest'
import ConceptDetails from './ConceptDetails'
import { conceptIdFor } from './DataView'
import { lookupConcept } from '../api'
vi.mock('../api', () => ({ lookupConcept: vi.fn() }))
afterEach(() => { cleanup(); vi.resetAllMocks() })

it('only recognizes allowlisted concept fields and integer identifiers', () => {
  const fields = ['measurement_concept_id']
  expect(conceptIdFor('MEASUREMENT_CONCEPT_ID', '12', fields)).toBe('12')
  expect(conceptIdFor('measurement_concept_id', 0, fields)).toBe('0')
  expect(conceptIdFor('person_id', 12, fields)).toBeUndefined()
  for (const value of [-1, 1.5, '12 OR 1=1', null, {}, 2147483648]) {
    expect(conceptIdFor('measurement_concept_id', value, fields)).toBeUndefined()
  }
  expect(conceptIdFor('measurement_concept_id', 12, [])).toBeUndefined()
})
it('displays the database label and available metadata', async () => {
  vi.mocked(lookupConcept).mockResolvedValue({ state: 'found', concept: { label: 'Synthetic measurement', domain_id: 'Measurement', standard_concept: 'S' } })
  render(<ConceptDetails id="12" />)
  expect(await screen.findByText('Synthetic measurement')).toBeInTheDocument()
  expect(screen.getByText('Standard (S)')).toBeInTheDocument()
  expect(lookupConcept).toHaveBeenCalledWith('12')
})
it('explains an unavailable vocabulary', async () => {
  vi.mocked(lookupConcept).mockResolvedValue({ state: 'unavailable', message: 'Database not installed' })
  render(<ConceptDetails id="12" />)
  expect(await screen.findByRole('status')).toBeInTheDocument()
  expect(await screen.findByText('Database not installed')).toBeInTheDocument()
})
