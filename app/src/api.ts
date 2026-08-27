import type { ApiError, Conversion, ConversionResponse } from './types'

async function readResponse<T>(response: Response): Promise<T> {
  const body = (await response.json()) as T | ApiError
  if (!response.ok || (body as ApiError).ok === false) {
    throw new Error((body as ApiError).error?.message || `Request failed (${response.status})`)
  }
  return body as T
}

export async function getConversions(): Promise<Conversion[]> {
  const response = await fetch('/api/conversions', { headers: { Accept: 'application/json' } })
  const body = await readResponse<{ ok: true; data: Conversion[] }>(response)
  return body.data
}

export async function getExample(source: string, transport?: 'json' | 'multipart'): Promise<{ data: unknown; filename: string }> {
  const query = transport ? `?transport=${transport}` : ''
  const response = await fetch(`/examples/${encodeURIComponent(source)}${query}`, { headers: { Accept: 'application/json' } })
  const body = await readResponse<{ ok: true; data: unknown; meta: { filename: string } }>(response)
  return { data: body.data, filename: body.meta.filename }
}

export async function runConversion(
  conversion: string,
  request: { input?: { data: unknown }; output: Record<string, unknown>; options: Record<string, unknown> },
  files?: Record<string, File[]>,
): Promise<ConversionResponse> {
  if (files) {
    const form = new FormData()
    form.append('request', JSON.stringify({ output: request.output, options: request.options }))
    for (const [role, roleFiles] of Object.entries(files)) {
      for (const file of roleFiles) form.append(role, file, file.name)
    }
    const response = await fetch(`/api/conversions/${encodeURIComponent(conversion)}`, {
      method: 'POST',
      headers: { Accept: 'application/json' },
      body: form,
    })
    return readResponse<ConversionResponse>(response)
  }
  const response = await fetch(`/api/conversions/${encodeURIComponent(conversion)}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify(request),
  })
  return readResponse<ConversionResponse>(response)
}
