import { Fragment, useDeferredValue, useEffect, useState } from 'react'
import type { Artifact, ReviewAction, TerminologyAudit, TerminologyAuditRow } from '../types'

type ReviewFilter = 'actionable' | 'all' | ReviewAction

const ACTIONS: Array<{
  action: ReviewAction
  label: string
  shortLabel: string
  description: string
}> = [
  { action: 'keep', label: 'Keep', shortLabel: 'Keep', description: 'Exact, direct, or configured' },
  { action: 'review_similarity', label: 'Review similarity', shortLabel: 'Review', description: 'Confirm lexical matches' },
  { action: 'resolve_or_accept_fallback', label: 'Unresolved', shortLabel: 'Unresolved', description: 'Map or accept fallback' },
  { action: 'review_source_fallback', label: 'Source fallback', shortLabel: 'Fallback', description: 'Inspect source-derived terms' },
]

const ACTIONABLE = new Set<ReviewAction>([
  'review_similarity',
  'resolve_or_accept_fallback',
  'review_source_fallback',
])

function actionMetadata(action: ReviewAction) {
  return ACTIONS.find((item) => item.action === action) || ACTIONS[0]
}

function text(value: string | number | null | undefined) {
  return value === null || value === undefined || value === '' ? '—' : String(value)
}

function score(value: string | number | null | undefined) {
  if (value === null || value === undefined || value === '') return '—'
  const numeric = Number(value)
  return Number.isFinite(numeric) ? numeric.toFixed(4) : String(value)
}

function fieldLabel(field: string) {
  return field.replaceAll('_', ' ').replace(/^./, (character) => character.toUpperCase())
}

export default function TerminologyReview({
  audit,
  report,
  onDownload,
}: {
  audit: TerminologyAudit
  report: Artifact
  onDownload: (artifact: Artifact) => void
}) {
  const actionableCount = Array.from(ACTIONABLE)
    .reduce((total, action) => total + (audit.counts[action] || 0), 0)
  const defaultFilter: ReviewFilter = actionableCount > 0 ? 'actionable' : 'all'
  const [filter, setFilter] = useState<ReviewFilter>(defaultFilter)
  const [query, setQuery] = useState('')
  const [ontology, setOntology] = useState('all')
  const [expanded, setExpanded] = useState<TerminologyAuditRow>()
  const deferredQuery = useDeferredValue(query.trim().toLocaleLowerCase())

  useEffect(() => {
    setFilter(defaultFilter)
    setQuery('')
    setOntology('all')
    setExpanded(undefined)
  }, [audit, defaultFilter])

  const ontologies = Array.from(new Set(audit.rows.map((row) => row.ontology).filter(Boolean))).sort()
  const rows = audit.rows.filter((row) => {
    if (filter === 'actionable' && !ACTIONABLE.has(row.review_action)) return false
    if (filter !== 'actionable' && filter !== 'all' && row.review_action !== filter) return false
    if (ontology !== 'all' && row.ontology !== ontology) return false
    if (!deferredQuery) return true
    return [
      row.source_field,
      row.source_value,
      row.source_label,
      row.lookup_query,
      row.converted_term_label,
      row.converted_term_id,
      row.best_candidate_label,
      row.best_candidate_id,
    ].some((value) => String(value ?? '').toLocaleLowerCase().includes(deferredQuery))
  })

  return (
    <section className="terminology-review" aria-labelledby="terminology-review-title">
      <header className="terminology-review-heading">
        <div>
          <p className="eyebrow">Terminology review</p>
          <h3 id="terminology-review-title">Review mapped terms before using the output</h3>
          <p>Recommendations organize review; they are not measures of clinical confidence.</p>
        </div>
        <div className="audit-actions">
          <a href="https://cnag-biomedical-informatics.github.io/convert-pheno/terminology-search" target="_blank" rel="noreferrer">How to review <span aria-hidden="true">↗</span></a>
          <button className="secondary" type="button" onClick={() => onDownload(report)}>Download full {report.kind.toUpperCase()}</button>
        </div>
      </header>

      <div className="audit-summary" aria-label="Terminology decision summary">
        {ACTIONS.map((item) => (
          <button
            type="button"
            className={`audit-summary-card audit-${item.action}`}
            aria-pressed={filter === item.action}
            onClick={() => setFilter(item.action)}
            key={item.action}
          >
            <span>{item.label}</span>
            <strong>{(audit.counts[item.action] || 0).toLocaleString()}</strong>
            <small>{item.description}</small>
          </button>
        ))}
      </div>

      <div className="audit-toolbar">
        <div className="audit-view-switch" role="group" aria-label="Terminology review scope">
          <button type="button" aria-pressed={filter === 'actionable'} onClick={() => setFilter('actionable')}>Needs review <span>{actionableCount.toLocaleString()}</span></button>
          <button type="button" aria-pressed={filter === 'all'} onClick={() => setFilter('all')}>All preview <span>{audit.previewRows.toLocaleString()}</span></button>
        </div>
        <label><span>Search decisions</span><input type="search" value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Source value, query, or term" /></label>
        <label><span>Ontology</span><select value={ontology} onChange={(event) => setOntology(event.target.value)}><option value="all">All</option>{ontologies.map((item) => <option key={item}>{item}</option>)}</select></label>
      </div>

      <div className="audit-table-scroll" role="region" aria-label="Terminology review decisions" tabIndex={0}>
        <table className="audit-table">
          <thead><tr><th>Source</th><th>Lookup</th><th>Emitted term</th><th>Candidate evidence</th><th>Recommended action</th><th /></tr></thead>
          <tbody>
            {rows.map((row, index) => {
              const metadata = actionMetadata(row.review_action)
              const isExpanded = expanded === row
              return (
                <Fragment key={`${row.row ?? 'row'}-${row.source_field ?? 'field'}-${index}`}>
                  <tr className={`audit-row audit-row-${row.review_action}`}>
                    <td><strong>{text(row.source_value)}</strong><small>{text(row.source_field)}{row.row ? ` · row ${row.row}` : ''}</small></td>
                    <td><strong>{text(row.lookup_query)}</strong><small>{text(row.ontology)}</small></td>
                    <td><strong>{text(row.converted_term_label)}</strong><small>{text(row.converted_term_id)}</small></td>
                    <td><strong>{text(row.best_candidate_label)}</strong><small>Score {score(row.best_candidate_score)} · gap {score(row.score_margin)}</small></td>
                    <td><span className={`audit-action audit-action-${row.review_action}`}>{metadata.shortLabel}</span><small>{fieldLabel(row.decision_reason || 'not recorded')}</small></td>
                    <td><button type="button" className="text-button" aria-expanded={isExpanded} onClick={() => setExpanded(isExpanded ? undefined : row)}>{isExpanded ? 'Close' : 'Evidence'}</button></td>
                  </tr>
                  {isExpanded && <tr className="audit-evidence-row"><td colSpan={6}><dl>{Object.entries(row).filter(([, value]) => value !== null && value !== undefined && value !== '').map(([field, value]) => <div key={field}><dt>{fieldLabel(field)}</dt><dd>{String(value)}</dd></div>)}</dl></td></tr>}
                </Fragment>
              )
            })}
          </tbody>
        </table>
        {rows.length === 0 && <p className="audit-empty">No decisions match the current review filters.</p>}
      </div>
      <p className="audit-preview-note">
        Showing {rows.length.toLocaleString()} of {audit.previewRows.toLocaleString()} retained preview decisions from {audit.totalDecisions.toLocaleString()} total.
        {audit.truncated && ` The full report retains every decision; the browser keeps at most ${audit.previewLimitPerAction} rows per review action.`}
      </p>
    </section>
  )
}
