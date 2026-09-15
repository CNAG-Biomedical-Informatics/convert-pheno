import { useState } from 'react'
import Papa from 'papaparse'
import { Table2, Braces, Search, ListTree, Database } from 'lucide-react'
import type { Preview } from '../types'

export type Inspection = { name: string; value: unknown; conceptId?: string; source?: string; row?: number }
export function conceptIdFor(field: string, value: unknown, fields: string[]): string | undefined {
  if (!fields.includes(field.toLowerCase()) || (typeof value !== 'string' && typeof value !== 'number')) return
  const text = String(value).trim()
  if (/^\d{1,10}$/.test(text) && Number(text) <= 2147483647) return String(Number(text))
}
export default function DataView({ preview, onInspect, conceptFields = [], source }: { preview: Preview; onInspect: (value: Inspection) => void; conceptFields?: string[]; source?: string }) {
  const [view, setView] = useState<'table' | 'text'>('table')
  const [query, setQuery] = useState('')
  let data = preview.data
  if (!data && !preview.truncated) {
    try { data = JSON.parse(preview.text) } catch { /* Non-JSON input uses the text view. */ }
  }
  let rows: Record<string, unknown>[] = []
  if (Array.isArray(data)) rows = data.filter((item) => item && typeof item === 'object').slice(0, 100)
  else if (data && typeof data === 'object') rows = [data as Record<string, unknown>]
  else if (preview.kind === 'csv' || preview.kind === 'tsv') {
    const parsed = Papa.parse<Record<string, unknown>>(preview.text, { header: true, delimiter: preview.kind === 'tsv' ? '\t' : '', preview: 100, skipEmptyLines: true })
    rows = parsed.data
    // Only discard an incomplete tail if parsing actually reached the byte limit.
    if (preview.truncated && !parsed.meta.truncated && !preview.text.endsWith('\n')) rows.pop()
  }
  const fields = [...new Set(rows.flatMap((row) => Object.keys(row)))]
  const shown = rows.map((row, index) => ({row, index})).filter(({row}) => JSON.stringify(row).toLowerCase().includes(query.toLowerCase()))
  return <div className="data-view">
    <div className="viewer-toolbar">
      <button aria-pressed={view === 'table' && rows.length > 0} disabled={!rows.length} onClick={() => setView('table')}><Table2 aria-hidden="true" />Table</button>
      <button aria-pressed={view === 'text' || !rows.length} onClick={() => setView('text')}><Braces aria-hidden="true" />Text / JSON</button>
      {view === 'table' && rows.length > 0 && <label className="preview-search"><Search aria-hidden="true" /><input aria-label="Filter preview rows" placeholder="Find in loaded rows" value={query} onChange={(event) => setQuery(event.target.value)} /></label>}
    </div>
    <div className="data-scroll">
      {view === 'table' && rows.length ? <table><thead><tr><th>#</th>{fields.map((field) => <th key={field}>{field}</th>)}</tr></thead>
        <tbody>{shown.map(({row, index}) => <tr key={index}><td>{index + 1}</td>{fields.map((field) => {
          const conceptId = conceptIdFor(field, row[field], conceptFields)
          return <td key={field}>
          <button className={`cell-value${conceptId !== undefined ? ' concept-cell' : ''}`} title={conceptId !== undefined ? `Look up OMOP concept ${conceptId}` : undefined} onClick={() => onInspect({ name: field, value: row[field], conceptId, source, row: index + 1 })}>
            {conceptId !== undefined && <Database aria-hidden="true" />}
            {row[field] && typeof row[field] === 'object' ? <><ListTree aria-hidden="true" />{`View details${Array.isArray(row[field]) ? ` (${row[field].length})` : ''}`}</> : String(row[field] ?? '').slice(0, 160)}
          </button></td>})}</tr>)}</tbody></table>
        : <pre>{preview.text}</pre>}
    </div>
    {view === 'table' && rows.length > 0 && shown.length === 0 && <p className="empty-state">No loaded records match this search.</p>}
    <p className="preview-caption">{preview.previewNote || (preview.truncated ? 'Partial preview: first 256 KiB. Open the original file for the complete data.' : rows.length ? `Preview contains ${rows.length} records (up to 100).` : 'Text preview.')}{rows.length > 0 && view === 'table' && ` ${shown.length} match the current filter.`}</p>
  </div>
}
