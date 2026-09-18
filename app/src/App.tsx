import { lazy, Suspense, useEffect, useRef, useState } from 'react'
import * as api from './api'
import { openExternal, revealRun, selectPaths, connection, confirmAction, saveMappingCopy, installOhdsi, downloadOhdsi, cancelOhdsiDownload, resourceDirectory, chooseResourceDirectory, projectFile, finishQuit, type DownloadProgress } from './desktop'
import DataView, { type Inspection } from './components/DataView'
import TerminologyReview from './components/TerminologyReview'
import ConceptDetails from './components/ConceptDetails'
import RunActions from './components/RunActions'
import CopyButton from './components/CopyButton'
import ConversionOptions from './components/ConversionOptions'
import JobSettings from './components/JobSettings'
const MappingEditor = lazy(() => import('./components/MappingEditor'))
import type { Artifact, Conversion, FileHandle, Job, Preview, Resource } from './types'
import { readSettings, saveSettings, type ThemeChoice } from './settings'
import { isTauri } from '@tauri-apps/api/core'
import { getCurrentWindow } from '@tauri-apps/api/window'
import { listen } from '@tauri-apps/api/event'
import { FolderOpen, Folder, FileText, Save, Play, Square, Database, Settings as SettingsIcon, BookOpen, GitFork, ArrowRightLeft, PanelLeftClose, PanelLeftOpen, Trash2, RotateCcw, LoaderCircle, Download } from 'lucide-react'

type Tab = 'Input' | 'Conversion' | 'Mapping' | 'Outputs' | 'Terminology Review' | 'Warnings' | 'Compare'
type Draft = { conversion: string; options: Record<string, unknown>; output: { entities?: string[] } }
type MissingSource = { role: string; path: string; directory: boolean; index?: number }
type Project = { file: FileHandle; settings: Draft; files: Record<string, FileHandle[]>; jsonInput?: string; mapping?: string; mappingDirty?: boolean; destination?: FileHandle; missing: MissingSource[]; runs: string[] }
const busy = (job: Job) => ['queued', 'running', 'cancelling'].includes(job.status)
const size = (bytes: number) => bytes >= 1073741824 ? `${(bytes / 1073741824).toFixed(1)} GiB` : bytes > 1048576 ? `${(bytes / 1048576).toFixed(1)} MiB` : `${Math.ceil(bytes / 1024)} KiB`
const DEFAULT: Draft = { conversion: '', options: {}, output: {} }

export default function App() {
  const [routes, setRoutes] = useState<Conversion[]>([])
  const [jobs, setJobs] = useState<Job[]>([])
  const [runQuery, setRunQuery] = useState('')
  const [resources, setResources] = useState<Resource[]>([])
  const [draft, setDraft] = useState<Draft>(DEFAULT)
  const [files, setFiles] = useState<Record<string, FileHandle[]>>({})
  const [collapsedGroups, setCollapsedGroups] = useState<Record<string, boolean>>({})
  const [navigationWidth, setNavigationWidth] = useState(225)
  const navigationDrag = useRef<{ pointer: number; x: number; width: number } | null>(null)
  const resizeNavigation = (width: number) => setNavigationWidth(Math.max(170, Math.min(350, width)))
  const toggleGroup = (name: string) => setCollapsedGroups((current) => ({ ...current, [name]: !current[name] }))
  const [destination, setDestination] = useState<FileHandle>()
  const [outputRoot, setOutputRoot] = useState('')
  const [pendingAction, setPendingAction] = useState<string>()
  const [resourceInstalling, setResourceInstalling] = useState(false)
  const [resourcePath, setResourcePath] = useState('')
  const [resourceChanging, setResourceChanging] = useState(false)
  const [downloadProgress, setDownloadProgress] = useState<DownloadProgress>()
  const [downloadCancelling, setDownloadCancelling] = useState(false)
  const [tab, setTab] = useState<Tab>('Conversion')
  const [section, setSection] = useState<'workspace' | 'resources' | 'settings'>('workspace')
  const [sourcePreview, setSourcePreview] = useState<{ file: FileHandle; data?: Preview }>()
  const [pasteInput, setPasteInput] = useState(false)
  const [resultPreview, setResultPreview] = useState<{ job: string; id: string; data?: Preview; error?: string }>()
  const previewRequest = useRef(0)
  function resetPreviews() {
    previewRequest.current += 1
    setSourcePreview(undefined); setResultPreview(undefined); setInspection(undefined)
  }
  function inspect(value: Inspection) { setInspection(value); setSettings((current) => ({ ...current, inspector: true })) }
  async function inspectSource(file: FileHandle) {
    const request = ++previewRequest.current
    setSourcePreview({ file }); setInspection(undefined); setTab('Input'); setSection('workspace')
    const data = await api.inputPreview(file.id)
    if (request === previewRequest.current) setSourcePreview({ file, data })
  }
  async function inspectOutput(runId: string, id: string) {
    const selected = jobs.find((item) => item.id === runId)
    if (['term-audit', 'term-audit-tsv'].includes(id) && selected?.result?.meta.terminologyAudit) {
      setSelectedJob(runId); setTab('Terminology Review'); setSection('workspace')
      return
    }
    const request = ++previewRequest.current
    setSelectedOutput(id); setResultPreview({ job: runId, id }); setInspection(undefined)
    try {
      const data = await api.outputPreview(runId, id)
      if (request === previewRequest.current) setResultPreview({ job: runId, id, data })
    } catch (reason) {
      if (request === previewRequest.current) setResultPreview({ job: runId, id, error: (reason as Error).message })
    }
  }
  async function installOhdsiResource(download = false) {
    setResourceInstalling(true)
    setDownloadCancelling(false)
    setDownloadProgress(download ? { completedBytes: 0, totalBytes: ohdsi?.byteSize || 0 } : undefined)
    try {
      const installed = download ? await downloadOhdsi(setDownloadProgress) : await installOhdsi()
      if (!installed) return
      const [nextResources, nextRoutes] = await Promise.all([api.getResources(), api.getConversions()])
      setResources(nextResources); setRoutes(nextRoutes)
      setMessage('The verified OHDSI terminology database is installed.')
    } finally {
      setResourceInstalling(false)
      setDownloadProgress(undefined)
      setDownloadCancelling(false)
    }
  }
  async function changeResourceFolder() {
    setResourceChanging(true)
    try {
      const directory = await chooseResourceDirectory()
      if (!directory) return
      setResourcePath(directory)
      const [nextResources, nextRoutes] = await Promise.all([api.getResources(), api.getConversions()])
      setResources(nextResources); setRoutes(nextRoutes)
      setMessage('Resource folder changed. Existing files were not moved.')
    } finally { setResourceChanging(false) }
  }
  const [inspection, setInspection] = useState<Inspection>()
  const [selectedJob, setSelectedJob] = useState('')
  const [selectedOutput, setSelectedOutput] = useState('')
  const [comparison, setComparison] = useState('')
  const [mapping, setMapping] = useState('')
  const [mappingDirty, setMappingDirty] = useState(false)
  const mappingEpoch = useRef(0)
  const [jsonInput, setJsonInput] = useState('')
  const [project, setProject] = useState<FileHandle>()
  const [projectRuns, setProjectRuns] = useState<string[]>([])
  const [missingSources, setMissingSources] = useState<MissingSource[]>([])
  const [savedProject, setSavedProject] = useState<{configuration: string; jsonInput: string; mapping: string} | null>(null)
  const [projectBusy, setProjectBusy] = useState(false)
  const projectSaving = useRef(false)
  const [projectPrompt, setProjectPrompt] = useState<(() => Promise<void>) | null>(null)
  const projectPromptRef = useRef(false)
  // Job polling must not repeatedly serialize potentially large pasted inputs.
  const projectSnapshot = {configuration: JSON.stringify({draft, files, mappingDirty, destination, projectRuns, missingSources}), jsonInput, mapping}
  const projectDirty = !!savedProject && (savedProject.configuration !== projectSnapshot.configuration || savedProject.jsonInput !== jsonInput || savedProject.mapping !== mapping)
  const [message, setMessage] = useState('')
  const [error, setError] = useState('')
  const windowTitle = project
    ? `${project.filename.replace(/\.cpheno$/i, '')}${projectDirty ? ' *' : ''} - Convert-Pheno`
    : 'Convert-Pheno'
  useEffect(() => {
    if (isTauri()) void getCurrentWindow().setTitle(windowTitle).catch((reason: Error) => setError(reason.message))
  }, [windowTitle])
  const [submitting, setSubmitting] = useState(false)
  const [settings, setSettings] = useState(readSettings)
  const taskPanel = settings.tasks
  const setTaskPanel = (tasks: boolean) => setSettings((current) => ({ ...current, tasks }))
  useEffect(() => {
    try { saveSettings(settings) } catch { setError('Could not save application settings.') }
    const media = window.matchMedia('(prefers-color-scheme: dark)')
    const apply = () => { document.documentElement.dataset.theme = settings.theme === 'system' ? (media.matches ? 'dark' : 'light') : settings.theme }
    apply()
    media.addEventListener('change', apply)
    if (isTauri()) void getCurrentWindow().setTheme(settings.theme === 'system' ? null : settings.theme).catch((reason: Error) => setError(reason.message))
    return () => media.removeEventListener('change', apply)
  }, [settings])
  const [ready, setReady] = useState(false)
  useEffect(() => { if (ready && !savedProject) setSavedProject(projectSnapshot) }, [ready, savedProject, projectSnapshot])
  const route = routes.find((item) => item.id === draft.conversion)
  const job = jobs.find((item) => item.id === selectedJob)
  const jobRoute = routes.find((item) => item.id === job?.conversion)
  const other = jobs.find((item) => item.id === comparison)
  const outputs = job?.result?.artifacts || []
  const browsingRun = section === 'workspace' && ['Outputs', 'Terminology Review', 'Warnings', 'Compare'].includes(tab) && Boolean(job)
  const displayedRoute = browsingRun ? jobRoute : route
  const tabs: Tab[] = ['Conversion', 'Input']
  if (route?.input.files.some((file) => file.name === 'mapping')) tabs.push('Mapping')
  tabs.push('Outputs')
  if (job?.result?.meta.terminologyAudit) tabs.push('Terminology Review')
  if (job?.result?.warnings.length) tabs.push('Warnings')
  if (job && jobs.length > 1) tabs.push('Compare')
  const firstPreview = outputs.find((file) => ['json', 'jsonld', 'csv', 'tsv'].includes(file.kind) && !file.id.startsWith('term-audit'))
  useEffect(() => {
    if (!tabs.includes(tab)) setTab(['Mapping', 'Input', 'Conversion'].includes(tab) ? 'Conversion' : 'Outputs')
  }, [tab, tabs.join('|')])
  useEffect(() => {
    if (section !== 'workspace' || tab !== 'Outputs' || job?.status !== 'completed' || selectedOutput || !firstPreview) return
    void inspectOutput(job.id, firstPreview.id).catch((reason: Error) => setError(reason.message))
  }, [section, tab, job?.id, job?.status, firstPreview?.id, selectedOutput])
  const active = jobs.filter(busy)
  const ohdsi = resources.find((item) => item.id === 'ohdsi')
  const inspectionText = typeof inspection?.value === 'string' ? inspection.value : JSON.stringify(inspection?.value, null, 2) ?? ''
  const bundledResources = resources.filter((item) => item.id !== 'ohdsi')
  const hasActiveJobs = active.length > 0
  const runRank = (item: Job) => ['running', 'cancelling'].includes(item.status) ? 0 : item.status === 'queued' ? 1 : 2
  const visibleJobs = jobs.filter((item) => `${item.conversion} ${item.id} ${item.status} ${item.sources.join(' ')}`.toLowerCase().includes(runQuery.toLowerCase()))
    .sort((a, b) => runRank(a) - runRank(b) || (a.status === 'queued' && b.status === 'queued' ? (a.queuePosition ?? Infinity) - (b.queuePosition ?? Infinity) : b.created - a.created))
  const sources = [...new Map(routes.map((item) => [item.source.id, item.source])).values()]
  const run = async (action: () => Promise<void>) => { setError(''); setMessage(''); try { await action() } catch (reason) { setError((reason as Error).message) } }
  function selectRoute(next: Conversion) {
    setMessage('')
    setMissingSources([])
    mappingEpoch.current++
    setDraft({ conversion: next.id, output: next.entities.supported.length ? { entities: next.entities.default } : {},
      options: Object.fromEntries(next.options.filter((item) => item.default !== undefined).map((item) => [item.name, item.default])) })
    setFiles({}); setJsonInput(''); setPasteInput(false); setMapping(''); setMappingDirty(false); resetPreviews(); setTab('Conversion')
  }
  useEffect(() => {
    let alive = true
    connection().then((service) => { if (alive) setOutputRoot(service.outputRoot) }).catch((reason: Error) => { if (alive) setError(reason.message) })
    resourceDirectory().then((directory) => { if (alive) setResourcePath(directory) }).catch((reason: Error) => { if (alive) setError(reason.message) })
    api.getConversions().then((items) => { if (alive) { setRoutes(items); if (items[0]) selectRoute(items[0]); setReady(true) } }).catch((reason) => { if (alive) setError(reason.message) })
    void api.listJobs().then((items) => { if (alive) setJobs(items) }).catch((reason) => { if (alive) setError(reason.message) })
    return () => { alive = false }
  }, [])

  useEffect(() => {
    let alive = true
    const refresh = () => api.listJobs().then((items) => { if (alive) setJobs(items) }).catch((reason) => { if (alive) setError(reason.message) })
    const timer = window.setInterval(refresh, hasActiveJobs ? 250 : 1500)
    return () => { alive = false; window.clearInterval(timer) }
  }, [hasActiveJobs])

  async function choose(role: string, directory = false, multiple = false) {
    const selected = await selectPaths(directory, multiple)
    if (!selected.length) return
    setFiles((current) => ({ ...current, [role]: selected }))
    setMissingSources((current) => current.filter((item) => item.role !== role))
    if (role === 'source') { setJsonInput(''); setPasteInput(false); resetPreviews() }
    if (role === 'mapping') {
      const epoch = ++mappingEpoch.current
      setMapping(''); setMappingDirty(false)
      const content = await api.inputPreview(selected[0].id)
      if (epoch !== mappingEpoch.current) return
      if (content.truncated) throw new Error('Mapping is too large for the editor; the selected file can still be used for conversion.')
      setMapping(content.text); setMappingDirty(false); setTab('Mapping')
    }
  }
  async function validateMapping(text: string) {
    const epoch = mappingEpoch.current
    const file = await api.post<FileHandle>('/api/mappings', {text})
    if (epoch !== mappingEpoch.current) throw new Error('The mapping changed while validation was running. Validate the current document again.')
    setFiles((current) => ({...current, mapping:[file]})); setMappingDirty(false)
  }
  async function submit() {
    if (!route || submitting) return
    if (missingSources.length) throw new Error('Locate the missing project files before running.')
    if (mappingDirty) throw new Error('Validate and use the edited mapping before running.')
    const missing = route.input.files.find((item) => item.required && !files[item.name]?.length)
    if (!jsonInput.trim() && missing) throw new Error(`Select ${missing.label} before running.`)
    setSubmitting(true)
    try {
      const selected = {...files}
      const hasAuxiliaryFiles = Object.entries(selected).some(([role, items]) => role !== 'source' && items.length)
      // JSON plus a mapping uses the same managed-file route as file input.
      // Otherwise the JSON request would silently omit the selected mapping.
      if (jsonInput.trim() && hasAuxiliaryFiles) {
        JSON.parse(jsonInput)
        selected.source = await api.uploadFiles([new File([jsonInput], 'input.json', {type: 'application/json'})])
      }
      const input = jsonInput.trim() && !hasAuxiliaryFiles ? { data: JSON.parse(jsonInput) } : { files: Object.fromEntries(Object.entries(selected).map(([key, value]) => [key, value.map((item) => item.id)])) }
      const created = await api.submitJob({ ...draft, input, ...(destination ? { destination: destination.id } : {}) })
      setProjectRuns((current) => [...current, created.id])
      setJobs((current) => [created, ...current]); setSelectedJob(created.id); setSelectedOutput(''); setTab('Outputs'); resetPreviews()
    } finally { setSubmitting(false) }
  }
  async function cancelRun(item: Job) {
    if (pendingAction) return
    const queued = item.status === 'queued'
    setPendingAction(item.id)
    try {
      if (!await confirmAction(queued ? 'Remove queued run?' : 'Cancel conversion?', `${item.conversion} (${item.id.slice(0, 8)})${queued ? ' will be removed from the queue.' : ' will be stopped. Incomplete outputs are not published.'}`)) return
      const updated = await api.cancelJob(item.id)
      setJobs((current) => current.map((entry) => entry.id === updated.id ? updated : entry))
    } finally { setPendingAction(undefined) }
  }
  async function cancelPending() {
    if (pendingAction) return
    setPendingAction('pending')
    try {
      if (!await confirmAction('Cancel all pending runs?', 'Remove all currently queued runs? The active conversion will continue.')) return
      await api.cancelPendingJobs()
      setJobs(await api.listJobs())
    } finally { setPendingAction(undefined) }
  }
  async function deleteRun(item: Job, fromDisk = false) {
    if (pendingAction) return
    setPendingAction(item.id)
    try {
      if (!await confirmAction(fromDisk ? 'Permanently delete run and output files?' : 'Delete run from history?', fromDisk
        ? `This permanently deletes this run's saved outputs and internal run files. It cannot be undone. Original source files and copies saved elsewhere are not deleted.\n\nOutput folder: ${item.directory || item.outputDirectory || 'Private run folder'}`
        : 'This removes the run from the list. Source files and generated output files are kept on disk.')) return
      if (fromDisk) await api.deleteJobFiles(item.id)
      else await api.deleteJob(item.id)
      setJobs((current) => current.filter((entry) => entry.id !== item.id))
      if (selectedJob === item.id) { setSelectedJob(''); setSelectedOutput(''); resetPreviews(); setTab('Conversion') }
    } finally { setPendingAction(undefined) }
  }
  async function setUpAgain(item: Job) {
    const next = routes.find((entry) => entry.id === item.conversion)
    if (!next) throw new Error('This conversion is not available in the current installation.')
    if (!await confirmAction('Set up this conversion again?', 'Replace the current draft with this run\'s configuration? You will need to reselect the input files and any custom output folder.')) return
    selectRoute(next)
    setDraft({ conversion: item.conversion, options: { ...item.options }, output: { ...item.output } })
    setDestination(undefined); setSection('workspace')
    setMessage('Configuration restored. Reselect your inputs and check the output folder before running again.')
  }
  async function deleteAllRuns(fromDisk: boolean) {
    if (pendingAction) return
    setPendingAction('delete-all')
    try {
      if (!await confirmAction(fromDisk ? 'Permanently delete all finished run files?' : 'Delete all finished runs from history?', fromDisk
        ? 'This permanently deletes saved outputs and internal files for all finished runs, including those previously removed from history. Active runs, original source files and copies saved elsewhere are kept. This cannot be undone.'
        : 'Remove all finished runs from the list? Active runs and all files on disk are kept.')) return
      const result = await api.deleteAllJobs(fromDisk)
      setJobs(await api.listJobs())
      if (result.deleted.includes(selectedJob)) { setSelectedJob(''); setSelectedOutput(''); resetPreviews(); setTab('Conversion') }
      setMessage(`${result.deleted.length} run${result.deleted.length === 1 ? '' : 's'} deleted${fromDisk ? ' with their output files' : ' from history'}. ${result.skipped.length} active run${result.skipped.length === 1 ? '' : 's'} kept.`)
      if (result.failed.length) setError(`${result.failed.length} runs could not be deleted: ${result.failed.map((item) => `${item.id.slice(0,8)}: ${item.message}`).join('; ')}`)
    } finally { setPendingAction(undefined) }
  }
  async function example() {
    if (!route) return
    mappingEpoch.current++
    setMapping(''); setMappingDirty(false)
    resetPreviews()
    const data = await api.getExample(route.source.id) as { transport?: string; options?: Record<string, unknown>; files?: Array<{role: string;filename: string;content: string}> }
    if (data.transport === 'multipart' && data.files) {
      const selected: Record<string, FileHandle[]> = {}
      for (const item of data.files) {
        const bytes = Uint8Array.from(atob(item.content), (c) => c.charCodeAt(0))
        const handles = await api.uploadFiles([new File([bytes], item.filename)])
        selected[item.role] = [...(selected[item.role] || []), ...handles]
        if (item.role === 'mapping') setMapping(new TextDecoder().decode(bytes))
      }
      setFiles(selected); setDraft((current) => ({...current,options:{...current.options,...data.options}})); setJsonInput('')
    } else { setJsonInput(JSON.stringify(data, null, 2)); setFiles({}) }
    const hasMapping = data.transport === 'multipart' && data.files?.some((file) => file.role === 'mapping')
    setPasteInput(false); setTab(tab === 'Mapping' && hasMapping ? 'Mapping' : 'Input')
    setMessage(`${route.source.label} synthetic example loaded.${hasMapping ? ' Input data and mapping are both ready; no second load is needed.' : ''} Your own files have not been changed.`)
  }
  async function saveProject(as = false): Promise<boolean> {
    if (projectSaving.current) return false
    if (missingSources.length) throw new Error('Locate the missing project files before saving. The existing project has not been changed.')
    projectSaving.current = true
    setProjectBusy(true)
    try {
    const snapshot = projectSnapshot
    const saved = await projectFile<{file: FileHandle}>('save', { settings: draft,
      files: Object.fromEntries(Object.entries(files).map(([role, items]) => [role, items.map((item) => item.id)])),
      jsonInput, mapping, mappingDirty, destination: destination?.id, runs: projectRuns }, as ? undefined : project?.id)
    if (!saved) return false
    setProject(saved.file); setSavedProject(snapshot)
    setMessage('Project saved. Keep the .cpheno file and its .cpheno.data folder together. External input files remain in their original locations.')
    return true
    } finally { projectSaving.current = false; setProjectBusy(false) }
  }
  async function openProject() {
    const saved = await projectFile<Project>('open')
    if (!saved) return
    if (!routes.some((item) => item.id === saved.settings.conversion)) throw new Error('The saved conversion is not supported by this installation.')
    mappingEpoch.current++
    setDraft(saved.settings); setFiles(saved.files); setJsonInput(saved.jsonInput || ''); setMapping(saved.mapping || '')
    setMappingDirty(!!saved.mappingDirty); setDestination(saved.destination); setProjectRuns(saved.runs)
    setMissingSources(saved.missing); setProject(saved.file); setSavedProject(null); setPasteInput(false)
    resetPreviews(); setTab('Conversion'); setSection('workspace'); setSelectedJob('')
    setMessage(saved.missing.length ? 'Project opened. Locate its missing files before converting.' : 'Project opened. Inputs and conversion settings are restored.')
  }
  async function newProject() {
    if (route) selectRoute(route)
    setDestination(undefined); setProject(undefined); setProjectRuns([]); setMissingSources([]); setSavedProject(null)
    setSelectedJob(''); resetPreviews(); setSection('workspace')
  }
  async function locateSource(missing: MissingSource) {
    const [file] = await selectPaths(missing.directory)
    if (!file) return
    if (missing.role === 'destination') setDestination(file)
    else setFiles((current) => {
      const items = [...(current[missing.role] || [])]
      const earlierMissing = missingSources.filter((item) => item.role === missing.role && (item.index ?? 0) < (missing.index ?? 0)).length
      items.splice(Math.max(0, (missing.index ?? items.length) - earlierMissing), 0, file)
      return {...current, [missing.role]: items}
    })
    setMissingSources((current) => current.filter((item) => item !== missing))
  }
  async function guardProject(action: () => Promise<void>) {
    if (projectPromptRef.current) return
    if (projectDirty) { projectPromptRef.current = true; setProjectPrompt(() => action) }
    else await action()
  }
  async function resolveProjectPrompt(choice: 'save' | 'discard' | 'cancel') {
    if (projectBusy) return
    if (choice === 'cancel') { setProjectPrompt(null); projectPromptRef.current = false; return }
    setProjectBusy(true)
    try {
      if (choice === 'save' && !await saveProject()) return
      const next = projectPrompt
      setProjectPrompt(null); projectPromptRef.current = false
      await next?.()
    } finally { setProjectBusy(false) }
  }
  async function quitProject() {
    if (active.length && !await confirmAction('Quit with active conversions?', 'Active and queued conversions will be stopped when the application exits. Keep the app open to let them finish.')) return
    await finishQuit()
  }
  const menuAction = useRef<(id: string) => void>(() => {})
  menuAction.current = (id) => {
    if (projectPromptRef.current || projectBusy || projectSaving.current) return
    const actions: Record<string, () => Promise<void> | void> = {
      new: () => guardProject(newProject),
      'close-project': () => guardProject(newProject),
      quit: () => guardProject(quitProject),
      open: () => guardProject(openProject), save: async () => { await saveProject() },
      'save-as': async () => { await saveProject(true) }, run: submit,
      cancel: async () => {
        const target = active.find((item) => item.id === selectedJob)
        if (target) await cancelRun(target)
        else setMessage('Select an active run in Runs to cancel it.')
      },
      'cancel-pending': cancelPending,
      'delete-history': () => deleteAllRuns(false),
      'delete-files': () => deleteAllRuns(true),
      settings: () => setSection('settings'),
      explorer: () => setSettings((value) => ({ ...value, explorer: !value.explorer })),
      inspector: () => setSettings((value) => ({ ...value, inspector: !value.inspector })),
      tasks: () => setSettings((value) => ({ ...value, tasks: !value.tasks })),
      resources: async () => { setResources(await api.getResources()); setSection('resources') },
      docs: () => openExternal('https://cnag-biomedical-informatics.github.io/convert-pheno/'),
      github: () => openExternal('https://github.com/CNAG-Biomedical-Informatics/convert-pheno'),
    }
    if (actions[id]) void run(async () => { await actions[id]() })
  }
  useEffect(() => {
    if (!isTauri()) return
    const subscription = listen<string>('desktop-menu', (event) => menuAction.current(event.payload))
    return () => { void subscription.then((unlisten) => unlisten()) }
  }, [])
  useEffect(() => {
    if (isTauri()) return // Native accelerators already dispatch these actions.
    const listener = (event: KeyboardEvent) => {
      if (!(event.metaKey || event.ctrlKey)) return
      if (event.key === 'Enter') { event.preventDefault(); void run(submit) }
      if (event.key.toLowerCase() === 's') { event.preventDefault(); menuAction.current('save') }
      if (event.key.toLowerCase() === 'o') { event.preventDefault(); menuAction.current('open') }
    }
    window.addEventListener('keydown', listener)
    return () => window.removeEventListener('keydown', listener)
  })

  return <div className="desktop-shell">
    {projectPrompt && <dialog ref={(node) => { if (node && !node.open) { if (node.showModal) node.showModal(); else node.setAttribute('open', '') } }} aria-modal="true" aria-labelledby="project-prompt-title" className="project-modal" onCancel={(event) => { event.preventDefault(); void resolveProjectPrompt('cancel') }}>
      <h2 id="project-prompt-title">Save changes to {project?.filename || 'Untitled project'}?</h2>
      <p>Your input selections, pasted data, mapping edits and conversion settings have unsaved changes.</p>
      {error && <p role="alert">{error}</p>}
      <div className="input-actions"><button autoFocus disabled={projectBusy} onClick={() => void run(() => resolveProjectPrompt('cancel'))}>Cancel</button><button disabled={projectBusy} onClick={() => void run(() => resolveProjectPrompt('discard'))}>Discard</button><button className="primary" disabled={projectBusy} onClick={() => void run(() => resolveProjectPrompt('save'))}>Save</button></div>
    </dialog>}
    <header className="desktop-titlebar"><img src="/convert-pheno-mark.svg" alt="" /><strong>Convert-Pheno</strong><span>Clinical data conversion</span></header>
    <div className="desktop-toolbar">
      <button aria-label={settings.explorer ? 'Collapse left navigation' : 'Expand left navigation'} title={settings.explorer ? 'Collapse left navigation' : 'Expand left navigation'} aria-expanded={settings.explorer} aria-controls="workspace-navigation" onClick={() => setSettings((value) => ({ ...value, explorer: !value.explorer }))}>{settings.explorer ? <PanelLeftClose aria-hidden="true" /> : <PanelLeftOpen aria-hidden="true" />}</button>
      <button onClick={() => { setSection('workspace'); setTab('Conversion') }}><ArrowRightLeft aria-hidden="true" />Conversion</button>
      <RunActions label="Run management" toolbar>
        <button disabled={Boolean(pendingAction)} onClick={() => void run(() => deleteAllRuns(false))}><Trash2 aria-hidden="true" />Delete all from history</button>
        <button className="delete-run" disabled={Boolean(pendingAction)} onClick={() => void run(() => deleteAllRuns(true))}><Trash2 aria-hidden="true" />Delete all run files</button>
      </RunActions>
      {displayedRoute ? <div className="route-badges" aria-label="Conversion formats"><span className={`format-label format-${displayedRoute.source.id}`}>{displayedRoute.source.label}</span><span aria-hidden="true">→</span><span className={`format-label format-${displayedRoute.target.id}`}>{displayedRoute.target.label}</span>{browsingRun && job && <span className="run-context">Run {job.id.slice(0, 6)} · {new Date(job.created * 1000).toLocaleString()}</span>}</div>
        : <span className="route-title">{browsingRun ? job?.conversion : 'Connecting to the conversion engine'}</span>}
      {job && busy(job) && <button disabled={Boolean(pendingAction)} onClick={() => void run(() => cancelRun(job))}><Square aria-hidden="true" />Cancel selected run</button>}
    </div>
    <div className="desktop-body">
      {settings.explorer && <><aside id="workspace-navigation" className="workspace-tree" aria-label="Workspace explorer" style={{ width: navigationWidth, flexBasis: navigationWidth }}>
        <div className="workspace-tree-scroll">
        <h3><button className="tree-disclosure" aria-expanded={!collapsedGroups.sources} aria-controls="source-groups" onClick={() => toggleGroup('sources')}><span aria-hidden="true">{collapsedGroups.sources ? '\u25b8' : '\u25be'}</span>Sources</button></h3>
        <div id="source-groups" hidden={collapsedGroups.sources}>
        {!Object.keys(files).length && <p className="muted">Select files or load an example.</p>}
        {Object.entries(files).map(([role, items]) => <div key={role}><button className="tree-label tree-disclosure" aria-expanded={!collapsedGroups[`file:${role}`]} aria-controls={`source-group-${role}`} onClick={() => toggleGroup(`file:${role}`)}><span aria-hidden="true">{collapsedGroups[`file:${role}`] ? '\u25b8' : '\u25be'}</span>{route?.input.files.find((definition) => definition.name === role)?.label || role}</button><div id={`source-group-${role}`} hidden={collapsedGroups[`file:${role}`]}>{items.map((file) =>
          <button key={file.id} className="tree-file" title={file.filename} onClick={() => void run(() => inspectSource(file))}>{file.directory ? <Folder aria-hidden="true" /> : <FileText aria-hidden="true" />} {file.filename}</button>)}</div></div>)}
        </div>
        <h3><button className="tree-disclosure" aria-expanded={!collapsedGroups.runs} aria-controls="run-groups" onClick={() => toggleGroup('runs')}><span aria-hidden="true">{collapsedGroups.runs ? '\u25b8' : '\u25be'}</span>Runs <span>{jobs.length}</span></button></h3>
        <div id="run-groups" hidden={collapsedGroups.runs}>
        <div className="run-filter"><input aria-label="Find runs" placeholder="Find a run..." value={runQuery} onChange={(event) => setRunQuery(event.target.value)} /><small>{active.filter((item) => item.status === 'running').length} running · {active.filter((item) => item.status === 'queued').length} queued</small></div>
        {jobs.some((item) => item.status === 'queued') && <button className="cancel-pending" disabled={Boolean(pendingAction)} onClick={() => void run(cancelPending)}>Cancel all pending</button>}
        <div className="run-tree">{visibleJobs.map((item) => <div key={item.id} className="run-entry" data-selected={selectedJob === item.id || undefined}>
          <button aria-pressed={selectedJob === item.id} className="tree-run" onClick={() => {setSelectedJob(item.id);setSelectedOutput('');resetPreviews();setTab('Outputs');setSection('workspace')}}>
          <strong>{item.conversion}</strong><span className={`run-state ${item.status}`}>{item.status}{item.queuePosition ? ` · #${item.queuePosition}` : ''}</span><small>{new Date(item.created * 1000).toLocaleString()} · {item.id.slice(0, 6)}</small></button>
          <RunActions label={`Actions for ${item.conversion} ${item.id}`}>
            {['running', 'queued'].includes(item.status) && <button disabled={Boolean(pendingAction)} onClick={() => void run(() => cancelRun(item))}><Square aria-hidden="true" />{item.status === 'queued' ? 'Remove from queue' : 'Cancel run'}</button>}
            {item.status === 'cancelling' && <span><LoaderCircle aria-hidden="true" />Stopping...</span>}
            {item.status === 'completed' && <button onClick={() => void run(() => revealRun(item.id))}><FolderOpen aria-hidden="true" />Open output folder</button>}
            {['completed', 'failed', 'cancelled', 'interrupted'].includes(item.status) && <button onClick={() => void run(() => setUpAgain(item))}><RotateCcw aria-hidden="true" />Set up again</button>}
            <button className="delete-run" disabled={busy(item) || Boolean(pendingAction)} title={busy(item) ? 'Cancel the run and wait for it to stop first' : undefined} onClick={() => void run(() => deleteRun(item))}><Trash2 aria-hidden="true" />Delete from history</button>
            <button className="delete-run" disabled={busy(item) || Boolean(pendingAction)} onClick={() => void run(() => deleteRun(item, true))}><Trash2 aria-hidden="true" />Delete run and output files</button>
          </RunActions>
        </div>)}{runQuery && !visibleJobs.length && <p className="muted">No matching runs.</p>}</div>
        </div>
        </div>
        <nav className="workspace-nav" aria-label="Application">
          <button onClick={() => void run(async () => {setResources(await api.getResources());setSection('resources')})}><Database aria-hidden="true" />Resources</button>
          <button onClick={() => setSection('settings')}><SettingsIcon aria-hidden="true" />Settings</button>
          <a href="https://cnag-biomedical-informatics.github.io/convert-pheno/" onClick={(event)=>{event.preventDefault();void openExternal(event.currentTarget.href)}}><BookOpen aria-hidden="true" />Documentation</a>
          <a href="https://github.com/CNAG-Biomedical-Informatics/convert-pheno" onClick={(event)=>{event.preventDefault();void openExternal(event.currentTarget.href)}}><GitFork aria-hidden="true" />GitHub</a>
        </nav>
      </aside><div className="navigation-divider" role="separator" aria-label="Resize left navigation" aria-orientation="vertical" aria-controls="workspace-navigation" aria-valuemin={170} aria-valuemax={350} aria-valuenow={navigationWidth} tabIndex={0}
        title="Drag to resize; double-click to reset"
        onPointerDown={(event) => {
          if (event.button !== 0) return
          event.preventDefault()
          event.currentTarget.focus()
          event.currentTarget.setPointerCapture(event.pointerId)
          navigationDrag.current = { pointer: event.pointerId, x: event.clientX, width: navigationWidth }
        }}
        onPointerMove={(event) => {
          const drag = navigationDrag.current
          if (drag && drag.pointer === event.pointerId) resizeNavigation(drag.width + event.clientX - drag.x)
        }}
        onPointerUp={(event) => {
          if (event.currentTarget.hasPointerCapture(event.pointerId)) event.currentTarget.releasePointerCapture(event.pointerId)
          navigationDrag.current = null
        }}
        onPointerCancel={() => { navigationDrag.current = null }}
        onLostPointerCapture={() => { navigationDrag.current = null }}
        onDoubleClick={() => setNavigationWidth(225)}
        onKeyDown={(event) => {
          const width = { ArrowLeft: navigationWidth - 10, ArrowRight: navigationWidth + 10, Home: 170, End: 350, Enter: 225 }[event.key]
          if (width !== undefined) { event.preventDefault(); resizeNavigation(width) }
        }}
      /></>}
      <main className="desktop-content">
        {error && <div className="desktop-alert" role="alert">{error}<button aria-label="Dismiss error" onClick={()=>setError('')}>×</button></div>}
        {message && <div className="desktop-message" role="status">{message}<button aria-label="Dismiss message" onClick={()=>setMessage('')}>×</button></div>}
        {section === 'resources' ? <section className="settings-pane resources-pane"><h1>Terminology resources</h1><p>Small terminology databases are included with Convert-Pheno. Install OHDSI separately only for routes that use the OMOP vocabulary.</p>
          <section className="external-resource" aria-labelledby="ohdsi-resource"><div className="resource-heading"><div><span className="eyebrow">Optional database</span><h2 id="ohdsi-resource">Athena OHDSI vocabulary</h2></div><span className={`resource-status ${ohdsi?.installed ? 'installed' : 'missing'}`}>{ohdsi?.installed ? 'Installed' : 'Not installed'}</span></div>
            <dl><div><dt>Content version</dt><dd>{ohdsi?.contentVersion || 'Current supported bundle'}</dd></div><div><dt>Download size</dt><dd>{ohdsi?.byteSize ? size(ohdsi.byteSize) : 'About 3.2 GB'}</dd></div></dl>
            <p>Download and install the database here, or select a copy you already have.</p>
            <p>Resource folder: <code className="resource-path">{resourcePath || 'Loading...'}</code></p>
            <button disabled={resourceInstalling || resourceChanging || hasActiveJobs} onClick={() => void run(changeResourceFolder)}><FolderOpen aria-hidden="true" />{resourceChanging ? 'Changing folder...' : 'Change folder...'}</button>
            <p className="resource-note">Existing files are not moved. Folder changes are available when downloads and conversions have finished.</p>
            <div className="resource-actions">
              <button className="primary" disabled={resourceInstalling || resourceChanging} onClick={() => void run(() => installOhdsiResource(true))}><Download aria-hidden="true" />{ohdsi?.installed ? 'Download and reinstall' : 'Download and install'}</button>
              <button disabled={resourceInstalling || resourceChanging} onClick={() => void run(() => installOhdsiResource())}><Database aria-hidden="true" />Install from file...</button>
              {downloadProgress && <button disabled={downloadCancelling} onClick={() => { setDownloadCancelling(true); void run(cancelOhdsiDownload) }}><Square aria-hidden="true" />{downloadCancelling ? 'Cancelling...' : 'Cancel download'}</button>}
            </div>
            {downloadProgress && <div><progress aria-label="OHDSI download progress" value={downloadProgress.completedBytes} max={downloadProgress.totalBytes || 1} /><p>{size(downloadProgress.completedBytes)} / {size(downloadProgress.totalBytes)} downloaded</p></div>}
            <p className="resource-note" role="status" aria-live="polite">{resourceInstalling ? (downloadProgress ? 'Downloading and checking the database. Keep Convert-Pheno open until installation finishes.' : 'Verifying and installing the selected database...') : 'The file size and SHA-256 checksum are checked before installation. The database is stored outside the application bundle.'}</p>
          </section>
          <details className="bundled-resources"><summary>Included terminology databases ({bundledResources.length})</summary><table><thead><tr><th>Resource</th><th>Version</th><th>Status</th></tr></thead><tbody>{bundledResources.map((item)=><tr key={item.id}><td>{item.id.toUpperCase()}</td><td>{item.contentVersion}</td><td><span className={`resource-status ${item.installed ? 'installed' : 'missing'}`}>{item.installed?'Included':'Unavailable'}</span></td></tr>)}</tbody></table></details>
        </section> : section === 'settings' ? <section className="settings-pane"><h1>Settings</h1>
          <h2>Appearance</h2><div className="appearance-settings">
            <label>Theme<select value={settings.theme} onChange={(event) => setSettings({ ...settings, theme: event.target.value as ThemeChoice })}><option value="system">Follow system</option><option value="light">Light</option><option value="dark">Dark</option></select></label>
            <label><input type="checkbox" checked={settings.explorer} onChange={(event) => setSettings({ ...settings, explorer: event.target.checked })} />Show workspace explorer</label>
            <label><input type="checkbox" checked={settings.inspector} onChange={(event) => setSettings({ ...settings, inspector: event.target.checked })} />Show record inspector</label>
            <label><input type="checkbox" checked={taskPanel} onChange={(event)=>setTaskPanel(event.target.checked)} />Show task panel</label>
          </div><p>Appearance settings are remembered on this device.</p>
          <JobSettings />
          <p>Inputs remain unchanged. Results are written into a separate run directory.</p></section> : <>
          <nav className="workspace-tabs" aria-label="Workspace views">{tabs.map((item)=><button key={item} aria-current={item===tab?'page':undefined} onClick={()=>setTab(item)}>{item}{item==='Warnings'&&job?.result?.warnings.length ? ` (${job.result.warnings.length})`:''}</button>)}</nav>
          <div className="workspace-view">
            {!!missingSources.length && <section aria-label="Missing project files"><h2>Missing project files</h2>{missingSources.map((item, index) => <p key={index}><code>{item.path}</code> <button onClick={() => void run(() => locateSource(item))}>Locate missing file</button></p>)}</section>}
            {tab === 'Conversion' && route && <section className="conversion-editor">
              <header className="conversion-heading"><div><h1>Build your conversion</h1><p>Choose the source, add your files, and configure the output.</p></div><ArrowRightLeft aria-hidden="true" /></header>
              <div className="conversion-grid">
              <section className="conversion-card route-card" aria-labelledby="route-heading">
              <header className="step-heading"><span aria-hidden="true">1</span><div><h2 id="route-heading">Choose a route</h2><p>Select the data model you have and the output you need.</p></div></header>
              <div className="route-fields"><label>Source format<select value={route.source.id} onChange={(event)=>{const next=routes.find((item)=>item.source.id===event.target.value);if(next)selectRoute(next)}}>{sources.map((item)=><option value={item.id} key={item.id}>{item.label}</option>)}</select></label>
                <span aria-hidden="true">→</span><label>Target format<select value={route.id} onChange={(event)=>{const next=routes.find((item)=>item.id===event.target.value);if(next)selectRoute(next)}}>{routes.filter((item)=>item.source.id===route.source.id).map((item)=><option value={item.id} key={item.id}>{item.target.label}</option>)}</select></label></div>
              {route.maturity && <p className="maturity">Source profile: {route.maturity}</p>}
              {!route.available && <p className="desktop-alert">{route.unavailableReason}</p>}
              <p className="source-explanation"><strong>Expected input</strong>{route.source.inputShape}</p>
              </section>
              <section className="conversion-card input-card" aria-labelledby="files-heading">
              <header className="step-heading"><span aria-hidden="true">2</span><div><h2 id="files-heading">Add your input</h2><p>Source files remain unchanged.</p></div></header>
              {route.input.files.map((definition)=><div className="file-selection" key={definition.name}><div><strong>{definition.label}{definition.required?' *':''}</strong>{definition.description && <small>{definition.description}</small>}<small>{files[definition.name]?.map((item)=>item.filename).join(', ') || 'No file selected'}</small></div><button onClick={()=>void run(()=>choose(definition.name,false,definition.multiple))}>Browse...</button>
                {definition.name==='source' && ['omop','i2b2','pcornet','sentinel','cbioportal'].includes(route.source.id) && <button onClick={()=>void run(()=>choose(definition.name,true))}>Folder...</button>}</div>)}
              <button onClick={()=>void run(example)}>Load synthetic example</button>
              {jsonInput.trim() && <p className="input-loaded">JSON input loaded. <button onClick={() => { resetPreviews(); setTab('Input') }}>Inspect input</button></p>}
              </section>
              <section className="conversion-card output-card" aria-labelledby="output-heading">
              <header className="step-heading"><span aria-hidden="true">3</span><div><h2 id="output-heading">Configure output</h2><p>Only settings supported by this route are shown.</p></div></header>
              <div className="file-selection"><div><strong>Output location</strong><small className="output-path">{destination ? destination.displayPath || destination.filename : outputRoot || 'Locating application output folder...'}</small><small>{destination ? 'A new convert-pheno-<run-id> subfolder will be created here.' : 'Each run gets its own <run-id>/outputs subfolder here.'}</small></div><button onClick={()=>void run(async()=>{const [chosen]=await selectPaths(true);if(chosen)setDestination(chosen)})}>Choose folder...</button>{destination && <button onClick={() => setDestination(undefined)}>Use default folder</button>}</div>
              {route.entities.supported.length>0 && <fieldset><legend>Beacon entities</legend>{route.entities.supported.map((entity)=><label key={entity}><input type="checkbox" checked={draft.output.entities?.includes(entity)||false} onChange={(event)=>setDraft((current)=>({...current,output:{entities:event.target.checked?[...(current.output.entities||[]),entity]:(current.output.entities||[]).filter((item)=>item!==entity)}}))}/>{entity}</label>)}</fieldset>}
              {route.options.some((option)=>option.name==='term_audit') && <label><input type="checkbox" checked={draft.options.term_audit==='xlsx'} onChange={(event)=>setDraft((current)=>({...current,options:{...current.options,term_audit:event.target.checked?'xlsx':'none'}}))}/>Create terminology audit (adds processing time)</label>}
              <ConversionOptions definitions={route.options} values={draft.options} onChange={options => setDraft(current => ({...current, options}))} />
              </section>
              <section className="conversion-card review-card" aria-labelledby="review-heading">
                <header className="step-heading"><span aria-hidden="true">4</span><div><h2 id="review-heading">Review and convert</h2><p>Check the configuration, then start the conversion.</p></div></header>
                <dl className="conversion-summary"><div><dt>Source</dt><dd>{route.source.label}</dd></div><div><dt>Output</dt><dd>{route.target.label}</dd></div><div><dt>Input</dt><dd>{jsonInput.trim() ? 'JSON payload' : `${Object.values(files).flat().length} selected files`}</dd></div></dl>
                <p className="muted">Outputs and any terminology report will appear under Runs.</p>
                <button className="primary run-conversion" disabled={!route.available || submitting || !ready} onClick={() => void run(submit)}><Play aria-hidden="true" />{submitting ? 'Submitting...' : 'Run conversion'}</button>
              </section>
              </div>
            </section>}
            {(tab === 'Input' || tab === 'Mapping') && <div className="input-actions"><button className="primary" onClick={() => setTab('Conversion')}><ArrowRightLeft aria-hidden="true" />Back to conversion</button></div>}
            {tab === 'Input' && <section className="input-pane">{sourcePreview ? <><div className="pane-heading"><FileText aria-hidden="true" /><h1>{sourcePreview.file.filename}</h1><span className="read-only-label">Read-only preview</span></div>{sourcePreview.data ? <DataView key={sourcePreview.file.id} preview={sourcePreview.data} onInspect={inspect} source={sourcePreview.file.filename} conceptFields={route?.source.id === 'omop' ? route.omopConceptFields : []}/> : <p role="status">Loading input preview...</p>}</> : <>
              {jsonInput && !pasteInput ? <>
                <div className="pane-heading"><h1>Input preview</h1><span className="read-only-label">Read-only preview</span></div>
                <p>This is the {route?.source.label} data selected for conversion. You do not need to paste anything.</p>
                <div className="input-actions"><button onClick={() => setPasteInput(true)}>Edit JSON</button></div>
                <DataView preview={{text: jsonInput, truncated: false, kind: 'json'}} onInspect={inspect} />
              </> : <>
              <h1>Input data</h1>
              <p>{Object.values(files).flat().length ? 'Your input files are already loaded. Preview them below, then return to Conversion to review and run. Loading the example again replaces the current selection.' : `Add your ${route?.source.label} files, or load a synthetic example to see the expected structure.`}</p>
              <div className="input-actions"><button onClick={() => setTab('Conversion')}><FolderOpen aria-hidden="true" />Add files</button><button disabled={!route} onClick={() => void run(example)}><FileText aria-hidden="true" />Load synthetic example</button>
                {route?.input.transports.includes('json') && !Object.values(files).flat().length && !pasteInput && !jsonInput && <button onClick={() => setPasteInput(true)}>Paste JSON instead</button>}
              </div>
              {!!Object.values(files).flat().length && <><h2>Selected files</h2><p>Choose a file to preview it without changing the original.</p><div className="input-files">{Object.values(files).flat().map((file) => <button key={file.id} onClick={() => void run(() => inspectSource(file))}><FileText aria-hidden="true" />{file.filename}</button>)}</div></>}
              {route?.input.transports.includes('json') && pasteInput && <div className="paste-input"><h2>{route.source.label} JSON</h2><p id="json-input-help">{route.source.inputShape}. Paste the data itself, not an API request or a filename. Load the example above if you are unsure of the structure.</p><textarea className="code-editor" aria-label="JSON input" aria-describedby="json-input-help" placeholder={`Paste your ${route.source.label} JSON here`} value={jsonInput} onChange={(event) => setJsonInput(event.target.value)} spellCheck={false}/><div className="input-actions"><button disabled={!jsonInput.trim()} onClick={() => void run(async () => { JSON.parse(jsonInput); setPasteInput(false) })}>View input</button></div><p className="muted">Pasted data is saved in the project's companion data folder.</p></div>}
              </>}
            </>}</section>}
            {tab === 'Mapping' && <>{!mapping && route?.input.files.some((file)=>file.name==='mapping') && <button onClick={()=>void run(example)}>Load synthetic example</button>}<Suspense fallback={<p role="status">Loading mapping editor...</p>}><MappingEditor key={route?.id} value={mapping} filename={files.mapping?.[0]?.filename} dirty={mappingDirty} onChange={(text) => { mappingEpoch.current++; setMapping(text); setMappingDirty(true) }} onValidate={validateMapping} onSave={saveMappingCopy}/></Suspense></>}
            {tab === 'Outputs' && <section className="output-pane">{!job?<div className="empty-state"><h1>Inspect converted data</h1><p>Configure a conversion or select a previous run.</p></div>:<><div className="pane-heading"><h1>{job.conversion}</h1><span className={`run-state ${job.status}`}>{job.status}</span>{job.status==='completed'&&<button onClick={()=>void run(()=>revealRun(job.id))}>Open containing folder</button>}</div>
              {job.message&&<p role="status">{job.message}</p>}
              {job.status === 'completed' && <div className="result-summary" aria-label="Output summary"><span><strong>{outputs.length}</strong> output {outputs.length === 1 ? 'file' : 'files'}</span><span>{size(outputs.reduce((total, file) => total + file.bytes, 0))}</span>{job.result?.warnings.length ? <button onClick={() => setTab('Warnings')}>{job.result.warnings.length} {job.result.warnings.length === 1 ? 'warning' : 'warnings'}</button> : <span>No warnings recorded</span>}</div>}
              {(job.directory || job.outputDirectory) && <div className="run-output-location"><strong>{job.status === 'completed' ? 'Saved to' : 'Output destination'}</strong><code>{job.directory || job.outputDirectory}</code></div>}
              <div className="output-workspace"><div className="output-files"><h2>Output files</h2>{outputs.map((file)=><button aria-pressed={selectedOutput===file.id} key={file.id} onClick={()=>void run(()=>inspectOutput(job.id,file.id))}><FileText aria-hidden="true" /><strong>{file.filename}</strong><small><span className={`format-label format-${file.kind}`}>{file.kind.toUpperCase()}</span> {size(file.bytes)}</small></button>)}</div><div className="output-preview">
                {selectedOutput&&resultPreview?.job===job.id&&resultPreview.id===selectedOutput ? <>
                  <div className="output-preview-heading"><strong>{outputs.find((file)=>file.id===selectedOutput)?.filename}</strong><button onClick={()=>void run(()=>api.downloadOutput(job.id,selectedOutput,outputs.find((file)=>file.id===selectedOutput)!.filename))}><Save aria-hidden="true" />Save a copy...</button></div>
                  {resultPreview.data ? <DataView key={`${job.id}:${selectedOutput}`} preview={resultPreview.data} onInspect={inspect} source={outputs.find((file)=>file.id===selectedOutput)?.filename} conceptFields={jobRoute?.target.id === 'omop' ? jobRoute.omopConceptFields : []}/>
                    : resultPreview.error ? <div className="empty-state"><p role="alert">{resultPreview.error}</p><button onClick={() => void inspectOutput(job.id, selectedOutput)}>Retry preview</button></div>
                    : <p role="status">Loading output preview...</p>}
                </> : <div className="empty-state"><FileText aria-hidden="true" /><h2>{busy(job)?'Conversion in progress':'Your converted files'}</h2><p>{busy(job)?'You can continue navigating while the engine works.':'Select a file on the left to inspect its records or save a copy.'}</p></div>}
              </div></div></>}</section>}
            {tab === 'Terminology Review' && (job?.result?.meta.terminologyAudit ? <TerminologyReview key={job.id} audit={job.result.meta.terminologyAudit} report={{...outputs.find((file)=>file.id===job.result?.meta.terminologyAudit?.reportArtifactId)!,content:'',encoding:'utf-8'} as Artifact} onHelp={() => void run(() => openExternal('https://cnag-biomedical-informatics.github.io/convert-pheno/terminology-search'))} onDownload={(file)=>void run(()=>api.downloadOutput(job.id,file.id,file.filename))}/>:<div className="empty-state"><h1>Terminology review</h1><p>Enable Create terminology audit before running a supported conversion, then select the completed run here. Auditing is optional because it adds processing time.</p></div>)}
            {tab === 'Warnings' && <section className="settings-pane"><h1>Conversion warnings</h1>{job?.result?.warnings.length?<ul>{job.result.warnings.map((warning,index)=><li key={index}>{warning}</li>)}</ul>:<p>No warnings are recorded for this selection.</p>}</section>}
            {tab === 'Compare' && <section className="settings-pane"><h1>Compare runs</h1><p>Compare configuration and terminology review counts. This is not a claim of semantic equivalence.</p><select aria-label="Comparison run" value={comparison} onChange={(event)=>setComparison(event.target.value)}><option value="">Select another run</option>{jobs.filter((item)=>item.id!==selectedJob).map((item)=><option key={item.id} value={item.id}>{item.conversion} · {new Date(item.created*1000).toLocaleString()}</option>)}</select><div className="comparison">{[job,other].map((item,index)=><div key={index}><h2>{item?.conversion || 'Select a run'}</h2>{item&&<pre>{JSON.stringify({options:item.options,entities:item.output,outputs:item.result?.artifacts.map((file)=>file.filename),terminology:item.result?.meta.terminologyAudit?.counts},null,2)}</pre>}</div>)}</div></section>}
          </div>
        </>}
      </main>
      {settings.inspector && <aside className="record-inspector" aria-label="Record inspector"><div className="pane-heading"><h2>Inspector</h2>{inspection && <CopyButton text={inspectionText} label="Copy inspected value" />}<button onClick={()=>setInspection(undefined)} aria-label="Clear inspector">×</button></div>{inspection?<><h3>{inspection.name}</h3>{inspection.source && <p className="inspection-source">{inspection.source} · row {inspection.row}</p>}<pre>{inspectionText}</pre>{inspection.conceptId !== undefined && <ConceptDetails id={inspection.conceptId}/>}</>:<p>Select a cell to inspect its value. OMOP concept cells also offer a vocabulary lookup.</p>}{job&&<details><summary>Run provenance</summary><pre>{JSON.stringify({engine:job.engineVersion,sources:job.fingerprints},null,2)}</pre></details>}</aside>}
    </div>
    {taskPanel&&<section className="task-panel" aria-label="Tasks"><strong>Tasks</strong>{active.length?active.map((item)=><span key={item.id}>{item.conversion}: {item.status}</span>):<span>No active conversions</span>}<button onClick={()=>setTaskPanel(false)}>Hide</button></section>}
    <footer className="desktop-status"><span><i className={ready?'status-ready':''}/>{ready?'Local engine connected':'Connecting to local engine'}</span><span>{mappingDirty?'Mapping has unused edits':'Source files are read-only'} · {routes.length} routes</span></footer>
  </div>
}
