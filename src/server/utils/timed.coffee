# All request to the external should use this module
# It's used to make sure all functions return within specified time

#TODO apply desc to util.format

logger = require('./log').getLogger('TIMED')
toMilliseconds = (tuple) ->
  return tuple[0] * 1000 + tuple[1] / 1e6

try
  # TODO bug, defaultTimeout 不能成功load
  config = require('./config')
  defaultTimeout = config['Timed'].defaultTimeout
catch err
  logger.caught(err, 'Failed to load default timeout settings')

defaultTimeout = 5000 if not defaultTimeout?

callback = (cb, desc, timeout, handlers) ->
  desc = desc ? 'CALLBACK'
  timer = logger.time(desc)
  [cleanup, dispose] = handlers
  timedout = false
  timeoutHandler = ->
    timedout = true
    msg = "#{desc} TIMEDOUT"
    logger.warn(msg)
    cleanup?()
    cb(new Error(msg))
  wrapper = ->
    timer.end()
    if not timedout
      clearTimeout(handle)
      cb.apply(this, Array.prototype.slice.call(arguments))
    else
      logger.info('%s already timed out, %dms', desc, toMilliseconds(process.hrtime(start)))
      if typeof dispose == 'function'
        dispose.apply(this, Array.prototype.slice.call(arguments))
      return false
  handle = setTimeout(timeoutHandler, timeout)
  start = process.hrtime()
  return wrapper

event = (emitter, desc, timeout = defaultTimeout, freelist = []) ->
  desc = desc ? 'EVENT'
  timer = logger.time(desc)
  timedout = false
  emit = emitter.emit
  emitter.emit = (event) ->
    if event in freelist
      emit.apply(emitter, Array.prototype.slice.call(arguments))
    else
      timer.end()
      if not timedout
        clearTimeout(handle)
        emit.apply(emitter, Array.prototype.slice.call(arguments))
      else
        logger.info('%s already timed out, %dms, %s event not fired', desc, toMilliseconds(process.hrtime(start)), event)
        args = Array.prototype.slice.call(arguments)
        args.unshift('dispose')
        emit.apply(emitter, args)
        return false
  timeoutHandler = ->
    timedout = true
    msg = "#{desc} TIMEDOUT"
    logger.warn(msg)
    emit.call(emitter, 'timeout')
  handle = setTimeout(timeoutHandler, timeout)
  start = process.hrtime()
  return emitter

# must use module.exports here
module.exports = (obj, desc, timeout = defaultTimeout, params...) ->
  if typeof obj == 'function'
    return callback(obj, desc, timeout, params)
  else
    return event(obj, desc, timeout, params)

Object.defineProperty(module.exports, 'defaultTimeout', {
  enumerable: true,
  get: -> return defaultTimeout
})
