# This file only manipulate data organization, data fetching should be done in *entity* and *profile* module

url = require('url')
config = require('../utils/config')
logger = require('../utils/log').getLogger('FORMAT')
utils = require('../utils/routines')

config.setModuleDefaults('Format', {
  defaultIcon: 'default-icon',
  baseUrlPhoto: 'pic.cunpai.com',
  baseUrlAvatar: 'icon.cunpai.com',
  baseUrlWeb: 'static.cunpai.com',
  stylePhoto: {
    raw: '',
    display: '/display',
    display_large: '/large',
    thumb: '/thumb'
    preview: '/w360'
  },
  styleAvatar: {
    avatar: '/avatar',
    square: '/square'
  },
  styleWeb: {
  }
})

defaultIcon = config['Format']?.defaultIcon

module.exports = (obj) ->
  return utils.extend(obj ? {}, {
    protocol: 1.0
  })

getType = (type) ->
  switch type
    when 1
      'post'
    when 2
      'reply'
    when 3
      'request'
    when 4
      'like'
    when 7
      'response'
    when 20
      'brand'
    when 21
      'model'
    when 22
      'commodity'
    when 23
      'campaign'
    when 24
      'inventory'
    when 25
      'poster'
    when 26
      'payment'
    when 27
      'feedback'
    when 28
      'objection'
    else
      'unknown'

# 将text字段populate成json。
module.exports.secondary = secondary = (activities, type) ->
  timer = logger.time(type)

  logger.debug('Arguments:', activities, type)

  result = []
  for activity in activities
    try
      extra = parseText(activity)

      utils.extend(extra, {
        id: activity.key,
        type: type or activity.type or getType(activity.action),
        timestamp: activity.timestamp,
        owner: activity.uid
      }, true)
      result.push(extra)
    catch err
      logger.warn(err, activity)

  logger.debug('Results:', result)

  timer.end()

  return result

module.exports.reply = (activities) ->
  return secondary(activities, 'reply')

module.exports.sticker = (activities) ->
  return secondary(activities, 'sticker')

module.exports.blink = (activities) ->
  return secondary(activities, 'blink')

module.exports.request = (activities) ->
  return secondary(activities, 'request')

module.exports.response = (activities) ->
  return secondary(activities, 'response')

module.exports.like = (activities) ->
  return secondary(activities, 'like')

module.exports.entity = (activities) ->
  return secondary(activities)

module.exports.payment = (activities, trust = false) ->
  result = secondary(activities, 'payment')
  if not trust
    for e in result
      delete e._audit
  return result

module.exports.feedback = (activities) ->
  return secondary(activities, 'feedback')

module.exports.objection = (activities) ->
  return secondary(activities, 'objection')

module.exports.user = (users, publicFields, following, follower, friends, friendCounts, activityCounts, context = {}) ->
  timer = logger.time('user')

  logger.debug('Arguments:', users, publicFields, following, follower, friends, friendCounts, activityCounts)

  result = []
  for user in users
    data = {}
    privacy = null

    followingCount = if friendCounts? then friendCounts[user.uid]?.followingCount ? 0 else undefined
    subscribeChannelCount = if activityCounts?.subscribeChannelCounts? then activityCounts.subscribeChannelCounts[user.uid]?.subscribeChannelCount ? 0 else undefined
    # 关注用户数和关注频道数之和
    total_following_count = (subscribeChannelCount ? 0) + (followingCount ? 0)

    try
      data = JSON.parse(user.data ? null) ? {}
      # 设置默认introduction
      if not data.introduction
        data.introduction = defaultIntroductions[user.uid % defaultIntroductions.length]
    catch err
      logger.warn(err, user)
    try
      privacy = JSON.parse(user.privacy ? null)
    catch err
      logger.warn(err, user)
    if publicFields?
      #TODO filter aginst user's own privacy settings (e.privacy) in future
      privacy = null
      for key in Object.keys(data) when key not of publicFields
        delete data[key]
      delete user.time
      delete user.source
      delete user.handle
    result.push(utils.extend(data, {
      id: user.uid,
      nickname: user.nick,
      icon: if user.icon then user.icon else defaultIcon,
      source:  user.source ? undefined,
      email: if user.handle? and user.source == 1 then user.handle else undefined,
      time_created: if user.time? then user.time else undefined,
      following: if following? then user.uid of following else undefined,
      follower: if follower? then user.uid of follower else undefined,
      friend: if friends? then user.uid of friends else undefined,
      following_count: if friendCounts? then friendCounts[user.uid]?.followingCount ? 0 else undefined,
      follower_count: if friendCounts? then friendCounts[user.uid]?.followerCount ? 0 else undefined,
      chop_count: if activityCounts? then activityCounts.chopCount ? 0 else undefined,
      post_count: if activityCounts? then activityCounts.postCount ? 0 else undefined,
      like_count: if activityCounts? then activityCounts.likeCount ? 0 else undefined,
      privacy: if privacy? then privacy else undefined
      subscribe_channel_count: subscribeChannelCount
      total_following_count: total_following_count
    }))

  logger.debug('Results:', result)

  timer.end()

  return result

module.exports.photo = (activities, users, context = {}) ->
  timer = logger.time('photo')
  logger.debug('Arguments:', activities, users, context)

  # app端为传递屏幕大小时，默认用旧版display方式
  if context.width?
    displayWidth = Number(context.width)
    previewWidth = Number(context.width) / 2
    stylePhoto = utils.extend(stylePhoto, {display: "/w#{baseWidth[len - 1]}", preview: "/w#{baseWidth[len - 1]}"}, true) if len = baseWidth.length > 0
    for width in baseWidth
      if displayWidth <= width
        stylePhoto = utils.extend(stylePhoto, {display: "/w#{width}"}, true)
        break

    for width in baseWidth
      if previewWidth <= width
        stylePhoto = utils.extend(stylePhoto, {preview: "/w#{width}"}, true)
        break

  result = []
  for activity in activities
    try
      photos = activity.photos ? parseText(activity)?.photos ? []
      cover = activity.cover ? parseText(activity)?.cover
      photos.push(cover) if cover?
      picture = activity.picture
      photos.push(picture) if picture?

      for photo in photos when photo
        result.push(utils.extend({
          key: photo
          url_base: "http://#{baseUrlPhoto}/#{photo}"
        }, stylePhoto))
    catch err
      'do nothing because post() would log this error'
  for user in users
    icon = if user.icon then user.icon else defaultIcon
    result.push(utils.extend({
      key: icon,
      url_base: "http://#{baseUrlAvatar}/#{icon}"
    }, styleAvatar))

  logger.debug('Results:', result)

  timer.end()

  return result

module.exports.brand = (brands, counts) ->
  timer = logger.time('brand')

  logger.debug('Arguments:', brands, counts)

  if not counts?
    counts = {}
    defaultValue = undefined
  else
    defaultValue = 0

  result = []
  for brand in brands
    try
      extra = parseText(brand)
      utils.extend(extra, {
        id: brand.key,
        type: 'brand',
        model_count: counts[brand.key]?[21] ? defaultValue,
        commodity_count: counts[brand.key]?[22] ? defaultValue,
        post_count: counts[brand.key]?[1] ? defaultValue
      })
      result.push(extra)
    catch err
      logger.warn(err, brand)

  logger.debug('Results:', result)

  timer.end()

  return result

module.exports.model = (models, counts) ->
  timer = logger.time('model')

  logger.debug('Arguments:', models, counts)

  if not counts?
    counts = {}
    defaultValue = undefined
  else
    defaultValue = 0

  result = []
  for model in models
    try
      extra = parseText(model)
      utils.extend(extra, {
        id: model.key,
        type: 'model',
        commodity_count: counts[model.key]?[22] ? defaultValue,
        post_count: counts[model.key]?[1] ? defaultValue
      })
      result.push(extra)
    catch err
      logger.warn(err, model)

  logger.debug('Results:', result)

  timer.end()

  return result

module.exports.commodity = (commodities) ->
  timer = logger.time('commodity')

  logger.debug('Arguments:', commodities)

  result = []
  for commodity in commodities
    try
      extra = parseText(commodity)
      utils.extend(extra, {
        id: commodity.key,
        type: 'commodity'
      })
      result.push(extra)
    catch err
      logger.warn(err, commodity)

  logger.debug('Results:', result)

  timer.end()

  return result

module.exports.poster = (posters) ->
  timer = logger.time('poster')

  logger.debug('Arguments:', posters)

  result = []
  for poster in posters
    try
      extra = parseText(poster)
      utils.extend(extra, {
        id: poster.key,
        type: 'poster'
      })
      result.push(extra)
    catch err
      logger.warn(err, poster)

  logger.debug('Results:', result)

  timer.end()

  return result

module.exports.inventory = (inventories) ->
  timer = logger.time('inventory')

  logger.debug('Arguments:', inventories)

  result = []
  for inventory in inventories
    try
      extra = parseText(inventory)
      utils.extend(extra, {
        id: inventory.key,
        type: 'inventory'
      })
      result.push(extra)
    catch err
      logger.warn(err, inventory)

  logger.debug('Results:', result)

  timer.end()

  return result

module.exports.logo = (brands) ->
  timer = logger.time('logo')

  logger.debug('Arguments:', brands)

  result = []
  for brand in brands
    try
      if brand.text?
        extra = parseText(brand)
        logo = extra.logo
        logo_thumb = extra.logo_thumb
      else
        logo = brand.logo
        logo_thumb = brand.logo_thumb
      if logo
        result.push(utils.extend({
          key: logo
          url_base: "http://#{baseUrlWeb}/#{logo}"
        }, styleWeb))
      if logo_thumb
        result.push(utils.extend({
          key: logo_thumb
          url_base: "http://#{baseUrlWeb}/#{logo_thumb}"
        }, styleWeb))
    catch err
      'do nothing because brand() would log this error'

  logger.debug('Results:', result)

  timer.end()

  return result

# 为指定imageKey的图片添加style信息
module.exports.buildImage = buildImage = (imageKey) ->
  if not imageKey
    return null
  return utils.extend({
    key: imageKey
    url_base: "http://#{baseUrlWeb}/#{imageKey}"
  }, styleWeb)

# 处理Web(image)类型图片的交叉引用
module.exports.image = (entities, keys = 'image') ->
  timer = logger.time('image')
  logger.debug('Arguments:', entities, keys)

  keys = [keys] if not Array.isArray(keys)

  result = []
  # TODO, 兼容v4.0以前版本，以后可视情况重写
  for entity in entities
    try
      if entity.text?
        extra = parseText(entity)
      else
        extra = entity

      for key in keys
        imageKey = if extra? then extra[key] else entity[key]
        result.push(buildImage(imageKey)) if imageKey?
    catch err
      'do nothing because caller() would log this error'

  logger.debug('Results:', result)
  timer.end()
  return result

module.exports.objectify = utils.objectify

module.exports.previewPhoto = (key) ->
  return "http://#{baseUrlPhoto}/#{key}#{stylePhoto.thumb}"

module.exports.previewAvatar = (key) ->
  return "http://#{baseUrlAvatar}/#{key}#{styleAvatar.avatar}"

module.exports.previewWeb = (key) ->
  return "http://#{baseUrlWeb}/#{key}"

module.exports.defaultIcon = ->
  return defaultIcon

module.exports.parseText = parseText = (obj) ->
  try
    extra = if obj.text? then (JSON.parse(obj.text) ? {}) else obj
    extra.puid = utils.normalizeUserId(extra.puid) if extra.puid?
    for key in Object.keys(extra)
      val = extra[key]
      if val == undefined or val == null
        delete extra[key]
    return extra
  catch err
    logger.error('Invalid text', obj)
    return {}

module.exports.parseUrl = parseUrl = (uri) ->
  try
    return url.parse(uri, true, true)
  catch error
    logger.error('Invalid urL', uri)
    return {}