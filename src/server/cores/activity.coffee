# 所有和用户相关的API才会有appid，某一具体的事件一定只能属于单一的appid
#
# *** 类别约定 ***
#
# 1.	分享
# 2.	评论
# 3.	求链接
# 4.	喜欢
# 5.	收藏
# 6.	转发
# 7.	发布链接
# 8.	关注用户
# 9.	关注分享
# 10.	关注类别
# 11.	关注标签
# 12.	系统消息
# 13.	注册
# 14.	登陆
# 15.	分享提及
# 16.	评论提及
# 17.	转发提及
# 18.	关注后的新评论
# 19.	评论回复
# 20.	品牌
# 21.	单款货品
# 22.	店家商品
# 23.	各种活动
# 24.	活动位置
# 25.	活动海报
# 26.	资金变化
# 27.	用户反馈
# 28.	举报
# 29.	sticker水印
# 30.	品牌V2，用chop命名，而不是brand，上一版的“品牌”有较复杂的约束条件，故引入新的品牌实体
# 31.	ChopFollow，即关注品牌，事件
# 32.	Album，专辑，实体
# 33.	贴子推荐
# 34.	专辑添加一个帖子
# 35.	bag，水印包
# 36.	二元事件，将水印添加到水印包
# 37.	Topic，标签对应的话题
# 38.	TopicFollow, 关注Topic事件
# 39.	保留，用于event album
# 40.	保留，用于Splash album
#
# 50.	Arena，标签对应的话题
# 51.	ArenaFollow, 关注Topic事件
#
# 101 Blink, 动态贴纸
#
#
# 1-14可以作为outbox的action，其中10、11对应外部实体，8、13、14仅作为记录，是只读事件，以后可以增加更多的比如改昵称、换头像等等。
# 2-9，12，15-19可以作为observation的type。其中2-9的接收主体应是源事件的owner，12是因为系统消息，15-17是因为提及了，18是因为关注了，19是因为回复了
# 2-6，9可以作为relation的type
# 3-5，7，9可以作为constraint的type
#
# *** 状态约定 ***
#
# |<-- Higher Bit --- Lower Bit -->|
# 0x80 删除
# 0x40 被锁定（仅自己可见，管理员设置）
# 0x20 隐私保护（仅自己可见，优先于密码保护、额外指定人、以及各种好友关系可见性）
# 0x10 密码保护（仅getActivity适用，范围查询不显示）
# 0x08 额外指定人可见（范围查询API和getActivity要单独处理此类型）
# 0x04 保留，未使用
# 0x01, 0x02 (2 bits): 0 所有人可见; 1 登录用户可见; 2 仅关注的人可见; 3 仅好友可见
#
# *** 说明 ***
#
# Add/Delete/Erase race condition can be avoided via ForeignKey constraint
#   but it doesn't scale with sharding
# relation_count might cause hot lock contention for a popular activity
#
# Two types of race condition:
#   1. outbox vs. relation*
#   2. outbox vs. observation*
#
# SELECT * FROM outbox WHERE status = 0 FOR UPDATE works here as long as the real purge happens after status = 1
#
# Erase doesn't have to use transaction as long as DELETE outbox is the last statement
#
# Prepared Statements with idlist or userlist may have performance hit due to varied variable count
#   but it's mitigated by the fact that most query with idlist/userlist size same as the item count per page,
#   which is usually fixed.
#   userTimeline() is an exception because each user usually has different following people count compared to one another.
#

#TODO Mitigate userTimeline prepared statement performance overhead

#TODO Add status mask as input parameter for all query APIs

#FIXME we are using LIMIT offset, count now, replace early row lookup with late row lookup!

#FIXME Consider UNION ALL instead of user_timeline/observer_event/observer_unread indices
#       when filter count > 1, at the cost of fetching count items for each action/type.
#       But this doesn't work for offset-based pagination, which makes it a bit less appealing to us
#       If we don't support offset in Observation, then we can still use this approach

#FIXME updateActivityText and markAsRead might take quite a while if observation audience is large, thus degrading performance or even timing out

#FIXME potential dead lock

#FIXME potential InnoDB lock table size limit if deleting millions of rows within a transaction

#TODO merge itemActionByUser and itemActivityCount

#TODO check against parent status for 3 itemXXXXX methods

#TODO outbox_count query is temporarily inaccurate after deletion due to deferred erase

#TODO no necessary to use transaction for erase()?
#TODO if we add more kind of periodical scans, do we still need transaction? need observation_delivery & relation_reverse (latter two is local so perf overhead may be small)?

#TODO consider change relation_constraint to constraint as it may contain something more than that in relation, no existing code change needed. Add an (id, type, related_id, user_id) index or another table?

async = require('async')

config = require('../utils/config')
logger = require('../utils/log').getLogger('ACTIVITY')
pool = require('../drivers/mysql-pool').create(config['ActivityDB'])
recorder = require('../utils/record').create('ACTIVITY')
uniqid = require('../utils/uniqid')
utils = require('../utils/routines')

db = config['ActivityDB']?.db
offsetLimit = config['ActivityDB']?.offset_limit ? 1000
countLimit = config['ActivityDB']?.count_limit ? 200

# 获取某个appid的全局时间线列表，filter用于指定需要的类型，blacklist用于指定filter参数是包含还是排除
exports.timeline = (appid, count, start, backwards, filter = [], blacklist = false, offset, callback) ->
  return unless utils.validateArray(filter, 'filter', callback)

  timer = utils.prologue(logger, 'timeline')

  logger.debug('Arguments:', appid, count, start, backwards, filter, blacklist, offset)

  appid = utils.parseInt(appid, 0, 0)
  count = utils.parseInt(count, 20, 1, countLimit)
  start = (if backwards then '0' else '18446744073709551615') if not utils.validateId(start)
  offset = utils.parseInt(offset, 0, 0, offsetLimit)

  op = if backwards then '>' else '<'
  ordering = if backwards then 'ASC' else 'DESC'

  if filter.length == 1 and not blacklist
    index = 'app_action'
  else
    index = 'app_timeline'

  condition = ''

  if filter.length > 0
    condition = "AND action #{if blacklist then 'NOT' else ''} IN (?#{Array(filter.length).join(',?')}) "

  query = "SELECT CAST(id AS CHAR) AS id, user_id, action, text FROM `#{db}`.outbox FORCE INDEX (#{index}) WHERE app_id=? AND id#{op}? #{condition}AND status=0 ORDER BY outbox.id #{ordering} LIMIT ?,?"
  params = Array.prototype.concat.call([appid, start], filter, [offset, count])

  pool.execute(query, params, (err, command) ->
    if err?
      logger.caught(err, 'Failed to query timeline for appid %d', appid)
      err = new Error('Failed to query timeline')
    else
      result = ({
        key: row.id,
        uid: row.user_id,
        appid: appid,
        timestamp: uniqid.extractTimestamp(row.id),
        action: row.action,
        text: utils.binaryToString(row.text)
      } for row in command.result.rows)
    utils.epilogue(logger, 'timeline', timer, callback, err, result)
  )

# 获取某个appid的全局时间线的数量，filter用于指定需要的类型，blacklist用于指定filter参数是包含还是排除，limit用于指定上限，因为数量是通过计算取回元素的个数实现的
exports.timelineCount = (appid, since, filter, blacklist, limit, callback) ->
  return unless utils.validateArray(filter, 'filter', callback)

  timer = utils.prologue(logger, 'timelineCount')

  logger.debug('Arguments:', appid, filter, blacklist)

  appid = utils.parseInt(appid, 0, 0)
  since = uniqid.fromTimestamp(utils.parseInt(since, 0, 0))
  limit = utils.parseInt(limit, 1000, 1, offsetLimit)

  condition = ''

  if filter.length > 0
    condition = "AND action #{if blacklist then 'NOT' else ''} IN (?#{Array(filter.length).join(',?')}) "

  query = "SELECT action FROM `#{db}`.outbox FORCE INDEX (app_timeline) WHERE app_id=? AND id>? #{condition}AND status=0 ORDER BY id DESC LIMIT ?"
  params = Array.prototype.concat.call([appid, since], filter, [limit])

  pool.execute(query, params, (err, command) ->
    if err?
      logger.caught(err, 'Failed to query timeline count for appid %d', appid)
      err = new Error('Failed to query timeline count')
    else
      result = { total: command.result.rows.length }
      for row in command.result.rows
        result[row.action] = 0 if row.action not of result
        result[row.action]++
    utils.epilogue(logger, 'timelineCount', timer, callback, err, result)
  )

# 获取某个userid在某appid下的通知列表，unreadOnly用于指定是否只返回未读通知，filter用于指定通知类型，blacklist用于指定filter参数是包含还是排除，source用于指定消息来源的userid
exports.userObservation = (userid, appid, unreadOnly = false, count, start = 0, backwards, filter = [], blacklist = false, source = [], offset, callback) ->
  return false unless utils.validateUserId(userid, callback)
  return false unless utils.validateArray(filter, 'filter', callback)
  return false unless utils.validateArray(source, 'source', callback)

  timer = utils.prologue(logger, 'userObservation')

  logger.debug('Arguments:', userid, appid, unreadOnly, count, start, backwards, filter, blacklist, source, offset)

  appid = utils.parseInt(appid, 0, 0)
  count = utils.parseInt(count, 20, 1, countLimit)
  start = (if backwards then '0' else '18446744073709551615') if not utils.validateId(start)
  offset = utils.parseInt(offset, 0, 0, offsetLimit)

  op = if backwards then '>' else '<'
  ordering = if backwards then 'ASC' else 'DESC'

  # in future after sharding, we can't do join directly, instead, we need a 2-step query

  if unreadOnly
    if filter.length == 1 and not blacklist
      index = 'observer_unread_type'
    else
      index = 'observer_unread'
  else
    if filter.length == 1 and not blacklist
      index = 'observer_type'
    else
      index = 'observer_event'

  condition = ''

  if unreadOnly
    condition += 'AND T2.unread=1 '

  if filter.length > 1
    condition += "AND T2.type #{if blacklist then 'NOT ' else ''}IN (?#{Array(filter.length).join(',?')}) "
  else if filter.length == 1
    condition += if blacklist then 'AND T2.type!=? ' else 'AND T2.type=? '

  if source.length > 0
    condition += "AND T2.owner_id IN (?#{Array(source.length).join(',?')}) "

  query = "SELECT CAST(T2.event_id AS CHAR) AS event_id, T2.owner_id, T2.unread, T2.type, T1.action, T1.text FROM `#{db}`.outbox AS T1 FORCE INDEX (PRIMARY), `#{db}`.observation AS T2 FORCE INDEX (#{index}) WHERE T2.observer_id=? AND T2.app_id=? AND T2.event_id#{op}? #{condition}AND T1.id=T2.event_id ORDER BY T2.event_id #{ordering} LIMIT ?,?"

  params = Array.prototype.concat.call([userid, appid, start], filter, source, [offset, count])

  pool.execute(query, params, (err, command) ->
    result = null
    if err?
      logger.caught(err, 'Failed to get observations for user %d appid %d', userid, appid)
      err = new Error('Failed to get observations')
    else
      result = ({
        key: row.event_id,
        unread: row.unread,
        type: row.type,
        uid: row.owner_id,
        appid: appid,
        timestamp: uniqid.extractTimestamp(row.event_id),
        action: row.action,
        text: utils.binaryToString(row.text)
      } for row in command.result.rows)
    utils.epilogue(logger, 'userObservation', timer, callback, err, result)
  )

# 获取某个userid在某appid下的通知数量，unreadOnly用于指定是否只返回未读通知，filter用于指定通知类型，limit用于指定上限，因为数量是通过计算取回元素的个数实现的，source用于指定消息来源的userid
exports.userObservationCount = (userid, appid, unreadOnly = false, filter = [], limit = 100, source = [], callback) ->
  return false unless utils.validateUserId(userid, callback)
  return false unless utils.validateArray(filter, 'filter', callback)
  return false unless utils.validateArray(source, 'source', callback)

  timer = utils.prologue(logger, 'userObservationCount')

  logger.debug('Arguments:', userid, appid, unreadOnly, filter, limit, source)

  appid = utils.parseInt(appid, 0, 0)
  limit = utils.parseInt(limit, 100, 1, offsetLimit)

  filter = utils.removeDuplicates(filter)
  logger.debug('Normalized filter list:', filter)

  condition = ''

  if unreadOnly
    index = 'observer_unread_type'
    condition += 'AND unread=1 '
  else
    index = 'observer_type'

  if source.length > 0
    condition += "AND owner_id IN (?#{Array(source.length).join(',?')}) "

  if filter.length > 0
    baseQuery = "(SELECT ? AS type, COUNT(*) AS count FROM (SELECT event_id FROM `#{db}`.observation FORCE INDEX(#{index}) WHERE observer_id=? AND app_id=? AND type=? #{condition}LIMIT ?) AS T)"

    query = baseQuery + utils.repeat(' UNION ALL ' + baseQuery, filter.length - 1)

    params = []

    for type in filter
      Array.prototype.push.apply(params, Array.prototype.concat.call([type, userid, appid, type], source, [limit]))
  else
    query = "SELECT 0 AS type, COUNT(*) AS count FROM (SELECT event_id FROM `#{db}`.observation FORCE INDEX(#{index}) WHERE observer_id=? AND app_id=? #{condition}LIMIT ?) AS T"

    params = Array.prototype.concat.call([userid, appid], source, [limit])

  pool.execute(query, params, (err, command) ->
    if err?
      logger.caught(err, 'Failed to get observation count for user %d appid %d', userid, appid)
      err = new Error('Failed to get observation count')
    else
      result = {}
      for row in command.result.rows
        result[row.type] = row.count
    utils.epilogue(logger, 'userObservationCount', timer, callback, err, result)
  )

# 获取一组userid在某个appid下的时间线列表，filter用于指定需要的类型，blacklist用于指定filter参数是包含还是排除
exports.userTimeline = (userlist, appid, count, start = 0, end = 0, backwards = false, filter = [], blacklist = false, offset, callback) ->
  return false unless utils.validateArray(userlist, 'userlist', callback)
  return false unless utils.validateArray(filter, 'filter', callback)

  timer = utils.prologue(logger, 'userTimeline')

  logger.debug('Arguments:', userlist, appid, count, start, end, backwards, filter, blacklist, offset)

  appid = utils.parseInt(appid, 0, 0)
  userlist = utils.normalizeUserIdList(userlist)
  count = utils.parseInt(count, 20, 1, countLimit)
  start = (if backwards then '0' else '18446744073709551615') if not utils.validateId(start)
  end = (if backwards then '18446744073709551615' else '0') if not utils.validateId(end)
  offset = utils.parseInt(offset, 0, 0, offsetLimit)

  op1 = '<'
  op2 = '>'
  [op2, op1] = [op1, op2] if backwards
  ordering = if backwards then 'ASC' else 'DESC'

  userlist = utils.removeDuplicates(userlist)
  logger.debug('Normalized user id list:', userlist)

  if userlist.length == 0
    return utils.epilogue(logger, 'userTimeline', timer, callback, null, [])

  if filter.length == 1 and not blacklist
    index = 'user_action'
  else
    index = 'user_timeline'

  condition = ''

  if filter.length > 1
    condition = "AND action #{if blacklist then 'NOT' else ''}IN (?#{Array(filter.length).join(',?')}) "
  else if filter.length == 1
    condition = if blacklist then 'AND action!=? ' else 'AND action=? '

  baseQuery = "(SELECT CAST(id AS CHAR) AS id, user_id, action, text FROM `#{db}`.outbox FORCE INDEX (#{index}) WHERE user_id=? AND app_id=? AND id#{op1}? AND id#{op2}? #{condition}AND status=0 ORDER BY outbox.id #{ordering} LIMIT ?,?)"

  query = baseQuery + utils.repeat(' UNION ALL ' + baseQuery, userlist.length - 1)

  params = []

  for userid in userlist
    Array.prototype.push.apply(params, Array.prototype.concat.call([userid, appid, start, end], filter, [offset, count]))

  pool.execute(query, params, (err, command) ->
    if err?
      logger.caught(err, 'Failed to query user timeline', userlist, appid)
      err = new Error('Failed to query user timeline')
    else
      result = ({
        key: row.id,
        uid: row.user_id,
        appid: appid,
        timestamp: uniqid.extractTimestamp(row.id),
        action: row.action,
        text: utils.binaryToString(row.text)
      } for row in command.result.rows)
    utils.epilogue(logger, 'userTimeline', timer, callback, err, result)
  )

# 获取一组userid在某个appid下的时间线数量
exports.userTimelineCount = (userlist, appid, callback) ->
  return false unless utils.validateArray(userlist, 'userlist', callback)

  timer = utils.prologue(logger, 'userTimelineCount')

  logger.debug('Arguments:', userlist, appid)

  appid = utils.parseInt(appid, 0, 0)
  userlist = utils.normalizeUserIdList(userlist)

  logger.debug('Normalized id list:', userlist)

  if userlist.length == 0
    utils.epilogue(logger, 'userTimelineCount', timer, callback, null, {})
  else
    query = "SELECT user_id, action, count FROM `#{db}`.outbox_count FORCE INDEX (PRIMARY) WHERE user_id IN (?#{Array(userlist.length).join(',?')})"
    pool.execute(query, userlist, (err, command) ->
      if err?
        logger.caught(err, 'Failed to get user timeline count', userlist)
        err = new Error('Failed to get user timeline count')
      else
        result = {}
        for row in command.result.rows
          result[row.user_id] ?= {}
          result[row.user_id][row.action] = row.count
      utils.epilogue(logger, 'userTimelineCount', timer, callback, err, result)
    )

# 获取一组userid在某个appId和action下的时间线数量, filter为action类型
exports.userTimeLineCountByAction = (userList, appId, filter = [], context = {}, callback) ->
  return false unless utils.validateArray(userList, 'userList', callback)
  return false unless utils.validateArray(filter, 'filter', callback)

  timer = utils.prologue(logger, 'userTimeLineCountByAction')

  logger.debug('Arguments:', userList, appId, filter, context)

  appId = utils.parseInt(appId, 0, 0)
  userList = utils.normalizeUserIdList(userList)

  logger.debug('Normalized id list:', userList)

  if userList.length == 0
    utils.epilogue(logger, 'userTimeLineCountByAction', timer, callback, null, {})
  else
    query = "SELECT count(*) as actionCount FROM `#{db}`.outbox FORCE INDEX (PRIMARY) WHERE app_id=? AND user_id IN (?#{Array(userList.length).join(',?')}) AND action IN (?#{Array(filter.length).join(',?')})"
    params = [].concat([appId], userList, filter)
    pool.execute(query, params, (err, command) ->
      if err?
        logger.caught(err, 'Failed to count blacklist timeline count', userList)
        err = new Error('Failed to count blacklist timeline count')
      else
        result = null
        for row in command.result.rows
          result = row.actionCount

      utils.epilogue(logger, 'userTimeLineCountByAction', timer, callback, err, result)
    )

# 获取某一userid对一组事件id所做的*所有*约束类操作id列表，比如获取用户X在帖子A, B和C中所有喜欢、求链接等操作id，主要用于判断是否喜欢或求过链接
exports.itemActionByUser = (idlist, ownerlist, userid, callback) ->
  return false unless utils.validateUserId(userid, callback)
  return false unless utils.validateArray(idlist, 'idlist', callback)
  return false unless utils.validateArray(idlist, 'ownerlist', callback)

  logger.debug('Arguments:', idlist, ownerlist, userid)

  if idlist.length != ownerlist.length
    logger.warn("Length of idlist and ownerlist does't match")
    callback(new Error("Length of idlist and ownerlist does't match"))
    return false

  timer = utils.prologue(logger, 'itemActionByUser')

  idlist = (utils.normalizeId(id) for id, pos in idlist when utils.validateId(id) and utils.validateUserId(ownerlist[pos]))
  ownerlist = (owner for owner, pos in ownerlist when utils.validateId(idlist[pos]) and utils.validateUserId(owner))

  logger.debug('Normalized id list:', idlist)
  logger.debug('Normalized owner list:', ownerlist)

  # use of ownerlist is to locate shards in future

  if idlist.length == 0
    utils.epilogue(logger, 'itemActionByUser', timer, callback, null, {})
  else
    query = "SELECT CAST(id AS CHAR) AS id, type, CAST(related_id AS CHAR) as target FROM `#{db}`.relation_constraint FORCE INDEX (PRIMARY) WHERE user_id=? AND id IN (?#{Array(idlist.length).join(',?')})"
    pool.execute(query, [userid].concat(idlist), (err, command) ->
      result = null
      if err?
        logger.caught(err, "Failed to get user %d's actions for items %d", userid, idlist)
        err = new Error('Failed to get user actions on items')
      else
        result = {}
        for row in command.result.rows
          result[row.id] ?= {}
          result[row.id][row.type] = row.target
      utils.epilogue(logger, 'itemActionByUser', timer, callback, err, result)
    )

# 获取某一事件eventid下所有类型为type的事件列表
exports.itemActivity = (eventid, ownerid, type, count, start = 0, backwards = false, offset, callback) ->
  return false unless utils.validateId(eventid, callback)
  return false unless utils.validateUserId(ownerid, callback)

  timer = utils.prologue(logger, 'itemActivity')

  logger.debug('Arguments:', eventid, ownerid, type, count, start, backwards, offset)

  count = utils.parseInt(count, 20, 1, countLimit)
  start = (if backwards then '0' else '18446744073709551615') if not utils.validateId(start)
  offset = utils.parseInt(offset, 0, 0, offsetLimit)

  op = if backwards then '>' else '<'
  ordering = if backwards then 'ASC' else 'DESC'

  query = "SELECT CAST(T1.id AS CHAR) AS id, T1.user_id, T1.text FROM `#{db}`.outbox AS T1 FORCE INDEX (PRIMARY), `#{db}`.relation AS T2 FORCE INDEX (PRIMARY) WHERE T2.id=? AND T2.type=? AND T2.related_id#{op}? AND T1.id=T2.related_id ORDER BY T2.related_id #{ordering} LIMIT ?,?"

  pool.execute(query, [eventid, type, start, offset, count], (err, command) ->
    result = null
    if err?
      logger.caught(err, 'Failed to get activities of type %d under item %d', type, eventid)
      err = new Error('Failed to get activities on specific item')
    else
      result = ({
        key: row.id,
        uid: row.user_id,
        timestamp: uniqid.extractTimestamp(row.id),
        text: utils.binaryToString(row.text)
      } for row in command.result.rows)
    utils.epilogue(logger, 'itemActivity', timer, callback, err, result)
  )

# 类似itemActivity，在获取某一事件eventid下所有类型为type的事件列表的同时，
# 也读取列表中每个事件下对应的descendantType类型的事件的id和时间戳。
# descendantOldest用于指定是选取最新还是最老的一个descendantType事件
exports.itemActivityIdWithDescendant = (eventid, ownerid, type, descendantType, descendantOldest, count, start = 0, backwards = false, offset, callback) ->
  return false unless utils.validateId(eventid, callback)
  return false unless utils.validateUserId(ownerid, callback)

  timer = utils.prologue(logger, 'itemActivityIdWithDescendant')

  logger.debug('Arguments:', eventid, ownerid, type, descendantType, descendantOldest, count, start, backwards, offset)

  count = utils.parseInt(count, 20, 1, countLimit)
  start = (if backwards then '0' else '18446744073709551615') if not utils.validateId(start)
  offset = utils.parseInt(offset, 0, 0, offsetLimit)

  op = if backwards then '>' else '<'
  ordering = if backwards then 'ASC' else 'DESC'
  ordering2 = if descendantOldest then 'ASC' else 'DESC'

  query = "SELECT CAST(related_id AS CHAR) as id, user_id, CAST((SELECT related_id FROM `#{db}`.relation WHERE id=T.related_id AND type=? ORDER BY related_id #{ordering2} LIMIT 1) AS CHAR) AS cid FROM `#{db}`.relation AS T WHERE id=? AND type=? AND related_id#{op}? ORDER BY related_id #{ordering} LIMIT ?,?"
  pool.execute(query, [descendantType, eventid, type, start, offset, count], (err, command) ->
    result = null
    if err?
      logger.caught(err, 'Failed to get activities of type %d under item %d', type, eventid)
      err = new Error('Failed to get activities on specific item')
    else
      result = ({
        key: row.id,
        uid: row.user_id,
        timestamp: uniqid.extractTimestamp(row.id),
        descendantKey: row.cid,
        descendantTimestamp: uniqid.extractTimestamp(row.cid)
      } for row in command.result.rows)
    utils.epilogue(logger, 'itemActivityIdWithDescendant', timer, callback, err, result)
  )

# 类似itemActivity，在获取某一事件eventid下所有类型为type的事件列表，只是排序依据是关系表的time字段而非事件时间戳
#
# Notes: 这里start是timestamp类型
exports.itemActivityByTime = (eventid, ownerid, type, count, start = 0, backwards = false, offset, callback) ->
  return false unless utils.validateId(eventid, callback)
  return false unless utils.validateUserId(ownerid, callback)

  timer = utils.prologue(logger, 'itemActivityByTime')

  logger.debug('Arguments:', eventid, ownerid, type, count, start, backwards, offset)

  count = utils.parseInt(count, 20, 1, countLimit)
  start = (if backwards then 0 else 2147483648) if not utils.isNumber(start)
  # MySQL/MariaDB only accept up to 2^31 - 1 for TIMESTAMP type
  start = utils.parseInt(start, 2147483647, 0, 2147483647)
  start = 2147483647 if start == 0 and not backwards
  offset = utils.parseInt(offset, 0, 0, offsetLimit)

  op = if backwards then '>' else '<'
  ordering = if backwards then 'ASC' else 'DESC'

  query = "SELECT CAST(T1.id AS CHAR) AS id, T1.user_id, T1.text, UNIX_TIMESTAMP(T2.time) AS time FROM `#{db}`.outbox AS T1 FORCE INDEX (PRIMARY), `#{db}`.relation AS T2 FORCE INDEX (time) WHERE T2.id=? AND T2.type=? AND T2.time#{op}FROM_UNIXTIME(?) AND T1.id=T2.related_id ORDER BY T2.time #{ordering} LIMIT ?,?"

  pool.execute(query, [eventid, type, start, offset, count], (err, command) ->
    result = null
    if err?
      logger.caught(err, 'Failed to get activities by time of type %d under item %d', type, eventid)
      err = new Error('Failed to get activities by time')
    else
      result = ({
        key: row.id,
        uid: row.user_id,
        timestamp: uniqid.extractTimestamp(row.id),
        time: row.time,
        text: utils.binaryToString(row.text)
      } for row in command.result.rows)
    utils.epilogue(logger, 'itemActivityByTime', timer, callback, err, result)
  )

# 获取一组事件id下所有类型事件的数量
exports.itemActivityCount = (idlist, ownerlist, callback) ->
  return false unless utils.validateArray(idlist, 'idlist', callback)
  return false unless utils.validateArray(idlist, 'ownerlist', callback)

  logger.debug('Arguments:', idlist, ownerlist)

  if idlist.length != ownerlist.length
    logger.warn("Length of idlist and ownerlist does't match")
    callback(new Error("Length of idlist and ownerlist does't match"))
    return false

  timer = utils.prologue(logger, 'itemActivityCount')

  idlist = (utils.normalizeId(id) for id, pos in idlist when utils.validateId(id) and utils.validateUserId(ownerlist[pos]))
  ownerlist = (owner for owner, pos in ownerlist when utils.validateId(idlist[pos]) and utils.validateUserId(owner))

  logger.debug('Normalized id list:', idlist)
  logger.debug('Normalized owner list:', ownerlist)

  # use of ownerlist is to locate shards in future

  if idlist.length == 0
    utils.epilogue(logger, 'itemActivityCount', timer, callback, null, {})
  else
    query = "SELECT CAST(id AS CHAR) AS id, type, count FROM `#{db}`.relation_count FORCE INDEX (PRIMARY) WHERE id IN (?#{Array(idlist.length).join(',?')})"
    pool.execute(query, idlist, (err, command) ->
      result = null
      if err?
        logger.caught(err, 'Failed to get activity count', idlist, ownerlist)
        err = new Error('Failed to get activity count on specific items')
      else
        result = {}
        for row in command.result.rows
          result[row.id] ?= {}
          result[row.id][row.type] = row.count
      utils.epilogue(logger, 'itemActivityCount', timer, callback, err, result)
    )

# 获取一组指定id的事件列表，stable用于指定返回顺序是否和id指定顺序一致
# TODO ownerlist 必须真实存在且一一对应
exports.getActivity = (idlist, ownerlist, stable = false, callback) ->
  return false unless utils.validateArray(idlist, 'idlist', callback)
  return false unless utils.validateArray(idlist, 'ownerlist', callback)

  logger.debug('Arguments:', idlist, ownerlist, stable)

  if idlist.length != ownerlist.length
    logger.warn("Length of idlist and ownerlist does't match")
    callback(new Error("Length of idlist and ownerlist does't match"))
    return false

  timer = utils.prologue(logger, 'getActivity')

  idlist = (utils.normalizeId(id) for id, pos in idlist when utils.validateId(id) and utils.validateUserId(ownerlist[pos]))
  ownerlist = (owner for owner, pos in ownerlist when utils.validateId(idlist[pos]) and utils.validateUserId(owner))

  logger.debug('Normalized id list:', idlist)
  logger.debug('Normalized owner list:', ownerlist)

  # use of ownerlist is to locate shards in future

  if idlist.length == 0
    utils.epilogue(logger, 'getActivity', timer, callback, null, [])
  else
    query = "SELECT CAST(id AS CHAR) AS id, user_id, app_id, action, status, text FROM `#{db}`.outbox FORCE INDEX (PRIMARY) WHERE id IN (?#{Array(idlist.length).join(',?')})"
    pool.execute(query, idlist, (err, command) ->
      result = null
      if err?
        logger.caught(err, 'Failed to get specified activities', idlist)
        err = new Error('Failed to get specified activities')
      else
        result = ({
          key: row.id,
          uid: row.user_id,
          appid: row.app_id,
          timestamp: uniqid.extractTimestamp(row.id),
          action: row.action,
          text: utils.binaryToString(row.text),
          status: row.status
        } for row in command.result.rows)
        result = utils.restoreOrder(idlist, result, 'key') if stable
      utils.epilogue(logger, 'getActivity', timer, callback, err, result)
    )

# 获取某一userid对某一事件eventid所做的某一action类型的约束类操作，比如获取用户X对贴子A的喜欢操作
# 这类事件通常情况下不知道activity的id，所以需要通过该接口获取。
exports.getUserAction = (eventid, ownerid, userid, action, callback) ->
  return false unless utils.validateId(eventid, callback)
  return false unless utils.validateUserId(ownerid, callback)
  return false unless utils.validateUserId(userid, callback)

  logger.debug('Arguments:', eventid, ownerid, userid, action)

  timer = utils.prologue(logger, 'getUserAction')

  action = utils.parseInt(action, 0)

  query = "SELECT CAST(T1.id AS CHAR) AS id, T1.user_id, app_id, action, status, text FROM `#{db}`.outbox AS T1 FORCE INDEX (PRIMARY), `#{db}`.relation_constraint AS T2 FORCE INDEX (PRIMARY) WHERE T2.id=? AND T2.user_id=? AND T2.type=? AND T1.id=T2.related_id"
  pool.execute(query, [eventid, userid, action], (err, command) ->
    result = null
    if err?
      logger.caught(err, "Failed to get user action", eventid, ownerid, userid, action)
      err = new Error('Failed to get user action')
    else
      result = {}
      for row in command.result.rows
        result = ({
          key: row.id,
          uid: row.user_id,
          appid: row.app_id,
          timestamp: uniqid.extractTimestamp(row.id),
          action: row.action,
          text: utils.binaryToString(row.text),
          status: row.status
        } for row in command.result.rows)
    utils.epilogue(logger, 'getUserAction', timer, callback, err, result)
  )

# 按userid从小到大或从大到小枚举事件记录满足一定条件的用户，比如枚举至少发过一个帖子的用户，conditions用于指定相应条件，语法参见Membership模块的默认配置
exports.enumerateUser = (appid, count, start = 0, backwards = false, conditions, offset = 0, callback) ->
  timer = utils.prologue(logger, 'enumerateUser')

  logger.debug('Arguments:', appid, count, start, backwards, conditions, offset)

  appid = utils.parseInt(appid, 0, 0)
  count = utils.parseInt(count, 20, 1, countLimit)
  start = (if backwards then 0 else 4294967295) if not utils.validateUserId(start)
  offset = utils.parseInt(offset, 0, 0, offsetLimit)

  op = if backwards then '>' else '<'
  ordering = if backwards then 'ASC' else 'DESC'

  conditions = utils.formulate(conditions, { 'type': 'action', 'count': 'count' })

  if conditions
    conditions = "AND #{conditions} "

  params = [start, appid, offset, count]

  pool.execute("SELECT DISTINCT user_id AS uid FROM `#{db}`.outbox_count FORCE INDEX(PRIMARY) WHERE user_id#{op}? AND app_id=? #{conditions}ORDER BY uid #{ordering} LIMIT ?,?", params, (err, command) ->
    if err?
      logger.caught(err, 'Failed to enumerate user')
      err = new Error('Failed to enumerate user')
    else
      result = command.result.rows
    utils.epilogue(logger, 'enumerateUser', timer, callback, err, result)
  )

exports.enumerateUserByCount = (appid, action, count, cursor, backwards = false, offset = 0, callback) ->
  throw new Error('Not Implemented')

# 创建一条事件记录，
# userid为事件宿主
# appid为应用类型
# action为事件类型
# targetid为父关系id
# ownerid为父关系id宿主
# observers用于指定收到通知的用户userid
# obsevationType用于指定通知的类型
# unique表明是否为约束性事件（如喜欢等）
# names用于指定全局唯一名称
# time用于指定创建时间
#
# err.duplicate, 在为unique的关系下，有可能抛出该err，表示该关系已经存在，注意：在callback为txmr时，err的抛出可能存在问题，详见注解
exports.addActivity = (userid, appid = 0, action, text = null,
                       targetid = null, ownerid = null,observers = [], obsevationType = [],
                       unique = false, names = [], time = null, callback) ->
  return false unless utils.validateUserId(userid, callback)
  return false unless utils.validateArray(observers, 'observers', callback)
  return false unless utils.validateArray(obsevationType, 'obsevationType', callback)
  return false unless utils.validateArray(names, 'names', callback)

  logger.debug('Arguments:', userid, appid, action, text, targetid, ownerid, observers, obsevationType, unique, names, time)

  appid = utils.parseInt(appid, 0, 0)
  action = utils.parseInt(action, 0)
  time = utils.parseInt(time, 0)
  time = null if time <= 0

  if action <= 0
    logger.warn('Invalid action', action)
    callback(new Error('Invalid action'))
    return false

  if Array.isArray(targetid) and Array.isArray(ownerid)
    targetid = utils.normalizeIdList(targetid)
    ownerid = utils.normalizeUserIdList(ownerid)
    if targetid.length != ownerid.length
      logger.warn("Length of targetid and ownerid does't match")
      callback(new Error("Length of targetid and ownerid does't match"))
      return false
  else if (targetid? or ownerid?) and not (utils.validateId(targetid) and utils.validateUserId(ownerid))
    logger.warn('Invalid targetid/ownerid pair', targetid, ownerid)
    callback(new Error('Invalid targetid/ownerid pair'))
    return false
  else if targetid?
    targetid = [targetid]
    ownerid = [ownerid]
  else
    targetid = []
    ownerid = []

  if observers.length != obsevationType.length
    logger.warn("Length of observers and observationType does't match")
    callback(new Error("Length of observers and observationType does't match"))
    return false

  timer = utils.prologue(logger, 'addActivity')

  id = if time then uniqid.fromTimestamp(time) else uniqid.generate()

  params = []

  # multiple shards may be involved
  # 1. outbox & outbox_count & relation_reverse & observation_delivery -- by userid
  # 2. relation & relation_constraint & relation_count -- by ownerid
  # 3. observation -- by observers

  for name in names when name? and name = name.toString().trim()
    params.push(["INSERT INTO `#{db}`.name_lookup(name, id) VALUES(?,?)", [name, id]])
  if unique
    # list it top to make it fail fast
    for tid in targetid
      params.push(["INSERT INTO `#{db}`.relation_constraint(id, type, related_id, user_id) VALUES(?,?,?,?)", [tid, action, id, userid]])
  params.push(["INSERT INTO `#{db}`.outbox(id, user_id, app_id, action, text) VALUES(?,?,?,?,?)", [id, userid, appid, action, utils.stringToBinary(text)]])
  params.push(["INSERT INTO `#{db}`.outbox_count(user_id, app_id, action, count) VALUES(?,?,?,1) ON DUPLICATE KEY UPDATE count=count+1", [userid, appid, action]])
  for observer, pos in observers when utils.validateUserId(observer) and obsevationType[pos] > 0
    params.push(["INSERT INTO `#{db}`.observation(observer_id, app_id, event_id, owner_id, type) VALUES(?,?,?,?,?)", [observer, appid, id, userid, obsevationType[pos]]])
    params.push(["INSERT INTO `#{db}`.observation_delivery(event_id, observer_id) VALUES(?,?)", [id, observer]])
  for tid, i in targetid
    params.push(["INSERT INTO `#{db}`.relation_reverse(id, target_id, owner_id, type) VALUES(?,?,?,?)", [id, tid, ownerid[i], action]])
    params.push(["INSERT INTO `#{db}`.relation(id, type, related_id, user_id) VALUES(?,?,?,?)", [tid, action, id, userid]])
    params.push(["INSERT INTO `#{db}`.relation_count(id, type, count) VALUES(?,?,1) ON DUPLICATE KEY UPDATE count=count+1", [tid, action]])

  cb = (err) ->
    if err?
      id = null
      # TODO: 这个err不能正常返回给上一层callback，可能是由于txmr里会将原err抛出，需要检查原因
      if err.num == 1062 # MySQL error code for key duplicate
        err = new Error('Entry already exists')
        err.duplicate = true
      else
        logger.caught(err, 'Failed to add activity', userid, appid, action, text, targetid, ownerid, observers, obsevationType, unique)
        err = new Error('Failed to add activity')
    utils.epilogue(logger, 'addActivity', timer, callback, err, id)

  if typeof callback.transaction == 'function'
    callback.transaction(params, cb)
  else if params.length > 1
    pool.transaction(params, cb)
  else
    params[0].push(cb)
    pool.execute.apply(pool, params[0])
  return id

# 更新用户userid创建的事件id的text字段
exports.updateActivityText = (id, userid, text, callback) ->
  return false unless utils.validateId(id, callback)
  return false unless utils.validateUserId(userid, callback)

  logger.debug('Arguments:', id, userid, text)

  timer = utils.prologue(logger, 'updateActivityText')

  params = []

  # multiple shards may be involved
  # 1. outbox -- by userid
  # 2. observation -- by observers

  params.push(["UPDATE `#{db}`.outbox SET text=? WHERE id=? AND user_id=? AND status=0", [utils.stringToBinary(text), id, userid]])
  params.push(["UPDATE `#{db}`.observation SET unread=1 WHERE event_id=? AND unread!=1 AND ROW_COUNT()=1", [id]])

  pool.transaction(params, (err, commands) ->
    if err?
      logger.caught(err, 'Failed to update activity text', id, userid, text)
      err = new Error('Failed to update activity text')
    else
      for command in commands
        success = command.result.affected_rows == 1
        break
    utils.epilogue(logger, 'updateActivityText', timer, callback, err, success)
  )

# 类似updateActivityText，更新用户userid创建的事件id的text字段，仅当原值为oldText时更新
exports.updateActivityTextTransaction = (id, userid, text, oldText, callback) ->
  return false unless utils.validateId(id, callback)
  return false unless utils.validateUserId(userid, callback)

  logger.debug('Arguments:', id, userid, text, oldText)

  timer = utils.prologue(logger, 'updateActivityTextTransaction')

  params = []

  params.push(["UPDATE `#{db}`.outbox SET text=? WHERE id=? AND user_id=? AND text=? AND status=0", [utils.stringToBinary(text), id, userid, utils.stringToBinary(oldText)], (result) ->
    if result.affected_rows != 1
      err = new Error('Transaction requirements not satisfied')
      err.aborted = true
      return err
  ])

  transaction = callback.transaction ? pool.transaction
  transaction(params, (err, commands) ->
    if err?
      logger.caught(err, 'Failed to update activity text', id, userid, text)
      if err.aborted
        err = null
        success = false
      else
        err = new Error('Failed to update activity text')
    else
      for command in commands
        success = command.result.affected_rows == 1
        break
    utils.epilogue(logger, 'updateActivityTextTransaction', timer, callback, err, success)
  )

# 为一组用户observers添加用户userid创建的事件id的通知，类型为obsevationType
exports.addActivityObserver = (id, userid, observers = [], obsevationType = [], callback) ->
  return false unless utils.validateUserId(userid, callback)
  return false unless utils.validateArray(observers, 'observers', callback)
  return false unless utils.validateArray(obsevationType, 'obsevationType', callback)

  logger.debug('Arguments:', id, userid, observers, obsevationType)

  if observers.length != obsevationType.length
    logger.warn("Length of observers and observationType does't match")
    callback(new Error("Length of observers and observationType does't match"))
    return false

  timer = utils.prologue(logger, 'addActivityObserver')

  delivery = []
  observation = []

  for observer, pos in observers when utils.validateUserId(observer) and obsevationType[pos] > 0
    delivery.push("(#{id},#{observer})")
    observation.push("(#{observer},?,#{id},#{userid},#{obsevationType[pos]})")

  if delivery.length == 0
    utils.epilogue(logger, 'addActivityObserver', timer, callback)
    return false

  deliveryParams = delivery.join(',')
  observationParams = observation.join(',')

  # multiple shards may be involved
  # 1. observation -- by observers
  pool.acquire((err, conn) ->
    if err?
      logger.caught(err, "Can't get a MySQL connection")
      utils.epilogue(logger, 'addActivityObserver', timer, callback, new Error("Can't get a MySQL connection"))
    else
      async.waterfall([
        async.apply(conn.query, 'START TRANSACTION'),
        async.apply(conn.query, "SELECT app_id FROM `#{db}`.outbox WHERE id='#{id}' AND user_id='#{userid}' AND status=0 LOCK IN SHARE MODE"),
        async.apply((command, cb) ->
          if command.result.rows.length != 1
            err = new Error('Activity Not Found')
          else
            observationParams = observationParams.replace(/\?/g, command.result.rows[0].app_id)
          cb(err)
        ),
        async.apply(conn.query, "INSERT IGNORE INTO `#{db}`.observation_delivery(event_id, observer_id) VALUES#{deliveryParams}"),
        async.apply((command, cb) ->
          conn.query("INSERT INTO `#{db}`.observation(observer_id, app_id, event_id, owner_id, type) VALUES#{observationParams} ON DUPLICATE KEY UPDATE unread=1, app_id=VALUES(app_id), owner_id=VALUES(owner_id), type=VALUES(type)", cb)
        )
      ], (err) ->
        if err?
          logger.caught(err, 'Failed to add new observers for activity', id, userid)
          err = new Error('Failed to add new observers for activity')
          conn.query('ROLLBACK')
          pool.release(conn)
          utils.epilogue(logger, 'addActivityObserver', timer, callback, err)
        else
          conn.query('COMMIT', (err, result) ->
            if err?
              logger.caught(err, 'Failed to commit new observers for activity', id, userid)
              err = new Error('Failed to commit new observers for activity')
            pool.release(conn)
            utils.epilogue(logger, 'addActivityObserver', timer, callback, err)
          )
      )
  )

#
# 将id和sinkid事件建立类型为type的关联，该关联是由于事件eventid产生的
#
# TODO(lyt): 由于事件eventid造成了id和sinkid的关联，因此应该在创建eventid，即addActivity时即建立
# 该关联关系，而不应该在事件创建完毕之后再通过该函数手动建立关联。这里是temporary solution.
#
# 注意：
#   这里必须注意区分id和sinkid，具体为id应该与relation表中的宿主id保持一致。
#
# id,宿主id，
# sinkid为与宿主id发生关联的id
# eventid，产生如上关联的事件id
# unique 该关联是否具有唯一性
exports.addAssociation = (id, uid, sinkid, suid, eventid, euid, unique = false, callback) ->
  return false unless utils.validateId(id, callback)
  return false unless utils.validateUserId(uid, callback)
  return false unless utils.validateId(sinkid, callback)
  return false unless utils.validateUserId(suid, callback)
  return false unless utils.validateId(eventid, callback)
  return false unless utils.validateUserId(euid, callback)

  timer = utils.prologue(logger, 'addAssociation')
  logger.debug('Arguments:', id, uid, sinkid, suid, eventid, euid)

  params = []

  params.push(["SELECT action INTO @action FROM `#{db}`.outbox WHERE id=? AND user_id=? LOCK IN SHARE MODE", [eventid, euid], (result) ->
    return new Error('Activity not found') if result.affected_rows != 1
  ])
  if unique
    # list it top to make it fail fast
    params.push(["INSERT INTO `#{db}`.association_constraint(id, sink_id, type, event_id, user_id) VALUES(?,?,@action,?,?)", [id, sinkid, eventid, euid]])
  params.push(["INSERT INTO `#{db}`.association(id, sink_id, type, event_id, user_id) VALUES(?,?,@action,?,?)", [id, sinkid, eventid, euid]])
  params.push(["INSERT INTO `#{db}`.association_count(id, sink_id, type, count) VALUES(?,?,@action,1) ON DUPLICATE KEY UPDATE count=count+1", [id, sinkid]])

  transaction = callback.transaction ? pool.transaction
  transaction(params, (err) ->
    if err?
      if err.num == 1062 # MySQL error code for key duplicate
        err.duplicate = true
      else
        logger.caught(err, 'Failed to add association', id, uid, sinkid, suid, eventid, euid, unique)
        err = new Error('Failed to add association')
    utils.epilogue(logger, 'addAssociation', timer, callback, err)
  )

# 具有唯一约束性的关联关系可以通过该函数获取产生该关联的eventid,该类事件往往不知道具体的eventid，
# 例如将帖子添加到专辑，一般知道专辑id及帖子id，而不知道添加事件的id
#
# TODO 该函数一般在deleteAssociation之前使用，在deleteAssociation优化之后，不再需要
exports.getUniqueAssociation = (id, uid, sinkid, suid, action, callback) ->
  return false unless utils.validateId(id, callback)
  return false unless utils.validateUserId(uid, callback)
  return false unless utils.validateId(sinkid, callback)
  return false unless utils.validateUserId(suid, callback)

  logger.debug('Arguments:', id, uid, sinkid, suid)
  timer = utils.prologue(logger, 'getUniqueAssociation')
  action = utils.parseInt(action, 0)

  query = "SELECT CAST(T1.id AS CHAR) AS id, T1.user_id, app_id, action, status, text FROM `#{db}`.outbox AS T1 FORCE INDEX (PRIMARY), `#{db}`.association_constraint AS T2 FORCE INDEX (PRIMARY) WHERE T2.id=? AND T2.sink_id=? AND T2.type=? AND T1.id=T2.event_id"
  pool.execute(query, [id, sinkid, action], (err, command) ->
    result = null
    if err?
      logger.caught(err, "Failed to get user action", eventid, ownerid, userid, action)
      err = new Error('Failed to get user action')
    else
      result = {}
      for row in command.result.rows
        result = ({
        key: row.id,
        uid: row.user_id,
        appid: row.app_id,
        timestamp: uniqid.extractTimestamp(row.id),
        action: row.action,
        text: utils.binaryToString(row.text),
        status: row.status
        } for row in command.result.rows)
    utils.epilogue(logger, 'getUniqueAssociation', timer, callback, err, result)
  )

# 删除id和sinkid类型为type的关联
#
# TODO，unique类型的关联可以不需要eventid，
# TODO，在删除关联时应同时删除eventid事件
# TODO, temporary sulution，caller调用deleteAssociation后应手动调用deleteActivitiy删除
exports.deleteAssociation = (id, uid, sinkid, suid, eventid, euid, callback) ->
  return false unless utils.validateId(id, callback)
  return false unless utils.validateUserId(uid, callback)
  return false unless utils.validateId(sinkid, callback)
  return false unless utils.validateUserId(suid, callback)
  return false unless utils.validateId(eventid, callback)
  return false unless utils.validateUserId(euid, callback)

  timer = utils.prologue(logger, 'deleteAssociation')

  logger.debug('Arguments:', id, uid, sinkid, suid, eventid, euid)
  eventid = utils.normalizeId(eventid)

  params = []

  params.push(["SELECT action INTO @action FROM `#{db}`.outbox WHERE id=? AND user_id=? LOCK IN SHARE MODE", [eventid, euid], (result) ->
    return new Error('Activity not found') if result.affected_rows != 1
  ])
  params.push(["DELETE T1 FROM `#{db}`.association_constraint AS T1 WHERE T1.id=? AND T1.sink_id=? AND T1.type=@action", [id, sinkid]])
  params.push(["DELETE T1 FROM `#{db}`.association AS T1 WHERE T1.id=? AND T1.sink_id=? AND T1.type=@action AND T1.event_id=?", [id, sinkid, eventid]])
  params.push(["UPDATE `#{db}`.association_count AS T1 SET T1.count=T1.count-1 WHERE T1.id=? AND T1.sink_id=? AND T1.type=@action", [id, sinkid]])
  params.push(["DELETE FROM `#{db}`.association_count WHERE id=? AND sink_id=? AND type=@action AND count=0", [id, sinkid]])

  transaction = callback.transaction ? pool.transaction
  transaction(params, (err, commands) ->
    if err?
      logger.caught(err, 'Failed to delete association', id, uid, sinkid, suid, eventid, euid)
      err = new Error('Failed to delete association')
    else
      rows = 0
      if not err?
        for command in commands
          rows += command.result.affected_rows ? 0
    utils.epilogue(logger, 'deleteAssociation', timer, callback, err, rows)
  )

# targetid事件为id事件的父关系
# 即targetid是宿主
exports.addRelation = (id, userid, targetid, ownerid, unique = false, callback) ->
  return false unless utils.validateId(id, callback)
  return false unless utils.validateId(targetid, callback)
  return false unless utils.validateUserId(userid, callback)
  return false unless utils.validateUserId(ownerid, callback)

  timer = utils.prologue(logger, 'addRelation')

  logger.debug('Arguments:', id, userid, targetid, ownerid, unique)

  params = []

  params.push(["SELECT action INTO @action FROM `#{db}`.outbox WHERE id=? AND user_id=? LOCK IN SHARE MODE", [id, userid], (result) ->
    return new Error('Activity not found') if result.affected_rows != 1
  ])
  if unique
    # list it top to make it fail fast
    params.push(["INSERT INTO `#{db}`.relation_constraint(id, type, related_id, user_id) VALUES(?,@action,?,?)", [targetid, id, userid]])
  params.push(["INSERT INTO `#{db}`.relation_reverse(id, target_id, owner_id, type) VALUES(?,?,?,@action)", [id, targetid, ownerid]])
  params.push(["INSERT INTO `#{db}`.relation(id, type, related_id, user_id) VALUES(?,@action,?,?)", [targetid, id, userid]])
  params.push(["INSERT INTO `#{db}`.relation_count(id, type, count) VALUES(?,@action,1) ON DUPLICATE KEY UPDATE count=count+1", [targetid]])

  transaction = callback.transaction ? pool.transaction

  transaction(params, (err) ->
    if err?
      if err.num == 1062 # MySQL error code for key duplicate
        err = new Error('Entry already exists')
        err.duplicate = true
      else
        logger.caught(err, 'Failed to add relation', id, userid, targetid, ownerid, unique)
        err = new Error('Failed to add relation')
    utils.epilogue(logger, 'addRelation', timer, callback, err)
  )

# 将事件targetid从事件id的父关系移除
exports.deleteRelation = (id, userid, targetid, ownerid, callback) ->
  return false unless utils.validateId(id, callback)
  return false unless utils.validateUserId(userid, callback)
  return false unless utils.validateId(targetid, callback)
  return false unless utils.validateUserId(ownerid, callback)

  timer = utils.prologue(logger, 'deleteRelation')

  logger.debug('Arguments:', id, userid, targetid, ownerid)

  params = []

  params.push(["SELECT 1 FROM `#{db}`.outbox WHERE id=? AND user_id=? LOCK IN SHARE MODE", [id, userid], (result) ->
    return new Error('Activity not found') if result.rows.length != 1
  ])
  params.push(["DELETE T1 FROM `#{db}`.relation_constraint AS T1, `#{db}`.relation_reverse AS T2 WHERE T2.id=? AND T2.target_id=? AND T1.id=T2.target_id AND T1.user_id=? AND T1.type=T2.type AND T1.related_id=T2.id", [id, targetid, userid]])
  params.push(["DELETE T1 FROM `#{db}`.relation AS T1, `#{db}`.relation_reverse AS T2 WHERE T2.id=? AND T2.target_id=? AND T1.id=T2.target_id AND T1.type=T2.type AND T1.related_id=T2.id", [id, targetid]])
  params.push(["UPDATE `#{db}`.relation_count AS T1, `#{db}`.relation_reverse AS T2 SET T1.count=T1.count-1 WHERE T2.id=? AND T2.target_id=? AND T1.id=T2.target_id AND T1.type=T2.type", [id, targetid]])
  params.push(["DELETE T1 FROM `#{db}`.relation_count AS T1, `#{db}`.relation_reverse AS T2 WHERE T2.id=? AND T2.target_id=? AND T1.id=T2.target_id AND T1.type=T2.type AND T1.count=0", [id, targetid]])
  params.push(["DELETE FROM `#{db}`.relation_reverse WHERE id=? AND target_id=?", [id, targetid]])

  transaction = callback.transaction ? pool.transaction

  transaction(params, (err, commands) ->
    if err?
      logger.caught(err, 'Failed to delete relation', id, userid, targetid, ownerid)
      err = new Error('Failed to delete relation')
    else
      rows = 0
      if not err?
        for command in commands
          rows += command.result.affected_rows ? 0
    utils.epilogue(logger, 'deleteRelation', timer, callback, err, rows)
  )

# 将事件id的所有关系迁移到targetid
#FIXME we only migrate as if it's never a child node which is fine if we only migrate Product nodes, because the other Product must already has a Brand associated with it
exports.migrateRelation = (id, userid, targetid, ownerid, callback) ->
  return false unless utils.validateId(id, callback)
  return false unless utils.validateId(targetid, callback)
  return false unless utils.validateUserId(userid, callback)
  return false unless utils.validateUserId(ownerid, callback)

  timer = utils.prologue(logger, 'migrateRelation')

  logger.debug('Arguments:', id, userid, targetid, ownerid)

  params = []

  params.push(["SELECT 1 FROM `#{db}`.outbox WHERE id=? AND user_id=? FOR UPDATE", [id, userid], (result) ->
    return new Error('Activity not found') if result.rows.length != 1
  ])
  params.push(["SELECT action INTO @action FROM `#{db}`.outbox WHERE id=? AND user_id=? LOCK IN SHARE MODE", [targetid, ownerid], (result) ->
    return new Error('Activity not found') if result.affected_rows != 1
  ])
  params.push(["UPDATE IGNORE `#{db}`.relation_reverse AS T1, `#{db}`.relation AS T2 SET T1.target_id=?, T1.owner_id=? WHERE T2.id=? AND T1.id=T2.related_id AND T1.target_id=T2.id", [targetid, ownerid, id]])
  params.push(["UPDATE IGNORE `#{db}`.relation SET id=? WHERE id=?", [targetid, id]])
  params.push(["UPDATE IGNORE `#{db}`.relation_constraint SET id=? WHERE id=?", [targetid, id]])
  params.push(["INSERT INTO `#{db}`.relation_count(id, type, count) SELECT id, type, COUNT(related_id) AS count FROM `#{db}`.relation WHERE id=? GROUP BY type LOCK IN SHARE MODE ON DUPLICATE KEY UPDATE count=VALUES(count)", [targetid]])
  params.push(["UPDATE `#{db}`.name_lookup SET id=? WHERE id=?", [targetid, id]])
  params.push(["UPDATE `#{db}`.outbox SET status=status|0x80 WHERE id=? AND status&0x80=0", [id]])

  transaction = callback.transaction ? pool.transaction
  transaction(params, (err, commands) ->
    if err?
      logger.caught(err, 'Failed to merge relation', id, userid, targetid, ownerid)
      err = new Error('Failed to merge relation')
    else
      rows = 0
      if not err?
        for command in commands
          rows += utils.parseInt(command.result.affected_rows, 0)
      rows -= 1 # for SELECT action INTO @action ...
    utils.epilogue(logger, 'migrateRelation', timer, callback, err, rows)
  )

# 为事件id添加一组全局唯一名称names
exports.addName = (id, names, callback) ->
  return false unless utils.validateId(id, callback)
  return false unless utils.validateArray(names, 'names', callback)

  timer = utils.prologue(logger, 'addName')

  logger.debug('Arguments:', id, names)

  params = []

  for name in names when name? and name = name.toString().trim()
    params.push(["INSERT INTO `#{db}`.name_lookup(name, id) VALUES(?,?)", [name, id]])

  if params.length > 0
    pool.transaction(params, (err, commands) ->
      if err?
        if err.num == 1062 # MySQL error code for key duplicate
          err = new Error('Entry already exists')
          err.duplicate = true
        else
          logger.caught(err, 'Failed to add name', id, names)
          err = new Error('Failed to add name')
      utils.epilogue(logger, 'addName', timer, callback, err)
    )
  else
    utils.epilogue(logger, 'addName', timer, callback)

# 查找全局名称为name的事件
exports.lookupName = (name, callback) ->
  timer = utils.prologue(logger, 'lookupName')

  logger.debug('Arguments:', name)

  if not name? or not name = name.toString().trim()
    return utils.epilogue(logger, 'lookupName', timer, callback, new Error('Invalid name'))

  query = "SELECT CAST(T1.id AS CHAR) AS id, user_id, app_id, action, status, text, name FROM `#{db}`.outbox AS T1, `#{db}`.name_lookup AS T2 WHERE T2.name=? AND T1.id=T2.id"
  pool.execute(query, [name], (err, command) ->
    result = null
    if err?
      logger.caught(err, 'Failed to lookup name', name)
      err = new Error('Failed to lookup name')
    else
      result = ({
        key: row.id,
        uid: row.user_id,
        appid: row.app_id,
        timestamp: uniqid.extractTimestamp(row.id),
        action: row.action,
        text: utils.binaryToString(row.text),
        status: row.status,
        name: utils.binaryToString(row.name)
      } for row in command.result.rows)[0]
    utils.epilogue(logger, 'lookupName', timer, callback, err, result)
  )

erase = (userid, eventid, callback) ->
  # only needs to run within each region sharded by userid

  # 1. delete relation_reverse for each event in relation with id=eventid (shards for relation.user_id where relation.id=eventid)
  # 2. delete observation with event_id=eventid (shards for observation_delivery.observer_id where observation_delivery.event_id=eventid)
  # 3. delete relation & relation_constraint with related_id=eventid (shards for relation_reverse.owner_id where relation_reverse.id=eventid)
  # 4. decrease relation_count with id=relation_reverse.owner_id (shards for relation_reverse.owner_id where relation_reverse.id=eventid)
  # 5. delete relation & relation_constraint & relation_count with id=eventid (current shard)
  # 6. delete observation_delivery with event_id=eventid (current shard)
  # 7. delete outbox & relation_reverse with id=eventid (current shard)
  # 8. decrease outbox_count with user_id=outbox.user_id (current shard)

  # right now, observation_delivery and relation_reverse are not used for query due to no shards

  timer = utils.prologue(logger, 'erase')

  logger.debug('Arguments:', userid, eventid)

  params = []

  params.push(["DELETE FROM `#{db}`.name_lookup WHERE id=?", [eventid]])

  params.push(["DELETE T1 FROM `#{db}`.relation_reverse AS T1, `#{db}`.relation AS T2 WHERE T2.id=? AND T1.id=T2.related_id AND T1.target_id=T2.id", [eventid]])

  params.push(["DELETE FROM `#{db}`.observation WHERE event_id=?", [eventid]])

  params.push(["DELETE T1 FROM `#{db}`.relation AS T1, `#{db}`.relation_reverse AS T2 WHERE T2.id=? AND T1.id=T2.target_id AND T1.type=T2.type AND T1.related_id=T2.id", [eventid]])
  params.push(["DELETE T1 FROM `#{db}`.relation_constraint AS T1, `#{db}`.relation_reverse AS T2 WHERE T2.id=? AND T1.id=T2.target_id AND T1.user_id=? AND T1.type=T2.type AND T1.related_id=T2.id", [eventid, userid]])
  params.push(["UPDATE `#{db}`.relation_count AS T1, `#{db}`.relation_reverse AS T2 SET T1.count=T1.count-1 WHERE T2.id=? AND T1.id=T2.target_id AND T1.type=T2.type", [eventid]])
  params.push(["DELETE T1 FROM `#{db}`.relation_count AS T1, `#{db}`.relation_reverse AS T2 WHERE T2.id=? AND T1.id=T2.target_id AND T1.type=T2.type AND T1.count=0", [eventid]])

  params.push(["DELETE FROM `#{db}`.relation WHERE id=?", [eventid]])
  params.push(["DELETE FROM `#{db}`.relation_constraint WHERE id=?", [eventid]])
  params.push(["DELETE FROM `#{db}`.relation_count WHERE id=?", [eventid]])
  params.push(["DELETE FROM `#{db}`.observation_delivery WHERE event_id=?", [eventid]])
  params.push(["DELETE FROM `#{db}`.relation_reverse WHERE id=?", [eventid]])
  params.push(["UPDATE `#{db}`.outbox_count AS T1, `#{db}`.outbox AS T2 SET T1.count=T1.count-1 WHERE T2.id=? AND T1.user_id=T2.user_id AND T1.app_id=T2.app_id AND T1.action=T2.action", [eventid]])
  params.push(["DELETE T1 FROM `#{db}`.outbox_count AS T1, `#{db}`.outbox AS T2 WHERE T2.id=? AND T1.user_id=T2.user_id AND T1.app_id=T2.app_id AND T1.action=T2.action AND T1.count=0", [eventid]])
  params.push(["DELETE FROM `#{db}`.outbox WHERE id=?", [eventid]])

  pool.transaction(params, (err, commands) ->
    result = null
    if err?
      logger.caught(err, 'An error occurred while erasing')
    else
      result = (command.result.affected_rows for command in commands)
      logger.verbose('Erase result for %d:', eventid, result)
    utils.epilogue(logger, 'erase', timer, callback, err, result)
  )

# 删除用户userid创建的类型为action的事件eventid
exports.deleteActivity = (userid, eventid, action, callback) ->
  return false unless utils.validateUserId(userid, callback)
  return false unless utils.validateId(eventid, callback)

  timer = utils.prologue(logger, 'deleteActivity')

  logger.debug('Arguments:', userid, eventid, action)

  params = []

  params.push(["SELECT action INTO @action FROM `#{db}`.outbox WHERE id=? AND user_id=?#{if action? then ' AND action=?' else ''} AND status&0x80=0 FOR UPDATE", [eventid, userid, action], (result) ->
    if result.affected_rows != 1
      err = new Error('Activity not found')
      err.notfound = true
      return err
  ])

  params.push(["DELETE FROM `#{db}`.name_lookup WHERE id=?", [eventid]])
  params.push(["DELETE T1 FROM `#{db}`.relation_constraint AS T1, `#{db}`.relation_reverse AS T2 WHERE T2.id=? AND T1.id=T2.target_id AND T1.user_id=? AND T1.type=T2.type AND T1.related_id=T2.id", [eventid, userid]])
  params.push(["DELETE T1 FROM `#{db}`.relation AS T1, `#{db}`.relation_reverse AS T2 WHERE T2.id=? AND T1.id=T2.target_id AND T1.type=T2.type AND T1.related_id=T2.id", [eventid]])
  params.push(["UPDATE `#{db}`.relation_count AS T1, `#{db}`.relation_reverse AS T2 SET T1.count=T1.count-1 WHERE T2.id=? AND T1.id=T2.target_id AND T1.type=T2.type", [eventid]])
  params.push(["DELETE T1 FROM `#{db}`.relation_count AS T1, `#{db}`.relation_reverse AS T2 WHERE T2.id=? AND T1.id=T2.target_id AND T1.type=T2.type AND T1.count=0", [eventid]])
  params.push(["DELETE FROM `#{db}`.relation_reverse WHERE id=?", [eventid]])
  params.push(["UPDATE `#{db}`.outbox SET status=status|0x80 WHERE id=? AND status&0x80=0", [eventid]])

  transaction = callback.transaction ? pool.transaction
  transaction(params, (err, commands) ->
    if err? and not err.notfound
      logger.caught(err, 'Failed to delete activity %d for user %d', eventid, userid)
      err = new Error('Failed to delete activity')
    else
      err = null
      rows = 0
      for command in (commands ? [])
        rows += command.result.affected_rows ? 0
    utils.epilogue(logger, 'deleteActivity', timer, callback, err, rows)
  )

# 删除用户userid对事件eventid所做的类型为action的约束性操作，比如删除用户X对贴子A的喜欢操作
#
# deleteUserAction不需要activity的id，所以只能删约束类型的activity，比如喜欢和求链接之类的
# deleteUserAction是一个helper，先拿到activityid的话也可以用deleteActivity
exports.deleteUserAction = (userid, targetid, ownerid, action, callback) ->
  return false unless utils.validateId(targetid, callback)
  return false unless utils.validateUserId(ownerid, callback)
  return false unless utils.validateUserId(userid, callback)

  logger.debug('Arguments:', userid, targetid, ownerid, action)

  timer = utils.prologue(logger, 'deleteUserAction')

  action = utils.parseInt(action, 0)

  params = []

  params.push(["SELECT T1.id INTO @id FROM `#{db}`.outbox AS T1, `#{db}`.relation_constraint AS T2 WHERE T2.id=? AND T2.user_id=? AND T2.type=? AND T1.id=T2.related_id AND T1.status&0x80=0 FOR UPDATE", [targetid, userid, action], (result) ->
    if result.affected_rows != 1
      err = new Error('Activity not found')
      err.notfound = true
      return err
  ])
  params.push(["UPDATE `#{db}`.outbox SET status=status|0x80 WHERE id=@id"])
  params.push(["UPDATE `#{db}`.relation_count AS T1, `#{db}`.relation_constraint AS T2 SET T1.count=T1.count-1 WHERE T2.id=? AND T2.user_id=? AND T2.type=? AND T1.id=T2.id AND T1.type=T2.type", [targetid, userid, action]])
  params.push(["DELETE T1 FROM `#{db}`.relation_count AS T1, `#{db}`.relation_constraint AS T2 WHERE T2.id=? AND T2.user_id=? AND T2.type=? AND T1.id=T2.id AND T1.type=T2.type AND T1.count=0", [targetid, userid, action]])
  params.push(["DELETE T1, T2, T3 FROM `#{db}`.relation AS T1, `#{db}`.relation_constraint AS T2, `#{db}`.relation_reverse AS T3 WHERE T2.id=? AND T2.user_id=? AND T2.type=? AND T1.id=T2.id AND T1.type=T2.type AND T1.related_id=T2.related_id AND T3.id=T2.related_id AND T3.target_id=T2.id", [targetid, userid, action]])

  transaction = callback.transaction ? pool.transaction
  pool.transaction(params, (err, commands) ->
    if err?
      logger.caught(err, 'Failed to delete user action', userid, targetid, ownerid, action)
      err = new Error('Failed to delete user action')
    else
      rows = 0
      for command in commands
        rows += command.result.affected_rows ? 0
    utils.epilogue(logger, 'deleteUserAction', timer, callback, err, rows)
  )

# 删除标记为待删除的事件，count用于指定一次至多删除count条记录，concurrency用于指定可以concurrency条同时进行，请始终填1，cancel为用于取消的回调函数，返回非0值表示取消
exports.cleanup = (count, concurrency, cancel, callback) ->
  timer = utils.prologue(logger, 'cleanup')

  logger.debug('Arguments:', count, concurrency)

  count = utils.parseInt(count, 100, 1)
  concurrency = utils.parseInt(concurrency, 10, 1, count)

  finished = false
  processed = 0

  async.doWhilst(
    (cb) ->
      pool.execute("SELECT CAST(id AS CHAR) AS id, user_id, app_id, action, text FROM `#{db}`.outbox FORCE INDEX(status) WHERE status>=0x80 LIMIT ?", [count - processed], (err, command) ->
        return cb(err) if err?
        result = command.result.rows
        finished = true if result.length == 0
        async.eachLimit(result, concurrency, (item, next) ->
          return next(new Error('Cancelled')) if cancel?()
          # Record all actually deleted rows, especially for Photo/CDN cleanup
          recorder.record(item.id, item.user_id, item.app_id, item.action, utils.binaryToString(item.text))
          erase(item.user_id, item.id, (err) ->
            processed++ if not err?
            next(err)
          )
        , cb)
      )
    -> not finished and processed < count
    (err) ->
      # return original error due to cleanup is of internal use only
      logger.caught(err, 'Error occurred while cleaning up') if err?
      utils.epilogue(logger, 'cleanup', timer, callback, err, processed)
  )

# 检查since到till时间范围内的数据库完整性
exports.sanitize = (since = 0, till = 0, callback) ->
  timer = utils.prologue(logger, 'sanitize')

  logger.debug('Arguments:', since, till)

  since = utils.parseInt(since, 0, 0)
  till = utils.parseInt(till, 0, 0)

  till = utils.timestamp() if till == 0

  start = uniqid.fromTimestamp(since)
  end = uniqid.fromTimestamp(till)

  pool.execute("SELECT CAST(T1.id AS CHAR) as id FROM `#{db}`.relation_reverse AS T1 FORCE INDEX (PRIMARY) LEFT OUTER JOIN `#{db}`.outbox AS T2 FORCE INDEX (PRIMARY) ON T2.id = T1.target_id WHERE T1.id>? AND T1.id<=? AND T2.id IS NULL", [start, end], (err, command) ->
    if err?
      logger.caught(err, 'Error occurred while scanning')
      err = new Error('Error occurred while scanning')
      utils.epilogue(logger, 'sanitize', timer, callback, err)
    else
      idlist = (row.id for row in command.result.rows)
      if idlist.length == 0
        utils.epilogue(logger, 'sanitize', timer, callback, null, 0)
      else
        pool.execute("UPDATE `#{db}`.outbox SET status=status|0x80 WHERE id IN (?#{Array(idlist.length).join(',?')}) AND status&0x80=0", idlist, (err, command) ->
          if err?
            logger.caught(err, 'Error occurred while sanitizing')
            err = new Error('Error occurred while sanitizing')
          utils.epilogue(logger, 'sanitize', timer, callback, err, command.result.affected_rows)
        )
  )

# 标记某一用户userid在appid下特定通知为已读，filter用于指定类别或事件id，useType指定filter是类别还是id
exports.markAsRead = (userid, appid, filter = [], useType = true, callback) ->
  return false unless utils.validateUserId(userid, callback)
  return false unless utils.validateArray(filter, 'filter', callback)

  timer = utils.prologue(logger, 'markAsRead')

  logger.debug('Arguments:', userid, appid, filter, useType)

  appid = utils.parseInt(appid, 0, 0)

  query = "UPDATE `#{db}`.observation SET unread=0 WHERE observer_id=? AND app_id=? AND unread=1 "
  params = [userid, appid]
  if filter.length > 0
    field = if useType then 'type' else 'event_id'
    query += "AND #{field} IN (?#{Array(filter.length).join(',?')})"
    Array.prototype.push.apply(params, filter)

  pool.execute(query, params, (err, command) ->
    rows = null
    if err?
      logger.caught(err, "Failed to mark observation as read for user %d appid %d with #{field}", userid, appid, filter)
      err = new Error('Failed to mark observation as read')
    else
      rows = command.result.affected_rows
    utils.epilogue(logger, 'markAsRead', timer, callback, err, rows)
  )

# 删除某一用户userid关于事件eventid的通知，不影响eventid给其他用户的通知
exports.removeObservation = (userid, eventid, callback) ->
  return false unless utils.validateUserId(userid, callback)
  return false unless utils.validateId(eventid, callback)

  timer = utils.prologue(logger, 'removeObservation')

  logger.debug('Arguments:', userid, eventid)

  params = [
    ["DELETE FROM `#{db}`.observation WHERE observer_id=? AND event_id=?", [userid, eventid]],
    ["DELETE FROM `#{db}`.observation_delivery WHERE event_id=? AND observer_id=?", [eventid, userid]]
  ]

  pool.transaction(params, (err, commands) ->
    rows = null
    if err?
      logger.caught(err, 'Failed to remove observation %d for user', eventid, userid)
      err = new Error('Failed to remove observation')
    else
      rows = 0
      for command in commands
        rows += command.result.affected_rows ? 0
    utils.epilogue(logger, 'removeObservation', timer, callback, err, rows)
  )

# 添加一条commit log，仅和txmgr联合使用才有意义
exports.transactionLog = (verb, id, userid, appid, type, extra, data, callback) ->
  globalid = uniqid.generate()

  if not callback?
    callback = data
    data = {}

  data = utils.extend(data, {
    verb: verb,
    timestamp: utils.timestamp(),
    id: id,
    userid: userid,
    appid: appid,
    type: type,
    extra: extra,
  }, true)

  logger.debug('Arguments:', globalid, data)

  params = [["INSERT INTO `#{db}`.transaction_log(global_id,data) VALUES(?,?)", [globalid, utils.stringToBinary(JSON.stringify(data))]]]

  callback.transaction(params)

# 枚举所有的activity，目前用于批量维护数据库json的值
# 一般情况下不使用该接口
exports.enumerateActivity = (appid, callback) ->
  timer = utils.prologue(logger, 'enumerateActivity')

  logger.debug('Arguments:', appid)

  appid = utils.parseInt(appid, 0, 0)

  query = "SELECT CAST(id AS CHAR) AS id, user_id, app_id, action, status, text FROM `#{db}`.outbox FORCE INDEX (PRIMARY)"
  params = [appid]

  pool.execute(query, params, (err, command) ->
    if err?
      logger.caught(err, 'Failed to enumerate activity')
      err = new Error('Failed to enumerate activity')
    else
      result = command.result.rows
    utils.epilogue(logger, 'enumerateActivity', timer, callback, err, result)
  )
