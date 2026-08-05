import type { RoomEvent } from './types'

export type Language = 'ru' | 'en'

export const copy = {
  ru: {
    roomCode: 'Код комнаты', pcConnected: 'Игровой ПК подключён', pcOffline: 'Игровой ПК не подключён',
    roomConnected: 'Связь с комнатой установлена', connectionError: 'Ошибка подключения', reconnecting: 'Переподключение…',
    admin: 'Администратор', online: 'Онлайн', blockedForever: 'Заблокирован навсегда', blocked: 'Блок',
    unblock: 'Разблокировать', seconds30: '30 сек', forever: 'Навсегда', logout: 'Выйти из комнаты',
    activeTitle: 'Система активна', pausedTitle: 'Система на паузе',
    activeText: 'Один игровой ПК. Общий кулдаун синхронизирован для всех контроллеров.',
    pausedText: 'Команды заблокированы, активные эффекты остановлены.', adminPauseOnly: 'Паузой управляет только администратор',
    adminPauseButton: 'Пауза — только админ', resume: 'Возобновить', emergencyPause: 'Экстренная пауза',
    restart: 'Перезапустить', shutdown: 'Выключить', restartTitle: 'Полностью перезапустить Chaos Link',
    shutdownTitle: 'Полностью выключить Chaos Link', restartConfirm: 'Перезапустить сервер и игровой агент? Соединение восстановится автоматически.',
    shutdownConfirm: 'Полностью выключить сервер и игровой агент? Запустить их снова можно будет только скриптом запуска.',
    eventsAria: 'Наказания', journal: 'Журнал событий', onServer: 'По серверу', executed: 'Выполнено', failed: 'Ошибка', sent: 'Отправлено',
    noCommands: 'Команды ещё не запускались', firstCommand: 'Первое действие появится здесь', active: 'Активно', availableIn: 'Доступно через', ready: 'Готово',
    secondsShort: 'сек', cooldown: 'Кулдаун', connecting: 'Подключаемся к комнате…',
    joinTitle: 'Подключиться к комнате', joinText: 'Один игровой ПК, любое число гостей и общий серверный кулдаун.',
    role: 'Роль', guest: 'Гость', room: 'Код комнаты', yourName: 'Ваше имя', namePlaceholder: 'Например, Егор',
    adminKey: 'Ключ администратора', accessKey: 'Ключ доступа', keyPlaceholder: 'Получите у владельца', join: 'Войти в комнату',
    keyStorage: 'Ключ хранится только до закрытия вкладки.', language: 'Язык',
  },
  en: {
    roomCode: 'Room code', pcConnected: 'Gaming PC connected', pcOffline: 'Gaming PC offline',
    roomConnected: 'Connected to the room', connectionError: 'Connection error', reconnecting: 'Reconnecting…',
    admin: 'Administrator', online: 'Online', blockedForever: 'Blocked permanently', blocked: 'Blocked',
    unblock: 'Unblock', seconds30: '30 sec', forever: 'Forever', logout: 'Leave room',
    activeTitle: 'System active', pausedTitle: 'System paused',
    activeText: 'One gaming PC. Shared cooldowns are synchronized for every controller.',
    pausedText: 'Commands are blocked and active effects have been stopped.', adminPauseOnly: 'Only the administrator can control pause',
    adminPauseButton: 'Admin pause only', resume: 'Resume', emergencyPause: 'Emergency pause',
    restart: 'Restart', shutdown: 'Shut down', restartTitle: 'Fully restart Chaos Link',
    shutdownTitle: 'Fully shut down Chaos Link', restartConfirm: 'Restart the server and gaming agent? The connection will recover automatically.',
    shutdownConfirm: 'Fully stop the server and gaming agent? They can only be started again with the launch script.',
    eventsAria: 'Effects', journal: 'Event log', onServer: 'Server-wide', executed: 'Executed', failed: 'Failed', sent: 'Sent',
    noCommands: 'No commands have been run yet', firstCommand: 'The first action will appear here', active: 'Active', availableIn: 'Available in', ready: 'Ready',
    secondsShort: 'sec', cooldown: 'Cooldown', connecting: 'Connecting to the room…',
    joinTitle: 'Join a room', joinText: 'One gaming PC, any number of guests, and shared server cooldowns.',
    role: 'Role', guest: 'Guest', room: 'Room code', yourName: 'Your name', namePlaceholder: 'For example, Alex',
    adminKey: 'Administrator key', accessKey: 'Access key', keyPlaceholder: 'Get it from the owner', join: 'Join room',
    keyStorage: 'The key is stored only until this tab is closed.', language: 'Language',
  },
} as const

const effects: Record<string, Record<Language, string>> = {
  knife: { ru: 'Достать нож', en: 'Pull out knife' }, reload: { ru: 'Перезарядка', en: 'Reload' },
  jump: { ru: 'Прыжок', en: 'Jump' }, drop_weapon: { ru: 'Выбросить оружие', en: 'Drop weapon' },
  mouse_jerk: { ru: 'Срыв сенсора', en: 'Jerk the mouse' }, hold_ctrl: { ru: 'Удерживать CTRL', en: 'Hold CTRL' },
  block_wasd: { ru: 'Блокировать WASD', en: 'Block WASD' }, block_lmb: { ru: 'Блокировать ЛКМ', en: 'Block left click' },
  grenade_feet: { ru: 'Граната под себя', en: 'Grenade at your feet' }, flash: { ru: 'Флешка', en: 'Flashbang' },
  screamer: { ru: 'Скример', en: 'Screamer' },
}

export const categoryIds = [
  { id: 'quick', effectIds: ['knife', 'reload', 'jump', 'drop_weapon'] },
  { id: 'control', effectIds: ['mouse_jerk', 'hold_ctrl', 'block_wasd', 'block_lmb', 'grenade_feet'] },
  { id: 'media', effectIds: ['flash', 'screamer'] },
] as const

const categories = {
  quick: { ru: 'Быстрые действия', en: 'Quick actions' },
  control: { ru: 'Управление', en: 'Controls' },
  media: { ru: 'Экран и звук', en: 'Screen and sound' },
} as const

const socketErrors: Record<string, Record<Language, string>> = {
  invalid_json: { ru: 'Некорректное сообщение', en: 'Invalid message' }, admin_required: { ru: 'Команда доступна только администратору', en: 'Administrator access is required' },
  unsupported_message: { ru: 'Команда не поддерживается', en: 'Unsupported command' }, unknown_effect: { ru: 'Неизвестный эффект', en: 'Unknown effect' },
  paused: { ru: 'Система на паузе', en: 'The system is paused' }, user_blocked: { ru: 'Администратор заблокировал ваши команды', en: 'The administrator blocked your commands' },
  agent_offline: { ru: 'Игровой ПК не подключён', en: 'The gaming PC is offline' }, cooldown: { ru: 'Общий кулдаун ещё активен', en: 'The shared cooldown is still active' },
  user_not_found: { ru: 'Пользователь уже отключился', en: 'The user has already disconnected' }, invalid_block_duration: { ru: 'Некорректное время блокировки', en: 'Invalid block duration' },
  invalid_cooldown: { ru: 'Некорректный кулдаун', en: 'Invalid cooldown' }, invalid_host_action: { ru: 'Неизвестная системная команда', en: 'Unknown system command' },
  host_control_unavailable: { ru: 'Игровой агент не подключён', en: 'The gaming agent is offline' },
}

export function effectLabel(id: string, language: Language, fallback = id) { return effects[id]?.[language] ?? fallback }
export function categoryLabel(id: typeof categoryIds[number]['id'], language: Language) { return categories[id][language] }
export function socketError(code: string | undefined, language: Language, fallback?: string) { return (code && socketErrors[code]?.[language]) || fallback || (language === 'ru' ? 'Неизвестная ошибка' : 'Unknown error') }
export function eventLabel(event: RoomEvent, language: Language) {
  if (effects[event.effectId]) return effectLabel(event.effectId, language, event.effectLabel)
  if (event.effectId === 'system_pause') return event.effectLabel.includes('возобнов') ? (language === 'ru' ? 'Система возобновлена' : 'System resumed') : (language === 'ru' ? 'Экстренная пауза' : 'Emergency pause')
  if (event.effectId === 'user_block') return language === 'ru' ? event.effectLabel : event.effectLabel.replace('Блокировка:', 'User block:')
  if (event.effectId === 'cooldown_change') return language === 'ru' ? event.effectLabel : `Cooldown: ${event.effectLabel.replace('Кулдаун:', '').trim()}`
  if (event.effectId === 'host_control') return event.effectLabel.includes('ерезапуск') ? (language === 'ru' ? 'Перезапуск системы' : 'System restart') : (language === 'ru' ? 'Выключение системы' : 'System shutdown')
  return event.effectLabel
}

export function readLanguage(): Language {
  const saved = localStorage.getItem('chaos-link-language')
  if (saved === 'ru' || saved === 'en') return saved
  return navigator.language.toLowerCase().startsWith('ru') ? 'ru' : 'en'
}
