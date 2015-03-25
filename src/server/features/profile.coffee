async = require('async')

config = require('../utils/config')
logger = require('../utils/log').getLogger('PROFILE')
utils = require('../utils/routines')

checker = require('./checker')
format = require('./format')

user = require('../cores/user')

User = require('../models/User')

defaultPublicFields = {}

config.setModuleDefaults('Profile', {
  defaultPublicFields: defaultPublicFields
})


module.exports = (self, userid, callback) ->
  return false unless utils.validateUserId(userid, callback)

  timer = utils.prologue(logger, 'profile')

  if self - userid == 0
    user.getExtendedProfiles([self], 1, false, (err, profiles) ->
      if err?
        logger.caught(err, 'Failed to query profile', self)
        err = new Error('Failed to query profile')
        err.tryagain = true
      else
        if profiles.length == 0
          err = new Error('No such user')
          err.notfound = true
        else
          profile = profiles[0]
          result = format({
            people: format.user([profile]),
            photos: format.objectify(format.photo([], [profile]), 'key')
          })
      utils.epilogue(logger, 'profile', timer, callback, err, result)
    )
  else
    full(self, false, [userid], (err, profiles) ->
      if err?
        err.tryagain = true
      else
        if profiles.length == 0
          err = new Error('No such user')
          err.notfound = true
        else
          result = format({
            people: profiles,
            photos: format.objectify(format.photo([], profiles), 'key')
          })
      utils.epilogue(logger, 'profile', timer, callback, err, result)
    )

isFriend = (self, idlist, callback) ->
  if self == 0
    callback(null, [], [], [])
  else
    follow.isFriend(self, 1, false, idlist, callback)

# 获取用户基本信息
module.exports.basic = exports.basic = (idlist, stable = false, callback) ->
  timer = utils.prologue(logger, 'basic')
  async.waterfall([
    async.apply(user.getProfiles, idlist, stable),
    async.apply((list, cb) -> cb(null, format.user(list)))
  ], (err, result) ->
    if err?
      logger.caught(err, 'Failed to query basic profile', idlist)
      err = new Error('Failed to query basic profile')
    utils.epilogue(logger, 'basic', timer, callback, err, result)
  )

# 获取basic()的基本信息及关注关系
module.exports.plentiful = exports.plentiful = (self, idlist, stable = false, callback) ->
  self = utils.normalizeUserId(self) ? 0
  timer = utils.prologue(logger, 'plentiful')
  async.waterfall([
    async.apply(async.parallel, {
      user: async.apply(user.getProfiles, idlist, stable),
      friend: async.apply(isFriend, self, idlist),
    }),
    async.apply((result, cb) ->
      cb(null, format.user(
        result.user,
        publicFields,
        format.objectify(result.friend[1]),
        format.objectify(result.friend[2]),
        format.objectify(result.friend[0])
      ))
    )
  ], (err, users) ->
    if err?
      logger.caught(err, 'Failed to query pentiful profile', idlist)
      err = new Error('Failed to query pentiful profile')
    utils.epilogue(logger, 'plentiful', timer, callback, err, users)
  )

module.exports.full= exports.full = full = (self, stable = false, idlist, callback) ->
  timer = utils.prologue(logger, 'full')

  self = utils.normalizeUserId(self) ? 0

  async.waterfall([
    async.apply(async.parallel, {
      user: async.apply(user.getExtendedProfiles, idlist, 1, stable),
      friend: async.apply(isFriend, self, idlist),
      # 返回的结果不再包含chop_count
    }),
    async.apply((result, cb) ->
      cb(null, format.user(
        result.user,
        publicFields,
        format.objectify(result.friend[1]),
        format.objectify(result.friend[2]),
        format.objectify(result.friend[0]),
        result.friendCount,
        result.activityCount
      ))
    )
  ], (err, result) ->
    if err?
      logger.caught(err, 'Failed to query full profile', idlist)
      err = new Error('Failed to query full profile')
    utils.epilogue(logger, 'full', timer, callback, err, result)
  )

module.exports.update = exports.update = (self, data = null, callback) ->
  logger.debug('Arguments:', self, data)
  return unless self = utils.normalizeUserId(self, callback)
  return callback(null, format({ success: true })) unless data

  timer = utils.prologue(logger, 'update')

  nick = data.nickname
  icon = data.icon
  privacy = data.privacy

  delete data.nickname
  delete data.icon
  delete data.privacy

  if nick? and not checker.validateNickname(nick)
    return utils.epilogue(logger, 'update', timer, callback, new Error('Invalid nickname'))

  if icon? and (typeof icon != 'string' or icon.indexOf(self + '/') != 0)
    return utils.epilogue(logger, 'update', timer, callback, new Error('Invalid icon'))

  # TODO check icon against Redis
  # in future we may want to present user their icon album, so don't delete from Cloud

  async.waterfall([
      async.apply((cb) ->
        return cb(null, true) unless nick? or icon?
        user.updateProfile(self, nick, icon, cb)
      ),
      async.apply((success, cb) ->
        if not success
          err = new Error("Failed to update nick/icon")
          err.tryagain = true
          cb(err)
        user.getExtendedProfiles([self], 1, false, cb)
      ),
      async.apply((profiles, cb) ->
        if profiles.length == 0
          err = new Error("User not found", self)
          err.notfound = true
          return cb(err)

        profile = profiles[0]
        oldData = JSON.parse(profile.data ? null) ? {}
        oldPrivacy = JSON.parse(profile.privacy ? null) ? {}

        if Object.keys(data).length == 0 and (not privacy or Object.keys(privacy).length == 0)
          # data fields not changed.
          return cb(null, true, profile, oldData, oldPrivacy)

        if Object.keys(data).length > 0
          try
            data = utils.extend(oldData, data, true)
          catch err
            logger.warn(err, profile)
        else
          data = null
        if privacy and Object.keys(privacy).length > 0
          try
            privacy = utils.extend(oldPrivacy, privacy, true)
          catch err
            logger.warn(err, profile)
        else
          privacy = null

        dataStr = JSON.stringify(data) if data?
        privacyStr = JSON.stringify(privacy) if privacy?
        user.updateProfileData(self, 1, dataStr, privacyStr, (err, success) ->
          if err?
            logger.caught(err, "Failed to update profile data")
          cb(err, success, profile, data ? oldData, privacy ? oldPrivacy)
        )
      ),
      # the data after updated.
      async.apply((success, profile, data, privacy, cb) ->
        tx = txManager()
        activity.transactionLog('update', null, self, 1, 'user', {
          nickname: profile.nick,
          handle: if profile.source == 1 then profile.handle else undefined,
          source: profile.source,
          introduction: data?.introduction ? undefined
        }, tx())
        tx.commit((err) ->
          if err?
            logger.caught(err, 'Failed to add transaction log profile update', self, nick, icon)
          cb(null, success)
        )
      )
    ], (err, success) ->
    if err?
      logger.caught(err, 'Failed to update profile data')
      if not err.duplicate and not err.notfound
        err.tryagain = true
    else
      result = format({ success: true })
    utils.epilogue(logger, 'update', timer, callback, err, result)
  )

module.exports.shareApp = exports.shareApp = (self, callback) ->
  logger.debug('Arguments:', self)
  return unless self = utils.normalizeUserId(self, callback) if self

  timer = utils.prologue(logger, 'shareApp')
  result =recorder.record(self, new Date())

  result = format
    share_title: "我是lookmook, ^_^"
    share_content: shareContent
    share_wb_content: "@lookmook官微"
    share_url: officialSite

  utils.epilogue(logger, 'shareApp', timer, callback, null, result)

module.exports.blacklist = exports.blacklist = (count, offset, context = {}, callback) ->
  logger.debug('Arguments:', count, offset, context)
  count = checker.normalizeCount(count)
  offset = checker.normalizeOffset(offset)

  timer = utils.prologue(logger, 'blacklist')

  async.waterfall([
    async.apply (cb1) ->
      User.find({isWanted: true}, (err, users) ->
        uidList = null
        uidList = users.map((user) -> return user._id)
        cb1(err, uidList)
      )
    async.apply((uidList, cb1) ->
      async.parallel({
        blacklistCount: async.apply(User.count.bind(User, {isWanted: true}))
        blacklistCommentsCount: async.apply(Reply.count.bind(Reply, {owner: {$in: uidList}, status: 0}))
        userTimeLine: (cb2) ->
          Reply.find({owner: {$in: uidList}, status: 0}).skip(offset).limit(count).exec(cb2)
      }, cb1)
    )
  ], (err, result) ->
    if err?
      logger.error('Get blacklist failed')

    result = format
      success: not err?
      result: result if not err?
    utils.epilogue(logger, 'blacklist', timer, callback, null, result)
  )