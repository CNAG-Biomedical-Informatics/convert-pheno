import { fireEvent, render, screen } from '@testing-library/react'
import { useState } from 'react'
import { describe, expect, it } from 'vitest'
import ConversionOptions from './ConversionOptions'
import registry from '../../../share/schema/public-conversions.json'
import type { OptionDefinition } from '../types'

function Form() {
  const [values, setValues] = useState<Record<string, unknown>>({search: 'exact'})
  const definitions = Object.entries(registry.option_definitions).map(([name, definition]) => ({name, ...definition})) as OptionDefinition[]
  definitions.find(option => option.name === 'omop_tables')!.values = ['MEASUREMENT', 'SPECIMEN']
  return <><ConversionOptions definitions={definitions} values={values} onChange={setValues} /><output data-testid="values">{JSON.stringify(values)}</output></>
}

describe('registry-driven conversion settings', () => {
  it('shows similarity settings only for mixed and fuzzy without losing edits', () => {
    render(<Form />)
    expect(screen.queryByLabelText('Minimum similarity score')).not.toBeInTheDocument()
    fireEvent.change(screen.getByLabelText('Terminology search'), {target: {value: 'mixed'}})
    const score = screen.getByLabelText('Minimum similarity score')
    expect(score).toHaveAttribute('min', '0')
    expect(score).toHaveAttribute('max', '1')
    expect(score).toHaveAttribute('step', 'any')
    fireEvent.change(score, {target: {value: '0.75'}})
    fireEvent.change(screen.getByLabelText('Terminology search'), {target: {value: 'exact'}})
    expect(screen.queryByLabelText('Minimum similarity score')).not.toBeInTheDocument()
    fireEvent.change(screen.getByLabelText('Terminology search'), {target: {value: 'fuzzy'}})
    expect(screen.getByLabelText('Minimum similarity score')).toHaveValue(0.75)
  })
  it('keeps booleans and table lists typed and explains source provenance', () => {
    render(<Form />)
    const provenance = screen.getByLabelText('Include source provenance')
    expect(provenance).toBeChecked()
    expect(provenance).toHaveAccessibleDescription(/original source fields/)
    fireEvent.click(provenance)
    fireEvent.click(screen.getByLabelText('MEASUREMENT'))
    fireEvent.click(screen.getByLabelText('SPECIMEN'))
    expect(JSON.parse(screen.getByTestId('values').textContent!)).toMatchObject({source_info: false, omop_tables: ['MEASUREMENT', 'SPECIMEN']})
    fireEvent.click(screen.getByLabelText('MEASUREMENT'))
    expect(JSON.parse(screen.getByTestId('values').textContent!).omop_tables).toEqual(['SPECIMEN'])
  })
  it('keeps datasetId propagation opt-in and explains its mapping source', () => {
    render(<Form />)
    const option = screen.getByLabelText('Include datasetId in records')
    expect(option).not.toBeChecked()
    expect(option).toHaveAccessibleDescription(/dataset ID from your mapping file/)
    fireEvent.click(option)
    expect(JSON.parse(screen.getByTestId('values').textContent!).include_dataset_id).toBe(true)
  })
})
