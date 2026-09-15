import { act, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, beforeEach, expect, it, vi } from 'vitest'
import { writeText } from '@tauri-apps/plugin-clipboard-manager'
import CopyButton from './CopyButton'
import DataView from './DataView'

vi.mock('@tauri-apps/plugin-clipboard-manager', () => ({ writeText: vi.fn() }))
beforeEach(() => { vi.mocked(writeText).mockReset().mockResolvedValue(undefined) })
afterEach(() => vi.useRealTimers())

it('copies exactly the supplied text and clears confirmation after two seconds', async () => {
  vi.useFakeTimers()
  const text = '{\n  "label": "Jos\u00e9"\n}'
  render(<CopyButton text={text} label="Copy JSON" />)
  await act(async () => { fireEvent.click(screen.getByRole('button', { name: 'Copy JSON' })) })
  expect(writeText).toHaveBeenCalledWith(text)
  expect(screen.getByRole('status')).toHaveTextContent('Copied')
  act(() => vi.advanceTimersByTime(2000))
  expect(screen.queryByRole('status')).not.toBeInTheDocument()
})

it('reports clipboard failures without exposing the text and allows retry', async () => {
  vi.mocked(writeText).mockRejectedValueOnce(new Error('internal diagnostic'))
  render(<CopyButton text="private text" label="Copy value" />)
  fireEvent.click(screen.getByRole('button', { name: 'Copy value' }))
  expect(await screen.findByRole('alert')).toHaveTextContent('Could not copy. Try again.')
  expect(screen.queryByText(/private text|internal diagnostic/)).not.toBeInTheDocument()
  fireEvent.click(screen.getByRole('button', { name: 'Copy value' }))
  expect(await screen.findByRole('status')).toHaveTextContent('Copied')
})

it('does not show a previous copy confirmation after the value changes', async () => {
  const { rerender } = render(<CopyButton text="first" label="Copy value" />)
  fireEvent.click(screen.getByRole('button', { name: 'Copy value' }))
  await screen.findByRole('status')
  rerender(<CopyButton text="second" label="Copy value" />)
  expect(screen.queryByRole('status')).not.toBeInTheDocument()
})

it('disables copying empty content', () => {
  render(<CopyButton text="" label="Copy value" />)
  expect(screen.getByRole('button', { name: 'Copy value' })).toBeDisabled()
})

it('copies the original JSON from text view rather than the filtered table', async () => {
  const text = '[{"id":"one"},{"id":"two"}]'
  render(<DataView preview={{ text, truncated: false }} onInspect={vi.fn()} />)
  fireEvent.change(screen.getByRole('textbox'), { target: { value: 'one' } })
  fireEvent.click(screen.getByRole('button', { name: 'Text / JSON' }))
  fireEvent.click(screen.getByRole('button', { name: 'Copy text / JSON' }))
  await screen.findByRole('status')
  expect(writeText).toHaveBeenCalledWith(text)
})

it('labels truncated previews explicitly and copies only their displayed content', async () => {
  const text = '[{"id":"partial'
  render(<DataView preview={{ text, truncated: true, kind: 'json' }} onInspect={vi.fn()} />)
  fireEvent.click(screen.getByRole('button', { name: 'Copy partial preview text (not the complete file)' }))
  await screen.findByRole('status')
  expect(writeText).toHaveBeenCalledWith(text)
  expect(screen.getByText(/Partial preview: first 256 KiB/)).toBeInTheDocument()
})
