import { useEffect, useState } from 'react'
import { writeText } from '@tauri-apps/plugin-clipboard-manager'
import { Check, Copy } from 'lucide-react'

export default function CopyButton({ text, label }: { text: string; label: string }) {
  const [result, setResult] = useState<{ text: string; status: 'copying' | 'copied' | 'failed' }>()
  const status = result?.text === text ? result.status : undefined
  useEffect(() => {
    if (status !== 'copied') return
    const timer = window.setTimeout(() => setResult(undefined), 2000)
    return () => window.clearTimeout(timer)
  }, [status, text])

  async function copy() {
    setResult({ text, status: 'copying' })
    try {
      await writeText(text)
      setResult({ text, status: 'copied' })
    } catch {
      setResult({ text, status: 'failed' })
    }
  }

  return <span className="copy-control">
    <button type="button" aria-label={label} title={label} disabled={!text || status === 'copying'} onClick={() => void copy()}>
      {status === 'copied' ? <Check aria-hidden="true" /> : <Copy aria-hidden="true" />}
    </button>
    {status === 'copied' && <span role="status">Copied</span>}
    {status === 'failed' && <span role="alert">Could not copy. Try again.</span>}
  </span>
}
