import { beforeEach, describe, expect, it } from 'vitest'
import { defaults, readSettings, saveSettings } from './settings'

describe('desktop appearance settings', () => {
  beforeEach(() => localStorage.clear())
  it('follows the system on a new installation', () => { expect(readSettings()).toEqual(defaults) })
  it.each(['light', 'dark', 'system'] as const)('remembers %s and panel visibility', (theme) => {
    const settings = { theme, explorer: false, inspector: true, tasks: false }
    saveSettings(settings)
    expect(readSettings()).toEqual(settings)
  })
  it('recovers from corrupt storage', () => {
    localStorage.setItem('convert-pheno.desktop.settings', '{')
    expect(readSettings()).toEqual(defaults)
  })
  it('ignores invalid setting types and unknown theme names', () => {
    localStorage.setItem('convert-pheno.desktop.settings', JSON.stringify({ theme: 'purple', tasks: 'false', explorer: null }))
    expect(readSettings()).toEqual(defaults)
  })
})
