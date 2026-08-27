export type OptionDefinition = {
  name: string
  label: string
  kind: 'boolean' | 'integer' | 'number' | 'select' | 'string'
  values?: string[]
  default?: string | number | boolean
  minimum?: number
  maximum?: number
}

export type FileDefinition = {
  name: string
  label: string
  description?: string
  required: boolean
  multiple: boolean
  maximum?: number
  accept?: string[]
}

export type Conversion = {
  id: string
  label: string
  maturity: string
  available: boolean
  unavailableReason?: string
  source: { id: string; label: string; kind: string; inputShape: string }
  target: { id: string; label: string; kind: string }
  entities: { default: string[]; supported: string[] }
  options: OptionDefinition[]
  resources: string[]
  input: { transports: Array<'json' | 'multipart'>; files: FileDefinition[] }
}

export type Artifact = {
  id: string
  filename: string
  mediaType: string
  kind: 'json' | 'jsonld' | 'csv' | 'tsv' | 'xlsx'
  encoding: 'utf-8' | 'base64'
  content: string
}

export type ReviewAction =
  | 'keep'
  | 'review_similarity'
  | 'resolve_or_accept_fallback'
  | 'review_source_fallback'

export type TerminologyAuditRow = {
  row?: number | string
  source_record?: string
  source_field?: string
  source_value?: string
  source_label?: string
  lookup_query?: string
  converted_term_label?: string
  converted_term_id?: string
  ontology?: string
  review_action: ReviewAction
  decision_reason?: string
  best_candidate_label?: string
  best_candidate_id?: string
  best_candidate_score?: number | string
  score_margin?: number | string
  [key: string]: string | number | null | undefined
}

export type TerminologyAudit = {
  totalDecisions: number
  counts: Record<ReviewAction, number>
  rows: TerminologyAuditRow[]
  previewRows: number
  previewLimitPerAction: number
  truncated: boolean
  reportArtifactId: string
  settings: {
    configuredSearchMode?: string
    textSimilarityMethod?: string
    minTextSimilarityScore?: number
    levenshteinWeight?: number
  }
}

export type ApiError = { ok: false; error: { code: string; message: string } }
export type ConversionResponse = {
  ok: true
  artifacts: Artifact[]
  warnings: string[]
  meta: { conversion: string; terminologyAudit?: TerminologyAudit }
}
