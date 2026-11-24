import type { Register } from 'claude-code'

// Hesabın kullanım pencerelerini (haftalık, model bazlı haftalık) ~/.claude/kullanim.json
// dosyasına yazar. Menü çubuğundaki gösterge bu dosyayı okur.
// Kaynak 1: masaüstü uygulamasının kendi kullanım kartı (ccd_session_mgmt.get_usage, salt okuma;
// "Weekly · Fable" gibi model bazlı sınırları da verir). Kaynak 2 (yedek): oturumun son API yanıtı.
// Oturum boşta dursa da birkaç dakikada bir yenilenir. Hiçbir şey Mac'in dışına çıkmaz.

const PERIOD_MS = 3 * 60 * 1000

type Win = { kind: string; label?: string; percentUsed: number; resetsAt?: string }

function kindOf(label: string): string {
  const l = label.toLowerCase()
  if (l.includes('all models')) return 'seven_day'
  if (l.startsWith('weekly')) {
    const model = label.split('·')[1]?.trim()
    return model ? 'seven_day_' + model.toLowerCase() : 'seven_day'
  }
  if (l.includes('5-hour') || l.includes('5 hour') || l.includes('session')) return 'five_hour'
  return label
}

async function fromApp($: any): Promise<Win[] | null> {
  try {
    const r = await $.mcp.call('ccd_session_mgmt', 'get_usage', {})
    if (!r || r.isError) return null
    const text = (r.content ?? []).map((c: any) => (c.type === 'text' ? c.text : '')).join('')
    const plan = JSON.parse(text).plan
    if (!plan || plan.status !== 'ok' || !Array.isArray(plan.windows)) return null
    const wins: Win[] = plan.windows
      .filter((w: any) => typeof w.percentUsed === 'number' && typeof w.label === 'string')
      .map((w: any) => ({ kind: kindOf(w.label), label: w.label, percentUsed: w.percentUsed, resetsAt: w.resetsAt }))
    return wins.length > 0 ? wins : null
  } catch {
    return null
  }
}

async function write($: any, rateLimits: Win[], source: string) {
  const home = await $.env.get('HOME')
  if (!home || rateLimits.length === 0) return
  await $.fs.write(`${home}/.claude/kullanim.json`,
    JSON.stringify({ updatedAt: new Date().toISOString(), source, rateLimits }, null, 2))
}

async function refresh($: any, sessionLimits?: Win[]) {
  try {
    const app = await fromApp($)
    if (app) return await write($, app, 'app')
    const limits = sessionLimits ?? (await $.session.usage()).rateLimits
    if (limits && limits.length > 0) await write($, limits, 'session')
  } catch {}
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const result = await next(e)
    await refresh($)
    $.clock.every(PERIOD_MS, () => refresh($))
    return result
  })
  on('session.measure', async ($, e, next) => {
    await refresh($, e.rateLimits)
    return next(e)
  })
}
