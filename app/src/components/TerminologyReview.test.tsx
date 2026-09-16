import { fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { it, expect, vi } from 'vitest'
import TerminologyReview from './TerminologyReview'
import type { Artifact, TerminologyAudit } from '../types'

const audit: TerminologyAudit={totalDecisions:1,previewRows:1,previewLimitPerAction:100,truncated:false,reportArtifactId:'term-audit',settings:{},counts:{keep:1,review_similarity:0,resolve_or_accept_fallback:0,review_source_fallback:0},rows:[{row:1,source_field:'Disease',source_value:'Asthma',lookup_query:'Asthma',converted_term_label:'Asthma',converted_term_id:'NCIT:C28397',ontology:'ncit',review_action:'keep',decision_reason:'exact_match'}]}
const report: Artifact={id:'term-audit',filename:'term-audit.xlsx',kind:'xlsx',mediaType:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',encoding:'base64',content:''}
it('shows preserved source values separately from failed lookups and needs review', () => {
  const preserved = {...audit.rows[0], source_field:'geographicOrigin', source_value:'England', converted_term_label:'England', converted_term_id:'', lookup_query:'', review_action:'preserve_source' as const, decision_reason:'source_value_preserved'}
  const unresolved = {...audit.rows[0], review_action:'resolve_or_accept_fallback' as const, decision_reason:'no_standard_concept'}
  render(<TerminologyReview audit={{...audit,totalDecisions:2,previewRows:2,counts:{...audit.counts,keep:0,preserve_source:1,resolve_or_accept_fallback:1},rows:[preserved,unresolved]}} report={report} onDownload={vi.fn()} onHelp={vi.fn()}/>)
  expect(screen.getByRole('button', {name:'Needs review 1'})).toHaveAttribute('aria-pressed','true')
  expect(within(screen.getByRole('table')).queryByText('England')).not.toBeInTheDocument()
  fireEvent.click(screen.getByRole('button', {name:/^Preserved/}))
  expect(within(screen.getByRole('table')).getAllByText('England')).toHaveLength(2)
  expect(within(screen.getByRole('table')).getByText('Preserved')).toBeInTheDocument()
})
it('groups repeated terms by default but retains separate contexts and individual occurrences', () => {
  const repeated: TerminologyAudit = { ...audit, totalDecisions: 4, previewRows: 4, counts: {...audit.counts, keep: 4}, rows: [
    audit.rows[0], {...audit.rows[0], row: 2, source_record: 'person-2'},
    {...audit.rows[0], row: 3, ontology: 'other'},
    {...audit.rows[0], row: 4, source_field: 'History'},
  ] }
  render(<TerminologyReview audit={repeated} report={report} onDownload={vi.fn()} onHelp={vi.fn()}/>)
  expect(screen.getByLabelText('Display')).toHaveValue('unique')
  const table = screen.getByRole('table')
  expect(within(table).getAllByRole('row')).toHaveLength(4)
  expect(within(table).getByRole('cell', {name: '2'})).toBeInTheDocument()
  fireEvent.click(screen.getAllByRole('button', {name: 'Evidence'})[0])
  expect(screen.getByText(/Row 2 .*record person-2/)).toBeInTheDocument()
  fireEvent.change(screen.getByLabelText('Display'), {target: {value: 'all'}})
  expect(within(table).getAllByRole('row')).toHaveLength(5)
  expect(screen.queryByText('Occurrences in preview')).not.toBeInTheDocument()
})
it('does not present preview group counts as complete totals', () => {
  render(<TerminologyReview audit={{...audit, truncated: true, totalDecisions: 1000, counts: {...audit.counts, keep: 1000}}} report={report} onDownload={vi.fn()} onHelp={vi.fn()}/>)
  expect(screen.getByText(/Unique-term counts and their occurrence lists cover only retained rows/)).toBeInTheDocument()
  expect(screen.getByText('unique in preview · 1,000 total occurrences')).toBeInTheDocument()
  expect(screen.getByRole('columnheader', {name: 'Occurrences in preview'})).toBeInTheDocument()
})
it('groups cached repetitions but keeps different source values and queries separate', () => {
  const row = {...audit.rows[0],source_field:'nancy_index_acute',source_value:'2',source_label:'2 - mild',lookup_query:'nancy_index_acute',match_source:'fallback_na'}
  const rows = [row, {...row,row:2,match_source:'cache'}, {...row,row:3,source_value:'3',source_label:'3 - moderate'}, {...row,row:4,lookup_query:''}]
  render(<TerminologyReview audit={{...audit,rows,previewRows:4,totalDecisions:4}} report={report} onDownload={vi.fn()} onHelp={vi.fn()}/>)
  expect(screen.getAllByRole('button',{name:'Evidence'})).toHaveLength(3)
  fireEvent.click(screen.getAllByRole('button',{name:'Evidence'})[0])
  expect(screen.getByText(/Row 2 .*cache/)).toBeInTheDocument()
  expect(screen.getByText(/Row 1 .*fallback_na/)).toBeInTheDocument()
})
it('shows one unresolved lookup across different individuals and raw values', () => {
  const row = {...audit.rows[0],review_action:'resolve_or_accept_fallback' as const,source_field:'nancy_index_acute',source_value:'2',source_label:'mild',lookup_query:'nancy_index_acute',converted_term_id:'NCIT:NA0000',converted_term_label:'NA',decision_reason:'no_candidate'}
  const rows = [row,{...row,row:2,source_value:'3',source_label:'moderate',match_source:'cache'}]
  render(<TerminologyReview audit={{...audit,rows,previewRows:2,totalDecisions:2,counts:{...audit.counts,keep:0,resolve_or_accept_fallback:2}}} report={report} onDownload={vi.fn()} onHelp={vi.fn()}/>)
  expect(screen.getAllByRole('button',{name:'Evidence'})).toHaveLength(1)
  expect(screen.getByRole('cell',{name:/2, 3/})).toBeInTheDocument()
  fireEvent.click(screen.getByRole('button',{name:'Evidence'}))
  expect(screen.getByText(/Row 2 .*moderate/)).toBeInTheDocument()
})
it('downloads the complete Excel report without reconstructing it from preview rows', () => {
  const onDownload = vi.fn()
  render(<TerminologyReview audit={audit} report={report} onDownload={onDownload} onHelp={vi.fn()}/>)
  fireEvent.click(screen.getByRole('button',{name:'Save Excel report...'}))
  expect(onDownload).toHaveBeenCalledWith(report)
})
it('keeps filters and expanded evidence during run polling and downloads the full audit', async () => {
  const onDownload=vi.fn(), onHelp=vi.fn()
  const {rerender}=render(<TerminologyReview audit={audit} report={report} onDownload={onDownload} onHelp={onHelp}/>)
  fireEvent.change(screen.getByLabelText('Search decisions'),{target:{value:'Asthma'}})
  fireEvent.click(screen.getByRole('button',{name:'Evidence'}))
  rerender(<TerminologyReview audit={structuredClone(audit)} report={report} onDownload={onDownload} onHelp={onHelp}/>)
  await waitFor(() => expect(screen.getByLabelText('Search decisions')).toHaveValue('Asthma'))
  expect(screen.getByRole('button',{name:'Close'})).toHaveAttribute('aria-expanded','true')
  fireEvent.click(screen.getByRole('button',{name:'Save Excel report...'}))
  expect(onDownload).toHaveBeenCalledWith(report)
  fireEvent.click(screen.getByRole('button',{name:/How to review/}))
  expect(onHelp).toHaveBeenCalledOnce()
})
