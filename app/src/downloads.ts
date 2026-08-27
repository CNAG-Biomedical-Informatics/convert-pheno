import { strToU8, zipSync } from 'fflate'
import type { Artifact } from './types'

export function artifactBytes(artifact: Artifact) {
  if (artifact.encoding !== 'base64') return strToU8(artifact.content)
  const binary = atob(artifact.content)
  return Uint8Array.from(binary, (character) => character.charCodeAt(0))
}

export function downloadBlob(content: BlobPart, filename: string, mediaType: string) {
  const url = URL.createObjectURL(new Blob([content], { type: mediaType }))
  const anchor = document.createElement('a')
  anchor.href = url
  anchor.download = filename
  anchor.click()
  URL.revokeObjectURL(url)
}

export function downloadArtifact(artifact: Artifact) {
  downloadBlob(artifactBytes(artifact), artifact.filename, artifact.mediaType)
}

export function createZip(artifacts: Artifact[]) {
  const entries = Object.fromEntries(artifacts.map((artifact) => [artifact.filename, artifactBytes(artifact)]))
  return zipSync(entries)
}

export function downloadZip(artifacts: Artifact[], conversion: string) {
  downloadBlob(createZip(artifacts), `${conversion}-output.zip`, 'application/zip')
}
