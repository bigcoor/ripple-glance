async = require('async')

User = require '../models/User'

logger = require('../utils/log').getLogger('USER')
utils = require('../utils/routines')
credentials = require('./credentials')

validateHandle = (handle, name, callback) ->
  if typeof handle != 'string' and handle not instanceof String or handle.trim().length == 0
    callback?(new Error("Invalid #{name}"))
    return false
  return true

createUser = (handle, wallet, source, phone, nick, icon, context = {}, hash, callback) ->
  User.create({email: handle, wallet: wallet, phone: phone, nick: nick, password: hash}, (err, user) ->
    if err?
      if err.code == 11000
        err.duplicate = true
        logger.caught(err, 'User has registered, handle = %s, nick = %s', handle, nick)
        err = new Error('User has registered')
      else
        logger.caught(err, 'Failed to create user handle = %s, nick = %s', handle, nick)
        err = new Error('Failed to create user handle')
    callback(err, user?._id)
  )

# TODO, 加密密码和验证密码可在mongodb中间件完成
exports.createUser = (handle, wallet, source,  phone, nick, icon, password, context = {}, callback) ->
  logger.debug('Arguments:', handle, wallet, source,  phone, nick, icon, password, context)
  timer = utils.prologue(logger, 'createUser')

  return unless validateHandle(handle, 'handle', callback) if handle?
  return unless validateHandle(nick, 'nick', callback)
  return unless validateHandle(icon, 'icon', callback)

  handle = handle.trim() if handle?
  nick = nick.trim()
  source = utils.parseInt(source, 0, 0)

  async.waterfall([
    async.apply((cb) ->
      if password?
        credentials.generatePasswordHash(password, cb)
      else
        cb(null, null)
    ),
    async.apply(createUser, handle, wallet, source,  phone, nick, icon, context),
  ], (err, uid) ->
    utils.epilogue(logger, 'createUser', timer, callback, err, uid)
  )

# TODO, 在ES中标记用户状态
exports.deactivateUser = (uid, callback) ->
  return unless utils.validateUserId(uid, callback)

  timer = utils.prologue(logger, 'deactivateUser')

  pool.execute("UPDATE `#{db}`.profile SET status=status|0x80 WHERE uid=? AND status&0x80=0", [uid], (err, command) ->
    result = null
    if err?
      logger.caught(err, 'Failed to deactivate user, uid =', uid)
      err = new Error('Failed to deactivate user')
    else
      result = command.result.affected_rows == 1
    utils.epilogue(logger, 'deactivateUser', timer, callback, err, result)
  )

exports.bindHandle = (uid, handle, source, callback) ->
  return unless utils.validateUserId(uid, callback)
  return unless validateHandle(handle, 'handle', callback)

  timer = utils.prologue(logger, 'bindHandle')

  handle = handle.trim()
  source = utils.parseInt(source, 0, 0)

  pool.execute("INSERT INTO `#{db}`.handle(handle, uid, source) SELECT ?,uid,? FROM `#{db}`.profile WHERE uid=? AND status&0x80=0", [handle, source, uid], (err, command) ->
    result = null
    if err? and err.num == 1062 # MySQL error code for key duplicate
      err = new Error('handle already exists')
      err.duplicate = true
    else if err?
      logger.caught(err, 'Failed to bind handle for user', uid)
      err = new Error('Failed to bind handle')
    else
      result = command.result.affected_rows == 1
    utils.epilogue(logger, 'bindHandle', timer, callback, err, result)
  )

exports.updateProfile = (uid, nick = null, icon = null, callback) ->
  logger.debug('Arguments:', uid, nick, icon)
  return unless uid = utils.normalizeUserId(uid, callback)
  timer = utils.prologue(logger, 'updateProfile')

  statmt = []
  args = []

  if validateHandle(nick)
    statmt.push('nick=?')
    args.push(utils.stringToBinary(nick.trim()))
  if validateHandle(icon)
    statmt.push('icon=?')
    args.push(icon.trim())

  if statmt.length == 0
    return utils.epilogue(logger, 'updateProfile', timer, callback, null, false)

  statmt = statmt.join(',')
  args.push(uid)
  params = [["UPDATE `#{db}`.profile SET #{statmt} WHERE uid=? AND status&0x80=0", args]]

  cb = (err, command) ->
    if err? and err.num == 1062 # MySQL error code for key duplicate
      err = new Error('nick already exists')
      err.duplicate = true
    else if err?
      logger.caught(err, 'Failed to update user profile, uid =', uid)
      err = new Error('Failed to update user profile')
    else
      result = command.result.affected_rows == 1
    utils.epilogue(logger, 'updateProfile', timer, callback, err, result)

  if typeof callback.transaction == 'function'
    callback.transaction(params, cb)
  else if params.length > 1
    pool.transaction(params, cb)
  else
    params[0].push(cb)
    pool.execute.apply(pool, params[0])

exports.updateProfileData = (uid, appid, data = null, privacy = null, callback) ->
  return unless uid = utils.normalizeUserId(uid, callback)

  timer = utils.prologue(logger, 'updateProfileData')
  appid = utils.parseInt(appid, 0, 0)

  stmt1 = ''
  stmt2 = ''
  stmt3 = []
  params = [appid]

  if data
    stmt1 += ',data'
    stmt2 += ',?'
    stmt3.push('data=VALUES(data)')
    params.push(utils.stringToBinary(data))
  if privacy
    stmt1 += ',privacy'
    stmt2 += ',?'
    stmt3.push('privacy=VALUES(privacy)')
    params.push(utils.stringToBinary(privacy))

  if stmt3.length == 0
    return utils.epilogue(logger, 'updateProfileData', timer, callback, null, false)

  stmt3 = stmt3.join(',')
  params.push(uid)

  pool.execute("INSERT INTO `#{db}`.profile_data(uid, app_id#{stmt1}) SELECT uid, ?#{stmt2} FROM `#{db}`.profile WHERE uid=? AND status&80=0 ON DUPLICATE KEY UPDATE #{stmt3}", params, (err, command) ->
    if err?
      logger.caught(err, 'Failed to update user profile data, uid =', uid)
      err = new Error('Failed to update user profile data')
    else
      result = command.result.affected_rows > 0
    utils.epilogue(logger, 'updateProfile', timer, callback, err, result)
  )

exports.getProfiles = (idlist, stable = false, callback) ->
  return unless utils.validateArray(idlist, 'idlist', callback)

  timer = utils.prologue(logger, 'getProfiles')

  idlist = utils.normalizeUserIdList(idlist)

  if idlist.length == 0
    utils.epilogue(logger, 'getProfiles', timer, callback, null, [])
    return

  pool.execute("SELECT uid, nick, icon FROM `#{db}`.profile WHERE uid IN (?#{Array(idlist.length).join(',?')}) AND status&0x80=0", idlist, (err, command) ->
    if err?
      logger.caught(err, 'Failed to query user profile, user list =', idlist)
      err = new Error('Failed to query user profile')
    else
      result = ({
        uid: row.uid,
        nick: utils.binaryToString(row.nick),
        icon: row.icon
      } for row in command.result.rows)
      result = utils.restoreOrder(idlist, result, 'uid') if stable
    utils.epilogue(logger, 'getProfiles', timer, callback, err, result)
  )

exports.getExtendedProfiles = (idlist, appid, stable = false, callback) ->
  return unless utils.validateArray(idlist, 'idlist', callback)

  timer = utils.prologue(logger, 'getExtendedProfiles')

  idlist = utils.normalizeUserIdList(idlist)

  if idlist.length == 0
    utils.epilogue(logger, 'getExtendedProfiles', timer, callback, null, [])
    return

  appid = utils.parseInt(appid, 0, 0)

  async.parallel({
    profile: async.apply(pool.execute, "SELECT uid, nick, icon, UNIX_TIMESTAMP(time) as time FROM `#{db}`.profile WHERE uid IN (?#{Array(idlist.length).join(',?')}) AND status&0x80=0", idlist),
    extended: async.apply(pool.execute, "SELECT uid, data, privacy FROM `#{db}`.profile_data WHERE uid IN (?#{Array(idlist.length).join(',?')}) AND app_id=?", idlist.concat([appid])),
    handle: async.apply(pool.execute, "SELECT uid, handle, source FROM `#{db}`.handle WHERE uid IN (?#{Array(idlist.length).join(',?')})", idlist)
  }, (err, result) ->
    if err?
      logger.caught(err, 'Failed to query extended user profile, user list =', idlist)
      err = new Error('Failed to query extended user profile')
    else
      extended = utils.objectify(result.extended.result.rows, 'uid')
      handle =  utils.objectify(result.handle.result.rows, 'uid')

      result = ({
        uid: row.uid,
        nick: utils.binaryToString(row.nick),
        icon: row.icon,
        time: row.time,
        handle: handle[row.uid]?.handle ? undefined,
        source: handle[row.uid]?.source ? 1,
        data: utils.binaryToString(extended[row.uid]?.data),
        privacy: utils.binaryToString(extended[row.uid]?.privacy)
      } for row in result.profile.result.rows)
      result = utils.restoreOrder(idlist, result, 'uid') if stable
    utils.epilogue(logger, 'getExtendedProfiles', timer, callback, err, result)
  )

exports.getPrivacySettings = (idlist, appid, stable = false, callback) ->
  return unless utils.validateArray(idlist, 'idlist', callback)

  timer = utils.prologue(logger, 'getPrivacySettings')

  idlist = utils.normalizeUserIdList(idlist)

  if idlist.length == 0
    utils.epilogue(logger, 'getPrivacySettings', timer, callback, null, [])
    return

  pool.execute("SELECT T1.uid, T1.privacy FROM `#{db}`.profile_data AS T1, `#{db}`.profile as T2 WHERE T1.uid IN (?#{Array(idlist.length).join(',?')}) AND T1.app_id=? AND T2.uid=T1.uid AND T2.status&0x80=0", idlist.concat([appid]), (err, command) ->
    if err?
      logger.caught(err, 'Failed to query user privacy list, user list =', idlist)
      err = new Error('Failed to query user privacy list')
    else
      result = ({
        uid: row.uid,
        privacy: utils.binaryToString(row.privacy)
      } for row in command.result.rows)
      result = utils.restoreOrder(idlist, result, 'uid') if stable
    utils.epilogue(logger, 'getPrivacySettings', timer, callback, err, result)
  )

exports.getProfileByHandle = getProfileByHandle = (handle, callback) ->
  return unless validateHandle(handle, 'handle', callback)

  timer = utils.prologue(logger, 'getProfileByHandle')

  handle = handle.trim()

  User.findOne({email: handle, status: 0}, (err, user) ->
    if err?
      logger.caught(err, 'Failed to query user profile, phone =', phone)
      err = new Error('Failed to query user profile')
    else if not user?
      err = new Error('No such user')
      err.notfound = true
    else
      profile = {
        uid: user._id.toString()
        email: user.email
        icon: user.icon
      }
    utils.epilogue(logger, 'getProfileByNick', timer, callback, err, profile)
  )

exports.getProfileByPhone = (phone, callback) ->
  return unless validateHandle(phone, 'phone', callback)

  timer = utils.prologue(logger, 'getProfileByNick')

  phone = phone.trim()

  User.findOne({phone: phone, status: 0}, (err, user) ->
    if err?
      logger.caught(err, 'Failed to query user profile, phone =', phone)
      err = new Error('Failed to query user profile')
    else if not user?
      err = new Error('No such user')
      err.notfound = true
    else
      profile = {
        uid: user._id.toString()
        phone: user.phone
        icon: user.icon
      }
    utils.epilogue(logger, 'getProfileByNick', timer, callback, err, profile)
  )

# 按userid从小到大或从大到小枚举头像不满足一定条件的用户，比如枚举非默认头像的用户，defaultIcon用于指定相应的否定条件
exports.enumerateProfile = (count, start, backwards, defaultIcon, offset, callback) ->
  timer = utils.prologue(logger, 'enumerateProfile')

  count = utils.parseInt(count, 20, 1, countLimit)
  start = (if backwards then 0 else 4294967295) if not utils.validateUserId(start)
  offset = utils.parseInt(offset, 0, 0, offsetLimit)

  op = if backwards then '>' else '<'
  ordering = if backwards then 'ASC' else 'DESC'

  condition = ''
  icon = []

  if defaultIcon
    condition = 'AND icon!=? '
    icon = [defaultIcon]

  params = Array.prototype.concat.call([start], icon, [offset, count])

  pool.execute("SELECT uid, nick, icon FROM `#{db}`.profile WHERE uid#{op}? #{condition}AND status=0 ORDER BY uid #{ordering} LIMIT ?,?", params, (err, command) ->
    if err?
      logger.caught(err, 'Failed to enumerate user profile')
      err = new Error('Failed to enumerate user profile')
    else
      result = ({
        uid: row.uid,
        nick: utils.binaryToString(row.nick),
        icon: row.icon
      } for row in command.result.rows)
    utils.epilogue(logger, 'enumerateProfile', timer, callback, err, result)
  )

exports.getMetadata = (uid, keyspace = null, callback) ->
  return unless utils.validateUserId(uid, callback)

  timer = utils.prologue(logger, 'getMetadata')

  if keyspace?
    keyspace = [keyspace] unless Array.isArray(keyspace)
    keyspace = (utils.stringToBinary(key) for key in keyspace when key? and key = key.toString().trim())
    if keyspace.length > 0
      query = "SELECT uid, `key`, value FROM `#{db}`.metadata WHERE uid=? AND `key` IN (?#{Array(keyspace.length).join(',?')})"
      params = [uid].concat(keyspace)

  if not query
    query = "SELECT uid, `key`, value FROM `#{db}`.metadata WHERE uid=?"
    params = [uid]

  pool.execute(query, params, (err, command) ->
    if err?
      logger.caught(err, 'Failed to get user metadata', uid, keyspace)
      err = new Error('Failed to get user metadata')
    else
      result = {}
      for row in command.result.rows
        result[utils.binaryToString(row.key)] = utils.binaryToString(row.value)
      if Object.keys(result).length > 0
        result.uid = command.result.rows[0].uid
    utils.epilogue(logger, 'getMetadata', timer, callback, err, result)
  )