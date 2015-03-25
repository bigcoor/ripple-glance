events = require('events')
fs = require('fs')
util = require('util')

logger = require('./log').getLogger('CONFIG')
signal = require('./signal')
utils = require('./routines')

exiting = false
polling = null

hostname = null
deployment = null
basenames = null
configDir = null

watcher = null

dirNotExists = false

class Config
  util.inherits(Config, events.EventEmitter)

  constructor: ->
    try
      hostname = process.env.HOST || process.env.HOSTNAME
      hostname = require('os').hostname() unless hostname
      hostname = hostname.split('.')[0]
    catch err
      logger.caught(err, 'Failed to load hostname')

    deployment = process.env.NODE_ENV || 'development'

    basenames = ['default',
                 hostname,
                 (if deployment != 'production' then 'dev-default' else null),
                 deployment,
                 deployment + '-private' ,
                 (if hostname then deployment + '-' + hostname else null),
                 'local',
                 deployment + '-local']

    configDir = process.env.NODE_CONFIG_DIR || process.cwd() + '/build/server/configs'

    @load()

    self = this

    watch = ->
      polling = null
      try
        watcher = fs.watch(configDir)
        if dirNotExists
          dirNotExists = false
          logger.verbose('Config directory `%s` newly created', configDir)
          self.load()
        watcher.on('change', (event, filename) ->
          logger.verbose('Config watcher change event: event=%s, filename=%s', event, filename)
          self.load()
        )
        watcher.on('error', (err) ->
          logger.caught(err, 'Error occurred on config watcher')
          watcher.close()
          watcher = null
          polling = setTimeout(watch, 10000) unless exiting
        )
      catch err
        logger.debug("%s doesn't exist\n%s", configDir, err.stack)
        polling = setTimeout(watch, 10000) unless exiting
        dirNotExists = true

    signal.once('exiting', ->
      logger.info('Got exiting event')
      clearTimeout(polling) if polling?
      watcher.close() if watcher?
    )

    watch()

  load: ->
    timer = logger.time('load')

    changed = false
    self = this

    basenames.forEach((basename) ->
      return unless basename

      path = configDir + '/' + basename
      logger.verbose('Processing config file: %s', path)
      try
        content = utils.reloadModule(require.resolve(path))
        if content?
          logger.debug('File:', path, 'Content:', content)
          for name, value of content
            self[name] = {} unless self[name]?
            utils.extend(self[name], value)
          changed = true
        else
          logger.verbose('Failed to load config file: %s', path)
      catch err
        logger.verbose('Config file not found: %s', path)
    )

    this.emit('change', this) if changed

    timer.end()

  setModuleDefaults: (moduleName, defaults) ->
    this[moduleName] = {} unless this[moduleName]?
    utils.extendNew(this[moduleName], defaults)

# make sure all methods exist when log used in the middle of ctor
# must use module.exports here
module.exports = Object.create(Config.prototype)

Config.call(module.exports)
