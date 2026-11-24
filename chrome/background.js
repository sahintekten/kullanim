// claude.ai'nin kendi kullanım sayfasının okuduğu veriyi, tarayıcıdaki oturumla okur
// ve yalnız yüzdeleri Mac'teki Kullanım göstergesine (yerel bağlantı "local.kullanim") iletir.
// Çerez ya da giriş bilgisi hiçbir yere gönderilmez.
const HOST = 'local.kullanim'
const PERIOD_MIN = 3
const ORDER = k => (k === 'seven_day' ? 0 : k.startsWith('seven_day_') ? 1 : 2)

async function getJSON(url) {
  const r = await fetch(url, { credentials: 'include', headers: { accept: 'application/json' } })
  if (!r.ok) throw new Error(`${url.replace(/[0-9a-f-]{36}/, '<org>')} → ${r.status}`)
  return r.json()
}

async function readUsage() {
  const orgs = await getJSON('https://claude.ai/api/organizations')
  if (!Array.isArray(orgs) || orgs.length === 0) throw new Error('kuruluş listesi boş')
  const paid = orgs.find(o => (o.capabilities || []).some(c => /max|pro|ultra|team|enterprise/i.test(c)))
  const org = paid || orgs[0]
  const data = await getJSON(`https://claude.ai/api/organizations/${org.uuid}/usage`)
  const rateLimits = []
  const skip = new Set(['limits', 'windows', 'models', 'model', 'by', 'by_model', 'usage', 'rate', 'rate_limits', 'weekly', 'per'])
  const walk = (node, path, depth) => {
    if (!node || typeof node !== 'object' || depth > 4) return
    for (const [key, v] of Object.entries(node)) {
      if (!v || typeof v !== 'object') continue
      const u = typeof v.utilization === 'number' ? v.utilization
        : typeof v.percent_used === 'number' ? v.percent_used : null
      const segs = [...path, String(v.model || v.model_name || v.name || key)].map(x => x.toLowerCase().replace(/[^a-z0-9_]+/g, '_'))
      if (u === null) { walk(v, Array.isArray(node) ? path : [...path, key], depth + 1); continue }
      const flat = segs.join('_')
      let kind
      if (flat === 'seven_day' || flat === 'five_hour') kind = flat
      else if (flat.includes('five_hour')) kind = 'five_hour_' + segs.filter(x => x !== 'five_hour' && !skip.has(x)).join('_')
      else {
        const extra = segs.flatMap(x => x.replace(/^seven_day_?/, '').split('_')).filter(x => x && !skip.has(x) && x !== 'seven' && x !== 'day')
        kind = extra.length ? 'seven_day_' + extra.join('_') : 'seven_day'
      }
      rateLimits.push({ kind, percentUsed: Math.round(u * 10) / 10, resetsAt: v.resets_at || v.resetsAt || undefined })
    }
  }
  // Asıl kaynak: "limits" listesi (haftalık toplam ve model bazlı sınırlar, ör. scope.model.display_name = "Fable").
  for (const l of (Array.isArray(data.limits) ? data.limits : [])) {
    if (!l || typeof l.percent !== 'number') continue
    const g = String(l.group || l.kind || '').toLowerCase()
    const base = g.includes('week') ? 'seven_day' : /session|five|hour/.test(g) ? 'five_hour' : null
    if (!base) continue
    const scope = l.scope || {}
    const name = (scope.model && (scope.model.display_name || scope.model.id)) || (scope.surface && (scope.surface.display_name || scope.surface.id || (typeof scope.surface === 'string' ? scope.surface : '')))
    let kind = base
    if (name) kind = base + '_' + String(name).toLowerCase().replace(/[^a-z0-9]+/g, '_')
    else if (String(l.kind || '').includes('scoped')) kind = base + '_scoped'
    rateLimits.push({ kind, percentUsed: Math.round(l.percent * 10) / 10, resetsAt: l.resets_at || undefined })
  }
  // Yedek: eski biçim (seven_day: { utilization }) ya da başka yerdeki pencereler.
  if (rateLimits.length === 0) walk(data, [], 0)
  const seen = new Set()
  const unique = rateLimits.filter(w => (seen.has(w.kind) ? false : (seen.add(w.kind), true)))
  unique.sort((a, b) => ORDER(a.kind) - ORDER(b.kind))
  return { rateLimits: unique, keys: shapeOf(data, 0) }
}

// Yanıtın iskeleti: yalnız alan adları ve null/sayı işareti, değer yok (tanı için).
function shapeOf(node, depth) {
  if (node === null) return 'null'
  if (typeof node !== 'object') return typeof node === 'number' ? 'n' : typeof node === 'string' ? 's' : typeof node
  if (depth > 3) return '…'
  if (Array.isArray(node)) return '[' + (node.length ? shapeOf(node[0], depth + 1) : '') + ']'
  return '{' + Object.entries(node).filter(([, v]) => v !== null).map(([k, v]) => k + ':' + shapeOf(v, depth + 1)).join(',') + '}'
}

async function tick() {
  try {
    const { rateLimits, keys } = await readUsage()
    if (rateLimits.length > 0) await chrome.runtime.sendNativeMessage(HOST, { rateLimits, shape: keys.slice(0, 600) })
    else await chrome.runtime.sendNativeMessage(HOST, { error: 'pencere bulunamadı; iskelet: ' + keys.slice(0, 600) })
  } catch (e) {
    try { await chrome.runtime.sendNativeMessage(HOST, { error: String(e && e.message || e) }) } catch {}
  }
}

function schedule() {
  chrome.alarms.create('kullanim', { periodInMinutes: PERIOD_MIN })
  tick()
}
chrome.runtime.onInstalled.addListener(schedule)
chrome.runtime.onStartup.addListener(schedule)
chrome.alarms.onAlarm.addListener(a => { if (a.name === 'kullanim') tick() })
