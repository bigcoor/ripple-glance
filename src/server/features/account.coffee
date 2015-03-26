async = require('async')
path = require('path')
request = require('request')
timers = require('timers')
emailTemplates = require('email-templates')

config = require('../utils/config')
logger = require('../utils/log').getLogger('ACCOUNT')
timed = require('../utils/timed')
utils = require('../utils/routines')

credentials = require('../cores/credentials')
user = require('../cores/user')

auth = require('./auth')
checker = require('./checker')
constant = require('./constant')
format = require('./format')
profile = require('./profile')
platform = require('./platform')

createUserInternal = (handle, wallet, source,  phone, nick, icon, password, context = {}, callback) ->
  logger.debug(handle, wallet, source,  phone, nick, icon, password)
  timer = utils.prologue(logger, 'createUserInternal')

  async.waterfall([
    async.apply(user.createUser, handle, wallet, source,  phone, nick, icon, password, context)
  ], (err, uid) ->
    if err?
      logger.caught(err, 'Failed to create user.')
    utils.epilogue(logger, 'createUserInternal', timer, callback, err, uid)
)

# email, required
# phone, required
# nick, 如果没有则随机创建一个
exports.register = (extra, context = {}, callback) ->
  timer = utils.prologue(logger, 'register')

  handle = extra?.email
  wallet = extra?.wallet
  phone = extra?.phone
  nick = extra?.nick
  icon = extra?.icon
  password = extra?.password

  if not checker.validateEmail(handle) or (nick? and not checker.validateNickname(nick)) or not checker.validatePassword(password)
    return utils.epilogue(logger, 'register', timer, callback, new Error('Bad arguments'))

  async.waterfall([
    async.apply((cb) ->
      return cb(null, nick) if nick?
      # TODO，有必要可以用特殊状态来标记随机生成nick的用户
      checker.generateNickname(null, cb)
    ),
    async.apply((nick, cb) ->
      createUserInternal(handle, wallet, 1, phone, nick, format.defaultIcon(), password, context, cb)
    )
  ], (err, uid) ->
    if err?
      logger.caught(err, 'Register failed', handle, nick)
      duplicate = err.duplicate
      err = new Error('Register failed')
      if duplicate
        err.duplicate = true
      else
        err.tryagain = true
    else
      result = format({ uid: uid })
    utils.epilogue(logger, 'register', timer, callback, err, result)
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
      upload.uploadUrlToQiniu(uid, 'icon', iconUrl, (err, avatarKey) ->
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
      result = format({ success: true })
    utils.epilogue(logger, 'changePassword', timer, callback, err, result)
  )

# 管理员强制更改密码
exports.setPassword = (userid, newPassword, callback) ->
  return unless utils.validateUserId(userid, callback)
  userid = utils.normalizeUserId(userid)
  timer = utils.prologue(logger, 'resetPassword')

  if not checker.validatePassword(newPassword)
    return utils.epilogue(logger, 'resetPassword', timer, callback, new Error('Bad password'))

  credentials.resetPassword(userid, newPassword, (err, rows) ->
    if err?
      logger.caught(err, 'Password reset failed', userid)
      err = new Error('Password reset failed')
      err.tryagain = true
    else
      logger.info('User [%d] can now use password to login', userid) if rows == 1
      result = format({ success: true })
    utils.epilogue(logger, 'resetPassword', timer, callback, err, result)
  )

# 用户找回密码
exports.resetPassword = (userid, token, newPassword, callback) ->
  return unless utils.validateUserId(userid, callback)
  userid = utils.normalizeUserId(userid)
  timer = utils.prologue(logger, 'resetPassword')

  if not checker.validatePassword(newPassword)
    return utils.epilogue(logger, 'resetPassword', timer, callback, new Error('Bad password'))

  async.waterfall([
    async.apply(auth.validateSession, userid, token),
    async.apply((token, cb) ->
      credentials.resetPassword(userid, newPassword, cb)
    )
  ], (err) ->
    if err?
      logger.caught(err, 'Password reset failed', userid)
    else
      result = format({ success: true })
    utils.epilogue(logger, 'resetPassword', timer, callback, err, result)
  )

# 找回密码
#
# 1. 验证邮箱是否合法
# 2. 发送重置密码邮件
exports.findPassword = (email, callback) ->
  timer = utils.prologue(logger, 'findPassword')
  email = email.trim()
  async.waterfall([
      async.apply(user.getProfileByHandle, email),
      async.apply((profile, cb) ->
        # 30分钟有效期
        # TODO
        # 目前和session采用相同的key产生token，为安全可使用独立的key
        # 链接点击之后应失效，目前还没有实现
        token = encodeURIComponent(credentials.generateToken(profile.uid, 30, 1800))
        data = {
          nick: profile.nick,
          resetLink: "#{officialSite}/u/reset/#{profile.uid}?token=#{token}"
        }
        emailTemplates(path.resolve(__dirname, '../config', 'templates'), (err, template) ->
          if err?
            logger.error('Failed to prepare email templates')
          cb(err, data, template)
        )
      ),
      async.apply((data, template, cb) ->
        template('reset-password', data, (err, html, text)->
          if err?
            logger.error("Failed to load template 'reset-password'")
          cb(err, data, html, text)
        )
      ),
      async.apply((data, html, text, cb) ->
        postmark.send({
            # 配置production帐号
            From: "dev@cunpai.com",
            To: email,
            Subject: "[lookmook]找回密码",
            HtmlBody: html,
            TextBody: text
          }, (err, success) ->
          if err?
            logger.caught(err, "Failed to send email")
          cb(err)
        )
      )
    ], (err) ->
      if err?
        if err.notfound
          logger.caught(err, "Email address not found", email)
        else
          logger.caught(err, "Unknown error when sending email", email)
      else
        result = format({ success: true })
      utils.epilogue(logger, 'findPassword', timer, callback, err, result)
  )