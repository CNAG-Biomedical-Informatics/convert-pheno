import { connection } from './desktop'
import { isTauri, invoke } from '@tauri-apps/api/core'
import type { ConceptLookup, Conversion, FileHandle, Job, Preview, Resource } from './types'

export async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  const service = await connection()
  const response = await fetch(service.url + path, {
    ...init, headers: { Accept: 'application/json', Authorization: `Bearer ${service.token}`, ...init.headers },
  })
  const body = await response.json()
  if (!response.ok || body.ok === false) throw new Error(body.error?.message || `Request failed (${response.status})`)
  return body.data as T
}
export const post = <T,>(path: string, body: unknown) =>
  request<T>(path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
export const getConversions = () => request<Conversion[]>('/api/conversions')
export const listJobs = () => request<Job[]>('/api/jobs')
export const getResources = () => request<Resource[]>('/api/resources')
export const lookupConcept = (id: string) => request<ConceptLookup>(`/api/ontology/omop/${encodeURIComponent(id)}`)
export const cancelJob = (id: string) => post<Job>(`/api/jobs/${id}/cancel`, {})
export const deleteJob = (id: string) => request(`/api/jobs/${encodeURIComponent(id)}`, { method: 'DELETE' })
export const deleteJobFiles = (id: string) => request(`/api/jobs/${encodeURIComponent(id)}/files`, { method: 'DELETE' })
export type RunDeletion = { deleted: string[]; skipped: string[]; failed: { id: string; message: string }[] }
export const deleteAllJobs = (files: boolean) => files ? post<RunDeletion>('/api/jobs/delete-all-files', {}) : request<RunDeletion>('/api/jobs', { method: 'DELETE' })
export const cancelPendingJobs = () => post<Job[]>('/api/jobs/cancel-pending', {})
export const inputPreview = (id: string) => request<Preview>(`/api/inputs/${id}/preview`)
export const outputPreview = (job: string, id: string) => request<Preview>(`/api/jobs/${job}/outputs/${encodeURIComponent(id)}/preview`)
export const submitJob = (body: unknown) => post<Job>('/api/jobs', body)
export async function uploadFiles(files: File[]): Promise<FileHandle[]> {
  const body = new FormData()
  for (const file of files) body.append('file', file)
  return request<FileHandle[]>('/api/inputs', { method: 'POST', body })
}
export async function getExample(source: string, transport = 'auto'): Promise<unknown> {
  return request<unknown>(`/examples/${source}?transport=${transport}`)
}
export async function downloadOutput(job: string, id: string, filename: string) {
  if (!isTauri()) throw new Error('Launch Convert-Pheno as a desktop application.')
  await invoke('save_output', { job, artifact: id, filename })
}
