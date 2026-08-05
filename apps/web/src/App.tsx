import { FormEvent, useEffect, useMemo, useState } from 'react'
import { Check, LogOut, RefreshCcw, ShieldAlert, Wifi, WifiOff, effectIcons } from './icons'
import type { Controller, Credentials, Effect } from './types'
import { useChaosSocket } from './useChaosSocket'

const categoryOrder = ['Быстрые действия', 'Управление', 'Экран и звук']

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
  const { snapshot, connection, notice, clockOffset, trigger, setPaused, blockUser, setCooldown } = useChaosSocket(credentials)
  const [clientNow, setClientNow] = useState(Date.now)

  useEffect(() => {
    const timer = window.setInterval(() => setClientNow(Date.now()), 250)
    return () => window.clearInterval(timer)
  }, [])

  if (!credentials) return <JoinScreen onJoin={setCredentials} />
  const isAdmin = credentials.role === 'admin'

  const disconnect = () => {
    sessionStorage.removeItem('chaos-link-credentials')
    setCredentials(null)
  }

  const now = clientNow + clockOffset
  const selfBlocked = (snapshot?.controllers.find(item => item.name === credentials.name && item.role === 'controller')?.blockedUntil ?? 0) > now
  const grouped = categoryOrder.map(category => ({
    category,
    effects: snapshot?.effects.filter(effect => effect.category === category) ?? [],
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
        onBlockUser={blockUser}
        onDisconnect={disconnect}
      />

      <section className={`system-strip ${snapshot?.paused ? 'is-paused' : ''}`}>
        <div className="system-message">
          <div className="system-icon">{snapshot?.paused ? <ShieldAlert /> : <Check />}</div>
          <div>
            <h1>{snapshot?.paused ? 'Система на паузе' : 'Система активна'}</h1>
            <p>{snapshot?.paused ? 'Команды заблокированы, активные эффекты остановлены.' : 'Один игровой ПК. Общий кулдаун синхронизирован для всех контроллеров.'}</p>
          </div>
        </div>
        <button
          className={`pause-button ${snapshot?.paused ? 'resume' : ''}`}
          onClick={() => setPaused(!snapshot?.paused)}
          disabled={!isAdmin || !snapshot || connection !== 'connected'}
          title={isAdmin ? undefined : 'Паузой управляет только администратор'}
        >
          {snapshot?.paused ? <RefreshCcw /> : <ShieldAlert />}
          <span>{!isAdmin ? 'Пауза — только админ' : snapshot?.paused ? 'Возобновить' : 'Экстренная пауза'}</span>
        </button>
      </section>

      {notice && <div className={`notice ${notice.tone}`}>{notice.text}</div>}

      <div className="dashboard-grid">
        <section className="effects-column" aria-label="Наказания">
          {grouped.map(group => group.effects.length > 0 && (
            <EffectGroup
              key={group.category}
              title={group.category}
              effects={group.effects}
              now={now}
              disabled={!snapshot?.agentConnected || !!snapshot?.paused || selfBlocked || connection !== 'connected'}
              canEditCooldown={isAdmin}
              onTrigger={trigger}
              onSetCooldown={setCooldown}
            />
          ))}
          {!snapshot && <LoadingPanel />}
        </section>

        <aside className="event-panel">
          <div className="panel-heading">
            <h2>Журнал событий</h2>
            <span>По серверу</span>
          </div>
          <div className="event-list">
            {snapshot?.events.length ? snapshot.events.map(event => (
              <article className="event-row" key={event.eventId}>
                <div className="avatar small">{event.actor.slice(0, 1).toUpperCase()}</div>
                <div className="event-copy">
                  <strong>{event.actor}</strong>
                  <span>{event.effectLabel}</span>
                </div>
                <div className={`event-state ${event.status}`}>
                  <span>{event.status === 'executed' ? 'Выполнено' : event.status === 'failed' ? 'Ошибка' : 'Отправлено'}</span>
                  <time>{new Date(event.timestamp).toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit', second: '2-digit' })}</time>
                </div>
              </article>
            )) : (
              <div className="empty-state">
                <span>Команды ещё не запускались</span>
                <small>Первое действие появится здесь</small>
              </div>
            )}
          </div>
        </aside>
      </div>
    </main>
  )
}

function Header({ roomCode, agentConnected, connection, controllers, now, isAdmin, onBlockUser, onDisconnect }: {
  roomCode: string
  agentConnected: boolean
  connection: string
  controllers: Controller[]
  now: number
  isAdmin: boolean
  onBlockUser: (id: string, blockSeconds: number) => void
  onDisconnect: () => void
}) {
  return (
    <header className="topbar">
      <div className="brand">CHAOS <em>LINK</em></div>
      <div className="room-code"><span>Код комнаты</span><strong>{roomCode}</strong></div>
      <div className={`agent-status ${agentConnected ? 'online' : ''}`}>
        {agentConnected ? <Wifi /> : <WifiOff />}
        <div><strong>{agentConnected ? 'Игровой ПК подключён' : 'Игровой ПК не подключён'}</strong><span>{connection === 'connected' ? 'Связь с комнатой установлена' : connection === 'error' ? 'Ошибка подключения' : 'Переподключение…'}</span></div>
      </div>
      <div className="controller-list">
        {controllers.map(controller => {
          const blocked = controller.blockedPermanently || controller.blockedUntil > now
          const status = controller.role === 'admin'
            ? 'Администратор'
            : controller.blockedPermanently
              ? 'Заблокирован навсегда'
              : controller.blockedUntil > now
                ? `Блок · ${Math.ceil((controller.blockedUntil - now) / 1000)} с`
                : 'Онлайн'
          return (
            <div className={`controller ${blocked ? 'blocked' : ''}`} key={controller.id}>
              <div className="avatar">{controller.name.slice(0, 1).toUpperCase()}</div>
              <div className="controller-copy"><strong>{controller.name}</strong><span><i />{status}</span></div>
              {isAdmin && controller.role === 'controller' && (
                <div className="controller-actions">
                  {blocked ? (
                    <button type="button" onClick={() => onBlockUser(controller.id, 0)}>Разблокировать</button>
                  ) : (
                    <>
                      <button type="button" onClick={() => onBlockUser(controller.id, 30)}>30 сек</button>
                      <button type="button" onClick={() => onBlockUser(controller.id, -1)}>Навсегда</button>
                    </>
                  )}
                </div>
              )}
            </div>
          )
        })}
      </div>
      <button className="icon-button" onClick={onDisconnect} aria-label="Выйти из комнаты" title="Выйти из комнаты"><LogOut /></button>
    </header>
  )
}

function EffectGroup({ title, effects, now, disabled, canEditCooldown, onTrigger, onSetCooldown }: {
  title: string
  effects: Effect[]
  now: number
  disabled: boolean
  canEditCooldown: boolean
  onTrigger: (id: string) => void
  onSetCooldown: (id: string, seconds: number) => void
}) {
  return (
    <section className="effect-group">
      <div className="group-heading"><h2>{title}</h2><span /></div>
      <div className="effect-grid">
        {effects.map(effect => <EffectButton key={effect.id} effect={effect} now={now} disabled={disabled} canEditCooldown={canEditCooldown} onTrigger={onTrigger} onSetCooldown={onSetCooldown} />)}
      </div>
    </section>
  )
}

function EffectButton({ effect, now, disabled, canEditCooldown, onTrigger, onSetCooldown }: {
  effect: Effect
  now: number
  disabled: boolean
  canEditCooldown: boolean
  onTrigger: (id: string) => void
  onSetCooldown: (id: string, seconds: number) => void
}) {
  const Icon = effectIcons[effect.id]
  const cooldownMs = Math.max(0, effect.nextAvailableAt - now)
  const activeMs = Math.max(0, effect.activeUntil - now)
  const isCoolingDown = cooldownMs > 0
  const isActive = activeMs > 0
  const rawRemaining = Math.ceil((isActive ? activeMs : cooldownMs) / 1000)
  const remaining = Math.min(isActive ? effect.durationSeconds : effect.cooldownSeconds, rawRemaining)
  const progress = isCoolingDown ? Math.max(0, Math.min(100, 100 - cooldownMs / (Math.max(1, effect.cooldownSeconds) * 10))) : 100

  return (
    <div className="effect-card">
      <button
      className={`effect-button ${isActive ? 'active' : ''} ${isCoolingDown ? 'cooldown' : 'ready'}`}
      disabled={disabled || isCoolingDown}
      onClick={() => onTrigger(effect.id)}
      >
        {Icon && <Icon className="effect-icon" />}
        <span className="effect-label">{effect.label}</span>
        <span className="effect-status">{isActive ? `Активно · ${remaining} сек` : isCoolingDown ? `Доступно через ${remaining} сек` : 'Готово'}</span>
        {isCoolingDown && <span className="cooldown-track"><i style={{ width: `${progress}%` }} /></span>}
      </button>
      {canEditCooldown && (
        <form key={effect.cooldownSeconds} className="cooldown-editor" onSubmit={event => { event.preventDefault(); onSetCooldown(effect.id, Number(new FormData(event.currentTarget).get('cooldown'))) }}>
          <label>Кулдаун<input name="cooldown" type="number" min="0" max="3600" defaultValue={effect.cooldownSeconds} /></label>
          <button>OK</button>
        </form>
      )}
    </div>
  )
}

function JoinScreen({ onJoin }: { onJoin: (credentials: Credentials) => void }) {
  const [room, setRoom] = useState('K7M2')
  const [name, setName] = useState('')
  const [token, setToken] = useState('')
  const [role, setRole] = useState<Credentials['role']>('controller')
  const canSubmit = useMemo(() => room.trim().length >= 3 && name.trim().length >= 2 && token.length >= 4, [room, name, token])

  const submit = (event: FormEvent) => {
    event.preventDefault()
    if (!canSubmit) return
    const credentials = { room: room.trim().toUpperCase(), name: name.trim(), token, role }
    sessionStorage.setItem('chaos-link-credentials', JSON.stringify(credentials))
    onJoin(credentials)
  }

  return (
    <main className="join-shell">
      <form className="join-panel" onSubmit={submit}>
        <div className="brand large">CHAOS <em>LINK</em></div>
        <h1>Подключиться к комнате</h1>
        <p>Один игровой ПК, любое число гостей и общий серверный кулдаун.</p>
        <div className="role-switch" role="group" aria-label="Роль">
          <button type="button" className={role === 'controller' ? 'selected' : ''} onClick={() => setRole('controller')}>Гость</button>
          <button type="button" className={role === 'admin' ? 'selected' : ''} onClick={() => setRole('admin')}>Администратор</button>
        </div>
        <label>Код комнаты<input value={room} onChange={event => setRoom(event.target.value)} maxLength={8} autoCapitalize="characters" /></label>
        <label>Ваше имя<input value={name} onChange={event => setName(event.target.value)} maxLength={24} placeholder="Например, Егор" autoComplete="nickname" /></label>
        <label>{role === 'admin' ? 'Ключ администратора' : 'Ключ доступа'}<input value={token} onChange={event => setToken(event.target.value)} type="password" placeholder="Получите у владельца" autoComplete="current-password" /></label>
        <button className="join-button" disabled={!canSubmit}>Войти в комнату</button>
        <small>Ключ хранится только до закрытия вкладки.</small>
      </form>
    </main>
  )
}

function LoadingPanel() {
  return <div className="loading-panel"><span /><p>Подключаемся к комнате…</p></div>
}
