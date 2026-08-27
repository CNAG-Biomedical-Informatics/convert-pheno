import { useEffect, useMemo, useRef, useState, type DragEvent } from 'react'
import Papa from 'papaparse'
import { getConversions, getExample, runConversion } from './api'
import { downloadArtifact, downloadZip } from './downloads'
import TerminologyReview from './components/TerminologyReview'
import type { Artifact, Conversion, OptionDefinition, TerminologyAudit } from './types'

const EMPTY_JSON = '{\n  \n}'

type FileExample = {
  transport: 'multipart'
  files: Array<{ role: string; filename: string; encoding: 'base64'; content: string }>
  options?: Record<string, unknown>
}

function isFileExample(data: unknown): data is FileExample {
  return Boolean(data && typeof data === 'object' && (data as FileExample).transport === 'multipart' && Array.isArray((data as FileExample).files))
}

function fileFromExample(example: FileExample['files'][number]) {
  const binary = atob(example.content)
  const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0))
  return new File([bytes], example.filename)
}

function uniqueById(items: Array<{ id: string; label: string }>) {
  return Array.from(new Map(items.map((item) => [item.id, item])).values())
}

function defaultsFor(route: Conversion) {
  return Object.fromEntries(
    route.options
      .filter((option) => option.default !== undefined)
      .map((option) => [option.name, option.name === 'term_audit' ? 'xlsx' : option.default]),
  )
}

function OptionControl({
  definition,
  value,
  onChange,
}: {
  definition: OptionDefinition
  value: unknown
  onChange: (value: unknown) => void
}) {
  if (definition.kind === 'boolean') {
    return (
      <label className="check-row">
        <input type="checkbox" checked={Boolean(value)} onChange={(event) => onChange(event.target.checked)} />
        <span>{definition.label}</span>
      </label>
    )
  }
  if (definition.kind === 'select') {
    return (
      <label>
        <span>{definition.label}</span>
        <select value={String(value ?? '')} onChange={(event) => onChange(event.target.value)}>
          {definition.values?.map((item) => <option key={item}>{item}</option>)}
        </select>
      </label>
    )
  }
  return (
    <label>
      <span>{definition.label}</span>
      <input
        type={definition.kind === 'string' ? 'text' : 'number'}
        min={definition.minimum}
        max={definition.maximum}
        step={definition.kind === 'integer' ? 1 : 'any'}
        value={String(value ?? '')}
        onChange={(event) => {
          const next = event.target.value
          onChange(definition.kind === 'string' ? next : next === '' ? undefined : Number(next))
        }}
      />
    </label>
  )
}

type TableData = { headers: string[]; rows: unknown[][] }
type TableColumn = { key: string; label: string; sourceIndex: number }

function tableDataFor(artifact: Artifact): TableData | undefined {
  if (artifact.kind === 'csv' || artifact.kind === 'tsv') {
    const parsed = Papa.parse<string[]>(artifact.content, { delimiter: artifact.kind === 'tsv' ? '\t' : ';', skipEmptyLines: true })
    const rows = parsed.data
    return rows[0]?.length ? { headers: rows[0], rows: rows.slice(1, 51) } : undefined
  }

  try {
    const decoded = JSON.parse(artifact.content)
    const records = Array.isArray(decoded) ? decoded : []
    if (!records.length || records.some((record) => !record || typeof record !== 'object' || Array.isArray(record))) return undefined
    const headers = Array.from(new Set(records.flatMap((record) => Object.keys(record as Record<string, unknown>))))
    return {
      headers,
      rows: records.slice(0, 50).map((record) => headers.map((header) => (record as Record<string, unknown>)[header])),
    }
  } catch {
    return undefined
  }
}

function TablePreview({ data, filename }: { data: TableData; filename: string }) {
  const columns = useMemo<TableColumn[]>(
    () => data.headers.map((label, sourceIndex) => ({ key: `${sourceIndex}:${label}`, label, sourceIndex })),
    [data.headers.join('\u0000')],
  )
  const [columnOrder, setColumnOrder] = useState<string[]>(columns.map((column) => column.key))
  const [hiddenColumns, setHiddenColumns] = useState<string[]>([])
  const [selectedCell, setSelectedCell] = useState<{ column: string; value: unknown }>()

  useEffect(() => {
    setColumnOrder(columns.map((column) => column.key))
    setHiddenColumns([])
    setSelectedCell(undefined)
  }, [columns])

  const columnByKey = new Map(columns.map((column) => [column.key, column]))
  const visibleKeys = columnOrder.filter((key) => !hiddenColumns.includes(key))
  const hiddenKeys = columnOrder.filter((key) => hiddenColumns.includes(key))
  const draggedColumn = (event: DragEvent) => event.dataTransfer.getData('text/convert-pheno-column')
  const beginDrag = (event: DragEvent, key: string) => {
    event.dataTransfer.effectAllowed = 'move'
    event.dataTransfer.setData('text/convert-pheno-column', key)
  }
  const showAtEnd = (key: string) => {
    if (!columnByKey.has(key)) return
    setHiddenColumns((current) => current.filter((item) => item !== key))
    setColumnOrder((current) => [...current.filter((item) => item !== key), key])
  }
  const showBefore = (key: string, target: string) => {
    if (!columnByKey.has(key) || key === target) return
    setHiddenColumns((current) => current.filter((item) => item !== key))
    setColumnOrder((current) => {
      const next = current.filter((item) => item !== key)
      next.splice(Math.max(0, next.indexOf(target)), 0, key)
      return next
    })
  }
  const hide = (key: string) => {
    if (columnByKey.has(key)) setHiddenColumns((current) => current.includes(key) ? current : [...current, key])
  }

  const columnChip = (key: string, hidden: boolean) => {
    const column = columnByKey.get(key)
    if (!column) return null
    return (
      <span
        className="column-chip"
        draggable
        key={key}
        onDragStart={(event) => beginDrag(event, key)}
        onDragOver={(event) => event.preventDefault()}
        onDrop={(event) => { event.preventDefault(); event.stopPropagation(); showBefore(draggedColumn(event), key) }}
      >
        <i aria-hidden="true">⠿</i><span>{column.label}</span>
        <button type="button" aria-label={`${hidden ? 'Show' : 'Hide'} ${column.label} column`} onClick={() => hidden ? showAtEnd(key) : hide(key)}>{hidden ? '+' : '×'}</button>
      </span>
    )
  }

  return (
    <>
      <details className="column-settings">
        <summary>Customize columns <span>{visibleKeys.length} of {columns.length} visible</span></summary>
        <div className="column-lanes">
          <div className="column-lane visible-lane" onDragOver={(event) => event.preventDefault()} onDrop={(event) => { event.preventDefault(); showAtEnd(draggedColumn(event)) }}>
            <div><strong>Visible</strong><small>Drag to reorder</small></div>
            <div className="column-chips">{visibleKeys.map((key) => columnChip(key, false))}</div>
          </div>
          <div className="column-lane hidden-lane" onDragOver={(event) => event.preventDefault()} onDrop={(event) => { event.preventDefault(); hide(draggedColumn(event)) }}>
            <div><strong>Hidden</strong><small>Drop columns here</small></div>
            <div className="column-chips">{hiddenKeys.length ? hiddenKeys.map((key) => columnChip(key, true)) : <span className="empty-columns">No hidden columns</span>}</div>
          </div>
        </div>
      </details>
      <div className="table-scroll" role="region" aria-label={`${filename} table preview`} tabIndex={0}>
        <table>
          <thead><tr>{visibleKeys.map((key) => <th key={key}>{columnByKey.get(key)?.label}</th>)}</tr></thead>
          <tbody>
            {data.rows.map((row, rowIndex) => (
              <tr key={rowIndex}>{visibleKeys.map((key) => {
                const column = columnByKey.get(key)!
                const value = row[column.sourceIndex]
                const nested = value !== null && typeof value === 'object'
                return <td key={key}>{nested
                  ? <button type="button" className="nested-cell" onClick={() => setSelectedCell({ column: column.label, value })}>View details</button>
                  : String(value ?? '')}</td>
              })}</tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="preview-limit">Showing the first {data.rows.length.toLocaleString()} row{data.rows.length === 1 ? '' : 's'}.</p>
      {selectedCell && <div className="cell-detail"><header><div><span>Details</span><strong>{selectedCell.column}</strong></div><button type="button" aria-label="Close details" onClick={() => setSelectedCell(undefined)}>×</button></header><pre>{JSON.stringify(selectedCell.value, null, 2)}</pre></div>}
    </>
  )
}

function ArtifactPreview({ artifact }: { artifact: Artifact }) {
  if (artifact.kind === 'xlsx') {
    return <p className="preview-limit">Binary spreadsheet preview is not available. Download the file to inspect the color-coded audit.</p>
  }
  const tableData = useMemo(() => tableDataFor(artifact), [artifact.content, artifact.kind])
  const [view, setView] = useState<'table' | 'raw'>(tableData ? 'table' : 'raw')
  let formatted = artifact.content
  if (artifact.kind !== 'csv' && artifact.kind !== 'tsv') {
    try { formatted = JSON.stringify(JSON.parse(artifact.content), null, 2) } catch { /* show serialized content */ }
  }

  return (
    <div className="artifact-preview">
      <div className="preview-tabs" role="tablist" aria-label={`${artifact.filename} preview mode`}>
        {tableData && <button type="button" role="tab" aria-selected={view === 'table'} onClick={() => setView('table')}>Table</button>}
        <button type="button" role="tab" aria-selected={view === 'raw'} onClick={() => setView('raw')}>Raw {artifact.kind === 'csv' ? 'CSV' : artifact.kind === 'tsv' ? 'TSV' : 'JSON'}</button>
      </div>
      {view === 'table' && tableData ? <TablePreview data={tableData} filename={artifact.filename} /> : <pre className="preview-code">{formatted}</pre>}
    </div>
  )
}

export default function App() {
  const [catalog, setCatalog] = useState<Conversion[]>([])
  const [conversionId, setConversionId] = useState('')
  const [inputText, setInputText] = useState(EMPTY_JSON)
  const [entities, setEntities] = useState<string[]>([])
  const [options, setOptions] = useState<Record<string, unknown>>({})
  const [artifacts, setArtifacts] = useState<Artifact[]>([])
  const [terminologyAudit, setTerminologyAudit] = useState<TerminologyAudit>()
  const [warnings, setWarnings] = useState<string[]>([])
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(true)
  const [running, setRunning] = useState(false)
  const [exampleLoading, setExampleLoading] = useState(false)
  const [fileName, setFileName] = useState('')
  const [filesByRole, setFilesByRole] = useState<Record<string, File[]>>({})
  const [dragActive, setDragActive] = useState(false)
  const [inputTransport, setInputTransport] = useState<'json' | 'multipart'>('json')
  const resultsRef = useRef<HTMLElement>(null)

  useEffect(() => {
    getConversions()
      .then(async (routes) => {
        setCatalog(routes)
        setConversionId(routes[0]?.id || '')
        if (routes[0]) {
          try {
            const example = await getExample(routes[0].source.id)
            setInputText(JSON.stringify(example.data, null, 2))
            setFileName(example.filename)
          } catch {
            // A bundled example is a convenience; catalog loading still succeeds without it.
          }
        }
      })
      .catch((reason: Error) => setError(reason.message))
      .finally(() => setLoading(false))
  }, [])

  const route = catalog.find((item) => item.id === conversionId)
  const sources = useMemo(() => uniqueById(catalog.map((item) => item.source)), [catalog])
  const targets = route ? catalog.filter((item) => item.source.id === route.source.id) : []
  const availableRoutes = catalog.filter((item) => item.available).length
  const usesFiles = inputTransport === 'multipart'
  const inputBytes = usesFiles
    ? Object.values(filesByRole).flat().reduce((total, file) => total + file.size, 0)
    : new Blob([inputText]).size
  const auditOption = route?.options.find((definition) => definition.name === 'term_audit')
  const advancedOptions = route?.options.filter((definition) => definition.name !== 'term_audit') || []
  const missingRequiredFiles = route?.input.files
    .filter((definition) => definition.required && !filesByRole[definition.name]?.length) ?? []
  const requiredFilesReady = missingRequiredFiles.length === 0
  let jsonReady = false
  let jsonError = ''
  if (!usesFiles) {
    try {
      JSON.parse(inputText)
      jsonReady = true
    } catch (reason) {
      jsonReady = false
      jsonError = (reason as Error).message
    }
  }
  const inputReady = usesFiles ? requiredFilesReady : jsonReady
  const configurationReady = route?.target.id !== 'beacon' || entities.length > 0
  const conversionReady = Boolean(route?.available && inputReady && configurationReady)
  const readinessMessage = !inputReady
    ? usesFiles
      ? `Add required input: ${missingRequiredFiles.map((definition) => definition.label).join(', ')}.`
      : `Provide valid JSON to continue${jsonError ? `: ${jsonError}` : '.'}`
    : !configurationReady
      ? 'Select at least one Beacon entity to continue.'
      : ''
  const workflowSteps = [
    { number: 1, label: 'Route', state: route ? 'complete' : 'current' },
    { number: 2, label: 'Input', state: !inputReady ? 'current' : 'complete' },
    { number: 3, label: 'Configure', state: inputReady && !configurationReady ? 'current' : inputReady ? 'complete' : 'pending' },
    { number: 4, label: 'Convert', state: artifacts.length ? 'complete' : inputReady && configurationReady ? 'current' : 'pending' },
  ]

  useEffect(() => {
    if (!route) return
    setEntities(route.entities.default)
    setOptions((current) => ({
      ...defaultsFor(route),
      ...Object.fromEntries(route.options.filter((definition) => definition.name in current).map((definition) => [definition.name, current[definition.name]])),
    }))
    setArtifacts([])
    setTerminologyAudit(undefined)
    setWarnings([])
    setError('')
  }, [route?.id])

  useEffect(() => {
    if (route) setInputTransport(route.input.transports[0] || 'json')
  }, [route?.source.id])

  useEffect(() => {
    if (artifacts.length) resultsRef.current?.scrollIntoView?.({ behavior: 'smooth', block: 'start' })
  }, [artifacts.length])

  const clearResults = () => {
    setArtifacts([])
    setTerminologyAudit(undefined)
    setWarnings([])
    setError('')
  }

  const changeSource = (sourceId: string) => {
    const next = catalog.find((item) => item.source.id === sourceId)
    if (next) {
      setFilesByRole({})
      changeInput(EMPTY_JSON)
      setConversionId(next.id)
    }
  }

  const changeInput = (text: string, selectedFileName = '') => {
    setInputText(text)
    setFileName(selectedFileName)
    clearResults()
  }

  const loadFile = async (file?: File) => {
    if (!file) return
    try {
      changeInput(await file.text(), file.name)
    } catch {
      setError('The selected file could not be read.')
    }
  }

  const loadExample = async () => {
    if (!route) return
    setExampleLoading(true)
    clearResults()
    try {
      const example = await getExample(
        route.source.id,
        route.input.transports.length > 1 ? inputTransport : undefined,
      )
      if (isFileExample(example.data)) {
        const fileExample = example.data
        const loaded: Record<string, File[]> = {}
        for (const item of fileExample.files) {
          loaded[item.role] ||= []
          loaded[item.role].push(fileFromExample(item))
        }
        setFilesByRole(loaded)
        setOptions((current) => ({ ...current, ...(fileExample.options || {}) }))
      } else {
        changeInput(JSON.stringify(example.data, null, 2), example.filename)
      }
    } catch (reason) {
      setError((reason as Error).message)
    } finally {
      setExampleLoading(false)
    }
  }

  const formatInput = () => {
    try {
      changeInput(JSON.stringify(JSON.parse(inputText), null, 2), fileName)
    } catch (reason) {
      setError(`Input is not valid JSON: ${(reason as Error).message}`)
    }
  }

  const submit = async () => {
    if (!route) return
    clearResults()
    let data: unknown
    if (usesFiles) {
      const missing = route.input.files.find((definition) => definition.required && !(filesByRole[definition.name]?.length))
      if (missing) {
        setError(`${missing.label} is required.`)
        return
      }
    } else {
      try {
        data = JSON.parse(inputText)
      } catch (reason) {
        setError(`Input is not valid JSON: ${(reason as Error).message}`)
        return
      }
    }
    const output = route.target.id === 'beacon' ? { entities } : {}
    setRunning(true)
    try {
      const response = await runConversion(
        route.id,
        { ...(usesFiles ? {} : { input: { data } }), output, options },
        usesFiles ? filesByRole : undefined,
      )
      setArtifacts(response.artifacts)
      setTerminologyAudit(response.meta.terminologyAudit)
      setWarnings(response.warnings)
    } catch (reason) {
      setError((reason as Error).message)
    } finally {
      setRunning(false)
    }
  }

  return (
    <div className="page-shell">
      <header className="masthead">
        <a className="brand" href="/" aria-label="Convert-Pheno home">
          <img className="brand-mark" src="/convert-pheno-mark.svg" alt="" />
          <strong>Convert-Pheno workbench</strong>
        </a>
        <div className="masthead-status">
          <nav className="masthead-links" aria-label="Project links">
            <a href="https://cnag-biomedical-informatics.github.io/convert-pheno/" target="_blank" rel="noreferrer">Docs <span aria-hidden="true">↗</span></a>
            <a href="https://github.com/CNAG-Biomedical-Informatics/convert-pheno" target="_blank" rel="noreferrer">GitHub <span aria-hidden="true">↗</span></a>
          </nav>
          <span className={`service-status ${!loading && catalog.length === 0 ? 'offline' : ''}`}>
            <i aria-hidden="true" />{loading ? 'Connecting…' : catalog.length ? 'Local service ready' : 'Service unavailable'}
          </span>
        </div>
      </header>

      <main>
        <section className="hero">
          <div className="hero-copy">
            <h1>Clinical and phenotypic data conversion</h1>
            <p>Select a supported route, provide its source data, and review the generated files.</p>
          </div>
          <div className="hero-context" aria-label="Local service summary">
            <p className="hero-context-status"><strong>{loading ? 'Reading conversion registry' : 'Available conversions'}</strong></p>
            {!loading && <p className="registry-summary"><strong>{availableRoutes}</strong> of <strong>{catalog.length}</strong> registered routes across <strong>{sources.length}</strong> source formats are available from this installation.</p>}
            <p className="privacy-note">Source data are processed by the local service. Temporary request files are removed after conversion.</p>
          </div>
        </section>

        {loading && <p className="notice">Loading conversion catalog…</p>}
        {!loading && catalog.length === 0 && <p className="error" role="alert">{error || 'No conversions are available.'}</p>}

        {route && (
          <section className="workbench" aria-label="Conversion workbench">
            <div className="workbench-heading">
              <h2>Build your conversion</h2>
              <ol className="workflow-steps" aria-label="Conversion steps">
                {workflowSteps.map((step) => <li className={step.state} aria-current={step.state === 'current' ? 'step' : undefined} key={step.number}><span>{step.state === 'complete' ? '✓' : step.number}</span>{step.label}</li>)}
              </ol>
            </div>

            <div className="workspace">
              <section className="card setup-card">
                <div className="section-heading"><span>1</span><div><h2>Choose a route</h2><p>Select the model you have and the output you need.</p></div></div>
                <div className="route-grid">
                  <label><span>Source format</span><select aria-label="Source format" value={route.source.id} onChange={(event) => changeSource(event.target.value)}>{sources.map((source) => <option value={source.id} key={source.id}>{source.label}</option>)}</select></label>
                  <div className="route-arrow" aria-hidden="true"><span>→</span></div>
                  <label><span>Target format</span><select aria-label="Target format" value={route.id} onChange={(event) => setConversionId(event.target.value)}>{targets.map((item) => <option value={item.id} key={item.id}>{item.target.label}{item.available ? '' : ' — unavailable'}</option>)}</select></label>
                </div>
                <div className="route-meta">
                  <span className={`maturity ${route.maturity}`}>{route.maturity}</span>
                  <span>{usesFiles ? 'File upload' : route.source.kind === 'tables' ? 'Table-oriented JSON' : 'JSON input'}</span>
                  {route.resources.map((resource) => <span key={resource}>{resource} required</span>)}
                </div>
                {!route.available && <p className="unavailable" role="status"><strong>Unavailable:</strong> {route.unavailableReason}</p>}
                <p className="shape"><strong>Expected input</strong><span>{route.source.inputShape}</span></p>
              </section>

              <section className="card input-card">
                <div className="section-heading"><span>2</span><div><h2>Add your input</h2><p>{usesFiles ? 'Select the source and supporting files required for this route.' : 'Drop one JSON file here or paste its contents below.'}</p></div></div>
                {route.input.transports.length > 1 && <div className="transport-switch" role="group" aria-label="OMOP input mode">
                  <button type="button" aria-pressed={usesFiles} onClick={() => { setInputTransport('multipart'); clearResults() }}>Table files</button>
                  <button type="button" aria-pressed={!usesFiles} onClick={() => { setInputTransport('json'); clearResults() }}>JSON payload</button>
                </div>}
                {usesFiles ? <div className="file-role-list">
                  {route.input.files.map((definition) => {
                    const selected = filesByRole[definition.name] || []
                    return <label className="file-role" key={definition.name}>
                      <span className="file-role-copy"><strong>{definition.label}{definition.required ? ' *' : ''}</strong><small>{definition.description}</small></span>
                      <input
                        aria-label={definition.label}
                        type="file"
                        multiple={definition.multiple}
                        accept={definition.accept?.join(',')}
                        onChange={(event) => {
                          clearResults()
                          setFilesByRole((current) => ({ ...current, [definition.name]: Array.from(event.target.files || []) }))
                        }}
                      />
                      <span className="browse-label">{selected.length ? `${selected.length} selected` : 'Browse'}</span>
                      {selected.length > 0 && <span className="selected-files">{selected.map((file) => file.name).join(', ')}</span>}
                    </label>
                  })}
                  <div className="editor-toolbar"><label>Input files</label><div><span>{inputBytes.toLocaleString()} bytes</span><button type="button" className="text-button example-action" disabled={exampleLoading} onClick={loadExample}>{exampleLoading ? 'Loading…' : 'Load example'}</button><button type="button" className="text-button" onClick={() => { setFilesByRole({}); clearResults() }}>Clear</button></div></div>
                </div> : <>
                <label
                  className={`dropzone ${dragActive ? 'drag-active' : ''}`}
                  onDragEnter={(event) => { event.preventDefault(); setDragActive(true) }}
                  onDragOver={(event) => { event.preventDefault(); setDragActive(true) }}
                  onDragLeave={() => setDragActive(false)}
                  onDrop={(event) => { event.preventDefault(); setDragActive(false); void loadFile(event.dataTransfer.files?.[0]) }}
                >
                  <input aria-label="Choose JSON file" type="file" accept=".json,application/json" onChange={(event) => loadFile(event.target.files?.[0])} />
                  <span className="drop-icon" aria-hidden="true">↑</span>
                  <span className="drop-copy"><strong>{fileName || 'Drop a JSON file'}</strong><small>{fileName ? 'Loaded into the editor below' : 'or select one from this device'}</small></span>
                  <span className="browse-label">Browse</span>
                </label>
                <div className="editor-toolbar">
                  <label htmlFor="json-input">JSON input</label>
                  <div><span>{new Blob([inputText]).size.toLocaleString()} bytes</span><button type="button" className="text-button example-action" disabled={exampleLoading} onClick={loadExample}>{exampleLoading ? 'Loading…' : 'Load example'}</button><button type="button" className="text-button" onClick={formatInput}>Format</button><button type="button" className="text-button" onClick={() => changeInput(EMPTY_JSON)}>Clear</button></div>
                </div>
                <textarea id="json-input" aria-label="JSON input" spellCheck={false} value={inputText} onChange={(event) => changeInput(event.target.value)} />
                </>}
              </section>

              <section className="card options-card">
                <div className="section-heading"><span>3</span><div><h2>Configure output</h2><p>Only settings supported by this route are shown.</p></div></div>
                {route.entities.supported.length > 0 && <fieldset><legend>Beacon entities</legend><div className="entity-grid">{route.entities.supported.map((entity) => <label className="check-row" key={entity}><input type="checkbox" checked={entities.includes(entity)} onChange={(event) => { clearResults(); setEntities(event.target.checked ? [...entities, entity] : entities.filter((item) => item !== entity)) }} /><span>{entity}</span></label>)}</div></fieldset>}
                {auditOption && <div className="audit-option">
                  <label className="audit-option-toggle"><input type="checkbox" checked={options.term_audit !== 'none'} onChange={(event) => { clearResults(); setOptions((current) => ({ ...current, term_audit: event.target.checked ? 'xlsx' : 'none' })) }} /><span><strong>Terminology review</strong><small>Generate a review panel and a complete report of terminology decisions.</small></span></label>
                  {options.term_audit !== 'none' && <label className="audit-format"><span>Full report</span><select aria-label="Terminology review report" value={String(options.term_audit || 'xlsx')} onChange={(event) => { clearResults(); setOptions((current) => ({ ...current, term_audit: event.target.value })) }}><option value="xlsx">Color-coded XLSX</option><option value="tsv">TSV</option></select></label>}
                </div>}
                {advancedOptions.length > 0 && <details><summary>Advanced settings</summary><div className="advanced-grid">{advancedOptions.map((definition) => <OptionControl key={definition.name} definition={definition} value={options[definition.name]} onChange={(value) => { clearResults(); setOptions((current) => ({ ...current, [definition.name]: value })) }} />)}</div></details>}
                {route.entities.supported.length === 0 && route.options.length === 0 && <p className="defaults-ready"><span aria-hidden="true">✓</span><span><strong>Recommended defaults are ready</strong>No additional output settings are needed for this route.</span></p>}
              </section>

              <section className="card run-card">
                <div className="section-heading"><span>4</span><div><h2>Review and convert</h2><p>Check the request before starting the conversion.</p></div></div>
                <dl className="summary"><div><dt>Route</dt><dd>{route.label}</dd></div><div><dt>Input size</dt><dd>{inputBytes.toLocaleString()} bytes</dd></div><div><dt>Output</dt><dd>{entities.length ? entities.join(', ') : route.target.label}</dd></div></dl>
                <p className="validation-reminder"><span aria-hidden="true">i</span>Formal schema validation is a separate step.</p>
                {readinessMessage && <p className="run-readiness" role="status">{readinessMessage}</p>}
                <button className="primary" disabled={!conversionReady || running} onClick={submit}><span>{running ? 'Converting…' : 'Run conversion'}</span><span aria-hidden="true">{running ? '···' : '→'}</span></button>
                {running && <p className="run-status" role="status"><i aria-hidden="true" />Running the conversion with the local service.</p>}
                {error && <p className="error" role="alert">{error}</p>}
              </section>
            </div>
          </section>
        )}

        {artifacts.length > 0 && route && (
          <section className="results" aria-live="polite" ref={resultsRef}>
            <div className="results-heading"><div className="result-title"><span className="success-mark" aria-hidden="true">✓</span><div><p className="eyebrow">Conversion complete</p><h2>{artifacts.length} output file{artifacts.length === 1 ? '' : 's'} ready</h2></div></div>{artifacts.length > 1 && <button className="secondary zip-button" onClick={() => downloadZip(artifacts, route.id)}>Download ZIP</button>}</div>
            {warnings.length > 0 && <div className="warnings"><strong>Conversion warnings</strong><ul>{warnings.map((warning, index) => <li key={index}>{warning}</li>)}</ul></div>}
            {terminologyAudit && artifacts.find((artifact) => artifact.id === terminologyAudit.reportArtifactId) && <TerminologyReview audit={terminologyAudit} report={artifacts.find((artifact) => artifact.id === terminologyAudit.reportArtifactId)!} onDownload={downloadArtifact} />}
            <div className="artifact-list">{artifacts.filter((artifact) => artifact.id !== terminologyAudit?.reportArtifactId).map((artifact) => <article className="artifact" key={artifact.id}><header><div><span className="output-kind">{artifact.kind.toUpperCase()}</span><h3>{artifact.filename}</h3><p>{artifact.mediaType} · {artifact.encoding === 'base64' ? 'binary' : new Blob([artifact.content]).size.toLocaleString() + ' bytes'}</p></div><button className="secondary" onClick={() => downloadArtifact(artifact)}>Download file</button></header><ArtifactPreview artifact={artifact} key={`${artifact.id}-${artifact.content}`} /></article>)}</div>
          </section>
        )}
      </main>

      <footer><span>Convert-Pheno</span><span>Manuel Rueda · CNAG · Artistic License 2.0</span></footer>
    </div>
  )
}
