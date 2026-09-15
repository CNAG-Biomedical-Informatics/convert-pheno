import { useEffect, useRef, useState, type ReactNode } from 'react'
import { Ellipsis } from 'lucide-react'

export default function RunActions({ label, children, toolbar = false }: { label: string; children: ReactNode; toolbar?: boolean }) {
  const [open, setOpen] = useState(false)
  const root = useRef<HTMLDivElement>(null)
  const trigger = useRef<HTMLButtonElement>(null)
  useEffect(() => {
    if (!open) return
    const outside = (event: PointerEvent) => { if (!root.current?.contains(event.target as Node)) setOpen(false) }
    const escape = (event: KeyboardEvent) => { if (event.key === 'Escape') { setOpen(false); trigger.current?.focus() } }
    document.addEventListener('pointerdown', outside)
    document.addEventListener('keydown', escape)
    return () => { document.removeEventListener('pointerdown', outside); document.removeEventListener('keydown', escape) }
  }, [open])
  return <div className={`run-action-disclosure${toolbar ? ' toolbar-run-actions' : ''}`} ref={root}>
    <button className="run-more" ref={trigger} aria-label={label} title={label} aria-expanded={open} onClick={() => setOpen(!open)}><Ellipsis aria-hidden="true" />{toolbar && 'Runs'}</button>
    {open && <div className="run-action-menu" role="group" aria-label={label} onClick={(event) => {
      if ((event.target as HTMLElement).closest('button:not(:disabled)')) { setOpen(false); trigger.current?.focus() }
    }}>{children}</div>}
  </div>
}
