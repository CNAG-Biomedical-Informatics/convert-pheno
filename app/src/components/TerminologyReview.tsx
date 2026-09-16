import { Fragment, useDeferredValue, useState } from 'react'
import type { Artifact, ReviewAction, TerminologyAudit, TerminologyAuditRow } from '../types'

type ReviewFilter = 'actionable' | 'all' | ReviewAction

const ACTIONS: Array<{
  action: ReviewAction
  label: string
  shortLabel: string
  description: string
}> = [
  { action: 'keep', label: 'Keep', shortLabel: 'Keep', description: 'Exact, direct, or configured' },
  { action: 'preserve_source', label: 'Preserved', shortLabel: 'Preserved', description: 'Source text retained; no lookup needed' },
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

function groupDecisions(rows: TerminologyAuditRow[]) {
  const groups = new Map<string, { row: TerminologyAuditRow; index: number; members: TerminologyAuditRow[] }>()
  rows.forEach((row, index) => {
    // Failed lookups are work items, even when participants have different raw values.
    const ignored = ['row', 'source_record', 'match_source']
    if (row.review_action === 'resolve_or_accept_fallback') ignored.push('source_value', 'source_label')
    const key = JSON.stringify(Object.entries(row)
      .filter(([field]) => !ignored.includes(field))
      .sort(([a], [b]) => a.localeCompare(b)))
    const existing = groups.get(key)
    if (existing) existing.members.push(row)
    else groups.set(key, { row, index, members: [row] })
  })
  return [...groups.values()]
}

export default function TerminologyReview({
  audit,
  report,
  onDownload,
  onHelp,
}: {
  audit: TerminologyAudit
  report: Artifact
  onDownload: (artifact: Artifact) => void
  onHelp: () => void
}) {
  const actionableCount = Array.from(ACTIONABLE)
    .reduce((total, action) => total + (audit.counts[action] || 0), 0)
  const defaultFilter: ReviewFilter = actionableCount > 0 ? 'actionable' : 'all'
  const [filter, setFilter] = useState<ReviewFilter>(defaultFilter)
  const [query, setQuery] = useState('')
  const [ontology, setOntology] = useState('all')
  const [expanded, setExpanded] = useState<number>()
  const [unique, setUnique] = useState(true)
  const deferredQuery = useDeferredValue(query.trim().toLocaleLowerCase())

  const ontologies = Array.from(new Set(audit.rows.map((row) => row.ontology).filter(Boolean))).sort()
  // Completed run results are immutable, but polling creates fresh objects.
  // Keep review controls stable; the parent keys this component by run ID.
  const groups = groupDecisions(audit.rows)
  const entries = unique ? groups : audit.rows.map((row, index) => ({row, index, members: [row]}))
  const rows = entries.filter(({row, members}) => {
    if (filter === 'actionable' && !ACTIONABLE.has(row.review_action)) return false
    if (filter !== 'actionable' && filter !== 'all' && row.review_action !== filter) return false
    if (ontology !== 'all' && row.ontology !== ontology) return false
    if (!deferredQuery) return true
    return members.some((row) => [
      row.source_field,
      row.source_value,
      row.source_label,
      row.lookup_query,
      row.converted_term_label,
      row.converted_term_id,
      row.best_candidate_label,
      row.best_candidate_id,
    ].some((value) => String(value ?? '').toLocaleLowerCase().includes(deferredQuery)))
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
          <button type="button" className="text-button" onClick={onHelp}>How to review <span aria-hidden="true">↗</span></button>
          <button className="secondary" type="button" onClick={() => onDownload(report)}>Save Excel report...</button>
        </div>
      </header>

      {audit.truncated && <p className="audit-preview-note">This is a limited preview. Unique-term counts and their occurrence lists cover only retained rows, not the full report.</p>}

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
            <strong>{unique ? groups.filter(({row}) => row.review_action === item.action).length.toLocaleString() : (audit.counts[item.action] || 0).toLocaleString()}</strong>
            <small>{unique ? `unique in preview · ${(audit.counts[item.action] || 0).toLocaleString()} total occurrences` : 'total occurrences'}</small>
            <small>{item.description}</small>
          </button>
        ))}
      </div>

      <div className="audit-toolbar">
        <label><span>Display</span><select value={unique ? 'unique' : 'all'} onChange={(event) => { setUnique(event.target.value === 'unique'); setExpanded(undefined) }}><option value="unique">Unique terms</option><option value="all">All occurrences</option></select></label>
        <div className="audit-view-switch" role="group" aria-label="Terminology review scope">
          <button type="button" aria-pressed={filter === 'actionable'} onClick={() => setFilter('actionable')}>Needs review <span>{actionableCount.toLocaleString()}</span></button>
          <button type="button" aria-pressed={filter === 'all'} onClick={() => setFilter('all')}>All preview <span>{audit.previewRows.toLocaleString()}</span></button>
        </div>
        <label><span>Search decisions</span><input type="search" value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Source value, query, or term" /></label>
        <label><span>Ontology</span><select value={ontology} onChange={(event) => setOntology(event.target.value)}><option value="all">All</option>{ontologies.map((item) => <option key={item}>{item}</option>)}</select></label>
      </div>

      <div className="audit-table-scroll" role="region" aria-label="Terminology review decisions" tabIndex={0}>
        <table className="audit-table">
          <thead><tr><th>Source</th><th>Lookup</th><th>Emitted term</th><th>Candidate evidence</th><th>Recommended action</th>{unique && <th>Occurrences{audit.truncated ? ' in preview' : ''}</th>}<th /></tr></thead>
          <tbody>
            {rows.map(({row, index, members}) => {
              const metadata = actionMetadata(row.review_action)
              const isExpanded = expanded === index
              return (
                <Fragment key={`${row.row ?? 'row'}-${row.source_field ?? 'field'}-${index}`}>
                  <tr className={`audit-row audit-row-${row.review_action}`}>
                    <td><strong>{unique ? [...new Set(members.map((member) => text(member.source_value)))].join(', ') : text(row.source_value)}</strong><small>{text(row.source_field)}{!unique && row.row ? ` · row ${row.row}` : ''}</small></td>
                    <td><strong>{text(row.lookup_query)}</strong><small>{text(row.ontology)}</small></td>
                    <td><strong>{text(row.converted_term_label)}</strong><small>{text(row.converted_term_id)}</small></td>
                    <td><strong>{text(row.best_candidate_label)}</strong><small>Score {score(row.best_candidate_score)} · gap {score(row.score_margin)}</small></td>
                    <td><span title={row.review_action === 'review_source_fallback' ? 'A source-derived term was retained rather than a database-confirmed ontology match. This does not necessarily mean a search failed.' : metadata.description} className={`audit-action audit-action-${row.review_action}`}>{metadata.shortLabel}</span><small>{fieldLabel(row.decision_reason || 'not recorded')}</small></td>
                    {unique && <td>{members.length.toLocaleString()}</td>}
                    <td><button type="button" className="text-button" aria-expanded={isExpanded} onClick={() => setExpanded(isExpanded ? undefined : index)}>{isExpanded ? 'Close' : 'Evidence'}</button></td>
                  </tr>
                  {isExpanded && <tr className="audit-evidence-row"><td colSpan={unique ? 7 : 6}>
                    {unique && <div><strong>Occurrences in preview</strong><ul>{members.map((member, occurrence) => <li key={occurrence}>Row {text(member.row)} · value {text(member.source_value)} · label {text(member.source_label)}{member.source_record ? ` · record ${member.source_record}` : ''}{member.match_source ? ` · ${member.match_source}` : ''}</li>)}</ul></div>}
                    <dl>{Object.entries(row).filter(([field, value]) => (!unique || !['row', 'source_record', 'match_source'].includes(field)) && value !== null && value !== undefined && value !== '').map(([field, value]) => <div key={field}><dt>{fieldLabel(field)}</dt><dd>{String(value)}</dd></div>)}</dl></td></tr>}
                </Fragment>
              )
            })}
          </tbody>
        </table>
        {rows.length === 0 && <p className="audit-empty">No decisions match the current review filters.</p>}
      </div>
      <p className="audit-preview-note">
        Showing {rows.length.toLocaleString()} {unique ? 'unique terms' : 'occurrences'} from {audit.previewRows.toLocaleString()} retained preview decisions. The full audit contains {audit.totalDecisions.toLocaleString()} occurrences.
        {unique && ' Repeated failures are grouped by source field, query, ontology and resolution evidence, even when individuals have different raw values.'}
        {audit.truncated && ` The full report retains every decision; this preview keeps at most ${audit.previewLimitPerAction} rows per review action.`}
      </p>
    </section>
  )
}
