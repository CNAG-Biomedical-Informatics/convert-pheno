import { invoke, isTauri } from '@tauri-apps/api/core'
import type { FileHandle } from './types'

export type Connection = { url: string; token: string; outputRoot: string }
let pending: Promise<Connection> | undefined
export function connection(): Promise<Connection> {
  if (!isTauri()) return Promise.reject(new Error('Launch Convert-Pheno as a desktop application.'))
  if (!pending) pending = invoke<Connection>('connection')
  return pending
}
export async function selectPaths(directory = false, multiple = false): Promise<FileHandle[]> {
  if (!isTauri()) throw new Error('Native file selection requires the Convert-Pheno desktop app.')
  return invoke<FileHandle[]>('select_paths', { directory, multiple })
}
export async function revealRun(id: string): Promise<void> {
  if (!isTauri()) throw new Error('Open the output folder from the desktop application.')
  await invoke('reveal_run', { id })
}
export async function saveMappingCopy(text: string): Promise<string | null> {
  if (!isTauri()) throw new Error('Save mapping copies from the desktop application.')
  return invoke<string | null>('save_mapping_copy', { text })
}
export async function openExternal(url: string): Promise<void> {
  if (!isTauri()) throw new Error('Launch Convert-Pheno as a desktop application.')
  await invoke('open_external', { url })
}
export async function confirmAction(title: string, message: string): Promise<boolean> {
  if (!isTauri()) throw new Error('Launch Convert-Pheno as a desktop application.')
  return invoke<boolean>('confirm_action', { title, message })
}
export async function installOhdsi(): Promise<string | null> {
  if (!isTauri()) throw new Error('Install terminology resources from the Convert-Pheno desktop app.')
  return invoke<string | null>('install_ohdsi')
}
