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
  module.exports[channel].apply(null, params)
)