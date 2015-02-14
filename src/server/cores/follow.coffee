async = require('async')

config = require('../utils/config')
logger = require('../utils/log').getLogger('FOLLOW')
pool = require('../drivers/mysql-pool').create(config['FollowDB'])
utils = require('../utils/routines')

db = config['FollowDB']?.db
offsetLimit = config['FollowDB']?.offset_limit ? 1000
countLimit = config['FollowDB']?.count_limit ? 200

exports.follow = (uid, appid, target, callback) ->
  return false unless utils.validateUserId(uid, callback)
  return false unless utils.validateUserId(target, callback)

  timer = utils.prologue(logger, 'follow')

  logger.debug('Arguments:', uid, appid, target)

  appid = utils.parseInt(appid, 0, 0)

  uid = utils.normalizeUserId(uid)
  target = utils.normalizeUserId(target)

  if uid == target
    utils.epilogue(logger, 'follow', timer, callback, new Error("Can't follow yourself"))
    return false

  params = [
    ["INSERT INTO `#{db}`.following(uid, app_id, target) VALUES(?,?,?)", [uid, appid, target]],
    ["INSERT INTO `#{db}`.follower(uid, app_id, target) VALUES(?,?,?)", [target, appid, uid]],
    ["INSERT INTO `#{db}`.follow_count(uid, app_id, following_count) VALUES(?,?,1) ON DUPLICATE KEY UPDATE following_count=following_count+1", [uid, appid]],
    ["INSERT INTO `#{db}`.follow_count(uid, app_id, follower_count) VALUES(?,?,1) ON DUPLICATE KEY UPDATE follower_count=follower_count+1", [target, appid]]
  ]

  pool.transaction(params, (err) ->
    if err?
      logger.caught(err, 'Failed to follow %d for user %d, appid %d', target, uid, appid)
      if err.num == 1062
        err = new Error('Entry already exists')
        err.duplicate = true
      else
        err = new Error('Failed to follow a user')
    utils.epilogue(logger, 'follow', timer, callback, err)
  )

exports.unfollow = (uid, appid, target, callback) ->
  return false unless utils.validateUserId(uid, callback)
  return false unless utils.validateUserId(target, callback)

  timer = utils.prologue(logger, 'unfollow')

  logger.debug('Arguments:', uid, appid, target)

  appid = utils.parseInt(appid, 0, 0)

  params = [
    ["DELETE FROM `#{db}`.following WHERE uid=? AND app_id=? AND target=?", [uid, appid, target], (result) ->
      if result.affected_rows != 1
        err = new Error("User #{uid} doesn't follow target #{target}")
        err.notfound = true
        return err
    ],
    ["UPDATE `#{db}`.follow_count SET following_count=following_count - ROW_COUNT() WHERE uid=? AND app_id=? AND ROW_COUNT() > 0", [uid, appid]],
    ["DELETE FROM `#{db}`.follower WHERE uid=? AND app_id=? AND target=?", [target, appid, uid]],
    ["UPDATE `#{db}`.follow_count SET follower_count=follower_count - ROW_COUNT() WHERE uid=? AND app_id=? AND ROW_COUNT() > 0", [target, appid]],
    ["DELETE FROM `#{db}`.follow_count WHERE uid IN (?,?) AND app_id=? AND following_count=0 AND follower_count=0", [uid, target, appid]]
  ]

  pool.transaction(params, (err, commands) ->
    rows = null
    if err?
      logger.caught(err, 'Failed to unfollow %d for user %d, appid %d', target, uid, appid)
      notfound = err.notfound
      err = new Error('Failed to unfollow a user')
      if notfound
        err.notfound = true
    else
      rows = 0
      for command in commands
        rows += command.result.affected_rows
    utils.epilogue(logger, 'unfollow', timer, callback, err, rows)
  )

exports.isFollowing = (uid, appid, stable = false, idlist, callback) ->
  return false unless utils.validateUserId(uid, callback)
  return false unless utils.validateArray(idlist, 'idlist', callback)

  timer = utils.prologue(logger, 'isFollowing')

  logger.debug('Arguments:', uid, appid, stable, idlist)

  appid = utils.parseInt(appid, 0, 0)
  idlist = utils.normalizeUserIdList(idlist)

  if idlist.length == 0
    utils.epilogue(logger, 'isFollowing', timer, callback, null, [])
    return

  pool.execute("SELECT target FROM `#{db}`.following FORCE INDEX(PRIMARY) WHERE uid=? AND app_id=? AND target IN (?#{Array(idlist.length).join(',?')})", [uid, appid].concat(idlist), (err, command) ->
    result = null
    if err?
      logger.caught(err, 'Failed to query following db for user %d, appid %d', uid, appid)
      err = new Error('Failed to query following db')
    else
      logger.debug('Result:', command.result.rows)
      result = (row.target for row in command.result.rows)
      result = utils.restoreOrder(idlist, result) if stable
    utils.epilogue(logger, 'isFollowing', timer, callback, err, result)
  )

exports.isFollower = (uid, appid, stable = false, idlist, callback) ->
  return false unless utils.validateUserId(uid, callback)
  return false unless utils.validateArray(idlist, 'idlist', callback)

  timer = utils.prologue(logger, 'isFollower')

  logger.debug('Arguments:', uid, appid, stable, idlist)

  appid = utils.parseInt(appid, 0, 0)
  idlist = utils.normalizeUserIdList(idlist)

  if idlist.length == 0
    utils.epilogue(logger, 'isFollower', timer, callback, null, [])
    return

  pool.execute("SELECT target FROM `#{db}`.follower FORCE INDEX(PRIMARY) WHERE uid=? AND app_id=? AND target IN (?#{Array(idlist.length).join(',?')})", [uid, appid].concat(idlist), (err, command) ->
    result = null
    if err?
      logger.caught(err, 'Failed to query follower db for user %d, appid %d', uid, appid)
      err = new Error('Failed to query follower db')
    else
      logger.debug('Result:', command.result.rows)
      result = (row.target for row in command.result.rows)
      result = utils.restoreOrder(idlist, result) if stable
    utils.epilogue(logger, 'isFollower', timer, callback, err, result)
  )

exports.isFriend = (uid, appid, stable = false, idlist, callback) ->
  return false unless utils.validateUserId(uid, callback)
  return false unless utils.validateArray(idlist, 'idlist', callback)

  timer = utils.prologue(logger, 'isFriend')

  logger.debug('Arguments:', uid, appid, stable, idlist)

  appid = utils.parseInt(appid, 0, 0)
  idlist = utils.normalizeUserIdList(idlist)

  if idlist.length == 0
    utils.epilogue(logger, 'isFriend', timer, callback, null, [], [], [])
    return

  async.parallel({
    following: async.apply(exports.isFollowing, uid, appid, false, idlist),
    follower: async.apply(exports.isFollower, uid, appid, false, idlist)
  }, (err, result) ->
    list = null
    if err?
      logger.caught(err, 'Failed to query following & follower dbs for user %d, appid %d', uid, appid)
      err = new Error('Failed to query following & follower dbs')
    else
      list = utils.intersect(result.following, result.follower)
      following = result.following
      followers = result.follower
      if stable
        list = utils.restoreOrder(idlist, list)
        following = utils.restoreOrder(idlist, following)
        followers = utils.restoreOrder(idlist, followers)
    utils.epilogue(logger, 'isFriend', timer, callback, err, list, following, followers)
  )

exports.followList = (uid, appid, callback) ->
  return false unless utils.validateUserId(uid, callback)

  timer = utils.prologue(logger, 'followList')

  logger.debug('Arguments:', uid, appid)

  appid = utils.parseInt(appid, 0, 0)

  pool.execute("SELECT target FROM `#{db}`.following WHERE uid=? AND app_id=?", [uid, appid], (err, command) ->
    result = null
    if err?
      logger.caught(err, 'Failed to get following list from db for user %d, appid %d', uid, appid)
      err = new Error('Failed to get following list from db')
    else
      logger.debug('Result:', command.result.rows)
      result = (row.target for row in command.result.rows)
    utils.epilogue(logger, 'followList', timer, callback, err, result)
  )

exports.followCount = (idlist, appid, callback) ->
  return false unless utils.validateArray(idlist, 'idlist', callback)

  timer = utils.prologue(logger, 'followCount')

  logger.debug('Arguments:', idlist, appid)

  appid = utils.parseInt(appid, 0, 0)
  idlist = utils.normalizeUserIdList(idlist)

  if idlist.length == 0
    utils.epilogue(logger, 'followCount', timer, callback, null, [])
    return

  pool.execute("SELECT uid, following_count, follower_count FROM `#{db}`.follow_count FORCE INDEX(PRIMARY) WHERE uid IN (?#{Array(idlist.length).join(',?')}) AND app_id=?", idlist.concat([appid]), (err, command) ->
    result = null
    if err?
      logger.caught(err, 'Failed to get follow count from db for user list %s, appid %d', idlist, appid)
      err = new Error('Failed to get follow count from db')
    else
      logger.debug('Result:', command.result.rows)
      result = {}
      for row in command.result.rows
        result[row.uid] = {
          followingCount: row.following_count,
          followerCount: row.follower_count
        }
    utils.epilogue(logger, 'followCount', timer, callback, err, result)
  )

exports.getFollowings = (uid, appid, count, start = 0, backwards = false, offset = 0, callback) ->
  return false unless utils.validateUserId(uid, callback)

  timer = utils.prologue(logger, 'getFollowings')

  logger.debug('Arguments:', uid, appid, count, start)

  appid = utils.parseInt(appid, 0, 0)
  count = utils.parseInt(count, 20, 1, countLimit)
  # MySQL/MariaDB only accept up to 2^31 - 1 for TIMESTAMP type
  start = utils.parseInt(start, 2147483647, 0, 2147483647)
  start = 2147483647 if start == 0 and not backwards
  offset = utils.parseInt(offset, 0, 0, offsetLimit)

  op = if backwards then '>' else '<'
  ordering = if backwards then 'ASC' else 'DESC'

  pool.execute("SELECT target, UNIX_TIMESTAMP(time) AS time FROM `#{db}`.following FORCE INDEX(query) WHERE uid=? AND app_id=? AND time#{op}FROM_UNIXTIME(?) ORDER BY time #{ordering} LIMIT ?,?", [uid, appid, start, offset, count], (err, command) ->
    result = null
    if err?
      logger.caught(err, 'Failed to get following list from db for user %d, appid %d', uid, appid)
      err = new Error('Failed to get following list from db')
    else
      logger.debug('Result:', command.result.rows)
      result = ({
        uid: row.target,
        time: row.time
      } for row in command.result.rows)
    utils.epilogue(logger, 'getFollowings', timer, callback, err, result)
  )

exports.getFollowers = (uid, appid, count, start = 0, backwards = false, offset = 0, callback) ->
  return false unless utils.validateUserId(uid, callback)

  timer = utils.prologue(logger, 'getFollowers')

  logger.debug('Arguments:', uid, appid, count, start)

  appid = utils.parseInt(appid, 0, 0)
  count = utils.parseInt(count, 20, 1, countLimit)
  # MySQL/MariaDB only accept up to 2^31 - 1 for TIMESTAMP type
  start = utils.parseInt(start, 2147483647, 0, 2147483647)
  start = 2147483647 if start == 0 and not backwards
  offset = utils.parseInt(offset, 0, 0, offsetLimit)

  op = if backwards then '>' else '<'
  ordering = if backwards then 'ASC' else 'DESC'

  pool.execute("SELECT target, UNIX_TIMESTAMP(time) AS time FROM `#{db}`.follower FORCE INDEX(query) WHERE uid=? AND app_id=? AND time#{op}FROM_UNIXTIME(?) ORDER BY time #{ordering} LIMIT ?,?", [uid, appid, start, offset, count], (err, command) ->
    result = null
    if err?
      logger.caught(err, 'Failed to get follower list from db for user %d, appid %d', uid, appid)
      err = new Error('Failed to get follower list from db')
    else
      logger.debug('Result:', command.result.rows)
      result = ({
        uid: row.target,
        time: row.time
      } for row in command.result.rows)
    utils.epilogue(logger, 'getFollowers', timer, callback, err, result)
  )

# 按userid从小到大或从大到小枚举关注关系满足一定条件的用户，比如枚举至少关注过别人的用户，conditions用于指定相应条件，语法参见Membership模块的默认配置
exports.enumerateUser = (appid, count, start = 0, backwards = false, conditions, offset = 0, callback) ->
  timer = utils.prologue(logger, 'enumerateUser')

  logger.debug('Arguments:', appid, count, start, backwards, conditions, offset)

  appid = utils.parseInt(appid, 0, 0)
  count = utils.parseInt(count, 20, 1, countLimit)
  start = (if backwards then 0 else 4294967295) if not utils.validateUserId(start)
  offset = utils.parseInt(offset, 0, 0, offsetLimit)

  op = if backwards then '>' else '<'
  ordering = if backwards then 'ASC' else 'DESC'

  conditions = utils.formulate(conditions, { 'following': 'following_count', 'follower': 'follower_count' })

  if conditions
    conditions = "AND #{conditions} "

  params = [start, appid, offset, count]

  pool.execute("SELECT uid FROM `#{db}`.follow_count FORCE INDEX(PRIMARY) WHERE uid#{op}? AND app_id=? #{conditions}ORDER BY uid #{ordering} LIMIT ?,?", params, (err, command) ->
    if err?
      logger.caught(err, 'Failed to enumerate user')
      err = new Error('Failed to enumerate user')
    else
      result = command.result.rows
    utils.epilogue(logger, 'enumerateUser', timer, callback, err, result)
  )

exports.enumerateUserByCount = (appid, count, cursor, backwards = false, offset = 0, callback) ->
  throw new Error('Not Implemented')
