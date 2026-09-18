import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import App from './App'
import * as api from './api'
import { selectPaths, confirmAction, revealRun, installOhdsi, downloadOhdsi, cancelOhdsiDownload, chooseResourceDirectory, projectFile, finishQuit } from './desktop'
import type { Conversion, Job } from './types'
import { writeText } from '@tauri-apps/plugin-clipboard-manager'

const native = vi.hoisted(() => ({ theme: vi.fn(), title: vi.fn(), listener: undefined as undefined | ((event: { payload: string }) => void) }))
vi.mock('@tauri-apps/api/core', () => ({ isTauri: () => true }))
vi.mock('@tauri-apps/plugin-clipboard-manager', () => ({ writeText: vi.fn() }))
vi.mock('@tauri-apps/api/window', () => ({ getCurrentWindow: () => ({ setTheme: native.theme, setTitle: native.title }) }))
vi.mock('@tauri-apps/api/event', () => ({ listen: vi.fn(async (_name, callback) => { native.listener = callback; return () => {} }) }))
vi.mock('./api', () => ({ getConversions: vi.fn(), listJobs: vi.fn(), submitJob: vi.fn(), getExample: vi.fn(), inputPreview: vi.fn(), outputPreview: vi.fn(), cancelJob: vi.fn(), deleteJob: vi.fn(), deleteJobFiles: vi.fn(), deleteAllJobs: vi.fn(), cancelPendingJobs: vi.fn(), getResources: vi.fn(), getJobSettings: vi.fn(), updateJobSettings: vi.fn(), post: vi.fn(), uploadFiles: vi.fn(), downloadOutput: vi.fn() }))
vi.mock('./desktop', () => ({ projectFile: vi.fn(), finishQuit: vi.fn(), selectPaths: vi.fn(), openExternal: vi.fn(), revealRun: vi.fn(), confirmAction: vi.fn(), saveMappingCopy: vi.fn(), installOhdsi: vi.fn(), downloadOhdsi: vi.fn(), cancelOhdsiDownload: vi.fn(), chooseResourceDirectory: vi.fn(), resourceDirectory: vi.fn(async () => '/synthetic/resources'), connection: vi.fn(async () => ({ outputRoot: '/synthetic/app/runs' })) }))

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
async function start() { render(<App />); await screen.findByLabelText('Conversion formats') }
async function loadExample() { fireEvent.click(screen.getByRole('button', { name: 'Load synthetic example' })); await screen.findByRole('heading', { name: 'Input preview' }) }
function menu(id: string) { act(() => native.listener?.({ payload: id })) }

describe('native desktop workspace', () => {
  beforeEach(() => {
    vi.clearAllMocks(); localStorage.clear()
    vi.stubGlobal('matchMedia', vi.fn(() => ({ matches: false, addEventListener: vi.fn(), removeEventListener: vi.fn() })))
    native.theme.mockResolvedValue(undefined)
    native.title.mockResolvedValue(undefined)
    vi.mocked(writeText).mockResolvedValue(undefined)
    vi.mocked(api.getConversions).mockResolvedValue([pxf, csv])
    vi.mocked(api.listJobs).mockResolvedValue([])
    vi.mocked(api.getResources).mockResolvedValue([])
    vi.mocked(api.getJobSettings).mockResolvedValue({ maxConcurrentJobs: 1, maxAllowedConcurrentJobs: 16 })
    vi.mocked(api.getExample).mockResolvedValue(example)
    vi.mocked(api.submitJob).mockResolvedValue(completed)
    vi.mocked(api.outputPreview).mockResolvedValue({ text: '[]', data: [], truncated: false })
    vi.mocked(selectPaths).mockResolvedValue([])
    vi.mocked(confirmAction).mockResolvedValue(true)
    vi.mocked(projectFile).mockResolvedValue(null)
    vi.mocked(finishQuit).mockResolvedValue(undefined)
  })
  it('links to documentation and the source repository', async () => {
    await start()
    expect(screen.getByRole('link', { name: 'Documentation' })).toHaveAttribute('href', 'https://cnag-biomedical-informatics.github.io/convert-pheno/')
    expect(screen.getByRole('link', { name: 'GitHub' })).toHaveAttribute('href', 'https://github.com/CNAG-Biomedical-Informatics/convert-pheno')
  })
  it('shows the saved project name and unsaved marker only in the native title', async () => {
    await start(); await loadExample()
    expect(native.title).toHaveBeenLastCalledWith('Convert-Pheno')
    expect(screen.queryByRole('heading', {name:/Untitled project/})).not.toBeInTheDocument()
    vi.mocked(projectFile).mockResolvedValue({file:{id:'project1',filename:'Study A.cpheno'}})
    menu('save')
    await waitFor(()=>expect(native.title).toHaveBeenLastCalledWith('Study A - Convert-Pheno'))
    expect(within(screen.getByRole('banner')).queryByText(/Study A/)).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button',{name:'Edit JSON'}))
    fireEvent.change(screen.getByLabelText('JSON input'),{target:{value:'[{"id":"changed"}]'}})
    await waitFor(()=>expect(native.title).toHaveBeenLastCalledWith('Study A * - Convert-Pheno'))
    expect(within(screen.getByRole('banner')).queryByText(/Study A/)).not.toBeInTheDocument()
    expect(within(screen.getByLabelText('Workspace explorer')).queryByText(/Study A/)).not.toBeInTheDocument()
    menu('save')
    await waitFor(()=>expect(native.title).toHaveBeenLastCalledWith('Study A - Convert-Pheno'))
    expect(within(screen.getByRole('banner')).queryByText(/Study A/)).not.toBeInTheDocument()
  })
  it.each(['new', 'open', 'close-project', 'quit'])('protects unsaved example data on %s', async (action) => {
    await start(); await loadExample(); menu(action)
    const prompt = screen.getByRole('dialog')
    expect(within(prompt).getByText(/unsaved changes/)).toBeInTheDocument()
    fireEvent.click(within(prompt).getByRole('button', { name: 'Cancel' }))
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    expect(projectFile).not.toHaveBeenCalled()
    expect(finishQuit).not.toHaveBeenCalled()
    expect(screen.getByRole('heading', { name: 'Input preview' })).toBeInTheDocument()
  })
  it('saves pasted data before closing a project and keeps global run history', async () => {
    vi.mocked(api.listJobs).mockResolvedValue([completed])
    vi.mocked(projectFile).mockResolvedValue({file: {id:'project1',filename:'example.cpheno'}})
    await start(); await loadExample(); menu('close-project')
    fireEvent.click(within(screen.getByRole('dialog')).getByRole('button', {name:'Save'}))
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())
    expect(projectFile).toHaveBeenCalledWith('save', expect.objectContaining({jsonInput: JSON.stringify(example, null, 2)}), undefined)
    expect(native.title).toHaveBeenLastCalledWith('Convert-Pheno')
    expect(screen.getByRole('button', {name:/^pxf2bff completed/})).toBeInTheDocument()
  })
  it('keeps the current project when the save dialog is cancelled or saving fails', async () => {
    await start(); await loadExample(); menu('new')
    fireEvent.click(within(screen.getByRole('dialog')).getByRole('button', {name:'Save'}))
    await waitFor(() => expect(projectFile).toHaveBeenCalledTimes(1))
    expect(screen.getByRole('dialog')).toBeInTheDocument()
    vi.mocked(projectFile).mockRejectedValueOnce(new Error('Disk full'))
    fireEvent.click(within(screen.getByRole('dialog')).getByRole('button', {name:'Save'}))
    expect(await within(screen.getByRole('dialog')).findByRole('alert')).toHaveTextContent('Disk full')
    fireEvent.click(within(screen.getByRole('dialog')).getByRole('button', {name:'Cancel'}))
    expect(screen.getByRole('heading', {name:'Input preview'})).toBeInTheDocument()
  })
  it('discards edits only after confirmation and completes an approved quit', async () => {
    await start(); await loadExample(); menu('new')
    fireEvent.click(within(screen.getByRole('dialog')).getByRole('button', {name:'Discard'}))
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())
    expect(projectFile).not.toHaveBeenCalled()
    expect(native.title).toHaveBeenLastCalledWith('Convert-Pheno')
    menu('quit')
    await waitFor(() => expect(finishQuit).toHaveBeenCalledOnce())
  })
  it('does not stop active runs when opening a project and asks separately before quitting', async () => {
    vi.mocked(api.listJobs).mockResolvedValue([{...completed,status:'running'}])
    await start(); menu('new')
    expect(api.cancelJob).not.toHaveBeenCalled()
    expect(screen.getByRole('button', {name:/^pxf2bff running/})).toBeInTheDocument()
    vi.mocked(confirmAction).mockResolvedValueOnce(false)
    menu('quit')
    await waitFor(() => expect(confirmAction).toHaveBeenCalledWith('Quit with active conversions?', expect.any(String)))
    expect(finishQuit).not.toHaveBeenCalled()
    expect(api.cancelJob).not.toHaveBeenCalled()
  })
  it('restores project data, prompts for missing sources and saves to the same project', async () => {
    vi.mocked(projectFile).mockResolvedValueOnce({file:{id:'project1',filename:'example.cpheno'},
      settings:{conversion:'csv2bff',options:{separator:';'},output:{entities:['individuals']}}, files:{},
      mapping:'mappingVersion: 2\n', mappingDirty:true, runs:['older-run'],
      missing:[{role:'source',path:'missing.csv',directory:false}]})
    await start(); menu('open')
    await screen.findByRole('button', {name:'Locate missing file'})
    expect(screen.getByLabelText('Source format')).toHaveValue('csv')
    menu('run')
    expect(await screen.findByRole('alert')).toHaveTextContent('Locate the missing project files')
    vi.mocked(selectPaths).mockResolvedValueOnce([{id:'found',filename:'missing.csv',bytes:10,directory:false}])
    fireEvent.click(screen.getByRole('button', {name:'Locate missing file'}))
    await waitFor(() => expect(screen.queryByRole('button', {name:'Locate missing file'})).not.toBeInTheDocument())
    vi.mocked(projectFile).mockResolvedValueOnce({file:{id:'project2',filename:'example.cpheno'}})
    menu('save')
    await waitFor(() => expect(projectFile).toHaveBeenLastCalledWith('save', expect.objectContaining({mapping:'mappingVersion: 2\n', mappingDirty:true, files:{source:['found']},runs:['older-run']}), 'project1'))
    await waitFor(() => expect(native.title).toHaveBeenLastCalledWith('example - Convert-Pheno'))
  })
  it('shows the toolbar route once using source and target badges', async () => {
    await start()
    const badges = screen.getByLabelText('Conversion formats')
    expect(within(badges).getByText(pxf.source.label)).toBeInTheDocument()
    expect(within(badges).getByText(pxf.target.label)).toBeInTheDocument()
    expect(screen.queryByText(pxf.label)).not.toBeInTheDocument()

    fireEvent.change(screen.getByLabelText('Source format'), { target: { value: 'csv' } })
    expect(within(badges).getByText(csv.source.label)).toBeInTheDocument()
    expect(within(badges).getByText(csv.target.label)).toBeInTheDocument()
    expect(within(badges).queryByText(pxf.source.label)).not.toBeInTheDocument()
    expect(screen.queryByText(csv.label)).not.toBeInTheDocument()
  })
  it('loads examples only when requested', async () => {
    await start(); expect(api.getExample).not.toHaveBeenCalled()
    await loadExample()
    expect(screen.queryByLabelText('JSON input')).not.toBeInTheDocument()
    expect(screen.getByText(/You do not need to paste anything/)).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Edit JSON' }))
    expect(screen.getByLabelText('JSON input')).toHaveValue(JSON.stringify(example, null, 2))
  })
  it.each(['pcornet', 'sentinel', 'i2b2'])('loads a file example for %s even when JSON input is accepted', async (source) => {
    vi.mocked(api.getConversions).mockResolvedValue([{...pxf, id:`${source}2bff`, source:{...pxf.source,id:source,label:source}}])
    vi.mocked(api.getExample).mockResolvedValue({transport:'multipart',files:[{role:'source',filename:`${source}.zip`,content:btoa('synthetic package')}]})
    vi.mocked(api.uploadFiles).mockResolvedValue([{id:'example-file',filename:`${source}.zip`,directory:false,bytes:17}])
    await start()
    fireEvent.click(screen.getByRole('button', {name:'Load synthetic example'}))
    await screen.findByRole('heading', {name:'Input data'})
    expect(api.getExample).toHaveBeenCalledWith(source)
    expect(api.uploadFiles).toHaveBeenCalledOnce()
    expect(screen.getByRole('button', {name:'Back to conversion'})).toBeInTheDocument()
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
    fireEvent.click(screen.getByRole('button', { name: 'Back to conversion' }))
    fireEvent.click(screen.getByRole('button', { name: 'Run conversion' }))
    await screen.findByRole('button', { name: /individuals.json/ })
    expect(api.submitJob).toHaveBeenCalledWith({ conversion: 'pxf2bff', input: { data: example }, options: {}, output: { entities: ['individuals'] } })
  })
  it('does not show a blank JSON editor unless explicitly requested', async () => {
    await start()
    fireEvent.click(screen.getByRole('button', { name: 'Input' }))
    expect(screen.queryByLabelText('JSON input')).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Paste JSON instead' }))
    expect(screen.getByLabelText('JSON input')).toHaveAccessibleDescription(expect.stringContaining('not an API request'))
  })
  it('forwards a disabled provenance option as a boolean', async () => {
    vi.mocked(api.getConversions).mockResolvedValue([{...pxf, options: [
      {name: 'source_info', label: 'Include source provenance', kind: 'boolean', default: true},
    ]}])
    await start(); await loadExample()
    fireEvent.click(screen.getByRole('button', {name: 'Back to conversion'}))
    fireEvent.click(screen.getByLabelText('Include source provenance'))
    fireEvent.click(screen.getByRole('button', {name: 'Run conversion'}))
    await waitFor(() => expect(api.submitJob).toHaveBeenCalledWith(expect.objectContaining({options: {source_info: false}})))
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
    menu('run')
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
    fireEvent.click(screen.getByRole('button',{name:'Load synthetic example'}))
    await waitFor(()=>expect(screen.getByRole('status')).toHaveTextContent('Input data and mapping are both ready; no second load is needed.'))
    expect(screen.getByRole('button',{name:'Mapping'})).toHaveAttribute('aria-current','page')
    expect(api.uploadFiles).toHaveBeenCalledTimes(2)
    fireEvent.click(screen.getByRole('button', { name: 'Back to conversion' }))
    expect(screen.getByRole('button', { name: 'Run conversion' })).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button',{name:'Input'}))
    expect(screen.getByText(/Your input files are already loaded/)).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Back to conversion' }))
    expect(screen.getByRole('button', { name: 'Run conversion' })).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Input' }))
    vi.mocked(api.inputPreview).mockResolvedValue({text:'id\n1\n',truncated:false})
    fireEvent.click(within(screen.getByRole('heading', { name: 'Input data' }).closest('section')!).getByRole('button', { name: 'example.csv' }))
    await screen.findByRole('heading', { name: 'example.csv' })
    fireEvent.click(screen.getByRole('button', { name: 'Back to conversion' }))
    expect(screen.getByRole('button', { name: 'Run conversion' })).toBeInTheDocument()
    expect(api.uploadFiles).toHaveBeenCalledTimes(2)
  })
  it('submits the optional mapping together with a loaded BFF JSON example', async () => {
    const route: Conversion = {...pxf, id:'bff2omop', source:{...pxf.source,id:'beacon',label:'Beacon v2'},
      target:{id:'omop',label:'OMOP-CDM',kind:'table'},
      input:{transports:['json','multipart'],files:[
        {name:'source',label:'BFF document',required:true,multiple:false,accept:['.json']},
        {name:'mapping',label:'Terminology mapping',required:false,multiple:false,accept:['.yaml']},
      ]}}
    vi.mocked(api.getConversions).mockResolvedValue([route])
    vi.mocked(api.getExample).mockResolvedValue([{id:'synthetic-1'}])
    vi.mocked(api.inputPreview).mockResolvedValue({text:'mappingVersion: 2',truncated:false})
    vi.mocked(api.uploadFiles).mockResolvedValue([{id:'json-handle',filename:'input.json',directory:false,bytes:20}])
    await start(); await loadExample()
    expect(api.getExample).toHaveBeenCalledWith('beacon')
    fireEvent.click(screen.getByRole('button',{name:'Back to conversion'}))
    vi.mocked(selectPaths).mockResolvedValueOnce([{id:'map-handle',filename:'terms.yaml',directory:false,bytes:20}])
    fireEvent.click(screen.getAllByRole('button',{name:'Browse...'})[1])
    await screen.findByRole('heading',{name:'Mapping file'})
    fireEvent.click(screen.getByRole('button',{name:'Back to conversion'}))
    await screen.findByText('terms.yaml',{selector:'small'})
    fireEvent.click(screen.getByRole('button',{name:'Run conversion'}))
    await waitFor(()=>expect(api.submitJob).toHaveBeenCalled())
    expect(vi.mocked(api.submitJob).mock.calls[0][0]).toMatchObject({input:{files:{source:['json-handle'],mapping:['map-handle']}}})
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
  it('opens the first output automatically and shows warnings separately', async () => {
    await start(); await loadExample(); menu('run')
    await waitFor(() => expect(api.outputPreview).toHaveBeenCalledWith('run1', 'individuals'))
    expect(screen.getByLabelText('Output summary')).toHaveTextContent('1 output file')
    fireEvent.click(screen.getByRole('button', { name: 'Warnings (1)' }))
    expect(screen.getByText('Synthetic warning')).toBeInTheDocument()
  })
  it('keeps draft and historical run routes distinct and hides irrelevant tabs', async () => {
    vi.mocked(api.listJobs).mockResolvedValue([completed])
    await start()
    const navigation = screen.getByRole('navigation', { name: 'Workspace views' })
    expect(within(navigation).queryByRole('button', { name: 'Mapping' })).not.toBeInTheDocument()
    expect(within(navigation).queryByRole('button', { name: 'Terminology Review' })).not.toBeInTheDocument()
    fireEvent.change(screen.getByLabelText('Source format'), { target: { value: 'csv' } })
    expect(within(navigation).getByRole('button', { name: 'Mapping' })).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /^pxf2bff completed/ }))
    expect(within(screen.getByLabelText('Conversion formats')).getByText('Phenopacket v2')).toBeInTheDocument()
    expect(screen.getByText(/Run run1/)).toBeInTheDocument()
    fireEvent.click(within(navigation).getByRole('button', { name: 'Conversion' }))
    expect(within(screen.getByLabelText('Conversion formats')).getByText('CSV')).toBeInTheDocument()
    expect(within(screen.getByRole('region', { name: 'Review and convert' })).getByRole('button', { name: 'Run conversion' })).toBeInTheDocument()
  })
  it('does not display a late preview from a previously selected run', async () => {
    const second = { ...completed, id: 'run2', conversion: 'csv2bff', created: 2 }
    vi.mocked(api.listJobs).mockResolvedValue([completed, second])
    let finishFirst!: (preview: {text: string; truncated: boolean}) => void
    vi.mocked(api.outputPreview).mockReturnValueOnce(new Promise((resolve) => { finishFirst = resolve }))
      .mockResolvedValueOnce({text: '[{"id":"second-output"}]', truncated: false})
    await start()
    fireEvent.click(screen.getByRole('button', { name: /^pxf2bff completed/ }))
    await waitFor(() => expect(api.outputPreview).toHaveBeenCalledWith('run1', 'individuals'))
    fireEvent.click(screen.getByRole('button', { name: /^csv2bff completed/ }))
    await screen.findByRole('button', { name: 'second-output' })
    await act(async () => finishFirst({text: '[{"id":"first-output"}]', truncated: false}))
    expect(screen.queryByRole('button', { name: 'first-output' })).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'second-output' })).toBeInTheDocument()
    expect(api.outputPreview).toHaveBeenCalledTimes(2)
  })
  it('allows retrying a failed automatic preview without looping requests', async () => {
    vi.mocked(api.outputPreview).mockRejectedValueOnce(new Error('Output file is unavailable'))
      .mockResolvedValueOnce({ text: '[{"id":"recovered"}]', truncated: false })
    await start(); await loadExample(); menu('run')
    expect(await screen.findByRole('alert')).toHaveTextContent('Output file is unavailable')
    expect(api.outputPreview).toHaveBeenCalledTimes(1)
    fireEvent.click(screen.getByRole('button', { name: 'Retry preview' }))
    await screen.findByRole('button', { name: 'recovered' })
    expect(api.outputPreview).toHaveBeenCalledTimes(2)
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
    fireEvent.click(screen.getByRole('button',{name:'Install from file...'}))
    expect(screen.getByRole('button',{name:'Install from file...'})).toBeDisabled()
    expect(screen.getByText(/Verifying and installing the selected/)).toBeInTheDocument()
    await act(async () => finish('/synthetic/ohdsi.db'))
    expect(await screen.findByText('The verified OHDSI terminology database is installed.')).toBeInTheDocument()
    expect(screen.getByText('Installed')).toBeInTheDocument()
  })
  it('shows the selected resource folder and refreshes installed resources', async () => {
    vi.mocked(chooseResourceDirectory).mockResolvedValue('/external/terminology')
    await start(); fireEvent.click(screen.getByRole('button',{name:'Resources'}))
    expect(await screen.findByText('/synthetic/resources')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button',{name:'Change folder...'}))
    expect(await screen.findByText('/external/terminology')).toBeInTheDocument()
    expect(await screen.findByText('Resource folder changed. Existing files were not moved.')).toBeInTheDocument()
  })
  it('downloads OHDSI with progress and refreshes availability after installation', async () => {
    const missing = {id:'ohdsi',installed:false,bundled:false,byteSize:100,contentVersion:'2022'}
    vi.mocked(api.getResources).mockResolvedValueOnce([missing]).mockResolvedValueOnce([{...missing,installed:true}])
    let finish!: (path: string) => void
    vi.mocked(downloadOhdsi).mockImplementation((report) => {
      report({completedBytes:50,totalBytes:100})
      return new Promise((resolve) => { finish = resolve })
    })
    await start(); fireEvent.click(screen.getByRole('button',{name:'Resources'}))
    fireEvent.click(await screen.findByRole('button',{name:'Download and install'}))
    expect(screen.getByRole('progressbar')).toHaveAttribute('value','50')
    expect(screen.getByRole('button',{name:'Install from file...'})).toBeDisabled()
    await act(async () => finish('/synthetic/ohdsi.db'))
    expect(await screen.findByText('The verified OHDSI terminology database is installed.')).toBeInTheDocument()
    expect(screen.getByRole('button',{name:'Download and reinstall'})).toBeEnabled()
  })
  it('cancels a download and allows retry after the native operation stops', async () => {
    let fail!: (error: Error) => void
    vi.mocked(downloadOhdsi).mockImplementation(() => new Promise((_, reject) => { fail = reject }))
    vi.mocked(cancelOhdsiDownload).mockResolvedValue(undefined)
    await start(); fireEvent.click(screen.getByRole('button',{name:'Resources'}))
    fireEvent.click(await screen.findByRole('button',{name:'Download and install'}))
    fireEvent.click(screen.getByRole('button',{name:'Cancel download'}))
    expect(cancelOhdsiDownload).toHaveBeenCalledOnce()
    await act(async () => fail(new Error('Download cancelled.')))
    expect(await screen.findByText('Download cancelled.')).toBeInTheDocument()
    expect(screen.getByRole('button',{name:'Download and install'})).toBeEnabled()
  })
  it('restores panels through native menu actions', async () => {
    await start(); menu('explorer')
    expect(screen.queryByLabelText('Workspace explorer')).not.toBeInTheDocument()
    menu('explorer'); expect(screen.getByLabelText('Workspace explorer')).toBeInTheDocument()
    menu('inspector'); expect(screen.queryByLabelText('Record inspector')).not.toBeInTheDocument()
  })
  it('resizes navigation using keyboard controls and resets without persisting width', async () => {
    await start()
    const divider = screen.getByRole('separator', { name: 'Resize left navigation' })
    fireEvent.keyDown(divider, { key: 'ArrowRight' })
    expect(screen.getByLabelText('Workspace explorer')).toHaveStyle({ width: '235px', flexBasis: '235px' })
    fireEvent.keyDown(divider, { key: 'End' })
    fireEvent.keyDown(divider, { key: 'ArrowRight' })
    expect(divider).toHaveAttribute('aria-valuenow', '350')
    fireEvent.keyDown(divider, { key: 'Home' })
    fireEvent.keyDown(divider, { key: 'ArrowLeft' })
    expect(divider).toHaveAttribute('aria-valuenow', '170')
    fireEvent.doubleClick(divider)
    expect(divider).toHaveAttribute('aria-valuenow', '225')
    expect(JSON.parse(localStorage.getItem('convert-pheno.desktop.settings')!)).toEqual({ theme: 'system', explorer: true, inspector: true, tasks: true })
    menu('explorer')
    expect(screen.queryByRole('separator')).not.toBeInTheDocument()
  })
  it('drags navigation within bounds and stops resizing after pointer release', async () => {
    await start()
    const divider = screen.getByRole('separator', { name: 'Resize left navigation' })
    divider.setPointerCapture = vi.fn()
    divider.hasPointerCapture = vi.fn(() => true)
    divider.releasePointerCapture = vi.fn()
    function pointer(type: string, clientX: number) {
      fireEvent(divider, Object.assign(new Event(type, { bubbles: true }), { pointerId: 1, button: 0, clientX }))
    }
    pointer('pointerdown', 225)
    pointer('pointermove', 305)
    expect(divider).toHaveAttribute('aria-valuenow', '305')
    pointer('pointermove', 800)
    expect(divider).toHaveAttribute('aria-valuenow', '350')
    pointer('pointerup', 800)
    pointer('pointermove', 170)
    expect(divider).toHaveAttribute('aria-valuenow', '350')
    expect(divider.releasePointerCapture).toHaveBeenCalledWith(1)
  })
  it('copies inspected objects as JSON and plain values without added quotes', async () => {
    vi.mocked(api.getExample).mockResolvedValue([{ id: 'synthetic-1', sex: { id: 'NCIT:C16576', label: 'Female' } }])
    await start(); await loadExample()
    fireEvent.click(screen.getByRole('button', { name: 'View details' }))
    const inspector = screen.getByLabelText('Record inspector')
    fireEvent.click(within(inspector).getByRole('button', { name: 'Copy inspected value' }))
    await waitFor(() => expect(writeText).toHaveBeenLastCalledWith(JSON.stringify({ id: 'NCIT:C16576', label: 'Female' }, null, 2)))
    fireEvent.click(screen.getByRole('button', { name: 'synthetic-1' }))
    fireEvent.click(within(inspector).getByRole('button', { name: 'Copy inspected value' }))
    await waitFor(() => expect(writeText).toHaveBeenLastCalledWith('synthetic-1'))
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
  it('toolbar cancellation targets the selected one of four running jobs', async () => {
    const runs = Array.from({length: 4}, (_, index) => ({...completed, id: `running-${index}`, status: 'running' as const}))
    vi.mocked(api.listJobs).mockResolvedValue(runs)
    vi.mocked(api.cancelJob).mockResolvedValue({...runs[2], status: 'cancelled'})
    await start()
    expect(screen.queryByRole('button', {name: 'Cancel selected run'})).not.toBeInTheDocument()
    fireEvent.click(screen.getAllByRole('button', {name: /^pxf2bff running/})[2])
    fireEvent.click(screen.getByRole('button', {name: 'Cancel selected run'}))
    await waitFor(() => expect(api.cancelJob).toHaveBeenCalledWith('running-2'))
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
