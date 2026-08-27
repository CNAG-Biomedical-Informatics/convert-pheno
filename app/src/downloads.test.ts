import { unzipSync, strFromU8 } from 'fflate'
import { describe, expect, it, vi } from 'vitest'
import { createZip } from './downloads'

describe('ZIP downloads', () => {
  it('puts every serialized artifact into one archive', async () => {
    const archive = createZip([
      { id: 'a', filename: 'individuals.json', mediaType: 'application/json', kind: 'json', encoding: 'utf-8', content: '[]' },
      { id: 'b', filename: 'PERSON.csv', mediaType: 'text/csv', kind: 'csv', encoding: 'utf-8', content: 'id\n1\n' },
    ])
    const files = unzipSync(archive)
    expect(strFromU8(files['individuals.json'])).toBe('[]')
    expect(strFromU8(files['PERSON.csv'])).toBe('id\n1\n')
  })
})
