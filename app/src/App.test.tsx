import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import App from './App'
import * as api from './api'
import { selectPaths, confirmAction, revealRun, installOhdsi } from './desktop'
import type { Conversion, Job } from './types'

const native = vi.hoisted(() => ({ theme: vi.fn(), listener: undefined as undefined | ((event: { payload: string }) => void) }))
vi.mock('@tauri-apps/api/core', () => ({ isTauri: () => true }))
vi.mock('@tauri-apps/api/window', () => ({ getCurrentWindow: () => ({ setTheme: native.theme }) }))
vi.mock('@tauri-apps/api/event', () => ({ listen: vi.fn(async (_name, callback) => { native.listener = callback; return () => {} }) }))
vi.mock('./api', () => ({ getConversions: vi.fn(), listJobs: vi.fn(), submitJob: vi.fn(), getExample: vi.fn(), inputPreview: vi.fn(), outputPreview: vi.fn(), cancelJob: vi.fn(), deleteJob: vi.fn(), deleteJobFiles: vi.fn(), deleteAllJobs: vi.fn(), cancelPendingJobs: vi.fn(), getResources: vi.fn(), post: vi.fn(), uploadFiles: vi.fn(), downloadOutput: vi.fn() }))
vi.mock('./desktop', () => ({ selectPaths: vi.fn(), openExternal: vi.fn(), revealRun: vi.fn(), confirmAction: vi.fn(), saveMappingCopy: vi.fn(), installOhdsi: vi.fn(), connection: vi.fn(async () => ({ outputRoot: '/synthetic/app/runs' })) }))

const pxf: Conversion = {
  id: 'pxf2bff', label: 'Phenopacket v2 to Beacon v2', available: true,
  source: { id: 'pxf', label: 'Phenopacket v2', kind: 'json', inputShape: 'Phenopacket' },
  target: { id: 'beacon', label: 'Beacon v2', kind: 'json' }, resources: [],
  input: { transports: ['json', 'multipart'], files: [{ name: 'source', label: 'Phenopacket document', required: true, multiple: false, accept: ['.json'] }] },
  entities: { default: ['individuals'], supported: ['individuals', 'biosamples'] }, options: [],
}
const csv: Conversion = {
  ...pxf, id: 'csv2bff', label: 'CSV to Beacon v2', source: { id: 'csv', label: 'CSV', kind: 'table', inputShape: 'Rows' },
  input: { transports: ['multipart'], files: [
    { name: 'source', label: 'CSV data', required: true, multiple: false, accept: ['.csv'] },
    { name: 'mapping', label: 'Mapping file', required: true, multiple: false, accept: ['.yaml'] },
  ] }, options: [{ name: 'separator', label: 'Column separator', kind: 'string', default: ',' }],
}
const example = { phenopacket: { id: 'synthetic-1' } }
const completed: Job = { id: 'run1', conversion: 'pxf2bff', created: 1, status: 'completed', sources: [], options: {}, output: {},
  result: { artifacts: [{ id: 'individuals', filename: 'individuals.json', kind: 'json', mediaType: 'application/json', bytes: 2 }], warnings: ['Synthetic warning'], meta: {} },
}
async function start() { render(<App />); await screen.findByText(pxf.label) }
async function loadExample() { fireEvent.click(screen.getByRole('button', { name: 'Load synthetic example' })); await screen.findByRole('heading', { name: 'Input preview' }) }
function menu(id: string) { act(() => native.listener?.({ payload: id })) }

describe('native desktop workspace', () => {
  beforeEach(() => {
    vi.clearAllMocks(); localStorage.clear()
    vi.stubGlobal('matchMedia', vi.fn(() => ({ matches: false, addEventListener: vi.fn(), removeEventListener: vi.fn() })))
    native.theme.mockResolvedValue(undefined)
    vi.mocked(api.getConversions).mockResolvedValue([pxf, csv])
    vi.mocked(api.listJobs).mockResolvedValue([])
    vi.mocked(api.getResources).mockResolvedValue([])
    vi.mocked(api.getExample).mockResolvedValue(example)
    vi.mocked(api.submitJob).mockResolvedValue(completed)
    vi.mocked(api.outputPreview).mockResolvedValue({ text: '[]', data: [], truncated: false })
    vi.mocked(selectPaths).mockResolvedValue([])
    vi.mocked(confirmAction).mockResolvedValue(true)
  })
  it('links to documentation and the source repository', async () => {
    await start()
    expect(screen.getByRole('link', { name: 'Documentation' })).toHaveAttribute('href', 'https://cnag-biomedical-informatics.github.io/convert-pheno/')
    expect(screen.getByRole('link', { name: 'GitHub' })).toHaveAttribute('href', 'https://github.com/CNAG-Biomedical-Informatics/convert-pheno')
  })
  it('loads examples only when requested', async () => {
    await start(); expect(api.getExample).not.toHaveBeenCalled()
    await loadExample()
    expect(screen.queryByLabelText('JSON input')).not.toBeInTheDocument()
    expect(screen.getByText(/You do not need to paste anything/)).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Edit JSON' }))
    expect(screen.getByLabelText('JSON input')).toHaveValue(JSON.stringify(example, null, 2))
  })
  it('clears stale success banners when loading another example and identifies the loaded format', async () => {
    await start(); await loadExample()
    expect(screen.getByRole('status')).toHaveTextContent('Phenopacket v2 synthetic example loaded.')
    fireEvent.click(screen.getByRole('button', {name: 'Back to conversion'}))
    let resolveExample!: (value: unknown) => void
    vi.mocked(api.getExample).mockReturnValueOnce(new Promise((resolve) => { resolveExample = resolve }))
    fireEvent.click(screen.getByRole('button', {name: 'Load synthetic example'}))
    expect(screen.queryByText(/synthetic example loaded/)).not.toBeInTheDocument()
    await act(async () => resolveExample(example))
    expect(screen.getByRole('status')).toHaveTextContent('Phenopacket v2 synthetic example loaded.')
    fireEvent.click(screen.getByRole('button', {name: 'Back to conversion'}))
    fireEvent.change(screen.getByLabelText('Source format'), {target: {value: 'csv'}})
    expect(screen.queryByText(/synthetic example loaded/)).not.toBeInTheDocument()
  })
  it('submits a job using the catalog output defaults', async () => {
    await start(); await loadExample()
    fireEvent.click(screen.getByRole('button', { name: 'Run conversion' }))
    await screen.findByText('individuals.json')
    expect(api.submitJob).toHaveBeenCalledWith({ conversion: 'pxf2bff', input: { data: example }, options: {}, output: { entities: ['individuals'] } })
  })
  it('does not show a blank JSON editor unless explicitly requested', async () => {
    await start()
    fireEvent.click(screen.getByRole('button', { name: 'Input' }))
    expect(screen.queryByLabelText('JSON input')).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Paste JSON instead' }))
    expect(screen.getByLabelText('JSON input')).toHaveAccessibleDescription(expect.stringContaining('not an API request'))
  })
  it('keeps auditing optional and disabled until selected', async () => {
    vi.mocked(api.submitJob).mockResolvedValueOnce(completed).mockResolvedValueOnce({...completed,id:'run2'})
    vi.mocked(api.getConversions).mockResolvedValue([{ ...pxf, options: [{ name: 'term_audit', label: 'Terminology audit', kind: 'string', default: 'none', values: ['none', 'tsv', 'xlsx'] }] }])
    await start()
    expect(screen.getByLabelText('Create terminology audit (adds processing time)')).not.toBeChecked()
    await loadExample()
    fireEvent.click(screen.getByRole('button', {name:'Back to conversion'}))
    menu('run')
    await waitFor(() => expect(api.submitJob).toHaveBeenCalledWith(expect.objectContaining({ options: { term_audit: 'none' } })))
    fireEvent.click(within(screen.getByRole('navigation', {name:'Workspace views'})).getByRole('button', {name:'Conversion'}))
    fireEvent.click(screen.getByLabelText('Create terminology audit (adds processing time)'))
    menu('run')
    await waitFor(() => expect(api.submitJob).toHaveBeenLastCalledWith(expect.objectContaining({ options: { term_audit: 'xlsx' } })))
  })
  it('uses selected files rather than a previously loaded JSON example', async () => {
    await start(); await loadExample()
    fireEvent.click(screen.getByRole('button', { name: 'Back to conversion' }))
    vi.mocked(selectPaths).mockResolvedValue([{id: 'replacement', filename: 'selected.json', directory: false, bytes: 2}])
    fireEvent.click(screen.getByRole('button', { name: 'Browse...' }))
    await screen.findByText('selected.json', {selector: '.file-selection small'})
    menu('run')
    await waitFor(() => expect(api.submitJob).toHaveBeenCalledWith(expect.objectContaining({input: {files: {source: ['replacement']}}})))
  })
  it('does not invent a maturity badge', async () => {
    await start(); expect(document.querySelector('.maturity')).not.toBeInTheDocument()
  })
  it.each(['term-audit', 'term-audit-tsv'])('opens terminology review when selecting %s instead of a spreadsheet placeholder', async (id) => {
    const artifacts = [
      {id:'term-audit',filename:'term-audit.xlsx',kind:'xlsx' as const,mediaType:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',bytes:100},
      {id:'term-audit-tsv',filename:'term-audit-tsv.tsv',kind:'tsv' as const,mediaType:'text/tab-separated-values',bytes:100},
    ]
    vi.mocked(api.submitJob).mockResolvedValue({
      ...completed,
      result: { artifacts, warnings: [], meta: { terminologyAudit: {
        totalDecisions: 0, previewRows: 0, previewLimitPerAction: 100, truncated: false,
        reportArtifactId: 'term-audit', settings: {}, rows: [],
        counts: { keep: 0, review_similarity: 0, resolve_or_accept_fallback: 0, review_source_fallback: 0 },
      } } },
    })
    await start(); await loadExample(); menu('run')
    await screen.findByText('term-audit.xlsx')
    fireEvent.click(screen.getByRole('button',{name: new RegExp(id === 'term-audit' ? 'term-audit.xlsx' : 'term-audit-tsv.tsv')}))
    expect(await screen.findByRole('heading',{name:'Review mapped terms before using the output'})).toBeInTheDocument()
    expect(api.outputPreview).not.toHaveBeenCalled()
    expect(screen.getByRole('button',{name:'Save Excel report...'})).toBeInTheDocument()
  })
  it('shows maturity supplied by the registry', async () => {
    vi.mocked(api.getConversions).mockResolvedValue([{ ...pxf, maturity: 'experimental' }])
    await start(); expect(screen.getByText('Source profile: experimental')).toBeInTheDocument()
  })
  it('rejects malformed JSON without starting a job', async () => {
    await start(); await loadExample()
    fireEvent.click(screen.getByRole('button', { name: 'Edit JSON' }))
    fireEvent.change(screen.getByLabelText('JSON input'), { target: { value: '{bad' } })
    fireEvent.click(screen.getByRole('button', { name: 'Run conversion' }))
    await screen.findByRole('alert'); expect(api.submitJob).not.toHaveBeenCalled()
  })
  it('requires the input files declared by the registry', async () => {
    await start(); fireEvent.click(screen.getByRole('button', { name: 'Run conversion' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Select Phenopacket document')
    expect(api.submitJob).not.toHaveBeenCalled()
  })
  it('loads data and mapping together from Mapping without redirecting to another load prompt', async () => {
    vi.mocked(api.getExample).mockResolvedValue({transport:'multipart',files:[
      {role:'source',filename:'example.csv',content:btoa('id\n1\n')},
      {role:'mapping',filename:'mapping.yaml',content:btoa('mappingVersion: 2\n')},
    ]})
    vi.mocked(api.uploadFiles).mockResolvedValueOnce([{id:'data',filename:'example.csv',directory:false,bytes:5}])
      .mockResolvedValueOnce([{id:'map',filename:'mapping.yaml',directory:false,bytes:18}])
    await start()
    fireEvent.change(screen.getByLabelText('Source format'),{target:{value:'csv'}})
    fireEvent.click(screen.getByRole('button',{name:'Mapping'}))
    fireEvent.click(screen.getByRole('button',{name:'Load synthetic data and mapping'}))
    await waitFor(()=>expect(screen.getByRole('status')).toHaveTextContent('Input data and mapping are both ready; no second load is needed.'))
    expect(screen.getByRole('button',{name:'Mapping'})).toHaveAttribute('aria-current','page')
    expect(api.uploadFiles).toHaveBeenCalledTimes(2)
    fireEvent.click(screen.getByRole('button',{name:'Input'}))
    expect(screen.getByText(/Your input files are already loaded/)).toBeInTheDocument()
  })
  it('sends opaque native file handles, not filesystem paths', async () => {
    await start(); fireEvent.change(screen.getByLabelText('Source format'), { target: { value: 'csv' } })
    vi.mocked(selectPaths).mockResolvedValueOnce([{ id: 'source-handle', filename: 'synthetic.csv', directory: false, bytes: 20 }])
    fireEvent.click(screen.getAllByRole('button', { name: 'Browse...' })[0])
    await screen.findByText('synthetic.csv', { selector: 'small' })
    vi.mocked(selectPaths).mockResolvedValueOnce([{ id: 'mapping-handle', filename: 'mapping.yaml', directory: false, bytes: 20 }])
    vi.mocked(api.inputPreview).mockResolvedValue({ text: 'mapping_version: 2', truncated: false })
    fireEvent.click(screen.getAllByRole('button', { name: 'Browse...' })[1])
    await screen.findByLabelText('Mapping editor')
    menu('run')
    await waitFor(() => expect(api.submitJob).toHaveBeenCalledWith(expect.objectContaining({ conversion: 'csv2bff', input: { files: { source: ['source-handle'], mapping: ['mapping-handle'] } }, options: { separator: ',' } })))
  })
  it('keeps completed runs when starting another conversion', async () => {
    vi.mocked(api.listJobs).mockResolvedValue([completed])
    await start(); menu('new')
    expect(screen.getByText('pxf2bff', { selector: '.tree-run strong' })).toBeInTheDocument()
  })
  it('sends a literal tab separator for OMOP table files', async () => {
    const omop: Conversion = { ...csv, id: 'omop2bff', label: 'OMOP to Beacon', source: { ...csv.source, id: 'omop', label: 'OMOP' },
      input: { transports: ['multipart'], files: [{ ...csv.input.files[0], label: 'OMOP tables', multiple: true }] },
      options: [{ name: 'separator', label: 'Column separator', kind: 'string' }] }
    vi.mocked(api.getConversions).mockResolvedValue([pxf, omop])
    await start()
    fireEvent.change(screen.getByLabelText('Source format'), { target: { value: 'omop' } })
    expect(screen.getByLabelText('Column separator')).toHaveValue('')
    fireEvent.change(screen.getByLabelText('Column separator'), { target: { value: '\t' } })
    vi.mocked(selectPaths).mockResolvedValue([{ id: 'tables', filename: 'omop-tables', directory: true, bytes: 0 }])
    fireEvent.click(screen.getByRole('button', { name: 'Folder...' }))
    await screen.findByText('omop-tables', { selector: '.file-selection small' })
    menu('run')
    await waitFor(() => expect(api.submitJob).toHaveBeenCalledWith(expect.objectContaining({ conversion: 'omop2bff', options: { separator: '\t' } })))
  })
  it('fetches output previews on demand and shows warnings separately', async () => {
    await start(); await loadExample(); menu('run')
    fireEvent.click(await screen.findByText('individuals.json'))
    await waitFor(() => expect(api.outputPreview).toHaveBeenCalledWith('run1', 'individuals'))
    fireEvent.click(screen.getByRole('button', { name: 'Warnings (1)' }))
    expect(screen.getByText('Synthetic warning')).toBeInTheDocument()
  })
  it('displays an engine error without reporting success', async () => {
    vi.mocked(api.submitJob).mockRejectedValueOnce(new Error('Terminology database unavailable'))
    await start(); await loadExample(); menu('run')
    expect(await screen.findByRole('alert')).toHaveTextContent('Terminology database unavailable')
    expect(screen.queryByText('individuals.json')).not.toBeInTheDocument()
  })
  it('changes both application and native theme through Settings', async () => {
    await start(); menu('settings')
    fireEvent.change(screen.getByLabelText('Theme'), { target: { value: 'dark' } })
    expect(document.documentElement.dataset.theme).toBe('dark')
    expect(native.theme).toHaveBeenLastCalledWith('dark')
    fireEvent.change(screen.getByLabelText('Theme'), { target: { value: 'system' } })
    expect(document.documentElement.dataset.theme).toBe('light')
    expect(native.theme).toHaveBeenLastCalledWith(null)
  })
  it('keeps the OHDSI install visibly busy while the native checksum is running', async () => {
    const missing = {id:'ohdsi',installed:false,bundled:false,contentVersion:'2022',byteSize:3178364928}
    const installed = {...missing,installed:true}
    let finish!: (path: string) => void
    vi.mocked(api.getResources).mockResolvedValueOnce([missing]).mockResolvedValueOnce([installed])
    vi.mocked(installOhdsi).mockReturnValue(new Promise((resolve) => { finish = resolve }))
    await start()
    fireEvent.click(screen.getByRole('button',{name:'Resources'}))
    expect(await screen.findByText('3.0 GiB')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button',{name:'Install downloaded database...'}))
    expect(screen.getByRole('button',{name:'Verifying and installing...'})).toBeDisabled()
    expect(screen.getByText(/Keep Convert-Pheno open/)).toBeInTheDocument()
    await act(async () => finish('/synthetic/ohdsi.db'))
    expect(await screen.findByText('The verified OHDSI terminology database is installed.')).toBeInTheDocument()
    expect(screen.getByText('Installed')).toBeInTheDocument()
  })
  it('restores panels through native menu actions', async () => {
    await start(); menu('explorer')
    expect(screen.queryByLabelText('Workspace explorer')).not.toBeInTheDocument()
    menu('explorer'); expect(screen.getByLabelText('Workspace explorer')).toBeInTheDocument()
    menu('inspector'); expect(screen.queryByLabelText('Record inspector')).not.toBeInTheDocument()
  })
  it('shows the default output location before submission', async () => {
    await start()
    expect(screen.getByText('/synthetic/app/runs')).toBeInTheDocument()
    expect(screen.getByText(/Each run gets its own/)).toBeInTheDocument()
  })
  it('cancels the selected queued run rather than the active run', async () => {
    const running = { ...completed, id: 'active', status: 'running' as const }
    const pending = { ...completed, id: 'pending', status: 'queued' as const }
    vi.mocked(api.listJobs).mockResolvedValue([running, pending])
    vi.mocked(api.cancelJob).mockResolvedValue({ ...pending, status: 'cancelled' })
    await start()
    fireEvent.click(screen.getByRole('button', { name: 'Actions for pxf2bff pending' }))
    fireEvent.click(within(screen.getByRole('group', { name: 'Actions for pxf2bff pending' })).getByRole('button', { name: 'Remove from queue' }))
    await waitFor(() => expect(api.cancelJob).toHaveBeenCalledWith('pending'))
    expect(api.cancelJob).toHaveBeenCalledTimes(1)
  })
  it('does not cancel when confirmation is declined', async () => {
    vi.mocked(api.listJobs).mockResolvedValue([{ ...completed, status: 'running' }])
    vi.mocked(confirmAction).mockResolvedValue(false)
    await start(); fireEvent.click(screen.getByRole('button', { name: 'Actions for pxf2bff run1' })); fireEvent.click(screen.getByRole('button', { name: 'Cancel run' }))
    await waitFor(() => expect(confirmAction).toHaveBeenCalled())
    expect(api.cancelJob).not.toHaveBeenCalled()
  })
  it('bulk cancellation uses the pending-only API', async () => {
    vi.mocked(api.listJobs).mockResolvedValue([{ ...completed, status: 'queued' }])
    vi.mocked(api.cancelPendingJobs).mockResolvedValue([])
    await start(); fireEvent.click(screen.getByRole('button', { name: 'Cancel all pending' }))
    await waitFor(() => expect(api.cancelPendingJobs).toHaveBeenCalledOnce())
    expect(api.cancelJob).not.toHaveBeenCalled()
  })
  it('opens the output folder for the chosen completed run', async () => {
    vi.mocked(api.listJobs).mockResolvedValue([completed])
    await start(); fireEvent.click(screen.getByRole('button', { name: 'Actions for pxf2bff run1' })); fireEvent.click(screen.getByRole('button', { name: 'Open output folder' }))
    expect(revealRun).toHaveBeenCalledWith('run1')
  })
  it('collapses and reopens the left navigation from the toolbar', async () => {
    await start()
    fireEvent.click(screen.getByRole('button', { name: 'Collapse left navigation' }))
    expect(screen.queryByRole('complementary', { name: 'Workspace explorer' })).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Expand left navigation' })).toHaveAttribute('aria-expanded', 'false')
    fireEvent.click(screen.getByRole('button', { name: 'Expand left navigation' }))
    expect(screen.getByRole('complementary', { name: 'Workspace explorer' })).toBeInTheDocument()
  })
  it('deletes history only after confirmation', async () => {
    vi.mocked(api.listJobs).mockResolvedValue([completed])
    vi.mocked(api.deleteJob).mockResolvedValue({})
    await start()
    expect(screen.queryByRole('button', { name: 'Delete from history' })).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Actions for pxf2bff run1' }))
    fireEvent.click(screen.getByRole('button', { name: 'Delete from history' }))
    await waitFor(() => expect(api.deleteJob).toHaveBeenCalledWith('run1'))
    expect(confirmAction).toHaveBeenCalledWith('Delete run from history?', expect.stringContaining('kept on disk'))
    await waitFor(() => expect(screen.queryByRole('button', { name: 'Actions for pxf2bff run1' })).not.toBeInTheDocument())
  })
  it('offers separate confirmed disk deletion with the output path', async () => {
    vi.mocked(api.listJobs).mockResolvedValue([{ ...completed, directory: '/synthetic/run/outputs' }])
    vi.mocked(api.deleteJobFiles).mockResolvedValue({})
    await start()
    fireEvent.click(screen.getByRole('button', { name: 'Actions for pxf2bff run1' }))
    expect(screen.getByRole('button', { name: 'Delete from history' })).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Delete run and output files' }))
    await waitFor(() => expect(api.deleteJobFiles).toHaveBeenCalledWith('run1'))
    expect(api.deleteJob).not.toHaveBeenCalled()
    expect(confirmAction).toHaveBeenCalledWith('Permanently delete run and output files?', expect.stringContaining('/synthetic/run/outputs'))
  })
  it('does not delete files when confirmation is declined', async () => {
    vi.mocked(api.listJobs).mockResolvedValue([completed])
    vi.mocked(confirmAction).mockResolvedValue(false)
    await start()
    fireEvent.click(screen.getByRole('button', { name: 'Actions for pxf2bff run1' }))
    fireEvent.click(screen.getByRole('button', { name: 'Delete run and output files' }))
    await waitFor(() => expect(confirmAction).toHaveBeenCalled())
    expect(api.deleteJobFiles).not.toHaveBeenCalled()
  })
  it('offers bulk actions in the toolbar and reports skipped and failed runs', async () => {
    vi.mocked(api.deleteAllJobs).mockResolvedValue({deleted:['done'],skipped:['active'],failed:[{id:'blocked',message:'Output folder contains unrecognized files'}]})
    await start()
    fireEvent.click(screen.getByRole('button', {name:'Run management'}))
    fireEvent.click(screen.getByRole('button', {name:'Delete all run files'}))
    await waitFor(() => expect(api.deleteAllJobs).toHaveBeenCalledWith(true))
    expect(await screen.findByText('1 run deleted with their output files. 1 active run kept.')).toBeInTheDocument()
    expect(screen.getByRole('alert')).toHaveTextContent('unrecognized files')
  })
  it('uses the same confirmation for native bulk history deletion', async () => {
    vi.mocked(confirmAction).mockResolvedValue(false)
    await start(); menu('delete-history')
    await waitFor(() => expect(confirmAction).toHaveBeenCalledWith('Delete all finished runs from history?', expect.any(String)))
    expect(api.deleteAllJobs).not.toHaveBeenCalled()
  })
  it('disables active run deletion and dismisses actions with Escape', async () => {
    vi.mocked(api.listJobs).mockResolvedValue([{ ...completed, status: 'running' }])
    await start()
    const trigger = screen.getByRole('button', { name: 'Actions for pxf2bff run1' })
    fireEvent.click(trigger)
    expect(screen.getByRole('button', { name: 'Delete from history' })).toBeDisabled()
    expect(screen.getByRole('button', { name: 'Delete run and output files' })).toBeDisabled()
    fireEvent.keyDown(document, { key: 'Escape' })
    expect(trigger).toHaveFocus()
    expect(trigger).toHaveAttribute('aria-expanded', 'false')
  })
  it('folds Sources and Runs independently', async () => {
    await start()
    fireEvent.click(screen.getByRole('button', { name: 'Sources' }))
    expect(screen.getByRole('button', { name: 'Sources' })).toHaveAttribute('aria-expanded', 'false')
    expect(screen.getByLabelText('Find runs')).toBeVisible()
    fireEvent.click(screen.getByRole('button', { name: /^Runs/ }))
    expect(screen.getByLabelText('Find runs')).not.toBeVisible()
    fireEvent.click(screen.getByRole('button', { name: 'Sources' }))
    expect(screen.getByText('Select files or load an example.')).toBeVisible()
    expect(screen.getByLabelText('Find runs')).not.toBeVisible()
  })
  it('restores a failed configuration without automatically resubmitting input', async () => {
    vi.mocked(api.listJobs).mockResolvedValue([{ ...completed, conversion: 'csv2bff', options: { separator: '\t' }, status: 'failed' }])
    await start(); fireEvent.click(screen.getByRole('button', { name: 'Actions for csv2bff run1' })); fireEvent.click(screen.getByRole('button', { name: 'Set up again' }))
    await screen.findByText(/Configuration restored/)
    expect(screen.getByLabelText('Source format')).toHaveValue('csv')
    expect(api.submitJob).not.toHaveBeenCalled()
  })
})
