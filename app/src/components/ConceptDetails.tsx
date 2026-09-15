import { useEffect, useState } from 'react'
import { Database } from 'lucide-react'
import { lookupConcept } from '../api'
import type { ConceptLookup } from '../types'

const labels: Record<string, string> = {
  concept_id: 'Concept ID', id: 'Vocabulary identifier', vocabulary_id: 'Vocabulary',
  domain_id: 'Domain', concept_class_id: 'Concept class', standard_concept: 'Standard concept',
  valid_start_date: 'Valid from', valid_end_date: 'Valid until', invalid_reason: 'Invalid reason',
}
function display(field: string, value: string | number | null): string {
  if (field === 'standard_concept') return value === 'S' ? 'Standard (S)' : value === 'C' ? 'Classification (C)' : value == null || value === '' ? 'Non-standard' : String(value)
  if (field === 'invalid_reason') return value === 'D' ? 'Deleted (D)' : value === 'U' ? 'Updated (U)' : value == null || value === '' ? 'Not marked invalid' : String(value)
  return value == null || value === '' ? 'Not recorded' : String(value)
}

export default function ConceptDetails({ id }: { id: string }) {
  const [state, setState] = useState<{ id: string; result?: ConceptLookup; error?: string }>()
  useEffect(() => {
    let current = true
    lookupConcept(id).then((result) => { if (current) setState({ id, result }) })
      .catch((error: Error) => { if (current) setState({ id, error: error.message }) })
    return () => { current = false }
  }, [id])
  const selected = state?.id === id ? state : undefined
  return <section className="concept-details" aria-label="OMOP concept details">
    <header><span className="format-label format-omop"><Database aria-hidden="true" />OHDSI</span><span className="read-only-label">Exact ID lookup</span></header>
    {!selected ? <p role="status">Looking up concept {id}...</p> : selected.error ? <p role="alert">Concept lookup failed: {selected.error}</p> : selected.result?.state !== 'found' ? <p role="status">{selected.result?.message}</p> : <>
      <h3>{selected.result.concept?.label || 'Label not recorded'}</h3>
      <dl>{Object.entries(labels).filter(([field]) => Object.hasOwn(selected.result?.concept || {}, field)).map(([field, label]) => <div key={field}><dt>{label}</dt><dd>{display(field, selected.result!.concept![field])}</dd></div>)}</dl>
    </>}
    <p className="concept-note">From the installed vocabulary. Inspection does not alter or validate the converted record.</p>
  </section>
}
