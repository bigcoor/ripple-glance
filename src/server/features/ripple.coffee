async = require('async')
path = require('path')
util = require('util')
request = require('request')
timers = require('timers')
emailTemplates = require('email-templates')
crawler = require("crawler")

config = require('../utils/config')
logger = require('../utils/log').getLogger('ACCOUNT')
timed = require('../utils/timed')
utils = require('../utils/routines')

credentials = require('../cores/credentials')
user = require('../cores/user')

Payment = require '../models/Payment'

auth = require('./auth')
checker = require('./checker')
constant = require('./constant')
format = require('./format')
profile = require('./profile')
platform = require('./platform')

rpVersion = 'v1'
rpBaseUri = 'https://api.ripple.com/'
resultsPerPage = 1000
account =
  getAccountBalances: "%s/#{rpVersion}/accounts/%s/balances"
  getPaymentHistory: "%s/#{rpVersion}/accounts/%s/payments?results_per_page=#{resultsPerPage}&page=%s"

buildRequestOption = (address) ->
  return util.fotmat(account.getAccountBalances, rpBaseUri, address)

handleRippleBalanceError = (response, callback) ->
  balanceList = []
  if not response?.success
    logger.caught("Failed to get balance", response)
    err = new Error(response.message)
  else
    balanceList = (balance.ledger = response.ledger for balance in response.balances)
  callback(err, balanceList)

buildPayments = (payments) ->
  results = []
  for payment in payments
    results.sourceAccount = payment.source_account
    results.values = payment.source_amount.value
    results.issuer = payment.source_amount.issuer
    results.currency = payment.source_amount.currency
    results.destinationAccount = payment.destination_account
    results.direction = payment.direction
    results.timestamp = payment.timestamp
    results.fee = payment.fee
    results.hash =  payment.hash
    results.ledger = payment.ledger

    return results

exports.getAccountBalances = (context = {}, address, callback) ->
  logger.debug("Arguments:", context, address)
  timer = utils.prologue(logger, 'getAccountBalances')

  async.waterfall([
    async.apply(request.post, buildRequestOption(address))
    async.apply(handleRippleBalanceError)
  ], (err, balances) ->
    if err?
      logger.caught("Failed to get balances", err)
      err.tryagain = true
    utils.epilogue(logger, 'getAccountBalances', timer, callback, err, balances)
  )

exports.getPaymentHistory = (context = {}, address, callback) ->
  logger.debug("Arguments:", context, address)
  timer = utils.prologue(logger, 'getPaymentHistory')

  c = new Crawler({maxConnections : 10})
  continueCrawler = true
  page = 1

  async.whilst(
    async.apply -> return continueCrawler
    async.apply (cb) ->
      c.queue([{
        uri: util.fotmat(account.getPaymentHistory, rpBaseUri, address, page)
        jQuery: false,
        callback: (err, result) ->
          continueCrawler = false if result?.length < resultsPerPage
          Payment.create(buildPayments(result), (err, payment) ->
            if err.code = 11000
              err.duplicate = true
              logger.error("Payment has existed.")
              error = new Error("Payment has existed.")
            cb(err)
          )
      }])
    async.apply (err) ->
      if err?
        if not err.duplicate
          err.tryagain = true
          logger.error("Failed to crawler data from ripple network.")
  )