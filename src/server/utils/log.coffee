#TODO Add timer aggregation?
#TODO Enable log path load from config
#TODO Enable programatic log path set
#TODO apply time label to util.format

fs = require('fs')
util = require('util')

nodeId = null

configLoaded = false

levels = {
  'DEBUG': 4,
  'VERBOSE': 3,
  'INFO': 2,
  'WARN': 1,
  'ERROR': 0
}

currentLevelValue = levels.VERBOSE
if process.env.NODE_ENV == 'production'
  currentLevelValue = levels.INFO

categoryLevel = {}

getLevelFromValue = (levelValue) ->
  for level, value of levels
    return level if value == levelValue
  return null

format = (level, attributes, desc) ->
  return "[#{new Date().toISOString()}][#{nodeId ? ''}][#{level}]#{attributes} #{desc}\n"

formatInternal = (level, desc) ->
  return format(level, '[LOGGING]', desc)

toMilliseconds = (tuple) ->
  return tuple[0] * 1000 + tuple[1] / 1e6

formatError = (err) ->
  err.message += " [#{err.syscall ? 'errno'} #{err.errno}]" unless err.errno == err.code
  return err.stack ? util.inspect(err)

defaultStream = process.stderr
logDir = (process.env.APP_RUNTIME_PATH || process.cwd()) + '/logs'
logStream = null
lastLogPath = null
totalOpenFile = 0
allFileClosed = new (require('events').EventEmitter)
shuttingdown = false

# logging to default stream should use logDefault()
logDefault = (level, desc) ->
  if currentLevelValue >= levels[level]
    defaultStream.write(formatInternal(level, desc))

ensureDir = (dir) ->
  try
    fs.mkdirSync(dir) unless fs.existsSync(dir)
    return true
  catch err
    logDefault('ERROR', "Failed to make log directory `#{dir}`")
    return false

startTime = process.hrtime()
if not ensureDir(logDir)
  logDir = "/tmp/#{Math.random().toString(36).substring(2)}"
  logDefault('WARN', "Log directory defaulted to `#{logDir}`")
  if not ensureDir(logDir)
    logDefault('ERROR', "Can't log. Will now terminate")
    process.exit()
logDefault('INFO', "Log directory is now `#{logDir}`, #{toMilliseconds(process.hrtime(startTime))}ms")

close = (permanet = false) ->
  shuttingdown = true if permanet
  return unless logStream?
  logDefault('INFO', "Closing log file: `#{lastLogPath}`")
  try
    # must call end or destroySoon instead of close
    # because close doesn't flush the buffer
    logStream.destroySoon()
  catch err
    logDefault('ERROR', "Failed to flush and close the underlying stream\n#{formatError(err)}")
  logStream = null
  lastLogPath = null

getLogPath = ->
  if nodeId?
    return "#{logDir}/#{nodeId}-#{new Date().toISOString().substr(0, 10)}"
  else
    return "#{logDir}/default-#{new Date().toISOString().substr(0, 10)}"

open = (path) ->
  close()
  if shuttingdown
    logDefault('DEBUG', "Opening log file `#{path}` denied due to a requested shutdown")
    return
  logDefault('INFO', "Opening log file: `#{path}`")
  newStream = fs.createWriteStream(path, { flags: 'a' })
  cleanup = ->
    totalOpenFile--
    logStream = null if logStream == newStream
    allFileClosed.emit('finish') if totalOpenFile == 0
  openError = (err) -> # we need this because destroySoon won't trigger either error or close event if not opened
    logDefault('ERROR', "Failed to open log file `#{path}`\n#{formatError(err)}")
    newStream.removeListener('open', opened)
    cleanup()
  opened = ->
    logDefault('INFO', "Opened log file `#{path}`")
    newStream.removeListener('error', openError)
    newStream.once('error', error)
    newStream.once('close', closed)
    newStream.destroySoon() if shuttingdown # in case destroySoon in the close doesn't work as it's not opend yet
  error = (err) ->
    logDefault('ERROR', "Error occurred while writing to log file `#{path}`\n#{formatError(err)}")
    newStream.removeListener('close', closed)
    cleanup()
  closed = ->
    logDefault('INFO', "Closed log file `#{path}`")
    newStream.removeListener('error', error)
    cleanup()

  # for file open errors
  newStream.once('error', openError)
  newStream.once('open', opened)
  totalOpenFile++
  lastLogPath = path
  logStream = newStream

rotate = (newPath) ->
  return newPath != lastLogPath

ensureOpened = ->
  newPath = getLogPath()
  if not logStream? or rotate(newPath)
    open(newPath)

write = (str) ->
  ensureOpened()
  # logStream is not null even if an error event is queued, for example, when open failed
  # but this is toally fine
  (logStream ? defaultStream).write(str)

# logging in this module per se should use logInternal()
logInternal = (level, desc) ->
  if currentLevelValue >= levels[level]
    write(formatInternal(level, desc))
    return true
  return false

# time tracing in this module per se should use timeInternal()
timeInternal = (desc, start) ->
  if not start?
    if logInternal('VERBOSE', desc)
      return process.hrtime()
    else
      return null
  else
    desc = [desc, "#{toMilliseconds(process.hrtime(start))}ms."].join(' ')
    logInternal('VERBOSE', desc)

# to manually set nodeId, call require('./routines').setNodeId()
startTime = timeInternal('Loading nodeId from routines module')
try
  nodeidMod = require('./nodeid')
  nodeId = nodeidMod.nodeId()
  nodeidMod.seal()
catch err
  logInternal('ERROR', 'Failed to load nodeId\n' + formatError(err))
nodeId = '' if not nodeId
logInternal('INFO', "Set nodeId to `#{nodeId}`")
timeInternal("Loading nodeId ended.", startTime)

loadCurrentLevelValue = (config) ->
  categoryLevel = config['Logging']?.categoryLevel ? {}
  for category, value of categoryLevel
    categoryLevel[category] = levels[value]
    delete categoryLevel[category] if not categoryLevel[category]?

  level = config['Logging']?.currentLevel
  newLevelValue = levels[level]
  if not newLevelValue?
    logInternal('INFO', "Invalid logging level: #{level}")
    return false
  else if newLevelValue != currentLevelValue
    currentLevelValue = newLevelValue
    logInternal('INFO', "Logging level changed to: #{getLevelFromValue(currentLevelValue)}")
    return true
  else
    logInternal('DEBUG', "Logging level not changed: #{level}")
    return false

if process.env.NODE_LOGGING_LEVEL
  logInternal('VERBOSE', 'Set default logging level from process.env')
  loadCurrentLevelValue({ Logging: { currentLevel: process.env.NODE_LOGGING_LEVEL.toUpperCase() }})

dropCurrent = (requestedLevelValue = 0, category) ->
  return false if requestedLevelValue == 0
  if not configLoaded
    configLoaded = true
    startTime = timeInternal('Loading logging level from config module')
    try
      # put it here to give people a chance to call setDefaultLoggingLevel
      config = require('./config')
      config.setModuleDefaults('Logging', {
        currentLevel: getLevelFromValue(currentLevelValue)
      })
      # this line might cause a dup set of current value
      # but it's a must in case it's not called during config's ctor.
      # e.g. logging level is INFO or severer
      loadCurrentLevelValue(config)
      config.on('change', loadCurrentLevelValue)
    catch err
      logInternal('ERROR', 'Failed to load config module\n' + formatError(err))
    timeInternal('Loading logging level ended.', startTime)
  return categoryLevel[category] < requestedLevelValue if category and categoryLevel[category]?
  return currentLevelValue < requestedLevelValue

log = (level, category, desc) ->
  if typeof category == 'string'
    attributes = category
  else if not category?
    attributes = ''
  else if Array.isArray(category) and category.length > 0
    attributes = '[' + category.join('][') + ']'
  else
    attributes = '[' + category.toString() + ']'

  write(format(level, attributes, desc))

buildMethod = (level, levelValue, bind) ->
  return ->
    if dropCurrent(levelValue, if bind then @categoryBase else null)
      return
    desc = util.format.apply(util, arguments)
    log(level, (if bind then @category else null), desc)

buildCaught = (bind) ->
  return (err) ->
    args = Array.prototype.slice.call(arguments, 1)
    desc = util.format.apply(util, args)
    log('ERROR', (if bind then this.category else null), desc + '\n' + formatError(err))

buildTime = (bind) ->
  return (label) ->
    if dropCurrent(levels.VERBOSE)
      return { end: -> }
    return new Timer((if bind then this else null), label)

class Timer
  constructor: (@logger, @label) ->
    @start = process.hrtime()
  end: -> (@logger ? exports).verbose('%s took %dms', @label, toMilliseconds(process.hrtime(@start)))

class Logger
  for level, value of levels
    Logger::[level.toLowerCase()] = buildMethod(level, value, true)
  Logger::caught = buildCaught(true)
  Logger::time = buildTime(true)

  constructor: (@category) ->
    if not Array.isArray(@category)
      @category = Array.prototype.slice.call(arguments)
    if @category.length > 0
      @categoryBase = @category[0].trim()
      @category = '[' + @category.join('][') + ']'.replace(/\[\s*\]/g, '')
    else
      @category = ''

for level, value of levels
  exports[level.toLowerCase()] = buildMethod(level, value, false)

exports.caught = buildCaught(false)

exports.time = buildTime(false)

exports.getLogger = () ->
  return new (Function.prototype.bind.apply(Logger, [null].concat(Array.prototype.slice.call(arguments))))

# set at the very beginning to trace logs from config module
# will be overrided by settings in the config module
exports.setDefaultLoggingLevel = (level) ->
  if configLoaded
    logInternal('VERBOSE', 'Logging level already read from config')
    return false
  return loadCurrentLevelValue({ Logging: { currentLevel: level.toUpperCase() }})

exports.close = (callback) ->
  close(true)
  # flush underlying stream to OS page cache because the process is exiting
  if totalOpenFile > 0
    allFileClosed.once('finish', ->
      callback?()
    )
  else
    callback?()
