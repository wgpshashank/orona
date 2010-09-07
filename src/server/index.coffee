###
Orona, © 2010 Stéphan Kochen

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.
###

fs               = require 'fs'
url              = require 'url'
connect          = require 'connect'
WebSocket        = require './websocket'
ServerContext    = require './net'
Simulation       = require '..'
Tank             = require '../tank'
map              = require '../map'
net              = require '../net'
{pack}           = require '../struct'
{TICK_LENGTH_MS} = require '../constants'


class Game
  constructor: (gameMap) ->
    @sim = new Simulation(gameMap)
    @netctx = new ServerContext(@sim)
    @oddTick = no

  # Connection handling.

  onConnect: (ws) ->
    # In order to create the tank object, we need to be in the networking context.
    tank = net.inContext @netctx, => @sim.spawn Tank
    tank.client = null
    data = new Buffer(@netctx.changes)
    @broadcast data.toString('base64')

    # Set-up the websocket parameters.
    tank.client = ws
    ws.setTimeout 10000 # Disconnect after 10s of inactivity.
    ws.heartbeatTimer = 0
    ws.on 'message', (message) => @onMessage(tank, message)
    ws.on 'end', => @onEnd(tank)
    ws.on 'error', (exception) => @onError(tank, exception)
    ws.on 'timeout', => @onError(tank, 'Timed out')

    ws.buffered =>
      # Send the current map state.
      mapData = new Buffer(@sim.map.dump())
      ws.sendMessage mapData.toString('base64')

      # To synchronize the object list to the client, we simulate creation of all objects.
      net.inContext @netctx, =>
        for obj in @sim.objects
          net.created obj
      data = new Buffer(@netctx.changes)
      ws.sendMessage data.toString('base64')

      # Send the welcome message, along with the index of this player's tank.
      data = new Buffer(pack('BI', net.WELCOME_MESSAGE, tank.idx))
      ws.sendMessage data.toString('base64')

  onEnd: (tank) ->
    return unless ws = tank.client
    tank.client = null
    ws.end()
    @onDisconnect(tank)

  onError: (tank, exception) ->
    return unless ws = tank.client
    tank.client = null
    # FIXME: log exception
    ws.destroy()
    @onDisconnect(tank)

  onDisconnect: (tank) ->
    # In order to destroy the tank object, we need to be in the networking context.
    net.inContext @netctx, => @sim.destroy tank
    data = new Buffer(@netctx.changes)
    @broadcast data.toString('base64')

  onMessage: (tank, message) ->
    return unless tank.client
    switch message
      when '' then tank.client.heartbeatTimer = 0
      when net.START_TURNING_CCW  then tank.turningCounterClockwise = yes
      when net.STOP_TURNING_CCW   then tank.turningCounterClockwise = no
      when net.START_TURNING_CW   then tank.turningClockwise = yes
      when net.STOP_TURNING_CW    then tank.turningClockwise = no
      when net.START_ACCELERATING then tank.accelerating = yes
      when net.STOP_ACCELERATING  then tank.accelerating = no
      when net.START_BRAKING      then tank.braking = yes
      when net.STOP_BRAKING       then tank.braking = no
      when net.START_SHOOTING     then tank.shooting = yes
      when net.STOP_SHOOTING      then tank.shooting = no
      else @onError(tank, 'Received an unknown command')

  # Broadcast a message to all connected clients.
  broadcast: (message) ->
    for {client} in @sim.tanks when client != null
      client.sendMessage(message)
    return

  # An unreliable broadcast message is a message that may be dropped. Each client sends a periodic
  # hearbeat. If not received in a timely fashion, we drop some of the client's messages.
  broadcastUnreliable: (message) ->
    for {client} in @sim.tanks when client != null
      # Ticks are every 20ms. Network updates are every odd tick, i.e. every 40ms.
      # Allow a client to lag 20 updates behind, i.e. 800ms, before dropping messages.
      client.sendMessage(message) unless client.heartbeatTimer > 20
    return

  # Simulation updates.

  tick: ->
    net.inContext @netctx, => @sim.tick()

    # Buffer everything to minimize the number of packets.
    WebSocket.prototype.buffered()

    # Send critical updates.
    if @netctx.changes.length > 0
      data = new Buffer(@netctx.changes)
      @broadcast data.toString('base64')

    # Send attribute updates at half the tickrate.
    if @oddTick = !@oddTick
      data = new Buffer(@netctx.dump())
      @broadcastUnreliable data.toString('base64')

    for {client} in @sim.tanks when client != null
      # Increment the heartbeat counters.
      client.heartbeatTimer++ if @oddTick
      # Flush all buffers.
      client.flush()

    return


class Application
  constructor: ->
    @games = []
    @timer = setInterval =>
      for game in @games
        game.tick()
      return
    , TICK_LENGTH_MS

    # FIXME: this is for the demo
    data = fs.readFileSync 'maps/everard-island.map'
    gameMap = map.load data
    @games.push new Game(gameMap)

  destroy: ->
    # FIXME: The interval should be deactivated automatically when
    # there are no games. (And reactivated once a new one starts.)
    # Maybe we shouldn't update empty games either?
    clearInterval @timer

  # Determine what will handle a WebSocket's 'connect' event, based on
  # the resource that was requested.
  getSocketPathHandler: (path) ->
    # FIXME: Simple lobby with chat and match making.
    if path == '/lobby' then false

    # FIXME: Match joining based on a UUID.
    else if path.indexOf('/match/') == 0 then false

    # FIXME: This is the temporary entry point while none of the above is implemented.
    else if path == '/demo' then (ws) => @games[0].onConnect ws

    else false

  # Handle the 'upgrade' event.
  handleWebsocket: (request, connection, initialData) ->
    return connection.destroy() unless request.method == 'GET'

    path = url.parse(request.url).pathname
    handler = @getSocketPathHandler(path)
    return connection.destroy() if handler == false

    ws = new WebSocket(request, connection, initialData)
    ws.on 'connect', -> handler(ws)


# Don't export a server directly, but this factory function. Once called, the timer loop will
# start. I believe it's untidy to have timer loops start after a simple require().
createBoloServer = ->
  # FIXME: Correct way to find the path to the 'public' directory?
  server = connect.createServer(connect.logger(), connect.staticProvider('public'))

  # FIXME: There's no good way to deal with upgrades in Connect, yet. (issue #61)
  # (Servers that wrap this application will fail.)
  boloApp = new Application()
  server.on 'upgrade', (request, connection, initialData) ->
    boloApp.handleWebsocket(request, connection, initialData)

  server


# Exports.
module.exports = createBoloServer