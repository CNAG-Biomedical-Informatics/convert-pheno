import { useEffect, useRef, useState } from 'react'
import { basicSetup } from 'codemirror'
import { EditorState, Compartment } from '@codemirror/state'
import { EditorView, keymap } from '@codemirror/view'
import { indentWithTab } from '@codemirror/commands'
import { yaml } from '@codemirror/lang-yaml'
import { indentUnit, HighlightStyle, syntaxHighlighting } from '@codemirror/language'
import { tags } from '@lezer/highlight'
import { openSearchPanel } from '@codemirror/search'
import { setDiagnostics } from '@codemirror/lint'
import { Check, Save, Search } from 'lucide-react'

export function errorLine(message: string): number | undefined {
  const found = message.match(/\bline\s*:\s*(\d+)|\bline\s+(\d+)\s*,?\s+column/i)
  const line = Number(found?.[1] || found?.[2])
  return line > 0 ? line : undefined
}
export default function MappingEditor({ value, filename, dirty, onChange, onValidate, onSave }: {
  value: string; filename?: string; dirty: boolean; onChange: (value: string) => void
  onValidate: (value: string) => Promise<void>; onSave: (value: string) => Promise<string | null>
}) {
  const host = useRef<HTMLDivElement>(null)
  const editor = useRef<EditorView>(null)
  const change = useRef(onChange); change.current = onChange
  const editable = useRef(new Compartment())
  const [busy, setBusy] = useState(false)
  const [problem, setProblem] = useState('')
  const [notice, setNotice] = useState('')
  const [line, setLine] = useState<number>()
  function createState(doc: string) {
    return EditorState.create({doc, extensions: [
      basicSetup, yaml(), indentUnit.of('  '), keymap.of([indentWithTab]),
      editable.current.of(EditorView.editable.of(true)),
      syntaxHighlighting(HighlightStyle.define([
        {tag: [tags.propertyName, tags.attributeName], color: 'var(--desk-accent)'},
        {tag: [tags.string], color: 'var(--desk-success)'},
        {tag: [tags.number, tags.bool, tags.null], color: 'var(--desk-warning)'},
        {tag: tags.comment, color: 'var(--desk-muted)', fontStyle: 'italic'},
      ])),
      EditorView.contentAttributes.of({'aria-label': 'Mapping editor', 'aria-multiline': 'true', role: 'textbox'}),
      EditorView.updateListener.of((update) => {
        if (update.docChanged) { change.current(update.state.doc.toString()); setProblem(''); setNotice(''); setLine(undefined) }
      }),
    ]})
  }
  useEffect(() => {
    const view = new EditorView({state: createState(value), parent: host.current!})
    editor.current = view
    return () => { view.destroy(); editor.current = null }
  }, [])
  useEffect(() => {
    if (editor.current) editor.current.dispatch(setDiagnostics(editor.current.state, []))
    if (editor.current && editor.current.state.doc.toString() !== value) {
      // Loading another document must not let Undo restore the previous mapping.
      editor.current.setState(createState(value)); setProblem(''); setNotice(''); setLine(undefined)
    }
  }, [value])
  useEffect(() => { editor.current?.dispatch({effects: editable.current.reconfigure(EditorView.editable.of(!busy))}) }, [busy])
  async function action(validate: boolean) {
    if (busy) return
    setBusy(true); setProblem(''); setNotice(''); setLine(undefined)
    editor.current?.dispatch(setDiagnostics(editor.current.state, []))
    try {
      if (validate) { await onValidate(value); setNotice('Mapping validation passed. This copy will be used for the next run.') }
      else { const saved = await onSave(value); if (saved) setNotice(`Saved to ${saved}. ${dirty ? 'Validate the edited mapping before running.' : ''}`) }
    } catch (reason) {
      const message = (reason as Error).message
      setProblem(message)
      const at = errorLine(message)
      if (editor.current && at && at <= editor.current.state.doc.lines) {
        setLine(at)
        const location = editor.current.state.doc.line(at)
        editor.current.dispatch(setDiagnostics(editor.current.state, [{from: location.from, to: location.to, severity: 'error', message}]))
      }
    } finally { setBusy(false) }
  }
  return <section className="mapping-pane">
    <div className="pane-heading"><h1>Mapping file</h1><span className="read-only-label">{dirty ? 'Unvalidated edits' : 'Selected mapping'}</span></div>
    <p>{filename || 'Load a mapping in Conversion, or start with a synthetic example.'} Edits never overwrite the original.</p>
    <div className="mapping-actions">
      <button disabled={busy || !value.trim()} onClick={() => void action(true)}><Check aria-hidden="true" />{busy ? 'Working...' : 'Validate and use copy'}</button>
      <button disabled={busy || !value.trim()} onClick={() => void action(false)}><Save aria-hidden="true" />Save as...</button>
      <button onClick={() => { if (editor.current) openSearchPanel(editor.current) }}><Search aria-hidden="true" />Find</button>
    </div>
    {problem && <div className="mapping-error" role="alert"><strong>Mapping could not be validated or saved</strong><pre>{problem}</pre>{line && <button onClick={() => { if (editor.current) { const at = editor.current.state.doc.line(line).from; editor.current.dispatch({selection: {anchor: at}, scrollIntoView: true}); editor.current.focus() } }}>Go to line {line}</button>}</div>}
    {notice && <p role="status">{notice}</p>}
    <div ref={host} className="mapping-code-editor" />
    <p className="muted">YAML · two-space indentation · Ctrl/Cmd+F to find · Ctrl/Cmd+Z to undo. Validation uses the Convert-Pheno engine.</p>
  </section>
}
