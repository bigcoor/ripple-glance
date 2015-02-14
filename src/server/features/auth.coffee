async = require('async')

credentials = require('../cores/credentials')
user = require('../cores/user')

logger = require('../utils/log').getLogger('AUTH')
utils = require('../utils/routines')

account = require('./account')
format = require('./format')
checker = require('./checker')

swap = (a, b, callback) ->
  callback(null, b, a)

signIn = (name, fn, idleTimeout, persistSpan, handle, password, callback) ->
  if not checker.validatePassword(password, false)
    return callback (new Error('Invalid password'))

  timer = utils.prologue(logger, name)

  uid = null

  async.waterfall([
    async.apply(fn, handle),
    async.apply((profile, callback) -> callback(null, uid = profile.uid)),
    async.apply(swap, password)
    async.apply(credentials.verifyPassword)
  ], (err, success) ->
    if not err?
      success = format({
        uid: uid,
        sessionToken: credentials.generateToken(uid, 0, idleTimeout),
        persistToken: credentials.generateToken(uid, persistSpan, 0)
      }) if success
    else if err.notfound
      success = false
      err = null
    else
      logger.caught(err, 'Error occurred while verifying credentials for', handle)
      err = new Error('Error occurred while verifying credentials')
    utils.epilogue(logger, name, timer, callback, err, success)
  )

exports.validateSession = (uid, token, callback) ->
  token = credentials.decodeToken(uid, token)
  if not token?
    err = new Error('Invalid Session')
    err.unauthorized = true
    callback(err)
  else
    callback(null, token.renewToken)

exports.acquireSession = (uid, token, idleTimeout, persistSpan, callback) ->
  token = credentials.decodeToken(uid, token)
  if not token?
    callback(new Error('Invalid Token'))
  else
    callback(null, format({
      sessionToken: credentials.generateToken(uid, 0, idleTimeout),
      persistToken: credentials.generateToken(uid, persistSpan, 0)
    }))

exports.emailSignIn = (email, password, idleTimeout, persistSpan, callback) ->
  signIn('emailSignIn', user.getProfileByHandle, idleTimeout, persistSpan, email, password, callback)

exports.nickSignIn = (nick, password, idleTimeout, persistSpan, callback) ->
  signIn('nickSignIn', user.getProfileByNick, idleTimeout, persistSpan, nick, password, callback)

exports.generateCaptchaToken = (captcha, idleTimeout, callback) ->
  token = credentials.generateToken(0, 0, idleTimeout, '', captcha)
  callback(null, token)

exports.validateCaptchaToken = (captcha, token, callback) ->
  success = credentials.decodeToken(0, token, captcha)
  if not success
    err = new Error('Invalid Captcha')
    err.nothuman = true
  callback(err)
