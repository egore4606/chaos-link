import { useCallback, useEffect, useRef, useState } from 'react'
import type { ConnectionState, Credentials, Snapshot } from './types'
import { socketError, type Language } from './i18n'

type Notice = { tone: 'error' | 'info'; text: string } | null

export function useChaosSocket(credentials: Credentials | null, language: Language) {
  const [snapshot, setSnapshot] = useState<Snapshot | null>(null)
  const [connection, setConnection] = useState<ConnectionState>('disconnected')
  const [notice, setNotice] = useState<Notice>(null)
  const [clockOffset, setClockOffset] = useState(0)
  const socketRef = useRef<WebSocket | null>(null)
  const languageRef = useRef(language)

  useEffect(() => {
    languageRef.current = language
  }, [language])

  useEffect(() => {
    if (!credentials) return
    let retryTimer: number | undefined
    let connectTimer: number | undefined
    let heartbeatTimer: number | undefined
    let stopped = false
    let retryAllowed = true

    const clearSocketTimers = () => {
      window.clearTimeout(connectTimer)
      window.clearInterval(heartbeatTimer)
    }

    const scheduleReconnect = () => {
      if (stopped || !retryAllowed || retryTimer !== undefined) return
      retryTimer = window.setTimeout(() => {
        retryTimer = undefined
        connect()
      }, 1500)
    }

    const connect = () => {
      if (stopped) return
      clearSocketTimers()
      setConnection('connecting')
      const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
      const url = new URL(`${protocol}//${window.location.host}/ws`)
      url.searchParams.set('room', credentials.room.toUpperCase())
      url.searchParams.set('role', credentials.role)
      url.searchParams.set('name', credentials.name)
      const socket = new WebSocket(url)
      socketRef.current = socket
      let lastMessageAt = Date.now()

      connectTimer = window.setTimeout(() => {
        if (socketRef.current === socket && socket.readyState !== WebSocket.OPEN) {
          socket.close()
          scheduleReconnect()
        }
      }, 8000)

      socket.onopen = () => {
        if (socketRef.current !== socket) return
        window.clearTimeout(connectTimer)
        setConnection('connected')
        setNotice(null)
        socket.send(JSON.stringify({ type: 'auth', token: credentials.token }))
        socket.send(JSON.stringify({ type: 'ping', clientTime: Date.now() }))
        heartbeatTimer = window.setInterval(() => {
          if (socketRef.current !== socket || socket.readyState !== WebSocket.OPEN) return
          if (Date.now() - lastMessageAt > 30000) {
            socket.close(4000, 'Heartbeat timeout')
            return
          }
          socket.send(JSON.stringify({ type: 'ping', clientTime: Date.now() }))
        }, 10000)
      }
      socket.onmessage = (event) => {
        if (socketRef.current !== socket) return
        lastMessageAt = Date.now()
        const message = JSON.parse(event.data)
        if (message.type === 'snapshot') {
          setSnapshot(message)
          setClockOffset(message.serverTime - Date.now())
        } else if (message.type === 'pong') {
          const roundTrip = Date.now() - message.clientTime
          setClockOffset(message.serverTime + roundTrip / 2 - Date.now())
        } else if (message.type === 'triggerRejected' || message.type === 'error') {
          setNotice({ tone: 'error', text: socketError(message.code, languageRef.current, message.message) })
        } else if (message.type === 'hostControlAccepted') {
          setNotice({ tone: 'info', text: message.action === 'restart'
            ? (languageRef.current === 'ru' ? 'Перезапуск запущен. Панель скоро переподключится.' : 'Restart started. The panel will reconnect shortly.')
            : (languageRef.current === 'ru' ? 'Выключение запущено.' : 'Shutdown started.') })
        }
      }
      socket.onerror = () => {
        if (socketRef.current === socket) setConnection('error')
      }
      socket.onclose = (event) => {
        clearSocketTimers()
        if (socketRef.current !== socket) return
        socketRef.current = null
        if (event.code === 1008) {
          retryAllowed = false
          setConnection('error')
          setNotice({ tone: 'error', text: languageRef.current === 'ru'
            ? 'Ключ доступа устарел или неверен. Нажмите «Выйти» и войдите с текущим ключом друзей.'
            : 'The access key is outdated or invalid. Leave the room and sign in with the current friends key.' })
          return
        }
        setConnection('disconnected')
        scheduleReconnect()
      }
    }

    const reconnectWhenVisible = () => {
      if (document.visibilityState !== 'visible' || !retryAllowed) return
      const socket = socketRef.current
      if (!socket || socket.readyState === WebSocket.CLOSED || socket.readyState === WebSocket.CLOSING) {
        window.clearTimeout(retryTimer)
        retryTimer = undefined
        connect()
      }
    }

    document.addEventListener('visibilitychange', reconnectWhenVisible)
    connect()
    return () => {
      stopped = true
      window.clearTimeout(retryTimer)
      clearSocketTimers()
      document.removeEventListener('visibilitychange', reconnectWhenVisible)
      socketRef.current?.close()
      socketRef.current = null
    }
  }, [credentials])

  const send = useCallback((payload: object) => {
    if (socketRef.current?.readyState !== WebSocket.OPEN) {
      setNotice({ tone: 'error', text: languageRef.current === 'ru' ? 'Нет соединения с комнатой' : 'Not connected to the room' })
      return false
    }
    socketRef.current.send(JSON.stringify(payload))
    return true
  }, [])

  const trigger = useCallback((effectId: string) => {
    setNotice(null)
    send({ type: 'trigger', effectId })
  }, [send])

  const setPaused = useCallback((paused: boolean) => {
    setNotice(null)
    send({ type: 'pause', paused })
  }, [send])

  const blockUser = useCallback((targetClientId: string, blockSeconds: number) => {
    setNotice(null)
    send({ type: 'blockUser', targetClientId, blockSeconds })
  }, [send])

  const setCooldown = useCallback((effectId: string, cooldownSeconds: number) => {
    setNotice(null)
    send({ type: 'setCooldown', effectId, cooldownSeconds })
  }, [send])

  const hostControl = useCallback((action: 'restart' | 'shutdown') => {
    setNotice(null)
    send({ type: 'hostControl', action })
  }, [send])

  return { snapshot, connection, notice, clockOffset, trigger, setPaused, blockUser, setCooldown, hostControl }
}
