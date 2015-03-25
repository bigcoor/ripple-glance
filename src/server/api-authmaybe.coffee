# All Error fields visibble to this file are documented here
# Error Field - HTTP Status Code
# created      - 201
# unauthorized - 401
# nothuman     - 402
# notfound     - 404
# duplicate    - 409
# tryagain     - 500

activitystream = require('./features/activitystream')
albumlet = require('./features/albumlet')
arenalet = require('./features/arenalet')
auth = require('./features/auth')
baglet = require('./features/baglet')
blinklet = require('./features/blinklet')
choplet =  require('./features/choplet')
entity = require('./features/entity')
feedback = require('./features/feedback')
friend = require('./features/friend')
labellet = require('./features/labellet')
membership = require('./features/membership')
profile = require('./features/profile')
stickerlet = require('./features/stickerlet')
topiclet = require('./features/topiclet')
timeline = require('./features/timeline')
statistics = require('./features/statistics')
notification = require('./features/notification')
channelLet = require './features/channellet'
replyLet = require './features/replylet'
postLet = require './features/postlet'
likeLet = require './features/likelet'
salonLet = require './features/salonlet'

utils = require('./utils/routines')

#TODO 把channel过滤整合到middleware
_ = require('underscore')
config = require('./utils/config')
logger = require('./utils/log').getLogger('AUTHMAYBE-API')

boolFilter = config['Approach'].boolFilter
versionExclude = config['Approach'].versionExclude
postConservator = config['Admin'].postConservator

authenticate = (trust) ->
  return (req, res, next) ->
    return next() if trust
    uid = req.header('uid')
    token = req.header('token')
    limit = req.query.limit
    req.query.limit = utils.parseInt(limit, undefined, 0, 100) if limit?
    auth.validateSession(uid, token, (err, newToken) ->
      if err?
        req.headers['uid'] = 0
      else
        res.once('header', -> res.setHeader('sessionToken', newToken))
      next()
    )

_channelFilter = (context, result) ->
  if utils.channelFilter(context, boolFilter, versionExclude)
    result = _.extend(result, {channel: true}) if _.isObject(result)

module.exports = (app, trust = false) ->
  # 全站最新
  app.get('/api/activitystream/latest', authenticate(trust), (req, res) ->
    uid = req.header('uid')
    version = req.header('version')
    channel = req.header('channel')
    after = req.query.after
    count = req.query.limit
    # 屏幕分配率
    screenHeight = req.header('height')
    screenWidth = req.header('width')

    context = {version: version, channel: channel, height: screenHeight, width: screenWidth}

    postLet.latest(uid, count, after, context, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # 全站动态
  app.get('/api/activitystream/dynamics', authenticate(trust), (req, res) ->
    uid = req.header('uid')
    version = req.header('version')
    channel = req.header('channel')
    count = req.query.limit
    offset = req.query.offset

    context = {version: version, channel: channel}

    activitystream.dynamics(uid, count, offset, context, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # 全站日志
  app.get('/api/activitystream/activitylog', authenticate(trust), (req, res) ->
    start = req.query.after
    count = req.query.limit
    before = req.query.before
    offset = req.query.offset

    backwards = false

    if start? and before?
      return res.send(400)

    if before?
      start = before
      backwards = true

    activitystream.activityLog(count, start, backwards, offset, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  app.get('/api/activitystream/featured', authenticate(trust), (req, res) ->
    uid = req.header('uid')
    version = req.header('version')
    channel = req.header('channel')
    count = req.query.limit
    after = req.query.after
    # 屏幕分配率
    screenHeight = req.header('height')
    screenWidth = req.header('width')

    context = {version: version, channel: channel, height: screenHeight, width: screenWidth}

    postLet.listFeaturedPosts(uid, count, after, context, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # 个人原创的帖子
  app.get('/api/timelines/:userId/posts', authenticate(trust), (req, res) ->
    self = req.header('uid')
    version = req.header('version')
    channel = req.header('channel')
    # 屏幕分配率
    screenHeight = req.header('height')
    screenWidth = req.header('width')
    owner = req.params.userId
    after = req.query.after
    count = req.query.limit

    context = {version: version, channel: channel, height: screenHeight, width: screenWidth}

    postLet.personalPosts(self, owner, count, after, context, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # 个人原创的帖子的个数
  app.get('/api/timelines/:userId/posts/count', authenticate(trust), (req, res) ->
    self = req.header('uid')
    userId = req.params.userId
    # 屏幕分配率
    screenHeight = req.header('height')
    screenWidth = req.header('width')

    context = {height: screenHeight, width: screenWidth}

    postLet.postCount(self, userId, context, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  app.get('/api/posts/stream/label', authenticate(trust), (req, res) ->
    uid = req.header('uid')
    version = req.header('version')
    channel = req.header('channel')
    after = req.query.after
    count = req.query.limit
    label = req.query.label

    if not label?
      return res.send(400)

    context = {version: version, channel: channel}

    labellet.searchPostsByLabel(uid, label, count, after, context, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # 获取帖子详细信息，其中包括回帖个数，登录后还返回是否已喜欢、是否已求链接、是否已给过链接
  app.get('/api/posts/:postid', authenticate(trust), (req, res) ->
    self = req.header('uid')
    version = req.header('version')
    channel = req.header('channel')
    pid = req.params.postid
    owner = req.query.owner
    # 屏幕分配率
    screenHeight = req.header('height')
    screenWidth = req.header('width')

    context = {version: version, channel: channel, height: screenHeight, width: screenWidth}

    postLet.post(self, pid, owner, context, (err, result) ->
      if err?
        if err.notfound
          res.send(404)
        else if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # 获取一个帖子的回复列表
  app.get('/api/posts/:postid/replies', authenticate(trust), (req, res) ->
    version = req.header('version')
    channel = req.header('channel')
    postid = req.params.postid
    ownerid = req.query.owner

    after = req.query.after
    count = req.query.limit

    context = {version: version, channel: channel}

    replyLet.replies(postid, ownerid, count, after, context, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # 获取一个帖子的回复个数
  app.get('/api/posts/:postid/replies/count', authenticate(trust), (req, res) ->
    postid = req.params.postid
    ownerid = req.query.owner

    replyLet.replyCount(postid, ownerid, {}, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # 获取一个帖子的喜欢的人的列表
  app.get('/api/posts/:postid/likes', authenticate(trust), (req, res) ->
    postid = req.params.postid
    ownerid = req.query.owner

    start = req.query.after
    count = req.query.limit

    context = {}

    likeLet.likes(postid, ownerid, count, start, context, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # 获取一个帖子的喜欢的人的个数
  app.get('/api/posts/:postid/likes/count', authenticate(trust), (req, res) ->
    postid = req.params.postid
    ownerid = req.query.owner

    entity.count(postid, ownerid, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # 获取一个帖子的求链接的人的列表
  app.get('/api/posts/:postid/requests', authenticate(trust), (req, res) ->
    postid = req.params.postid
    ownerid = req.query.owner

    start = req.query.after
    count = req.query.limit
    before = req.query.before
    offset = req.query.offset

    backwards = false

    if start? and before?
      return res.send(400)

    if before?
      start = before
      backwards = true

    entity.requests(postid, ownerid, count, start, backwards, offset, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # 获取一个帖子的求链接的人的个数
  app.get('/api/posts/:postid/requests/count', authenticate(trust), (req, res) ->
    postid = req.params.postid
    ownerid = req.query.owner

    entity.count(postid, ownerid, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # 获取求链接内容
  app.get('/api/posts/:postid/requests/my', authenticate(trust), (req, res) ->
    uid = req.header('uid')
    postid = req.params.postid
    ownerid = req.query.owner

    entity.request(uid, postid, ownerid, (err, result) ->
      if err?
        if err.notfound
          res.send(404)
        else if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # 获取链接、商品属性等等
  app.get('/api/posts/:postid/responses', authenticate(trust), (req, res) ->
    postid = req.params.postid
    ownerid = req.query.owner

    entity.response(postid, ownerid, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # 好友列表
  app.get('/api/friends/:userid', authenticate(trust), (req, res) ->
    self = req.header('uid')
    userid = req.params.userid

    start = req.query.after
    count = req.query.limit
    offset = req.query.offset

    friend.friends(self, userid, count, start, offset, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # 好友人数
  app.get('/api/friends/:userid/count', authenticate(trust), (req, res) ->
    userid = req.params.userid

    friend.friendCount(userid, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # 关注列表
  app.get('/api/friends/:userid/following', authenticate(trust), (req, res) ->
    self = req.header('uid')
    userid = req.params.userid

    start = req.query.after
    count = req.query.limit
    before = req.query.before
    offset = req.query.offset

    backwards = false

    if start? and before?
      return res.send(400)

    if before?
      start = before
      backwards = true

    friend.followings(self, userid, count, start, backwards, offset, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # 关注人数
  app.get('/api/friends/:userid/following/count', authenticate(trust), (req, res) ->
    userid = req.params.userid

    friend.followCount(userid, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # 粉丝列表
  app.get('/api/friends/:userid/followers', authenticate(trust), (req, res) ->
    self = req.header('uid')
    userid = req.params.userid

    start = req.query.after
    count = req.query.limit
    before = req.query.before
    offset = req.query.offset

    backwards = false

    if start? and before?
      return res.send(400)

    if before?
      start = before
      backwards = true

    friend.followers(self, userid, count, start, backwards, offset, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # 粉丝人数
  app.get('/api/friends/:userid/followers/count', authenticate(trust), (req, res) ->
    userid = req.params.userid

    friend.followCount(userid, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # 关注列表是否更新
  app.get('/api/friends/:userid/following/ispost', authenticate(trust), (req, res) ->
    userid = req.params.userid

    friend.followingIsPost(userid, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # 更新用户刷新首页关注列表的时间
  app.put('/api/friends/:userid/following/refresh', authenticate(trust), (req, res) ->
    userid = req.params.userid

    friend.followingRefresh(userid, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  app.get('/accounts/search', authenticate(trust), (req, res) ->
    self = req.header('uid')
    query = req.query.query
    membership.searchUser(self, query, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # 个人 profile
  app.get('/api/profiles/:userid', authenticate(trust), (req, res) ->
    self = req.header('uid')
    userid = req.params.userid

    self = 0 if self - userid == 0

    profile(self, userid, (err, result) ->
      if err?
        if err.notfound
          res.send(404)
        else if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  app.get('/api/membership/latest', authenticate(trust), (req, res) ->
    uid = req.header('uid')
    count = req.query.limit
    offset = req.query.offset

    membership.latest(uid, count, offset, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  app.get('/api/brands', authenticate(trust), (req, res) ->
    entity.listBrand((err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  app.get('/api/brands/featured', authenticate(trust), (req, res) ->
    entity.listFeaturedBrand((err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  app.get('/api/brands/:id', authenticate(trust), (req, res) ->
    brandids = req.params.id.split(',')

    entity.getBrand(brandids, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        if result.brands.length == 0
          res.send(404)
        else
          res.json(result)
    )
  )

  app.get('/api/brands/:id/models', authenticate(trust), (req, res) ->
    brandid = req.params.id

    start = req.query.after
    count = req.query.limit
    offset = req.query.offset

    entity.listModel(brandid, count, start, offset, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  app.get('/api/brands/:id/models/:model', authenticate(trust), (req, res) ->
    brandid = req.params.id
    model = req.params.model

    entity.queryModel(brandid, model, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else if err.notfound
          res.send(404)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  app.get('/api/models/:id', authenticate(trust), (req, res) ->
    modelids = req.params.id.split(',')

    entity.getModel(modelids, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        if result.models.length == 0
          res.send(404)
        else
          res.json(result)
    )
  )

  app.get('/api/brands/:id/commodities', authenticate(trust), (req, res) ->
    brandid = req.params.id

    start = req.query.after
    count = req.query.limit
    offset = req.query.offset

    entity.listCommodity(brandid, count, start, offset, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  app.get('/api/models/:id/commodities', authenticate(trust), (req, res) ->
    modelid = req.params.id

    start = req.query.after
    count = req.query.limit
    offset = req.query.offset

    entity.listCommodity(modelid, count, start, offset, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  app.get('/api/commodities/:id', authenticate(trust), (req, res) ->
    ids = req.params.id.split(',')

    entity.getCommodity(ids, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        if result.commodities.length == 0
          res.send(404)
        else
          res.json(result)
    )
  )

  app.get('/api/brands/:id/posts', authenticate(trust), (req, res) ->
    uid = req.header('uid')
    version = req.header('version')
    channel = req.header('channel')
    brandid = req.params.id

    start = req.query.after
    count = req.query.limit
    offset = req.query.offset
    sort = req.query.sort

    context = {version: version, channel: channel}

    cb = (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)

    if sort == 'reply'
      return res.send(400) if start?
      entity.listPostByLatestReply(uid, brandid, count, offset, context, cb)
    else
      entity.listPost(uid, brandid, count, start, offset, context, cb)
  )

  app.get('/api/models/:id/posts', authenticate(trust), (req, res) ->
    uid = req.header('uid')
    modelid = req.params.id

    start = req.query.after
    count = req.query.limit
    offset = req.query.offset
    sort = req.query.sort

    cb = (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)

    if sort == 'reply'
      return res.send(400) if start?
      entity.listPostByLatestReply(uid, modelid, count, offset, cb)
    else
      entity.listPost(uid, modelid, count, start, offset, cb)
  )

  app.get('/api/posters/:id', authenticate(trust), (req, res) ->
    posterids = req.params.id.split(',')

    entity.getPoster(posterids, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        if result.posters.length == 0
          res.send(404)
        else
          res.json(result)
    )
  )
  app.get('/api/chops/search', authenticate(trust), (req, res) ->
    self = req.header('uid')
    query = req.query.query

    choplet.searchChop(self, query, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  app.get('/api/chops/suggest/typing', authenticate(trust), (req, res) ->
    input = req.query.input
    choplet.suggestChop(input, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  app.get('/api/chops/:chopid/followers', authenticate(trust), (req, res) ->
    self = req.header('uid')
    chopid = req.params.chopid
    count = req.query.limit
    offset = req.query.offset

    choplet.listChopFollowers(self, chopid, count, offset, (err, result) ->
      if err?
        if err.notfound
          res.send(404)
        else if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )


  app.get('/api/chops/:chopid', authenticate(trust), (req, res) ->
    self = req.header('uid')
    chopid = req.params.chopid

    choplet.getChop(self, chopid, (err, result) ->
      if err?
        if err.notfound
          res.send(404)
        else if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # 个人原创的帖子的个数
  app.get('/api/chops/:userid/following/count', authenticate(trust), (req, res) ->
    userid = req.params.userid

    choplet.chopFollowCount(userid, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # 获取关注品牌列表
  app.get('/api/chops/:userid/following', authenticate(trust), (req, res) ->
    self = req.header('uid')
    userid = req.params.userid

    start = req.query.after
    count = req.query.limit
    before = req.query.before
    offset = req.query.offset

    backwards = false

    if start? and before?
      return res.send(400)

    if before?
      start = before
      backwards = true

    choplet.listFollowChops(self, userid, count, start, backwards, offset, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  app.get('/api/chops/:chopid/posts', authenticate(trust), (req, res) ->
    self = req.header('uid')
    version = req.header('version')
    channel = req.header('channel')
    chopid = req.params.chopid
    count = req.query.limit
    after = req.query.after

    context = {version: version, channel: channel}

    choplet.searchChopPosts(self, chopid, count, after, context, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else if err.notfound
          res.send(404)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  app.get('/api/topics/search', authenticate(trust), (req, res) ->
    self = req.header('uid')
    query = req.query.query

    topiclet.searchTopic(self, query, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  app.get('/api/topics/:topicid/followers', authenticate(trust), (req, res) ->
    self = req.header('uid')
    topicid = req.params.topicid
    count = req.query.limit
    offset = req.query.offset

    topiclet.listTopicFollowers(self, topicid, count, offset, (err, result) ->
      if err?
        if err.notfound
          res.send(404)
        else if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  app.get('/api/topics/:topicid', authenticate(trust), (req, res) ->
    self = req.header('uid')
    version = req.header('version')
    channel = req.header('channel')
    topicid = req.params.topicid

    context = {version: version, channel: channel}

    topiclet.getTopic(self, topicid, (err, result) ->
      if err?
        if err.notfound
          res.send(404)
        else if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        _channelFilter(context, result)
        res.json(result)
    )
  )

  # 个人关注的主题数
  app.get('/api/topics/:userid/following/count', authenticate(trust), (req, res) ->
    userid = req.params.userid

    topiclet.topicFollowCount(userid, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # 获取关注主题列表
  app.get('/api/topics/:userid/following', authenticate(trust), (req, res) ->
    self = req.header('uid')
    userid = req.params.userid
    count = req.query.limit
    offset = req.query.offset

    topiclet.listFollowTopics(self, userid, count, offset, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  app.get('/api/topics/:topicid/posts', authenticate(trust), (req, res) ->
    self = req.header('uid')
    version = req.header('version')
    channel = req.header('channel')
    topicid = req.params.topicid
    count = req.query.limit
    after = req.query.after

    context = {version: version, channel: channel}

    topiclet.searchTopicPosts(self, topicid, count, after, context, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else if err.notfound
          res.send(404)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # list arenas
  app.get('/api/arenas', authenticate(trust), (req, res) ->
    self = req.header('uid')
    limit = req.query.limit
    after = req.query.after

    arenalet.listArena(self, limit, after, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # active活动列表
  # 最多返回8个活动，不支持分页
  app.get('/api/arenas/active', authenticate(trust), (req, res) ->
    self = req.header('uid')
    version = req.header('version')
    channel = req.header('channel')

    context = {version: version, channel: channel}

    arenalet.searchActiveArenas(self, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        _channelFilter(context, result)
        res.json(result)
    )
  )

  app.get('/api/arenas/:arenaid', authenticate(trust), (req, res) ->
    self = req.header('uid')
    version = req.header('version')
    channel = req.header('channel')
    arenaid = req.params.arenaid

    context = {version: version, channel: channel}

    arenalet.getArena(self, arenaid, (err, result) ->
      if err?
        if err.notfound
          res.send(404)
        else if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        _channelFilter(context, result)
        res.json(result)
    )
  )

  app.get('/api/arenas/:arenaid/posts', authenticate(trust), (req, res) ->
    self = req.header('uid')
    version = req.header('version')
    channel = req.header('channel')
    arenaid = req.params.arenaid
    count = req.query.limit
    after = req.query.after

    context = {version: version, channel: channel}

    arenalet.searchArenaPosts(self, arenaid, count, after, context, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else if err.notfound
          res.send(404)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  app.get('/api/arenas/:arenaid/posts/featured', authenticate(trust), (req, res) ->
    self = req.header('uid')
    arenaid = req.params.arenaid
    count = req.query.limit
    after = req.query.after

    arenalet.searchArenaFeaturedPosts(self, arenaid, count, after, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else if err.notfound
          res.send(404)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # list salons
  app.get('/api/salons', authenticate(trust), (req, res) ->
    self = req.header('uid')
    limit = req.query.limit
    after = req.query.after
    salonType = req.query.salon_type

    salonLet.listSalon(self, limit, after, salonType, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # active沙龙列表
  # 最多返回8个沙龙，不支持分页
  app.get('/api/salons/active', authenticate(trust), (req, res) ->
    self = req.header('uid')
    version = req.header('version')
    channel = req.header('channel')
    salonType = req.query.salon_type

    context = {version: version, channelCode: channel}

    salonLet.searchActiveSalons(self, salonType, context, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  app.get('/api/salons/:salonId', authenticate(trust), (req, res) ->
    self = req.header('uid')
    version = req.header('version')
    channel = req.header('channel')
    salonId = req.params.salonId
    owner = req.query.owner

    context = {version: version, channel: channel}

    salonLet.getSalon(self, salonId, owner, (err, result) ->
      if err?
        if err.notfound
          res.send(404)
        else if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        _channelFilter(context, result)
        res.json(result)
    )
  )

  app.get('/api/topics/stream/featured', authenticate(trust), (req, res) ->
    limit = req.query.limit
    after = req.query.after

    topiclet.listFeaturedTopics(limit, after, (err, result) ->
      if err?
        if err.badRequest
          res.send(400)
        else
          res.send(500)
      else
        res.json(result)
    )
  )

  app.get('/api/topics/:topicId/posts/featured', authenticate(trust), (req, res) ->
    self = req.header('uid')
    topicId = req.params.topicId
    count = req.query.limit
    after = req.query.after

    topiclet.searchTopicFeaturedPosts(self, topicId, count, after, (err, result) ->
      if err?
        if err.badRequest
          res.send(400)
        else
          res.send(500)
      else
        res.json(result)
    )
  )

  app.get('/api/bags/catalog', authenticate(trust), (req, res) ->
    version = req.header('version') ? 2.2
    baglet.listBagCatalog(version, (err, result) ->
      if err?
        if err.badRequest
          res.send(400)
        else
          res.send(500)
      else
        res.json(result)
    )
  )

  app.get('/api/bags/blinks', authenticate(trust), (req, res) ->
    version = req.header('version') ? 3.1
    baglet.listBagBlinksCatalog(version, (err, result) ->
      if err?
        if err.badRequest
          res.send(400)
        else
          res.send(500)
      else
        res.json(result)
    )
  )

  app.get('/api/bags/stickers', authenticate(trust), (req, res) ->
    version = req.header('version') ? 3.1
    baglet.listBagStickersCatalog(version, (err, result) ->
      if err?
        if err.badRequest
          res.send(400)
        else
          res.send(500)
      else
        res.json(result)
    )
  )

  app.get('/api/bags', authenticate(trust), (req, res) ->
    versions = (req.query.versions ? "1").split(',').map((x) -> return parseInt(x))
    baglet.listBag(versions, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
      else
        res.json(result)
    )
  )

  app.get('/api/bags/:ids', authenticate(trust), (req, res) ->
    ids = req.params.ids.split(',')

    baglet.getBag(ids, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        if result.bags.length == 0
          res.send(404)
        else
          res.json(result)
    )
  )

  app.get('/api/bags/:bagid/stickers', authenticate(trust), (req, res) ->
    self = req.header('uid')
    bagid = req.params.bagid

    baglet.listBagStickers(self, bagid, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  app.get('/api/stickers', authenticate(trust), (req, res) ->
    stickerlet.listSticker((err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  app.get('/api/stickers/default', authenticate(trust), (req, res) ->
    stickerlet.getDefaultSticker((err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        if result.stickers.length == 0
          res.send(404)
        else
          res.json(result)
    )
  )

  app.get('/api/stickers/:id', authenticate(trust), (req, res) ->
    stickerids = req.params.id.split(',')

    stickerlet.getSticker(stickerids, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        if result.stickers.length == 0
          res.send(404)
        else
          res.json(result)
    )
  )

  app.get('/api/blinks/:id', authenticate(trust), (req, res) ->
    blinkids = req.params.id.split(',')

    blinklet.getBlink(blinkids, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        if result.blinks.length == 0
          res.send(404)
        else
          res.json(result)
    )
  )

  app.get('/api/albums/stream/evented', authenticate(trust), (req, res) ->
    count = req.query.limit
    offset = req.query.offset

    albumlet.listEventAlbums(count, offset, (err, result) ->
      if err?
        if err.badRequest
          res.send(400)
        else
          res.send(500)
      else
        res.json(result)
    )
  )

  app.get('/api/albums/active_event', authenticate(trust), (req, res) ->
    albumlet.getActiveEventAlbums((err, result) ->
      if err?
        if err.badRequest
          res.send(400)
        else
          res.send(500)
      else
        res.json(result)
    )
  )

  app.get('/api/albums/stream/splash', authenticate(trust), (req, res) ->
    version = req.header('version')
    channel = req.header('channel')
    count = req.query.limit
    offset = req.query.offset

    context = {version: version, channel: channel}

    albumlet.listSplashAlbums(count, offset, (err, result) ->
      if err?
        if err.badRequest
          res.send(400)
        else
          res.send(500)
      else
        _channelFilter(context, result)
        res.json(result)
    )
  )

  app.get('/api/albums/active_splash', authenticate(trust), (req, res) ->
    albumlet.getActiveSplashAlbum((err, result) ->
      if err?
        if err.badRequest
          res.send(400)
        else
          res.send(500)
      else
        res.json(result)
    )
  )

  app.get('/api/albums/stream/featured', authenticate(trust), (req, res) ->
    count = req.query.limit
    offset = req.query.offset

    albumlet.listFeaturedAlbums(count, offset, (err, result) ->
      if err?
        if err.badRequest
          res.send(400)
        else
          res.send(500)
      else
        res.json(result)
    )
  )

  app.get('/api/albums/:ids', authenticate(trust), (req, res) ->
    ids = req.params.ids.split(',')

    albumlet.getAlbum(ids, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        if result.albums.length == 0
          res.send(404)
        else
          res.json(result)
    )
  )

  app.get('/api/albums/:albumid/sub_albums', authenticate(trust), (req, res) ->
    albumid = req.params.albumid

    albumlet.listSubAlbums(albumid, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  app.get('/api/albums/:albumid/posts', authenticate(trust), (req, res) ->
    self = req.header('uid')
    version = req.header('version')
    channel = req.header('channel')
    albumid = req.params.albumid
    count = req.query.limit
    offset = req.query.offset

    context = {version: version, channel: channel}

    albumlet.listAlbumPosts(self, albumid, count, offset, context, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  app.get('/api/inventories/:name/posters', authenticate(trust), (req, res) ->
    name = req.params.name

    start = req.query.after
    count = req.query.limit
    offset = req.query.offset

    entity.listInventoryPoster(name, count, start, offset, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else if err.notfound
          res.send(404)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  app.post('/api/objections', authenticate(trust), (req, res) ->
    self = req.header('uid')

    body = req.body

    feedback.newObjection(self, body, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  app.post('/api/visits', authenticate(trust), (req, res) ->
    self = req.header('uid')
    version = req.header('version')
    source = req.header('client')
    applicationId = req.body.applicationId
    idfa = req.body.idfa

    statistics.visitorJournal(applicationId, idfa, self, source, version, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  app.post('/api/notification/push/register', authenticate(trust), (req, res) ->
    self = req.header('uid')
    source = req.header('client')

    context = req.body

    notification.pushNotificationRegister(self, source, context, (err, result) ->
      if err?
        if err.badRequest
          res.send(400)
        else
          res.send(500)
      else
        res.json(result)
    )
  )
  app.get('/api/app/share', authenticate(trust), (req, res) ->
    self = req.header('uid')

    profile.shareApp(self, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  app.get('/api/channels/featured', authenticate(trust), (req, res) ->
    self = req.header('uid')
    version = req.header('version')
    # 过滤
    channelCode = req.header('channel')
    after = req.query.after
    limit = req.query.limit
    did = req.header('did')

    context = {did: did, channelCode: channelCode, version: version}
    channelLet.listFeaturedChannels(self, after, limit, context, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else if err.notfound
          res.send(404)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  app.get('/api/channels/:channelId', authenticate(trust), (req, res) ->
    self = req.header('uid')
    version = req.header('version')
    # 过滤
    channelCode = req.header('channel')
    owner = req.query.owner
    channelId = req.params.channelId
    did = req.header('did')

    context = {did: did, channelCode: channelCode, version: version}
    channelLet.getChannel(self, owner, channelId, context, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else if err.notfound
          res.send(404)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # 获取所有频道列表
  app.get('/api/channels', authenticate(trust), (req, res) ->
    self = req.header('uid')
    version = req.header('version')
    # 过滤
    channelCode = req.header('channel')
    since = req.query.after
    limit = req.query.limit
    did = req.header('did')

    context = {did: did, channelCode: channelCode, version: version}
    channelLet.listChannel(self, since, limit, context, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else if err.notfound
          res.send(404)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # 获取用户未关注的频道列表， v4.1版本以后调用
  app.get('/api/channels/unsubscribed/stream', authenticate(trust), (req, res) ->
    self = req.header('uid')
    version = req.header('version')
    # 过滤
    channelCode = req.header('channel')
    after = req.query.after
    limit = req.query.limit
    did = req.header('did')

    context = {versiondid: did, channelCode: channelCode, version: version}
    channelLet.listUnsubscribedChannel(self, after, limit, context, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else if err.notfound
          res.send(404)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  app.get('/api/channels/:channelId/posts', authenticate(trust), (req, res) ->
    self = req.header('uid')
    version = req.header('version')
    # 过滤
    channelCode = req.header('channel')
    # 频道
    channelId = req.params.channelId
    limit = req.query.limit
    since = req.query.after
    owner = req.query.owner
    popularity = req.query.popularity

    context = {version: version, channelCode: channelCode}
    # 频道热帖
    utils.extend(context, {popularity: true}, true) if popularity?

    channelLet.searchChannelPosts(self, channelId, owner, limit, since, context, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else if err.notfound
          res.send(404)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  app.put('/api/channels/:channelId/refresh', authenticate(trust), (req, res) ->
    self = req.header('uid')
    version = req.header('version')
    # 过滤
    channelCode = req.header('channel')
    channelId = req.params.channelId
    did = req.header('did')
    # TODO, 以后可移除
    idfa = req.query.idfa
    timestamp = new Date().getTime()

    context = {version: version, did: did ? idfa, channelCode: channelCode}

    res.send(400) if not self? and not idfa?

    channelLet.userLastSeenChannel(self, idfa, channelId, timestamp, context, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else if err.notfound
          res.send(404)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  app.put('/api/user/firsttime', authenticate(trust), (req, res) ->
    self = req.header('uid')
    version = req.header('version')
    idfa = req.query.idfa
    timestamp = new Date().getTime()

    context = {version: version}

    res.send(400) if not self? and not idfa?

    channelLet.userFirstSeenChannel(self, idfa, timestamp, context, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else if err.notfound
          res.send(404)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # 来自api-private.coffee
  app.put('/api/posts/:postId/feature', (req, res) ->
    uid = req.header('uid')
    postId = req.params.postId
    userId = req.query.owner

    return res.send(400) if postConservator? and uid not in postConservator

    postLet.markPostAsFeatured(postId, userId, {}, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else if err.notfound
          res.send(404)
        else if err.duplicate
          res.send(409)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # 来自旧版本帖子频道分类, 来自api-private.coffee
  app.put('/api/posts/:postId/classify', (req, res) ->
    uid = req.header('uid')
    postId = req.params.postId
    owner = req.query.owner
    body = req.body

    return res.send(400) if postConservator? and uid not in postConservator

    postLet.postClassify(uid, postId, owner, body, {}, (err, result) ->
      if err?
        if err.notfound
          res.send(404)
        else if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

