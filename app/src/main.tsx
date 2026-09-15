import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import App from './App'
import { isTauri } from '@tauri-apps/api/core'
import './desktop.css'
import './theme.css'

if (!isTauri()) {
  document.getElementById('root')!.textContent = 'Launch Convert-Pheno as a desktop application.'
} else createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
