async = require('async')
crypto = require('crypto')
scrypt = require('scrypt')

alloc = require('../utils/stack')
config = require('../utils/config')
logger = require('../utils/log').getLogger('CREDENTIALS')
pool = require('../drivers/mysql-pool').create(config['PasswordDB'])
uniqid = require('../utils/uniqid')
utils = require('../utils/routines')

config.setModuleDefaults('PasswordDB', {
  maxTime: 0.1
})

config.setModuleDefaults('Token', {
  tokenKey: 'LPFeRpJox1zovyWTprTQjYzG/JG2JYsGfZ0UVaq+3rs'
})

db = config['PasswordDB'].db

timeToConsume = config['PasswordDB'].maxTime
digestKey = utils.base64ToBuffer(config['Token'].tokenKey)

config.on('change', (newConfig) ->
  timeToConsume = config['PasswordDB'].maxTime
  digestKey = utils.base64ToBuffer(config['Token'].tokenKey)
)

queryHash = (uid, callback) ->
  pool.execute("SELECT hash FROM `#{db}`.password WHERE uid=?", [uid], (err, command) ->
    if not err? and command.result.rows.length > 0
      hash = command.result.rows[0].hash
    callback(err, hash)
  )

updateHash = (uid, oldHash, newHash, callback) ->
  pool.execute("UPDATE `#{db}`.password SET hash=? WHERE uid=? AND hash=?", [newHash, uid, oldHash], (err, command) ->
    callback(err, if err? then null else command.result.affected_rows == 1)
  )

resetHash = (uid, newHash, callback) ->
  pool.execute("REPLACE INTO `#{db}`.password(uid, hash) VALUES(?,?)", [uid, newHash], (err, command) ->
    callback(err, if err? then null else command.result.affected_rows)
  )

makeError = (str, unauthorized = true) ->
  err = new Error(str)
  err.unauthorized = unauthorized
  return err

validatePassword = (password, callback) ->
  if typeof password != 'string' and password not instanceof String or password.trim().length == 0
    callback(makeError('Invalid password', false))
    return false
  return true

generateHash = (password, callback) ->
  timer = logger.time('generateHash')
  scrypt.passwordHash(password.trim(), timeToConsume, (err, hash) ->
    timer.end()
    callback(err, hash)
  )

verifyHash = (password, hash, callback) ->
  if not hash?
    callback(makeError("No password found"))
    return

  timer = logger.time('verifyHash')

  scrypt.verifyHash(hash, password.trim(), (err, result) ->
    timer.end()

    if err? and err.message != 'password is incorrect' and err.scrypt_err_code != 11 # 1.x and 2.x
      callback(err)
    else if not result
      callback(makeError("Username and password don't match"))
    else
      callback()
  )

exports.generatePasswordHash = (password, callback) ->
  return unless validatePassword(password, callback)
  generateHash(password, callback)

exports.verifyPassword = (uid, password, callback) ->
  return unless utils.validateUserId(uid, callback)
  return unless validatePassword(password, callback)

  timer = utils.prologue(logger, 'verifyPassword')

  async.waterfall([
    async.apply(queryHash, uid),
    async.apply(verifyHash, password)
  ], (err) ->
    if not err?
      success = true
    else if err.unauthorized
      success = false
      err = null
    else
      logger.caught(err, 'Error occurred while verifying password for user', uid)
      err = new Error('Error occurred while verifying password')
    utils.epilogue(logger, 'verifyPassword', timer, callback, err, success)
  )

# update with the same password is ok due to a different salt
exports.changePassword = (uid, password, newPassword, callback) ->
  return unless utils.validateUserId(uid, callback)
  return unless validatePassword(password, callback)
  return unless validatePassword(newPassword, callback)

  timer = utils.prologue(logger, 'changePassword')

  stack = alloc()

  async.waterfall([
    async.apply(queryHash, uid),
    async.apply(stack.push),
    async.apply(verifyHash, password),
    async.apply(generateHash, newPassword),
    async.apply(stack.popBefore),
    async.apply(updateHash, uid)
  ], (err, success) ->
    if not err?
      'do nothing'
    else if err.unauthorized
      success = false
      err = null
    else
      logger.caught(err, 'Error occurred while changing password for user', uid)
      err = new Error('Error occurred while changing password')
    utils.epilogue(logger, 'changePassword', timer, callback, err, success)
  )

exports.resetPassword = (uid, newPassword, callback) ->
  return unless utils.validateUserId(uid, callback)
  return unless validatePassword(newPassword, callback)

  timer = utils.prologue(logger, 'resetPassword')

  async.waterfall([
    async.apply(generateHash, newPassword),
    async.apply(resetHash, uid)
  ], (err, result) ->
    if err?
      logger.caught(err, 'Error occurred while resetting password for user', uid)
      err = new Error('Error occurred while resetting password')
    utils.epilogue(logger, 'resetPassword', timer, callback, err, result)
  )

now = -> utils.timestampToUnixTime()

digest = (payload, key) ->
  return crypto.createHmac('sha256', key).update(payload).digest('base64').replace(/\=+$/, '')

generateToken = (key, secret, params) ->
  payload = params.join('|')
  return utils.stringToBase64(payload).replace(/\=+$/, '') + '$' + digest(payload + secret, key)

decodeToken = (token, key, secret) ->
  [payload, hash] = token.split('$')

  return null unless payload and hash

  payload = utils.base64ToString(payload)

  return null unless digest(payload + secret, key) == hash

  return payload.split('|')

exports.generateToken = (uid, absoluteTimeoutInMinutes, idleTimeoutInSeconds, data = '', secret = '') ->
  return null unless typeof data == 'string'
  return null unless typeof secret == 'string'

  uid = utils.normalizeUserId(uid) ? 0

  absoluteTimeoutInMinutes = utils.parseInt(absoluteTimeoutInMinutes,  2592000, 0) # defaults to 30 days
  idleTimeoutInSeconds = utils.parseInt(idleTimeoutInSeconds, 1800, 0) # defaults to 30 minutes

  if absoluteTimeoutInMinutes + idleTimeoutInSeconds == 0
    return null

  params = [uid, uniqid.generate(), absoluteTimeoutInMinutes, now(), idleTimeoutInSeconds]
  params.push(data) if data.length > 0

  return generateToken(digestKey, secret, params)

exports.decodeToken = (uid, token, secret = '') ->
  return null unless typeof token == 'string'
  return null unless typeof secret == 'string'

  uid = utils.normalizeUserId(uid) ? 0
  params = decodeToken(token, digestKey, secret)

  return null unless params?

  [user, tokenId, absTimeout, lastActiveTime, idleTimeout, data] = params

  return null unless uid - user == 0

  creationTime = utils.timestampToUnixTime(uniqid.extractTimestamp(tokenId))

  present = now()
  return null if absTimeout > 0 and present - creationTime >= absTimeout * 60
  return null if idleTimeout > 0 and present - lastActiveTime >= idleTimeout

  params[3] = now()

  return {
    uid: uid,
    tokenId: tokenId,
    createTime: Math.floor(creationTime),
    lastActiveTime: parseInt(lastActiveTime),
    data: data,
    renewToken: generateToken(digestKey, secret, params)
  }
