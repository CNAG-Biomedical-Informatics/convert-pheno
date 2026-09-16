import type { OptionDefinition } from '../types'

export default function ConversionOptions({ definitions, values, onChange }: {
  definitions: OptionDefinition[]
  values: Record<string, unknown>
  onChange: (values: Record<string, unknown>) => void
}) {
  const update = (name: string, value: unknown) => onChange({ ...values, [name]: value })
  return <details><summary>Advanced options</summary><div className="options-grid">
    {definitions.filter(option => option.name !== 'term_audit' &&
      Object.entries(option.visibleWhen || {}).every(([key, allowed]) =>
        allowed.includes(String(values[key] ?? definitions.find(item => item.name === key)?.default ?? ''))))
      .map(option => {
        const id = `conversion-option-${option.name}`
        const description = option.description ? `${id}-help` : undefined
        const value = values[option.name] ?? option.default
        if (option.kind === 'multiselect') return <fieldset key={option.name} aria-describedby={description}>
          <legend>{option.label}</legend>
          {option.values?.map(item => <label key={item}><input type="checkbox"
            checked={Array.isArray(value) && value.includes(item)}
            onChange={event => update(option.name, event.target.checked
              ? [...(Array.isArray(value) ? value : []), item]
              : (Array.isArray(value) ? value : []).filter(entry => entry !== item))} />{item}</label>)}
          {description && <small id={description}>{option.description}</small>}
        </fieldset>
        return <div key={option.name}><label htmlFor={id}>{option.label}</label>
          {option.name === 'separator' ? <select id={id} aria-describedby={description} value={String(value ?? '')} onChange={event => update(option.name, event.target.value)}>
            <option value="">Use file extension</option><option value=";">Semicolon (;)</option><option value=",">Comma (,)</option><option value={'\t'}>Tab</option><option value="|">Pipe (|)</option>
            {value && ![';', ',', '\t', '|'].includes(String(value)) ? <option value={String(value)}>Custom ({String(value)})</option> : null}
          </select> : option.kind === 'boolean' ? <input id={id} aria-describedby={description} type="checkbox" checked={Boolean(value)} onChange={event => update(option.name, event.target.checked)} />
            : option.values ? <select id={id} aria-describedby={description} value={String(value ?? '')} onChange={event => update(option.name, event.target.value)}>{option.values.map(item => <option key={item}>{item}</option>)}</select>
              : <input id={id} aria-describedby={description} type={['integer', 'number'].includes(option.kind) ? 'number' : 'text'}
                min={option.minimum} max={option.maximum} step={option.kind === 'number' ? 'any' : 1}
                value={String(value ?? '')} onChange={event => update(option.name,
                  ['integer', 'number'].includes(option.kind) ? (event.target.value === '' ? '' : Number(event.target.value)) : event.target.value)} />}
          {description && <small id={description}>{option.description}</small>}
        </div>
      })}
  </div></details>
}
