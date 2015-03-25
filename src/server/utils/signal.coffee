events = require('events')
util = require('util')

log = require('./log')
logger = log.getLogger('SIGNAL')

terminate = ->
  log.close( ->
    process.exit()
  )

class Signal
  util.inherits(Signal, events.EventEmitter)

  constructor: ->
    self = this

    process.on('exit', ->
      # this doesn't necessarily write to the underlying file, no hurt to put it here
      logger.info('Exited')
    )
    process.on('SIGHUP', -> ) # don't stop when SIGHUP
    process.once('SIGTERM', ->
      logger.info('SIGTERM received, exiting...')
      self.exit()
      process.on('SIGTERM', ->
        throw new Error('Program failed to exit before a second SIGTERM signaled')
      )
    )
    process.on('SIGUSR1', ->
      logger.info('SIGUSR1 received, GCing...')
      gc() if gc?
    )
    process.on('uncaughtException', (err) ->
      logger.caught(err, 'Unexpected exception detected')
      terminate()
    )

  exit: ->
    this.emit('exiting')

  abort: (err) ->
    if err?
      logger.caught(err, 'Program Aborted')
    else
      logger.error('Program Aborted')
    terminate()

module.exports = new Signal
