import { act, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { beforeEach, expect, it, vi } from 'vitest'
import JobSettings from './JobSettings'
import { getJobSettings, updateJobSettings } from '../api'

vi.mock('../api', () => ({ getJobSettings: vi.fn(), updateJobSettings: vi.fn() }))
const settings = { maxConcurrentJobs: 1, maxAllowedConcurrentJobs: 4 }
beforeEach(() => {
  vi.resetAllMocks()
  vi.mocked(getJobSettings).mockResolvedValue(settings)
})

it('loads the persisted limit and explains CPU and memory use', async () => {
  vi.mocked(getJobSettings).mockResolvedValue({ ...settings, maxConcurrentJobs: 4 })
  render(<JobSettings />)
  expect(await screen.findByLabelText('Maximum concurrent jobs')).toHaveValue('4')
  expect(screen.getByText(/Higher limits also require more memory/)).toBeInTheDocument()
  expect(screen.getAllByRole('option')).toHaveLength(4)
  expect(screen.queryByRole('option', { name: '5' })).not.toBeInTheDocument()
})

it.each([1, 2, 3, 4])('saves a limit of %i through the shared API', async limit => {
  vi.mocked(updateJobSettings).mockResolvedValue({ ...settings, maxConcurrentJobs: limit })
  render(<JobSettings />)
  fireEvent.change(await screen.findByLabelText('Maximum concurrent jobs'), { target: { value: String(limit) } })
  await waitFor(() => expect(updateJobSettings).toHaveBeenCalledWith(limit))
  await waitFor(() => expect(screen.getByLabelText('Maximum concurrent jobs')).not.toBeDisabled())
  expect(screen.getByLabelText('Maximum concurrent jobs')).toHaveValue(String(limit))
})

it('prevents overlapping updates and retains the old value if saving fails', async () => {
  let reject!: (reason: Error) => void
  vi.mocked(updateJobSettings).mockReturnValue(new Promise((_, fail) => { reject = fail }))
  render(<JobSettings />)
  fireEvent.change(await screen.findByLabelText('Maximum concurrent jobs'), { target: { value: '4' } })
  expect(screen.getByLabelText('Maximum concurrent jobs')).toBeDisabled()
  await act(async () => reject(new Error('Could not save scheduler settings')))
  expect(screen.getByRole('alert')).toHaveTextContent('Could not save scheduler settings')
  expect(screen.getByLabelText('Maximum concurrent jobs')).toHaveValue('1')
})

it('can retry a failed settings request', async () => {
  vi.mocked(getJobSettings).mockRejectedValueOnce(new Error('Service unavailable'))
  render(<JobSettings />)
  fireEvent.click(await screen.findByRole('button', { name: 'Retry loading settings' }))
  expect(await screen.findByLabelText('Maximum concurrent jobs')).toHaveValue('1')
})
