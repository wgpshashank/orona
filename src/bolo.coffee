###
Orona, © 2010 Stéphan Kochen

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.
###

{round, floor, random, cos, sin, PI}                = Math
{Tank}                                              = require './tank'
{MapCell, map}                                      = require './map'
{TILE_SIZE_PIXEL, PIXEL_SIZE_WORLD, TICK_LENGTH_MS} = require './constants'


# Global variables.

# The tilemap Image object.
# FIXME: make this an export somewhere somehow.
window.tilemap = null
# The jQuery object referring to the canvas.
canvas = null
# The jQuery object referring to the HUD.
hud = null
# The canvas 2D drawing context.
c = null
# The Tank object controlled by the player.
player = null


Bolo =
  start: ->
    # First, make sure the tilemap is loaded.
    unless window.tilemap?
      window.tilemap = new Image()
      $(tilemap).load(Bolo.start)
      # FIXME: Handle errors
      tilemap.src = 'img/tiles2x.png'
      return

    # Initialize the canvas.
    canvas = $('#game')
    Bolo.handleResize(); $(window).resize(Bolo.handleResize)
    c = canvas[0].getContext('2d')

    # Install key handlers.
    $(document).keydown(Bolo.handleKeydown).keyup(Bolo.handleKeyup)

    # Fetch and load the map.
    $.ajax(
      url: 'maps/everard-island.txt'
      dataType: 'text'
      success: (data) ->
        map.load data

        # Create a player tank.
        start = map.starts[round(random() * (map.starts.length - 1))]
        player = new Tank(start.x, start.y, start.direction)

        # Initialize the HUD.
        hud = $('#hud')
        Bolo.initHud()

        # Start the game loop.
        Bolo.startLoop()
    )


  # Event handlers.

  handleResize: ->
    canvas[0].width  = window.innerWidth
    canvas[0].height = window.innerHeight
    canvas.css(
      width:  window.innerWidth + 'px'
      height: window.innerHeight + 'px'
    )

  handleKeydown: (e) ->
    return unless player?
    switch e.which
      when 32 then player.shooting = yes
      when 37 then player.turningCounterClockwise = yes
      when 38 then player.accelerating = yes
      when 39 then player.turningClockwise = yes
      when 40 then player.braking = yes
      else return
    e.preventDefault()

  handleKeyup: (e) ->
    return unless player?
    switch e.which
      when 32 then player.shooting = no
      when 37 then player.turningCounterClockwise = no
      when 38 then player.accelerating = no
      when 39 then player.turningClockwise = no
      when 40 then player.braking = no
      else return
    e.preventDefault()


  # Game loop.

  gameTimer: null
  lastTick: null

  startLoop: ->
    Bolo.tick()
    Bolo.lastTick = Date.now()

    Bolo.gameTimer = window.setInterval(Bolo.timerCallback, TICK_LENGTH_MS)

  stopLoop: ->
    window.clearInterval(Bolo.gameTimer)

    Bolo.gameTimer = null
    Bolo.lastTick = null

  timerCallback: ->
    now = Date.now()
    while now - Bolo.lastTick >= TICK_LENGTH_MS
      Bolo.tick()
      Bolo.lastTick += TICK_LENGTH_MS
    Bolo.draw()


  # Simulation.

  tick: ->
    player.update()


  # Graphics.

  draw: ->
    c.save()

    # Apply a translation that centers everything around the player.
    {width, height} = canvas[0]
    left = round(player.x / PIXEL_SIZE_WORLD - width  / 2)
    top =  round(player.y / PIXEL_SIZE_WORLD - height / 2)
    c.translate(-left, -top)

    # Draw all canvas elements.
    map.draw(c, left, top, left + width, top + height)
    player.draw(c)
    Bolo.drawOverlay()

    c.restore()

    Bolo.updateHud()

  drawOverlay: ->
    # FIXME: variable firing distance
    # FIXME: hide when dead
    # FIXME: just use the DOM for this?
    distance = 7 * TILE_SIZE_PIXEL
    rad = (256 - player.direction) * 2 * PI / 256
    x = round(player.x / PIXEL_SIZE_WORLD + cos(rad) * distance)
    y = round(player.y / PIXEL_SIZE_WORLD + sin(rad) * distance)

    c.drawImage tilemap,
      17 * TILE_SIZE_PIXEL,    4 * TILE_SIZE_PIXEL,     TILE_SIZE_PIXEL, TILE_SIZE_PIXEL,
      x - TILE_SIZE_PIXEL / 2, y - TILE_SIZE_PIXEL / 2, TILE_SIZE_PIXEL, TILE_SIZE_PIXEL

  initHud: ->
    # Clear all existing contents
    hud.html('')

    # Create the pillbox status indicator.
    container = $('<div/>', id: 'pillStatus').appendTo(hud)
    $('<div/>', class: 'deco').appendTo(container)
    $('<div/>', class: 'pill').appendTo(container).data('pill', pill) for pill in map.pills

    # Create the base status indicator.
    container = $('<div/>', id: 'baseStatus').appendTo(hud)
    $('<div/>', class: 'deco').appendTo(container)
    $('<div/>', class: 'base').appendTo(container).data('base', base) for base in map.bases

    # Show WIP notice. This is really a temporary hack, so FIXME someday.
    unless location.host == 'localhost'
      $('<div/>').text('This is a work-in-progress; less than alpha quality!').css(
        'position': 'absolute', 'top': '8px', 'left': '0px', 'width': '100%', 'text-align': 'center',
        'font-family': 'monospace', 'font-size': '16px', 'font-weight': 'bold', 'color': 'white'
      ).appendTo(hud);
      $('<a href="http://github.com/stephank/orona"></a>')
        .css('position': 'absolute', 'top': '0px', 'right': '0px')
        .html('<img src="http://s3.amazonaws.com/github/ribbons/forkme_right_darkblue_121621.png" alt="Fork me on GitHub">')
        .appendTo(hud);

    # One-shot update to set all the real-time attributes.
    Bolo.updateHud()

  updateHud: ->
    # Pillboxes.
    $('#pillStatus .pill').each (i, node) =>
      # FIXME: allegiance
      $(node).attr('status', 'neutral')

    # Bases.
    $('#baseStatus .base').each (i, node) =>
      # FIXME: allegiance
      $(node).attr('status', 'neutral')


# Exports.
exports.Bolo = Bolo