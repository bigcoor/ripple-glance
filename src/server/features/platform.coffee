_ = require('underscore')
async = require('async')

userCore = require('../cores/user')
logger = require('../utils/log').getLogger('PLATFORM')
utils = require('../utils/routines')

User = require('../models/User')

exports.updateWeiboInfo = (openid, userid, tokens, isShare, callback) ->
  timer = utils.prologue(logger, 'updateWeiboInfo')
  if _.isArray(tokens) and tokens.length == 1
    token = tokens[0]
  else if tokens?
    token = tokens
  else
    error = new Error("No tokens support to update user weibo info.")
    logger.error(error)
    return utils.epilogue(logger, 'updateWeiboInfo', timer, callback, error, null)

  async.waterfall([
    async.apply (cb) ->
      User.findById(userid, (err, user) ->
        if err?
          logger.error("Find a user's weibo info fail: #{err}")
        cb(err, user)
      )
    async.apply (user, cb) ->
      #TODO 检验token是否有效
      if user?
        if isShare
          user.weiboShareId = openid
          user.weiboShareToken = token
          user.weiboAccessToken = token if user.weiboOpenId == openid
        else
          user.weiboOpenId = openid
          user.weiboAccessToken = token

        user.save(cb)
      else
        if isShare
          doc =
            _id: userid
            weiboShareId: openid
            weiboShareToken: token
        else
          doc =
            _id: userid
            weiboOpenId: openid
            weiboAccessToken: token
        #TODO migration之后删除
        User.create(doc, cb)
  ], (err, result) ->
    if err?
      logger.error("Update user weibo info fail: #{err}")
    utils.epilogue(logger, 'updateWeiboInfo', timer, callback, err, result)
  )