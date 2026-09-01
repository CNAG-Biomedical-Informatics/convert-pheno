import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import App from './App'

const routes = [
  {
    id: 'pxf2bff', label: 'Phenopacket v2 to Beacon v2', maturity: 'experimental', available: true,
    source: { id: 'pxf', label: 'Phenopacket v2', kind: 'json', inputShape: 'A Phenopacket object' },
    target: { id: 'beacon', label: 'Beacon v2', kind: 'json' }, resources: [],
    input: { transports: ['json', 'multipart'], files: [
      { name: 'source', label: 'Phenopacket document', required: true, multiple: false, accept: ['.json'] },
      { name: 'mapping', label: 'Dataset and cohort metadata', required: false, multiple: false, accept: ['.yaml'] },
    ] },
    entities: { default: ['individuals'], supported: ['individuals', 'biosamples'] }, options: [],
  },
  {
    id: 'pxf2csv', label: 'Phenopacket v2 to CSV', maturity: 'experimental', available: true,
    source: { id: 'pxf', label: 'Phenopacket v2', kind: 'json', inputShape: 'A Phenopacket object' },
    target: { id: 'csv', label: 'CSV', kind: 'csv' }, resources: [], entities: { default: [], supported: [] }, options: [],
    input: { transports: ['json'], files: [] },
  },
  {
    id: 'csv2bff', label: 'CSV to Beacon v2', maturity: 'experimental', available: true,
    source: { id: 'csv', label: 'CSV', kind: 'table', inputShape: 'A record table and Mapping V2 file' },
    target: { id: 'beacon', label: 'Beacon v2', kind: 'json' }, resources: [],
    entities: { default: ['individuals'], supported: ['individuals'] },
    options: [
      { name: 'separator', label: 'Column separator', kind: 'string', default: ',' },
      { name: 'term_audit', label: 'Terminology audit', kind: 'select', values: ['none', 'tsv', 'xlsx'], default: 'none' },
    ],
    input: { transports: ['multipart'], files: [
      { name: 'source', label: 'CSV data', required: true, multiple: false, accept: ['.csv'] },
      { name: 'mapping', label: 'Mapping file', required: true, multiple: false, accept: ['.yaml'] },
    ] },
  },
]

const example = { phenopacket: { id: 'example-1' } }

async function waitForInitialExample() {
  await screen.findByText('Phenopacket v2 to Beacon v2')
  await waitFor(() => expect(screen.getByLabelText('JSON input')).toHaveValue(JSON.stringify(example, null, 2)))
}

describe('workbench', () => {
  beforeEach(() => {
    vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL) => {
      if (String(input) === '/examples/pxf') {
        return {
          ok: true,
          json: async () => ({ ok: true, data: example, meta: { filename: 'phenopacket-example.json' } }),
        } as Response
      }
      return { ok: true, json: async () => ({ ok: true, data: routes }) } as Response
    }))
  })

  it('links to the project documentation and source repository', () => {
    render(<App />)
    expect(screen.getByRole('link', { name: /Docs/ })).toHaveAttribute(
      'href',
      'https://cnag-biomedical-informatics.github.io/convert-pheno/',
    )
    expect(screen.getByRole('link', { name: /GitHub/ })).toHaveAttribute(
      'href',
      'https://github.com/CNAG-Biomedical-Informatics/convert-pheno',
    )
  })

  it('builds a route-specific request and renders artifacts', async () => {
    render(<App />)
    await waitForInitialExample()
    fireEvent.change(screen.getByLabelText('JSON input'), { target: { value: '{"phenopacket":{"id":"P1"}}' } })
    vi.mocked(fetch).mockResolvedValueOnce({
      ok: true,
      json: async () => ({ ok: true, artifacts: [{ id: 'individuals', filename: 'individuals.json', mediaType: 'application/json', kind: 'json', content: '[]' }], warnings: [], meta: { conversion: 'pxf2bff' } }),
    } as Response)
    fireEvent.click(screen.getByRole('button', { name: 'Run conversion' }))
    await screen.findByText('individuals.json')
    const request = vi.mocked(fetch).mock.calls.find((call) => call[0] === '/api/conversions/pxf2bff')!
    expect(request[0]).toBe('/api/conversions/pxf2bff')
    expect(JSON.parse(String((request[1] as RequestInit).body))).toEqual({ input: { data: { phenopacket: { id: 'P1' } } }, output: { entities: ['individuals'] }, options: {} })
  })

  it('clears stale results when the route or input changes', async () => {
    render(<App />)
    await waitForInitialExample()
    fireEvent.change(screen.getByLabelText('JSON input'), { target: { value: '{}' } })
    vi.mocked(fetch).mockResolvedValueOnce({ ok: true, json: async () => ({ ok: true, artifacts: [{ id: 'individuals', filename: 'individuals.json', mediaType: 'application/json', kind: 'json', content: '[]' }], warnings: [], meta: { conversion: 'pxf2bff' } }) } as Response)
    fireEvent.click(screen.getByRole('button', { name: 'Run conversion' }))
    await screen.findByText('individuals.json')
    fireEvent.change(screen.getByLabelText('Target format'), { target: { value: 'pxf2csv' } })
    await waitFor(() => expect(screen.queryByText('individuals.json')).not.toBeInTheDocument())
  })

  it('prevents malformed JSON from being submitted', async () => {
    render(<App />)
    await waitForInitialExample()
    fireEvent.change(screen.getByLabelText('JSON input'), { target: { value: '{bad' } })
    expect(screen.getByRole('button', { name: 'Run conversion' })).toBeDisabled()
    expect(screen.getByRole('status')).toHaveTextContent('Provide valid JSON to continue')
    expect(vi.mocked(fetch).mock.calls.some((call) => String(call[0]).startsWith('/api/conversions/pxf2bff'))).toBe(false)
  })

  it('preloads and restores the bundled source example', async () => {
    render(<App />)
    await waitForInitialExample()
    expect(screen.getByText('phenopacket-example.json')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Clear' }))
    fireEvent.click(screen.getByRole('button', { name: 'Load example' }))
    await waitFor(() => expect(screen.getByLabelText('JSON input')).toHaveValue(JSON.stringify(example, null, 2)))
    expect(vi.mocked(fetch).mock.calls.filter((call) => call[0] === '/examples/pxf')).toHaveLength(2)
  })

  it('previews object artifacts as a configurable table and raw JSON', async () => {
    render(<App />)
    await waitForInitialExample()
    vi.mocked(fetch).mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        ok: true,
        artifacts: [{ id: 'individuals', filename: 'individuals.json', mediaType: 'application/json', kind: 'json', content: '[{"id":"P1","info":{"source":"test"}}]' }],
        warnings: [], meta: { conversion: 'pxf2bff' },
      }),
    } as Response)
    fireEvent.click(screen.getByRole('button', { name: 'Run conversion' }))
    expect(await screen.findByRole('region', { name: 'individuals.json table preview' })).toBeInTheDocument()
    expect(screen.getByRole('columnheader', { name: 'id' })).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Hide id column' }))
    expect(screen.queryByRole('columnheader', { name: 'id' })).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Show id column' }))
    expect(screen.getByRole('columnheader', { name: 'id' })).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'View details' }))
    expect(screen.getByText('Details')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('tab', { name: 'Raw JSON' }))
    expect(screen.getByText(/"source": "test"/)).toBeInTheDocument()
  })

  it('previews CSV artifacts as a table and raw serialized output', async () => {
    render(<App />)
    await waitForInitialExample()
    fireEvent.change(screen.getByLabelText('Target format'), { target: { value: 'pxf2csv' } })
    vi.mocked(fetch).mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        ok: true,
        artifacts: [{ id: 'csv', filename: 'phenopacket.csv', mediaType: 'text/csv', kind: 'csv', content: 'id;label\nP1;Example\n' }],
        warnings: [], meta: { conversion: 'pxf2csv' },
      }),
    } as Response)
    fireEvent.click(screen.getByRole('button', { name: 'Run conversion' }))
    expect(await screen.findByRole('columnheader', { name: 'id' })).toBeInTheDocument()
    expect(screen.getByRole('cell', { name: 'Example' })).toBeInTheDocument()
    fireEvent.click(screen.getByRole('tab', { name: 'Raw CSV' }))
    await waitFor(() => expect(screen.getByText(/id;label/)).toBeInTheDocument())
  })

  it('builds multipart requests from registry file roles', async () => {
    render(<App />)
    await waitForInitialExample()
    fireEvent.change(screen.getByLabelText('Source format'), { target: { value: 'csv' } })
    fireEvent.change(screen.getByLabelText('CSV data'), { target: { files: [new File(['id,name\n1,Ada\n'], 'records.csv', { type: 'text/csv' })] } })
    fireEvent.change(screen.getByLabelText('Mapping file'), { target: { files: [new File(['mappingVersion: 2\n'], 'mapping.yaml')] } })
    vi.mocked(fetch).mockResolvedValueOnce({
      ok: true,
      json: async () => ({ ok: true, artifacts: [{ id: 'individuals', filename: 'individuals.json', mediaType: 'application/json', kind: 'json', encoding: 'utf-8', content: '[]' }], warnings: [], meta: { conversion: 'csv2bff' } }),
    } as Response)
    fireEvent.click(screen.getByRole('button', { name: 'Run conversion' }))
    await screen.findByText('individuals.json')
    const call = vi.mocked(fetch).mock.calls.find((item) => item[0] === '/api/conversions/csv2bff')!
    const form = (call[1] as RequestInit).body as FormData
    expect(form.get('source')).toBeInstanceOf(File)
    expect(form.get('mapping')).toBeInstanceOf(File)
    expect(JSON.parse(String(form.get('request')))).toEqual({ output: { entities: ['individuals'] }, options: { separator: ',', term_audit: 'xlsx' } })
  })

  it('keeps compact dataset metadata optional for built-in routes', async () => {
    render(<App />)
    await waitForInitialExample()
    fireEvent.click(screen.getByRole('button', { name: 'File upload' }))
    fireEvent.change(screen.getByLabelText('Phenopacket document'), {
      target: { files: [new File(['{}'], 'phenopacket.json', { type: 'application/json' })] },
    })
    vi.mocked(fetch).mockResolvedValueOnce({
      ok: true,
      json: async () => ({ ok: true, artifacts: [{ id: 'individuals', filename: 'individuals.json', mediaType: 'application/json', kind: 'json', content: '[]' }], warnings: [], meta: { conversion: 'pxf2bff' } }),
    } as Response)
    fireEvent.click(screen.getByRole('button', { name: 'Run conversion' }))
    await screen.findByText('individuals.json')
    const call = vi.mocked(fetch).mock.calls.find((item) => item[0] === '/api/conversions/pxf2bff')!
    const form = (call[1] as RequestInit).body as FormData
    expect(form.get('source')).toBeInstanceOf(File)
    expect(form.get('mapping')).toBeNull()
  })

  it('renders the Perl terminology review contract as an actionable panel', async () => {
    render(<App />)
    await waitForInitialExample()
    fireEvent.change(screen.getByLabelText('Source format'), { target: { value: 'csv' } })
    expect(screen.getByRole('checkbox', { name: /Terminology review/ })).toBeChecked()
    expect(screen.getByLabelText('Terminology review report')).toHaveValue('xlsx')
    fireEvent.change(screen.getByLabelText('CSV data'), { target: { files: [new File(['id,name\n1,Ada\n'], 'records.csv', { type: 'text/csv' })] } })
    fireEvent.change(screen.getByLabelText('Mapping file'), { target: { files: [new File(['mappingVersion: 2\n'], 'mapping.yaml')] } })
    const rows = [
      { row: 2, source_field: 'diagnosis', source_value: 'Unknown source', lookup_query: 'Unknown source', ontology: 'ncit', converted_term_label: 'NA', converted_term_id: 'NCIT:NA0000', review_action: 'resolve_or_accept_fallback', decision_reason: 'no_candidate' },
      { row: 3, source_field: 'diagnosis', source_value: 'Possible source', lookup_query: 'Possible source', ontology: 'ncit', converted_term_label: 'Possible term', converted_term_id: 'NCIT:C1', best_candidate_score: 0.91, score_margin: 0.2, review_action: 'review_similarity', decision_reason: 'similarity_accepted' },
      { row: 4, source_field: 'diagnosis', source_value: 'Local source', ontology: 'local', converted_term_label: 'Local source', converted_term_id: 'local:source', review_action: 'review_source_fallback', decision_reason: 'source_fallback' },
      { row: 5, source_field: 'diagnosis', source_value: 'Exact source', lookup_query: 'Exact source', ontology: 'ncit', converted_term_label: 'Exact term', converted_term_id: 'NCIT:C2', review_action: 'keep', decision_reason: 'exact_match' },
    ]
    vi.mocked(fetch).mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        ok: true,
        artifacts: [
          { id: 'individuals', filename: 'individuals.json', mediaType: 'application/json', kind: 'json', encoding: 'utf-8', content: '[]' },
          { id: 'term-audit', filename: 'term-audit.xlsx', mediaType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', kind: 'xlsx', encoding: 'base64', content: '' },
        ],
        warnings: [],
        meta: {
          conversion: 'csv2bff',
          terminologyAudit: {
            totalDecisions: 4,
            counts: { keep: 1, review_similarity: 1, resolve_or_accept_fallback: 1, review_source_fallback: 1 },
            rows,
            previewRows: 4,
            previewLimitPerAction: 100,
            truncated: false,
            reportArtifactId: 'term-audit',
            settings: { configuredSearchMode: 'exact' },
          },
        },
      }),
    } as Response)
    fireEvent.click(screen.getByRole('button', { name: 'Run conversion' }))
    expect(await screen.findByRole('heading', { name: 'Review mapped terms before using the output' })).toBeInTheDocument()
    expect(screen.getAllByText('Unknown source').length).toBeGreaterThan(0)
    expect(screen.getAllByText('Possible source').length).toBeGreaterThan(0)
    expect(screen.getAllByText('Local source').length).toBeGreaterThan(0)
    expect(screen.queryByText('Exact source')).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /Keep 1/ }))
    expect(screen.getAllByText('Exact source').length).toBeGreaterThan(0)
    expect(screen.queryByText('Possible source')).not.toBeInTheDocument()
  })
})
