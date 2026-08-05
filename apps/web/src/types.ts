export type ConnectionState = 'connecting' | 'connected' | 'disconnected' | 'error'

export interface Controller {
  id: string
  name: string
  role: 'controller' | 'admin'
  blockedUntil: number
  blockedPermanently: boolean
}

export interface Effect {
  id: string
  label: string
  category: string
  icon: string
  cooldownSeconds: number
  durationSeconds: number
  nextAvailableAt: number
  activeUntil: number
}

export interface RoomEvent {
  eventId: string
  timestamp: number
  actor: string
  effectId: string
  effectLabel: string
  status: string
  detail: string
}

export interface Snapshot {
  type: 'snapshot'
  roomCode: string
  paused: boolean
  agentConnected: boolean
  controllers: Controller[]
  serverTime: number
  effects: Effect[]
  events: RoomEvent[]
}

export interface Credentials {
  room: string
  name: string
  token: string
  role: 'controller' | 'admin'
}
