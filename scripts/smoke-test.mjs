import assert from 'node:assert/strict'

const base = process.env.CHAOS_LINK_WS ?? 'ws://localhost:5075/ws'
const room = 'K7M2'

function connect(role, name, token) {
  return new Promise((resolve, reject) => {
    const url = new URL(base)
    url.searchParams.set('room', room)
    url.searchParams.set('role', role)
    url.searchParams.set('name', name)
    const socket = new WebSocket(url)
    const messages = []
    socket.addEventListener('message', event => messages.push(JSON.parse(event.data)))
    socket.addEventListener('open', () => {
      socket.send(JSON.stringify({ type: 'auth', token }))
      resolve({ socket, messages })
    })
    socket.addEventListener('error', reject)
  })
}

function waitFor(client, predicate, timeout = 2500) {
  return new Promise((resolve, reject) => {
    const started = Date.now()
    const timer = setInterval(() => {
      const found = client.messages.find(predicate)
      if (found) {
        clearInterval(timer)
        resolve(found)
      } else if (Date.now() - started > timeout) {
        clearInterval(timer)
        reject(new Error('Timed out waiting for WebSocket message'))
      }
    }, 20)
  })
}

function waitForNew(client, startIndex, predicate, timeout = 2500) {
  return new Promise((resolve, reject) => {
    const started = Date.now()
    const timer = setInterval(() => {
      const found = client.messages.slice(startIndex).find(predicate)
      if (found) {
        clearInterval(timer)
        resolve(found)
      } else if (Date.now() - started > timeout) {
        clearInterval(timer)
        reject(new Error('Timed out waiting for new WebSocket message'))
      }
    }, 20)
  })
}

const agent = await connect('agent', 'Test PC', 'agent-secret')
const first = await connect('controller', 'Егор', 'friend-access')
const second = await connect('controller', 'Макс', 'friend-access')
const admin = await connect('admin', 'Админ', 'admin-access')

first.socket.send(JSON.stringify({ type: 'pause', paused: true }))
const adminRequired = await waitFor(first, message => message.type === 'error' && message.code === 'admin_required')
assert.ok(adminRequired)

admin.socket.send(JSON.stringify({ type: 'pause', paused: true }))
await waitFor(admin, message => message.type === 'snapshot' && message.paused)
admin.socket.send(JSON.stringify({ type: 'pause', paused: false }))
await waitFor(admin, message => message.type === 'snapshot' && !message.paused && message.events.some(event => event.effectId === 'system_pause'))

admin.socket.send(JSON.stringify({ type: 'setCooldown', effectId: 'knife', cooldownSeconds: 2 }))
await waitFor(admin, message => message.type === 'snapshot' && message.effects.some(effect => effect.id === 'knife' && effect.cooldownSeconds === 2))

first.socket.send(JSON.stringify({ type: 'trigger', effectId: 'reload' }))
const command = await waitFor(agent, message => message.type === 'command' && message.effectId === 'reload')
const firstSnapshot = await waitFor(first, message => message.type === 'snapshot' && message.effects.some(effect => effect.id === 'reload' && effect.nextAvailableAt > Date.now()))
const secondSnapshot = await waitFor(second, message => message.type === 'snapshot' && message.effects.some(effect => effect.id === 'reload' && effect.nextAvailableAt > Date.now()))

const firstCooldown = firstSnapshot.effects.find(effect => effect.id === 'reload').nextAvailableAt
const secondCooldown = secondSnapshot.effects.find(effect => effect.id === 'reload').nextAvailableAt
assert.equal(firstCooldown, secondCooldown, 'Both controllers must receive one shared cooldown timestamp')

second.socket.send(JSON.stringify({ type: 'trigger', effectId: 'reload' }))
const rejection = await waitFor(second, message => message.type === 'triggerRejected' && message.effectId === 'reload')
assert.equal(rejection.code, 'cooldown')

agent.socket.send(JSON.stringify({ type: 'ack', eventId: command.eventId, status: 'executed', detail: 'Smoke test' }))
const ackSnapshot = await waitFor(first, message => message.type === 'snapshot' && message.events.some(event => event.eventId === command.eventId && event.status === 'executed'))
assert.ok(ackSnapshot)

first.socket.send(JSON.stringify({ type: 'trigger', effectId: 'jump' }))
second.socket.send(JSON.stringify({ type: 'trigger', effectId: 'jump' }))
await waitFor(agent, message => message.type === 'command' && message.effectId === 'jump')
await Promise.race([
  waitFor(first, message => message.type === 'triggerRejected' && message.effectId === 'jump'),
  waitFor(second, message => message.type === 'triggerRejected' && message.effectId === 'jump'),
])
await new Promise(resolve => setTimeout(resolve, 100))
const jumpCommands = agent.messages.filter(message => message.type === 'command' && message.effectId === 'jump')
const jumpRejections = [...first.messages, ...second.messages].filter(message => message.type === 'triggerRejected' && message.effectId === 'jump')
assert.equal(jumpCommands.length, 1, 'A simultaneous race must create exactly one agent command')
assert.equal(jumpRejections.length, 1, 'A simultaneous race must reject exactly one controller')

const usersSnapshot = await waitFor(admin, message => message.type === 'snapshot' && message.controllers.some(controller => controller.name === 'Макс'))
const secondId = usersSnapshot.controllers.find(controller => controller.name === 'Макс').id
admin.socket.send(JSON.stringify({ type: 'blockUser', targetClientId: secondId }))
await waitFor(admin, message => message.type === 'snapshot' && message.controllers.some(controller => controller.id === secondId && controller.blockedUntil > Date.now()))
second.socket.send(JSON.stringify({ type: 'trigger', effectId: 'drop_weapon' }))
const blocked = await waitFor(second, message => message.type === 'triggerRejected' && message.effectId === 'drop_weapon')
assert.equal(blocked.code, 'user_blocked')

let messageIndex = admin.messages.length
admin.socket.send(JSON.stringify({ type: 'blockUser', targetClientId: secondId, blockSeconds: 0 }))
await waitForNew(admin, messageIndex, message => message.type === 'snapshot' && message.controllers.some(controller => controller.id === secondId && controller.blockedUntil === 0))

messageIndex = admin.messages.length
admin.socket.send(JSON.stringify({ type: 'blockUser', targetClientId: secondId, blockSeconds: -1 }))
await waitForNew(admin, messageIndex, message => message.type === 'snapshot' && message.controllers.some(controller => controller.id === secondId && controller.blockedPermanently))

messageIndex = admin.messages.length
admin.socket.send(JSON.stringify({ type: 'blockUser', targetClientId: secondId, blockSeconds: 0 }))
await waitForNew(admin, messageIndex, message => message.type === 'snapshot' && message.controllers.some(controller => controller.id === secondId && !controller.blockedPermanently && controller.blockedUntil === 0))

messageIndex = agent.messages.length
first.socket.send(JSON.stringify({ type: 'trigger', effectId: 'block_lmb' }))
await waitForNew(agent, messageIndex, message => message.type === 'command' && message.effectId === 'block_lmb')

messageIndex = agent.messages.length
first.socket.send(JSON.stringify({ type: 'trigger', effectId: 'grenade_feet' }))
await waitForNew(agent, messageIndex, message => message.type === 'command' && message.effectId === 'grenade_feet')

messageIndex = first.messages.length
first.socket.send(JSON.stringify({ type: 'hostControl', action: 'restart' }))
await waitForNew(first, messageIndex, message => message.type === 'error' && message.code === 'admin_required')

const agentControlIndex = agent.messages.length
const adminControlIndex = admin.messages.length
admin.socket.send(JSON.stringify({ type: 'hostControl', action: 'restart' }))
await waitForNew(admin, adminControlIndex, message => message.type === 'hostControlAccepted' && message.action === 'restart')
await waitForNew(agent, agentControlIndex, message => message.type === 'hostControl' && message.action === 'restart')

for (const client of [agent, first, second, admin]) client.socket.close()
console.log('Smoke test passed: admin pause/block/host control, new effects, shared cooldown, atomic race rejection, and agent acknowledgement verified.')
