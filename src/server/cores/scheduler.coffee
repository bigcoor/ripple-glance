logger = require('../utils/log').getLogger('SCHEDULER')
timed = require '../utils/timed'
utils = require '../utils/routines'
redis = require '../drivers/redis'

module.exports = require '../features/ripple'

redisSubClient = redis.redisSubClient

redisSubClient.subscribe('getPaymentHistory')

redisSubClient.on("message", (channel, message) ->
  logger.debug("Arguments:", channel, message)
  params = message?.split(',')

  args = []
  for param in params
    item = null
    try
      item = JSON.parse(param)
    catch err
      item = param if err?
    finally
      args.push item
  module.exports[channel].apply(null, args)
)