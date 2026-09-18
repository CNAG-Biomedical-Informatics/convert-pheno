import { useEffect, useState } from 'react'
import { getJobSettings, updateJobSettings, type JobSettings as SchedulerSettings } from '../api'

export default function JobSettings() {
  const [settings, setSettings] = useState<SchedulerSettings>()
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [attempt, setAttempt] = useState(0)
  useEffect(() => {
    let current = true
    setError('')
    getJobSettings().then(value => { if (current) setSettings(value) })
      .catch((reason: Error) => { if (current) setError(reason.message) })
    return () => { current = false }
  }, [attempt])

  async function change(limit: number) {
    setSaving(true); setError('')
    try { setSettings(await updateJobSettings(limit)) }
    catch (reason) { setError((reason as Error).message) }
    finally { setSaving(false) }
  }

  return <section aria-labelledby="job-settings-heading">
    <h2 id="job-settings-heading">Conversions</h2>
    <div className="appearance-settings">
      {settings ? <label>Maximum concurrent jobs
        <select value={settings.maxConcurrentJobs} disabled={saving}
          aria-describedby="job-settings-help" onChange={event => void change(Number(event.target.value))}>
          {Array.from({ length: settings.maxAllowedConcurrentJobs }, (_, index) => index + 1)
            .map(value => <option key={value} value={value}>{value}{value === 1 ? ' (default)' : ''}</option>)}
        </select>
      </label> : !error && <p role="status">Loading conversion settings...</p>}
      {settings && <p>Available limit on this machine: {settings.maxAllowedConcurrentJobs} simultaneous jobs, based on available logical CPUs (up to 16).</p>}
      <p id="job-settings-help">Each conversion generally uses one CPU core. Increase this limit to run more conversions at once. Higher limits also require more memory.</p>
      <p>The setting is remembered on this device. Lowering it lets running jobs finish before more queued jobs start; it does not reserve CPU cores.</p>
      {saving && <p role="status">Saving conversion settings...</p>}
      {error && <p role="alert">{error}</p>}
      {!settings && error && <button onClick={() => setAttempt(value => value + 1)}>Retry loading settings</button>}
    </div>
  </section>
}
