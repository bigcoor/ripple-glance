async = require('async')
path = require('path')
util = require('util')
request = require('request')
timers = require('timers')
emailTemplates = require('email-templates')

config = require('../utils/config')
logger = require('../utils/log').getLogger('ACCOUNT')
timed = require('../utils/timed')
utils = require('../utils/routines')

activity = require('../cores/activity')
credentials = require('../cores/credentials')
user = require('../cores/user')

auth = require('./auth')
checker = require('./checker')
constant = require('./constant')
format = require('./format')
profile = require('./profile')
platform = require('./platform')

rpVersion = 'v1'
rpBaseUri = 'https://api.ripple.com/'
account =
  getAccountBalances: "%s/#{rpVersion}/accounts/%s/balances"

buildRequestOption = (address) ->
  return util.fotmat(account.getAccountBalances, rpBaseUri, address)

exports.getAccountBalances = (context = {}, address, callback) ->
  logger.debug("Arguments:", context, address)
  timer = utils.prologue(logger, 'getAccountBalances')

  async.waterfall([
    async.apply(request.post, buildRequestOption(address))
  ], (err, balances) ->
    if err?
      logger.caught("Failed to get balances", err)
      err.tryagain = true
    utils.epilogue(logger, 'getAccountBalances', timer, callback, err, balances)
  )
