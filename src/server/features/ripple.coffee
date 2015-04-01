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
rpBaseUri = 'https://api.ripple.com'
resultsPerPage = 1000
account =
  getAccountBalances: "%s/#{rpVersion}/accounts/%s/balances"
  getPaymentHistory: "%s/#{rpVersion}/accounts/%s/payments?results_per_page=#{resultsPerPage}&page=%s"

buildRequestOption = (address) ->
  return util.format(account.getAccountBalances, rpBaseUri, address)

handleRippleBalanceError = (response, callback) ->
  balanceList = []
  if not response?.success
    logger.caught("Failed to get balance", response)
    err = new Error(response.message)
  else
    balanceList = (balance.ledger = response.ledger for balance in response.balances)
  callback(err, balanceList)

buildPayments = (paymentDocs) ->
  results = []
  paymentDocs = [] if not Array.isArray(paymentDocs)

  for paymentDoc in paymentDocs
    paymentTmp = {}
    paymentTmp.sourceAccount = paymentDoc.payment.source_account
    paymentTmp.value = paymentDoc.payment.source_amount.value
    paymentTmp.issuer = paymentDoc.payment.source_amount.issuer
    paymentTmp.currency = paymentDoc.payment.source_amount.currency
    paymentTmp.destinationAccount = paymentDoc.payment.destination_account
    paymentTmp.direction = paymentDoc.payment.direction
    paymentTmp.timestamp = paymentDoc.payment.timestamp
    paymentTmp.fee = paymentDoc.payment.fee
    paymentTmp.hash =  paymentDoc.hash
    paymentTmp.ledger = paymentDoc.ledger

    results.push paymentTmp

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

  c = new crawler({maxConnections: 10})
  continueCrawler = true
  page = 1

  async.whilst(
    async.apply -> return continueCrawler
    async.apply (cb) ->
      c.queue([{
        uri: util.format(account.getPaymentHistory, rpBaseUri, address, page)
        jQuery: false,
        callback: (err, result) ->
          if result?.body.length < resultsPerPage
            continueCrawler = false
          else
            page++
          paymentsJson = JSON.parse(result?.body)
          Payment.create(buildPayments(paymentsJson.payments), (err, payment) ->
            if err?.code == 11000
              err.duplicate = true
              logger.error("Payment has existed.")
              err = new Error("Payment has existed.")
            cb(err)
          )
      }])
    async.apply (err) ->
      if err?
        if not err.duplicate
          err.tryagain = true
          logger.error("Failed to crawler data from ripple network.")
  )