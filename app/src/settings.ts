export type ThemeChoice = 'system' | 'light' | 'dark'
export type Settings = { theme: ThemeChoice; explorer: boolean; inspector: boolean; tasks: boolean }
const KEY = 'convert-pheno.desktop.settings'
export const defaults: Settings = { theme: 'system', explorer: true, inspector: true, tasks: true }
export function readSettings(): Settings {
  try {
    const value = JSON.parse(localStorage.getItem(KEY) || '{}')
    return {
      theme: ['system', 'light', 'dark'].includes(value.theme) ? value.theme : defaults.theme,
      explorer: typeof value.explorer === 'boolean' ? value.explorer : defaults.explorer,
      inspector: typeof value.inspector === 'boolean' ? value.inspector : defaults.inspector,
      tasks: typeof value.tasks === 'boolean' ? value.tasks : defaults.tasks,
    }
  } catch { return { ...defaults } }
}
export function saveSettings(settings: Settings): void { localStorage.setItem(KEY, JSON.stringify(settings)) }
