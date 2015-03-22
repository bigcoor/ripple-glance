async = require('async')
path = require('path')
request = require('request')
timers = require('timers')

config = require('../utils/config')
logger = require('../utils/log').getLogger('BLANCE')
timed = require('../utils/timed')
utils = require('../utils/routines')

credentials = require('../cores/credentials')
user = require('../cores/user')

auth = require('./auth')
checker = require('./checker')
constant = require('./constant')
format = require('./format')

ripple = request './ripple'

Balance = request '../models/Balance'

exports.addRpAccount = (self, address, context = {}, callback) ->
  logger.debug("Arguments:", self, address, context)
  return false unless self = utils.validateUserId(self, callback)
  timer = utils.prologue(logger, 'addRpAccount')

  # TODO, checkout address, context
  async.waterfall([
    # TODO, 检查address是否已经被绑定
    async.apply(ripple.getAccountBalances, context, address)
    async.apply (balances, cb) ->
      Balance.create(balances, (err, balance) ->
        if err?
          if err.code = 11000
            logger.warn("This balance has been registered", err)
            err.duplicate = true
          else
            logger.error("Failed to create balance", err)
          cb(err, balance)
      )
  ], (err, balance) ->
    if err?
      logger.caught(err, 'Register failed', self, address)
      duplicate = err.duplicate
      err = new Error('Register failed')
      if duplicate
        err.duplicate = true
      else
        err.tryagain = true
    else
      result = format({ balance: balance })
    utils.epilogue(logger, 'addRpAccount', timer, callback, err, result)
  )

getHandle = exports.getHandle = (openid, source) ->
  return "#{openid}_#{source}"

exports.createOAuth = (openid, source, nick, iconUrl, tokens, callback) ->
  timer = utils.prologue(logger, 'createOAuth')

  if not checker.validateOpenID(openid)
    return utils.epilogue(logger, 'createOAuth', timer, callback, new Error('Bad open id'))

  openid = openid.trim()
  source = utils.parseInt(source, 0, 0)

  result = {
    new_user: true
  }

  async.waterfall([
    async.apply(checker.generateNickname, nick),
    async.apply((nickname, cb) ->
      if nickname != nick
        result.nick_revised = true;
      createUserInternal(getHandle(openid, source), source, nickname, format.defaultIcon(), null, cb)
    ),
    async.apply((uid, cb)->
      # 尝试从iconUrl下载图片并上传到七牛服务器，然后设置为该用户的头像
      # 这一步的错误不影响整个api的结果。
      upload.uploadUrlToQiniu(uid, 'icon', iconUrl, (err, avatarKey)->
        if not err? and avatarKey?
          # 这里没有修改nick，不需要更新transactionLog
          user.updateProfile(uid, null, avatarKey, (err, result)->
            if err?
              # Ignore here.
              logger.error("Failed to update avatar for #{uid}, #{avatarKey}")
            cb(null, uid)
          )
        else
          logger.warn("Failed to download image from #{iconUrl}, #{err}")
          # ignore
          cb(null, uid)
      )
    )
  ], (err, uid) ->
    if err?
      logger.caught(err, 'Failed to create oauth account', openid, source, nick)
      err = new Error('Failed to create oauth account')
      err.tryagain = true
    else
      recorder.record(openid, source, uid, tokens)
      platform.updateWeiboInfo(openid, uid, tokens, false, -> "we don't care about the result") if source == 3
      result.uid = uid
    utils.epilogue(logger, 'createOAuth', timer, callback, err, format(result))
  )

exports.bindOAuth = (openid, source, userid, callback) ->
  return unless utils.validateUserId(userid, callback)

  timer = utils.prologue(logger, 'bindOAuth')

  if not checker.validateOpenID(openid)
    return utils.epilogue(logger, 'bindOAuth', timer, callback, new Error('Bad arguments'))

  openid = openid.trim()
  source = utils.parseInt(source, 0, 0)

  user.bindHandle(userid, getHandle(openid, source), source, (err, result) ->
    if err?
      duplicate = err.duplicate
      logger.caught(err, 'Failed to bind oauth account', openid, source, userid)
      err = new Error('Failed to bind oauth account')
      if duplicate
        err.duplicate = true
      else
        err.tryagain = true
    else if not result
      err = new Error('Not Found')
      err.notfound = true
      result = null
    else
      result = format({ success: true })
    utils.epilogue(logger, 'bindOAuth', timer, callback, err, result)
  )

exports.updateOAuthToken = (openid, source, userid, tokens, callback) ->
  return unless utils.validateUserId(userid, callback)

  if not checker.validateOpenID(openid)
    return callback(new Error('Bad arguments'))

  openid = openid.trim()
  source = utils.parseInt(source, 0, 0)

  recorder.record(openid, source, userid, tokens)
  platform.updateWeiboInfo(openid, userid, tokens, false, -> "we don't care about the result") if source == 3

  callback(null, format({ success: true }))

exports.changePassword = (userid, oldPassword, newPassword, callback) ->
  return unless utils.validateUserId(userid, callback)

  timer = utils.prologue(logger, 'changePassword')

  if not checker.validatePassword(oldPassword, false) or not checker.validatePassword(newPassword)
    return utils.epilogue(logger, 'changePassword', timer, callback, new Error('Bad password'))

  credentials.changePassword(userid, oldPassword, newPassword, (err, success) ->
    if err?
      logger.caught(err, 'Password change failed', userid)
      err = new Error('Password change failed')
      err.tryagain = true
    else if not success
      err = new Error('Wrong password')
      err.unauthorized = true
    else
      result = format({success: true})
    utils.epilogue(logger, 'changePassword', timer, callback, err, result)
  )