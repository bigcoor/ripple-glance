qiniu = require('qiniu')
fs = require('fs')
request = require('request')

config = require('../utils/config')
logger = require('../utils/log').getLogger('UPLOAD')
utils = require('../utils/routines')
timed = require('../utils/timed')
format = require('./format')

config.setModuleDefaults('Upload', {
  lifetime: 300,
  buckets: {
    pic: 'cunpai-pic-test',
    icon: 'cunpai-icon-test',
    web: 'cunpai-web-test'
  },
  styles: {
    pic: '',
    icon: '',
    web: ''
  },
  previews: {
    pic: 'previewPhoto',
    icon: 'previewAvatar',
    web: 'previewWeb'
  },
  callbackScheme: 'http'
  callbackAuthority: 'callback.cunpai.com'
  callbackPath: '/qiniu',
  callbackParams: 'uid=$(endUser)&name=$(fname)&hash=$(etag)&size=$(fsize)&mime=$(mimeType)&info=$(imageInfo)&exif=$(exif)&quiet=$(x:silence)',
  sizeLimit: 10485760,
  mimeLimit: 'image/*;application/zip'
})

tmpImgDir = (process.env.APP_RUNTIME_PATH || process.cwd()) + '/tmp'
lifetime = config['Upload']?.lifetime
buckets = config['Upload']?.buckets ? {}
qiniu.conf.ACCESS_KEY = config['Upload']?.accessKey
qiniu.conf.SECRET_KEY = config['Upload']?.secretKey
styles = config['Upload']?.styles ? {}
previews = config['Upload']?.previews ? {}
callbackScheme = config['Upload']?.callbackScheme
callbackAuthority = config['Upload']?.callbackAuthority
callbackPath = config['Upload']?.callbackPath
callbackParams = config['Upload']?.callbackParams
sizeLimit = config['Upload']?.sizeLimit
mimeLimit = config['Upload']?.mimeLimit

config.on('change', (newConfig) ->
  lifetime = config['Upload']?.lifetime
  buckets = config['Upload']?.buckets ? {}
  qiniu.conf.ACCESS_KEY = config['Upload']?.accessKey
  qiniu.conf.SECRET_KEY = config['Upload']?.secretKey
  styles = config['Upload']?.styles ? {}
  previews = config['Upload']?.previews ? {}
  callbackScheme = config['Upload']?.callbackScheme
  callbackAuthority = config['Upload']?.callbackAuthority
  callbackPath = config['Upload']?.callbackPath
  callbackParams = config['Upload']?.callbackParams
  sizeLimit = config['Upload']?.sizeLimit
  mimeLimit = config['Upload']?.mimeLimit
)

exports.callbackUrl = callbackUrl = ->
  return "#{callbackScheme}://#{callbackAuthority}#{callbackPath}"

exports.callbackPath = ->
  return callbackPath

getFlags = qiniu.rs.PutPolicy.prototype.getFlags

qiniu.rs.PutPolicy.prototype.getFlags = ->
  flags = getFlags.apply(this)
  flags.fsizeLimit = this.fsizeLimit if this.fsizeLimit?
  flags.detectMime = this.detectMime if this.detectMime?
  flags.mimeLimit = this.mimeLimit if this.mimeLimit?
  return flags

# 如果key为null，则自动生成key
authorize = (uid, key, bucketName, expires, web = false) ->
  if web
    return unless utils.validateId(uid)
  else
    return unless utils.validateUserId(uid)

  bucket = buckets[bucketName]
  style = styles[bucketName]
  preview = previews[bucketName]
  if not bucket or not style? or not preview
    logger.error('Unknown bucket', bucketName)
    return

  #TODO bookkeeping, return if too many requests from same uid

  timer = logger.time('authorize')

  now = utils.timestampToUnixTime()
  expires = now + lifetime if not expires
  expires = utils.parseInt(expires - now, lifetime, 60)

  # endUser must be string otherwise token would be considered as expired
  endUser = if web then utils.normalizeId(uid) else utils.normalizeUserId(uid).toString()
  if not key
    key = "#{endUser}/#{utils.randomString()}"

  policy = new qiniu.rs.PutPolicy("#{bucket}:#{key}", callbackUrl(), callbackParams, null, null, style, endUser, expires)
  policy.fsizeLimit = sizeLimit
  policy.detectMime = 1
  policy.mimeLimit = mimeLimit

  token = format({ key: key, token: policy.token(), preview: format[preview](key) })

  #TODO add key to Redis

  timer.end()

  return token

exports.delete = (uid, bucketName, keys, web, callback) ->
  if web
    return unless utils.validateId(uid, callback)
  else
    return unless utils.validateUserId(uid, callback)

  logger.debug('Arguments:', uid, bucketName, keys, web)

  bucket = buckets[bucketName]
  if not bucket
    logger.error('Unknown bucket', bucketName)
    return callback(new Error('Unknown bucket'))

  result = format({ success: true })

  return callback(null, result) if not keys
  keys = [keys] if not Array.isArray(keys)
  return callback(null, result) if keys.length == 0

  timer = utils.prologue(logger, 'delete')

  prefix = (if web then utils.normalizeId(uid) else utils.normalizeUserId(uid)) + '/'

  client = new qiniu.rs.Client();

  #TODO remove key from Redis

  entries = (new qiniu.rs.EntryPath(bucket, key) for key in keys when key.indexOf(prefix) == 0)
  if entries.length > 0
    client.batchDelete(entries, (err, data) ->
      if err?
        logger.error('Failed to delete from cloud, bucket = [%s], keys = [%s], uid = [%s]', bucket, keys, uid, err.stack)
        err = new Error('Failed to delete from cloud')
        err.external = true
        result = null
      else
        for ret, i in data when ret.code != 200
          logger.warn('Unable to delete', entries[i].key, entries[i].bucket, ret.code, ret.data)
      utils.epilogue(logger, 'delete', timer, callback, err, result)
    )
  else
    utils.epilogue(logger, 'delete', timer, callback, null, result)

# 从url获取图片并上传到qiniu服务器
exports.uploadUrlToQiniu = (id, bucket, url, callback) ->
  request.head(url, {
      method: 'HEAD',
      timeout: timed.defaultTimeout
    }, (err, res, body) ->
    if err?
      # QQ服务器经常不能正确返回head :(，这里只log不退出
      logger.warn("Failed to read headers of #{url}")
    else
      # TODO, potential bug here
      # 由于上述原因，这里只在正确返回header情况下做检查
      mime = res.headers['content-type']
      if typeof mime != 'string' or mime.indexOf('image/') != 0
        return callback(new Error("Invalid file type - [#{mime}]"))
      if res.headers['content-length'] > 10 * 1048576
        return callback(new Error("Too large image file - #{res.headers['content-length']}"))

    policy = authorize(id, null, bucket, true)
    # 生成随机文件名
    # TODO, 删除临时文件
    path = tmpImgDir + '/' + utils.timestamp() + '-' + Math.floor(Math.random() * 1000)
    writer = fs.createWriteStream(path)
    writer.on('error', ->
      callback(new Error('failed to download'), null)
    )
    writer.on('finish', ->
      qiniu.io.putFile(policy.token, policy.key, path, null, (err, body, res) ->
        if err? or res.statusCode != 200
          console.warn('putFile failed', path, policy.key, err ? res.statusCode, body)
          err = new Error("Failed to upload file to Qiniu #{path}, key = #{policy.key}")
        callback(err, policy.key)
      )
    )
    request.get(url, {
      timeout: 6000
    }, (err, res, body)->
      # 这个callback是在下载完成时立即调用，无需等待writer操作
      if err?
        # TODO, fix me
        logger.warn(err, "Failed to download image", url)
        callback(err)
    ).pipe(writer)
  )

exports.authorize = authorize
