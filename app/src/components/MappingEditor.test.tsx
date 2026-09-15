import { act, fireEvent, render, screen } from '@testing-library/react'
import { it, expect, vi } from 'vitest'
import { EditorView } from '@codemirror/view'
import MappingEditor, { errorLine } from './MappingEditor'

it('renders YAML with line numbers, edits and sends exact text for validation and save', async () => {
  const onChange=vi.fn(), onValidate=vi.fn().mockResolvedValue(undefined), onSave=vi.fn().mockResolvedValue('/synthetic/reviewed.yaml')
  const props={value:'mappingVersion: 2\n',dirty:false,onChange,onValidate,onSave}
  const {rerender}=render(<MappingEditor {...props}/>)
  expect(document.querySelector('.cm-lineNumbers')).toBeInTheDocument()
  const editor=EditorView.findFromDOM(screen.getByRole('textbox', {name:'Mapping editor'}))!
  act(() => editor.dispatch({changes:{from:0,to:editor.state.doc.length,insert:'mappingVersion: 2\n# reviewed\n'}}))
  expect(onChange).toHaveBeenCalledWith('mappingVersion: 2\n# reviewed\n')
  rerender(<MappingEditor {...props} value={'mappingVersion: 2\n# reviewed\n'} dirty/>)
  fireEvent.click(screen.getByRole('button',{name:'Validate and use copy'}))
  expect(await screen.findByRole('status')).toHaveTextContent('validation passed')
  expect(onValidate).toHaveBeenCalledWith('mappingVersion: 2\n# reviewed\n')
  fireEvent.click(screen.getByRole('button',{name:'Save as...'}))
  expect(await screen.findByText(/Saved to/)).toHaveTextContent('reviewed.yaml')
  expect(onSave).toHaveBeenCalledWith('mappingVersion: 2\n# reviewed\n')
})
it('shows engine diagnostics and navigates to a reported YAML line', async () => {
  render(<MappingEditor value={'mappingVersion: 2\ninvalid: [\n'} dirty onChange={vi.fn()} onSave={vi.fn()} onValidate={vi.fn().mockRejectedValue(new Error('YAML parse error at line 2, column 10'))}/>)
  fireEvent.click(screen.getByRole('button',{name:'Validate and use copy'}))
  expect(await screen.findByRole('alert')).toHaveTextContent('YAML parse error')
  fireEvent.click(screen.getByRole('button',{name:'Go to line 2'}))
  const editor=EditorView.findFromDOM(screen.getByRole('textbox', {name:'Mapping editor'}))!
  expect(editor.state.doc.lineAt(editor.state.selection.main.head).number).toBe(2)
  expect(errorLine('Schema validation failed: /beacon/individuals')).toBeUndefined()
})
