import { FormEvent, useEffect, useMemo, useState } from 'react'
import { Check, LogOut, RefreshCcw, ShieldAlert, Wifi, WifiOff, effectIcons } from './icons'
import type { Controller, Credentials, Effect } from './types'
import { categoryIds, categoryLabel, copy, effectLabel, eventLabel, readLanguage, type Language } from './i18n'
import { useChaosSocket } from './useChaosSocket'

function readCredentials(): Credentials | null {
  const raw = sessionStorage.getItem('chaos-link-credentials')
  if (!raw) return null
  try {
    const saved = JSON.parse(raw) as Credentials
    return { ...saved, role: saved.role === 'admin' ? 'admin' : 'controller' }
  } catch { return null }
}

export default function App() {
  const [credentials, setCredentials] = useState<Credentials | null>(readCredentials)
  const [language, setLanguageState] = useState<Language>(readLanguage)
  const { snapshot, connection, notice, clockOffset, trigger, setPaused, blockUser, setCooldown, hostControl } = useChaosSocket(credentials, language)
  const [clientNow, setClientNow] = useState(Date.now)
  const t = copy[language]

  const setLanguage = (next: Language) => {
    localStorage.setItem('chaos-link-language', next)
    setLanguageState(next)
  }

  useEffect(() => {
    document.documentElement.lang = language
  }, [language])

  useEffect(() => {
    const timer = window.setInterval(() => setClientNow(Date.now()), 250)
    return () => window.clearInterval(timer)
  }, [])

  if (!credentials) return <JoinScreen language={language} onLanguage={setLanguage} onJoin={setCredentials} />
  const isAdmin = credentials.role === 'admin'

  const disconnect = () => {
    sessionStorage.removeItem('chaos-link-credentials')
    setCredentials(null)
  }

  const runHostControl = (action: 'restart' | 'shutdown') => {
    const confirmed = window.confirm(action === 'restart' ? t.restartConfirm : t.shutdownConfirm)
    if (confirmed) hostControl(action)
  }

  const now = clientNow + clockOffset
  const selfBlocked = (snapshot?.controllers.find(item => item.name === credentials.name && item.role === 'controller')?.blockedUntil ?? 0) > now
  const grouped = categoryIds.map(category => ({
    ...category,
    effects: snapshot?.effects.filter(effect => category.effectIds.some(id => id === effect.id)) ?? [],
  }))

  return (
    <main className="app-shell">
      <Header
        roomCode={snapshot?.roomCode ?? credentials.room}
        agentConnected={snapshot?.agentConnected ?? false}
        connection={connection}
        controllers={snapshot?.controllers ?? [{ id: 'self', name: credentials.name, role: credentials.role, blockedUntil: 0, blockedPermanently: false }]}
        now={now}
        isAdmin={isAdmin}
        language={language}
        onLanguage={setLanguage}
        onBlockUser={blockUser}
        onDisconnect={disconnect}
      />

      <section className={`system-strip ${snapshot?.paused ? 'is-paused' : ''}`}>
        <div className="system-message">
          <div className="system-icon">{snapshot?.paused ? <ShieldAlert /> : <Check />}</div>
          <div>
            <h1>{snapshot?.paused ? t.pausedTitle : t.activeTitle}</h1>
            <p>{snapshot?.paused ? t.pausedText : t.activeText}</p>
          </div>
        </div>
        <div className="system-actions">
          <button
            className={`pause-button ${snapshot?.paused ? 'resume' : ''}`}
            onClick={() => setPaused(!snapshot?.paused)}
            disabled={!isAdmin || !snapshot || connection !== 'connected'}
            title={isAdmin ? undefined : t.adminPauseOnly}
          >
            {snapshot?.paused ? <RefreshCcw /> : <ShieldAlert />}
            <span>{!isAdmin ? t.adminPauseButton : snapshot?.paused ? t.resume : t.emergencyPause}</span>
          </button>
          {isAdmin && (
            <div className="host-actions">
              <button type="button" className="host-button restart" onClick={() => runHostControl('restart')} disabled={!snapshot?.agentConnected || connection !== 'connected'} title={t.restartTitle}>
                <RefreshCcw /><span>{t.restart}</span>
              </button>
              <button type="button" className="host-button shutdown" onClick={() => runHostControl('shutdown')} disabled={!snapshot?.agentConnected || connection !== 'connected'} title={t.shutdownTitle}>
                <ShieldAlert /><span>{t.shutdown}</span>
              </button>
            </div>
          )}
        </div>
      </section>

      {notice && <div className={`notice ${notice.tone}`}>{notice.text}</div>}

      <div className="dashboard-grid">
        <section className="effects-column" aria-label={t.eventsAria}>
          {grouped.map(group => group.effects.length > 0 && (
            <EffectGroup
              key={group.id}
              title={categoryLabel(group.id, language)}
              effects={group.effects}
              now={now}
              disabled={!snapshot?.agentConnected || !!snapshot?.paused || selfBlocked || connection !== 'connected'}
              canEditCooldown={isAdmin}
              language={language}
              onTrigger={trigger}
              onSetCooldown={setCooldown}
            />
          ))}
          {!snapshot && <LoadingPanel language={language} />}
        </section>

        <aside className="event-panel">
          <div className="panel-heading"><h2>{t.journal}</h2><span>{t.onServer}</span></div>
          <div className="event-list">
            {snapshot?.events.length ? snapshot.events.map(event => (
              <article className="event-row" key={event.eventId}>
                <div className="avatar small">{event.actor.slice(0, 1).toUpperCase()}</div>
                <div className="event-copy"><strong>{event.actor}</strong><span>{eventLabel(event, language)}</span></div>
                <div className={`event-state ${event.status}`}>
                  <span>{event.status === 'executed' ? t.executed : event.status === 'failed' ? t.failed : t.sent}</span>
                  <time>{new Date(event.timestamp).toLocaleTimeString(language === 'ru' ? 'ru-RU' : 'en-US', { hour: '2-digit', minute: '2-digit', second: '2-digit' })}</time>
                </div>
              </article>
            )) : <div className="empty-state"><span>{t.noCommands}</span><small>{t.firstCommand}</small></div>}
          </div>
        </aside>
      </div>
    </main>
  )
}

function LanguageToggle({ language, onChange, large = false }: { language: Language; onChange: (language: Language) => void; large?: boolean }) {
  return (
    <div className={`language-toggle ${large ? 'large' : ''}`} role="group" aria-label={copy[language].language}>
      <button type="button" className={language === 'ru' ? 'selected' : ''} onClick={() => onChange('ru')}>{large ? 'Русский' : 'RU'}</button>
      <button type="button" className={language === 'en' ? 'selected' : ''} onClick={() => onChange('en')}>{large ? 'English' : 'EN'}</button>
    </div>
  )
}

function Header({ roomCode, agentConnected, connection, controllers, now, isAdmin, language, onLanguage, onBlockUser, onDisconnect }: {
  roomCode: string; agentConnected: boolean; connection: string; controllers: Controller[]; now: number; isAdmin: boolean; language: Language
  onLanguage: (language: Language) => void; onBlockUser: (id: string, blockSeconds: number) => void; onDisconnect: () => void
}) {
  const t = copy[language]
  return (
    <header className="topbar">
      <div className="brand">CHAOS <em>LINK</em></div>
      <div className="room-code"><span>{t.roomCode}</span><strong>{roomCode}</strong></div>
      <div className={`agent-status ${agentConnected ? 'online' : ''}`}>
        {agentConnected ? <Wifi /> : <WifiOff />}
        <div><strong>{agentConnected ? t.pcConnected : t.pcOffline}</strong><span>{connection === 'connected' ? t.roomConnected : connection === 'error' ? t.connectionError : t.reconnecting}</span></div>
      </div>
      <div className="controller-list">
        {controllers.map(controller => {
          const blocked = controller.blockedPermanently || controller.blockedUntil > now
          const status = controller.role === 'admin' ? t.admin : controller.blockedPermanently ? t.blockedForever : controller.blockedUntil > now ? `${t.blocked} · ${Math.ceil((controller.blockedUntil - now) / 1000)} ${t.secondsShort}` : t.online
          return (
            <div className={`controller ${blocked ? 'blocked' : ''}`} key={controller.id}>
              <div className="avatar">{controller.name.slice(0, 1).toUpperCase()}</div>
              <div className="controller-copy"><strong>{controller.name}</strong><span><i />{status}</span></div>
              {isAdmin && controller.role === 'controller' && <div className="controller-actions">
                {blocked ? <button type="button" onClick={() => onBlockUser(controller.id, 0)}>{t.unblock}</button> : <><button type="button" onClick={() => onBlockUser(controller.id, 30)}>{t.seconds30}</button><button type="button" onClick={() => onBlockUser(controller.id, -1)}>{t.forever}</button></>}
              </div>}
            </div>
          )
        })}
      </div>
      <LanguageToggle language={language} onChange={onLanguage} />
      <button className="icon-button" onClick={onDisconnect} aria-label={t.logout} title={t.logout}><LogOut /></button>
    </header>
  )
}

function EffectGroup({ title, effects, now, disabled, canEditCooldown, language, onTrigger, onSetCooldown }: {
  title: string; effects: Effect[]; now: number; disabled: boolean; canEditCooldown: boolean; language: Language
  onTrigger: (id: string) => void; onSetCooldown: (id: string, seconds: number) => void
}) {
  return <section className="effect-group"><div className="group-heading"><h2>{title}</h2><span /></div><div className="effect-grid">
    {effects.map(effect => <EffectButton key={effect.id} effect={effect} now={now} disabled={disabled} canEditCooldown={canEditCooldown} language={language} onTrigger={onTrigger} onSetCooldown={onSetCooldown} />)}
  </div></section>
}

function EffectButton({ effect, now, disabled, canEditCooldown, language, onTrigger, onSetCooldown }: {
  effect: Effect; now: number; disabled: boolean; canEditCooldown: boolean; language: Language
  onTrigger: (id: string) => void; onSetCooldown: (id: string, seconds: number) => void
}) {
  const t = copy[language]
  const Icon = effectIcons[effect.id]
  const cooldownMs = Math.max(0, effect.nextAvailableAt - now)
  const activeMs = Math.max(0, effect.activeUntil - now)
  const isCoolingDown = cooldownMs > 0
  const isActive = activeMs > 0
  const rawRemaining = Math.ceil((isActive ? activeMs : cooldownMs) / 1000)
  const remaining = Math.min(isActive ? effect.durationSeconds : effect.cooldownSeconds, rawRemaining)
  const progress = isCoolingDown ? Math.max(0, Math.min(100, 100 - cooldownMs / (Math.max(1, effect.cooldownSeconds) * 10))) : 100

  return <div className="effect-card">
    <button className={`effect-button ${isActive ? 'active' : ''} ${isCoolingDown ? 'cooldown' : 'ready'}`} disabled={disabled || isCoolingDown} onClick={() => onTrigger(effect.id)}>
      {Icon && <Icon className="effect-icon" />}<span className="effect-label">{effectLabel(effect.id, language, effect.label)}</span>
      <span className="effect-status">{isActive ? `${t.active} · ${remaining} ${t.secondsShort}` : isCoolingDown ? `${t.availableIn} ${remaining} ${t.secondsShort}` : t.ready}</span>
      {isCoolingDown && <span className="cooldown-track"><i style={{ width: `${progress}%` }} /></span>}
    </button>
    {canEditCooldown && <form key={effect.cooldownSeconds} className="cooldown-editor" onSubmit={event => { event.preventDefault(); onSetCooldown(effect.id, Number(new FormData(event.currentTarget).get('cooldown'))) }}>
      <label>{t.cooldown}<input name="cooldown" type="number" min="0" max="3600" defaultValue={effect.cooldownSeconds} /></label><button>OK</button>
    </form>}
  </div>
}

function JoinScreen({ language, onLanguage, onJoin }: { language: Language; onLanguage: (language: Language) => void; onJoin: (credentials: Credentials) => void }) {
  const [room, setRoom] = useState('K7M2')
  const [name, setName] = useState('')
  const [token, setToken] = useState('')
  const [role, setRole] = useState<Credentials['role']>('controller')
  const canSubmit = useMemo(() => room.trim().length >= 3 && name.trim().length >= 2 && token.length >= 4, [room, name, token])
  const t = copy[language]

  const submit = (event: FormEvent) => {
    event.preventDefault()
    if (!canSubmit) return
    const credentials = { room: room.trim().toUpperCase(), name: name.trim(), token, role }
    sessionStorage.setItem('chaos-link-credentials', JSON.stringify(credentials))
    onJoin(credentials)
  }

  return <main className="join-shell"><form className="join-panel" onSubmit={submit}>
    <div className="brand large">CHAOS <em>LINK</em></div>
    <LanguageToggle language={language} onChange={onLanguage} large />
    <h1>{t.joinTitle}</h1><p>{t.joinText}</p>
    <div className="role-switch" role="group" aria-label={t.role}><button type="button" className={role === 'controller' ? 'selected' : ''} onClick={() => setRole('controller')}>{t.guest}</button><button type="button" className={role === 'admin' ? 'selected' : ''} onClick={() => setRole('admin')}>{t.admin}</button></div>
    <label>{t.room}<input value={room} onChange={event => setRoom(event.target.value)} maxLength={8} autoCapitalize="characters" /></label>
    <label>{t.yourName}<input value={name} onChange={event => setName(event.target.value)} maxLength={24} placeholder={t.namePlaceholder} autoComplete="nickname" /></label>
    <label>{role === 'admin' ? t.adminKey : t.accessKey}<input value={token} onChange={event => setToken(event.target.value)} type="password" placeholder={t.keyPlaceholder} autoComplete="current-password" /></label>
    <button className="join-button" disabled={!canSubmit}>{t.join}</button><small>{t.keyStorage}</small>
  </form></main>
}

function LoadingPanel({ language }: { language: Language }) {
  return <div className="loading-panel"><span /><p>{copy[language].connecting}</p></div>
}
