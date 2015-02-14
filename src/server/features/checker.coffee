async = require('async')
XRegExp = require('xregexp').XRegExp

config = require('../utils/config')
logger = require('../utils/log').getLogger('CHECKER')
utils = require('../utils/routines')
user = require('../cores/user')

format = require('./format')

config.setModuleDefaults('Checker', {
  minNickAsciiLength: 3,
  maxNickCharLength: 24, # 24 is the db limit
  minDescLength: 3,
  maxDescLength: 3584
})

minNickAsciiLength = config['Checker']?.minNickAsciiLength
maxNickCharLength = config['Checker']?.maxNickCharLength
minDescLength = config['Checker']?.minDescLength
maxDescLength = config['Checker']?.maxDescLength

defaultPageSize = config['Pagination'].defaultPageSize
maxPageSize = config['Pagination'].maxPageSize
maxOffset = config['Pagination'].maxOffset

nickChecker = XRegExp('^[\\p{Han}\\p{Bopomofo}\\p{Hangul}\\p{Hiragana}\\p{Katakana}0-9A-Za-z_\\-āáǎàōóǒòēéěèīíǐìūúǔùü]+$')
nickSanitizer = XRegExp('[^\\p{Han}\\p{Bopomofo}\\p{Hangul}\\p{Hiragana}\\p{Katakana}0-9A-Za-z_\\-āáǎàōóǒòēéěèīíǐìūúǔùü]+', 'g')
miniLengthChecker = XRegExp('[0-9A-Za-z_\\-āáǎàōóǒòēéěèīíǐìūúǔùü]')

validateNickname = exports.validateNickname = (nickname, resolve = {}) ->
  if typeof nickname != 'string' and nickname not instanceof String
    resolve.reason = 'WrongType'
    return false
  nickname = nickname.trim()

  length = nickname.length
  #
  # 如下实现是将汉字长度计为2，这里我们不区分英文字符和汉字
  # length = 0
  #  for char in nickname
  #    length += if miniLengthChecker.test(char) then 1 else 2
  if length < minNickAsciiLength
    resolve.reason = 'TooShort'
    return false
  if length > maxNickCharLength
    resolve.reason = 'TooLong'
    return false
  if not nickChecker.test(nickname)
    resolve.reason = 'InvalidChar'
    return false
  return true

sanitizeNickname = exports.sanitizeNickname = (nickname) ->
  return '' if typeof nickname != 'string'
  return nickname.replace(nickSanitizer, '').substr(0, maxNickCharLength)

generateNickname = exports.generateNickname = (nickname, callback) ->
  nick = sanitizeNickname(nickname)
  nickname = nick
  counter = 0
  success = false
  async.doUntil(async.apply((cb) ->
    nicknameAvailable(nickname, (err, resolve) ->
      if err?
        return cb(err)
      if resolve.available
        success = true
      else if not nick
        nickname = 'u' + Math.floor(Math.random() * 10000000)
      else
        padding = '' + Math.floor(Math.random() * 1000)
        nickname = nick.substr(0, maxNickCharLength - padding.length) + padding
      cb()
    )
  ), ->
    if success
      # nickname is available
      return true
    else if ++counter >= 5
      nickname = null
      return true
    else
      return false
  , (err) ->
    if err?
      logger.caught(err, 'Failed to generate nickname', nickname)
      err = new Error('Failed to generate nickname')
      err.tryagain = true
    else if not nickname
      err = new Error('Failed to find a nickname available in 5 attempts')
      err.tryagain = true
    callback(err, nickname)
  )

validateEmail = exports.validateEmail = (email, resolve = {}) ->
  if not utils.validateEmail(email)
    resolve.reason = 'Invalid'
    return false
  return true

validatePassword = exports.validatePassword = (password, ensureStrength = true) ->
  return false if typeof password != 'string' and password not instanceof String
  password = password.trim()
  #TODO in future we may want to enforce a minimum strength
  return password.length > 0

validateOpenID = exports.validateOpenID = (openid) ->
  return false if typeof openid != 'string' and openid not instanceof String
  return openid.trim().length > 0

# 验证图片的key是否是以 uid/ 为前缀
validateImageKey = exports.validateImageKey = (uid, key) ->
  return false if typeof key != 'string'
  prefix = uid.toString().trim() + "/"
  return false if key.trim().indexOf(prefix) != 0
  return true

normalizeDescription = exports.normalizeDescription = (description) ->
  return null if typeof description != 'string' and description not instanceof String
  description = description.trim()
  return null if description.length < minDescLength or description.length > maxDescLength
  return description

available = (name, validator, query, input, callback) ->
  resolve = { available: false }
  if not validator(input, resolve)
    return callback(null, format(resolve))

  query.call(user, input, (err, result) ->
    if err?
      if err.notfound
        err = null
        result = format({ available: true })
      else
        logger.caught(err, "Failed to check #{name} availability")
        err = new Error("Failed to check #{name} availability")
        err.tryagain = true
    else
      result = format({ available: false, reason: 'Occupied' })
    callback(err, result)
  )

nicknameAvailable = exports.nicknameAvailable = (nickname, callback) ->
  available('nickname', validateNickname, user.getProfileByNick, nickname, callback)

exports.emailAvailable = (email, callback) ->
  available('email', validateEmail, user.getProfileByHandle, email, callback)

exports.normalizeCount = (count) ->
  return  utils.parseInt(count, defaultPageSize, 1, maxPageSize)

exports.normalizeOffset = (offset) ->
  return utils.parseInt(offset, 0, 0, maxOffset)