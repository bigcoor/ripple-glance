logger = require('./log').getLogger('ROUTINES')

fs = require('fs')
mongoose = require 'mongoose'

#TODO refactor to merge these two methods
exports.extend = extend = (object, properties, nullAsUndefined = false) ->
  array = Array.isArray(properties)
  for key in Object.keys(properties)
    val = properties[key]
    if not array and (val == undefined or nullAsUndefined and val == null)
      delete object[key]
    else if typeof val != 'object' or val instanceof Boolean or val instanceof Number or val instanceof String or val instanceof RegExp or val == null
      object[key] = val
    else if val instanceof Date
      object[key] = new Date(val.getTime())
    else if Array.isArray(val)
      object[key] = new Array(val.length)
      extend(object[key], val)
    else
      object[key] = object[key] or {}
      extend(object[key], val)
  return object

#TODO refactor to merge these two methods
exports.extendNew = extendNew = (object, properties, undefinedAsNonExistence = false) ->
  array = Array.isArray(properties)
  for key in Object.keys(properties)
    val = properties[key]
    if not array and val == undefined
      'do nothing'
    else if typeof val != 'object' or val instanceof Boolean or val instanceof Number or val instanceof String or val instanceof RegExp or val == null
      object[key] = val if key not of object or undefinedAsNonExistence and object[key] == undefined
    else if val instanceof Date
      object[key] = new Date(val.getTime()) if key not of object or undefinedAsNonExistence and object[key] == undefined
    else if Array.isArray(val)
      if key not of object or undefinedAsNonExistence and object[key] == undefined
        object[key] = new Array(val.length)
        extendNew(object[key], val)
    else
      object[key] = object[key] or {}
      extendNew(object[key], val)
  return object

exports.parseInt = (number, default_value = NaN, min = -Infinity, max = Infinity) ->
  value = parseInt(number, 10)
  if isNaN(value)
    value = default_value
  else if value < min
    value = min
  else if value > max
    value = max
  return value

exports.parseFloat = (number, default_value = NaN, min = -Infinity, max = Infinity) ->
  value = parseFloat(number)
  if isNaN(value)
    value = default_value
  else if value < min
    value = min
  else if value > max
    value = max
  return value

exports.parseBool = (str) ->
  return str if str == true or str == false
  return false if /^\s*(false|no|off|0+)?\s*$/i.test(str)
  return Boolean(str)

exports.randomString = randomString = ->
  return Math.random().toString(36).substring(2)

exports.realRandomString = ->
  timer = logger.time('realRandomString')
  try
    return require('base64id').generateId()
  catch err
    logger.caught(err, 'Failed to generate real random string')
    return randomString()
  finally
    timer.end()

# Use with caution!!
# For example, config auto update fails if config module reloaded
exports.reloadModule = (moduleId, recursive = false) ->
  timer = logger.time('reloadModule')
  try
    if require.cache[moduleId]?.id == moduleId
      logger.debug('Found cached module', moduleId)
      traverse = (mod) ->
        logger.debug('Recursively process children of', mod.id)
        mod.children.forEach((child) ->
          logger.debug('Processing process child %s of', child.id, mod.id)
          traverse(child)
        )
        delete require.cache[mod.id]
      traverse(require.cache[moduleId]) if recursive
      delete require.cache[moduleId]
    return require(moduleId)
  catch err
    logger.caught(err, 'Failed to load module `%s`', moduleId)
  finally
    timer.end()
  return null

exports.timestamp = ->
  return Date.now()

exports.timestampToUnixTime = (timestamp) ->
  return Math.floor((timestamp or Date.now()) / 1000)

exports.unixTimeToTimestamp = (unixTime) ->
  return new Date().getTime() if not unixTime?
  return unixTime if unixTime.toString().trim().length == 13
  return unixTime * 1000

exports.validateString = validateString = (str, failureCallback) ->
  if not str? or typeof str != 'string' or str.trim().length == 0
    failureCallback?(new Error("validateString failed #{str}"))
    return false

  return true

exports.validateId = validateId = (id, failureCallback) ->
  if typeof id == 'number'
    return true if 0 < id < 18446744073709552000 and parseInt(id, 10) == parseFloat(id)
  else if typeof id == 'string' and isNumber(id) and id.indexOf('-') == -1 and id.indexOf('.') == -1 and parseInt(id) != 0
    if id.length >= 20 # in case >= 18446744073709551616
      id = id.trim()
      if id.length > 20
        id = id.replace(/^0+/g, '')
    return true if id.length < 20 or id.length == 20 and id < '18446744073709551616'

  if failureCallback?
    logger.warn("validateId failed [%s]", id)
    logger.warn(new Error('validateId failed').stack)
    failureCallback?(new Error('Bad id'))
  return false

exports.compareId = (id1, id2) ->
  id1.length - id2.length or if id1 < id2 then -1 else if id2 < id1 then 1 else 0

exports.validateUserId = validateUserId = (id, failureCallback) ->
  return true if isInteger(id) and 0 < parseInt(id, 10) < 4294967296

  if failureCallback?
    logger.warn("validateUserId failed [%s]", id)
    logger.warn(new Error('validateUserId failed').stack)
    failureCallback?(new Error('Bad user id'))
  return false

exports.normalizeId = normalizeId = (id, failureCallback = null) ->
  return null if not validateId(id, failureCallback)
  return id.toString().trim().replace(/^0+/g, '')

exports.normalizeUserId = normalizeUserId = (id, failureCallback = null) ->
  return null if not validateUserId(id, failureCallback)
  return parseInt(id, 10)

exports.validateArray = (array, name, failureCallback) ->
  if not Array.isArray(array)
    logger.warn('%s should be an array', name)
    logger.warn(new Error('validateArray failed').stack)
    failureCallback?(new Error("Bad #{name}"))
    return false

  return true

exports.normalizeIdList = (idlist, normalizeElement = false) ->
  if normalizeElement
    return (id for id in idlist when (id = normalizeId(id)) isnt null)
  else
    return (id for id in idlist when validateId(id))

exports.normalizeUserIdList = (idlist, normalizeElement = true) ->
  if normalizeElement
    return (id for id in idlist when (id = normalizeUserId(id)) isnt null)
  else
    return (id for id in idlist when validateUserId(id))

exports.isNumber = isNumber = (s) ->
  # isFinite() returns true for empty string and spaces
  # isFinite() can tell invalid numbers like '3 2', '3.2abc' and '3.2.1'
  # ' 3.2 ' is a valid number
  return not isNaN(parseFloat(s)) and isFinite(s)

exports.isInteger = isInteger = (s) ->
  return isNumber(s) and parseFloat(s) == parseInt(s, 10)

# For domain part, we require each domain label not starting or ending with "." or "-" and containing no consecutive "."
# For local part, we require the name not starting or ending with "." and containing no consecutive "."
# See Also:
#   http://en.wikipedia.org/wiki/Hostname#Restrictions_on_valid_host_names
#   http://en.wikipedia.org/wiki/Email_address#Local_part
# emailChecker = /^[a-z0-9!#$%&'*+\-/=?^_`{|}~]+(\.?[a-z0-9!#$%&'*+\-/=?^_`{|}~]+)*@[a-z0-9]+(\.?[a-z0-9\-]+)*\.[a-z0-9]+$/ # extremely slow for some cases
domainChecker = /^[a-zA-Z0-9\-]+$/
localChecker = /^[a-zA-Z0-9!#$%&'*+\-/=?^_`{|}~]+$/
exports.validateEmail = (email, record) ->
  return false if typeof email != 'string' and email not instanceof String
  email = email.trim()
  return false if email.length < 5 or email.length > 254

  components = email.split('@')
  return false if components.length != 2
  [localPart, domainPart] = components

  return false if domainPart.length < 3 or domainPart.length > 255
  labels = domainPart.split('.')
  return false if labels.length < 2
  for label in labels
    return false if label.length < 1 or label.length > 63
    if label[0] == '-' or label[label.length - 1] == '-'
      return false
    else if not domainChecker.test(label)
      return false

  return false if localPart.length < 1 or localPart.length > 64
  parts = localPart.split('.')
  for part in parts
    if not localChecker.test(part)
      return false

  return true

exports.prologue = (logger, name) ->
  logger.verbose('Entering', name)
  return logger.time(name)

exports.epilogue = (logger, name, timer, callback, err, params...) ->
  logger.debug(name, 'Error:', err) if err?
  params.forEach((each) -> logger.debug(name, 'Result:', each)) if params.length > 0
  timer.end()
  logger.verbose('Exiting', name)
  params.unshift(err)
  callback.apply(null, params)

exports.ensureSuccess = (err, desc) ->
  if err?
    logger.error(desc, err)
    throw err
  return

exports.removeDuplicates = (array, comparer = null, equalityComparer = null, count = 0) ->
  sorted = array.sort(comparer)
  result = []
  last = {}

  same = (if equalityComparer?
            equalityComparer
          else if comparer?
            (a, b) -> comparer(a, b) == 0
          else
            (a, b) -> a == b)

  for item in sorted
    if not same(item, last)
      result.push(item)
      last = item
    break if result.length >= count > 0

  return result

exports.repeat = (pattern, count) ->
  result = ''
  while count > 0
    result += pattern if count & 1
    count >>= 1
    pattern += pattern
  return result

exports.intersect = (list1, list2, comparer = null) ->
  i = 0; j = 0
  result = []

  list1.sort(comparer)
  list2.sort(comparer)

  if not comparer?
    comparer = (a, b) -> if a < b then -1 else if a > b then 1 else 0

  while i < list1.length and j < list2.length
    c = comparer(list1[i], list2[j])
    if c < 0
      i++
    else if c > 0
      j++
    else
      result.push(list1[i])
      i++; j++

  return result

# 以指定的字段为key生成交叉引用
exports.objectify = objectify = (list, keyname) ->
  result = {}
  for e in list
    if keyname
      result[e[keyname]] = e
    else
      result[e] = e
  return result

exports.restoreOrder = (idlist, datalist, keyname) ->
  return [] if not Array.isArray(idlist) or not Array.isArray(datalist)
  map = objectify(datalist, keyname)
  result = []
  for e in idlist when e of map
    result.push(map[e])
  return result

exports.bufferToBinary = bufferToBinary = (buf) ->
  return buf.toString('binary')

exports.binaryToBuffer = binaryToBuffer = (bin) ->
  return new Buffer(bin, 'binary')

exports.bufferToBase64 = bufferToBase64 = (buf) ->
  return buf.toString('base64')

exports.base64ToBuffer = base64ToBuffer = (base64) ->
  return new Buffer(base64, 'base64')

exports.bufferToString = bufferToString = (buf) ->
  return buf.toString('utf8')

exports.stringToBuffer = stringToBuffer = (str) ->
  return new Buffer(str, 'utf8')

exports.stringToBinary = (str) ->
  #return String.fromCharCode.apply(String, new Buffer(str, 'utf8'))
  return null unless str?
  return bufferToBinary(stringToBuffer(str))

exports.binaryToString = (bin) ->
  return null unless bin?
  return bufferToString(binaryToBuffer(bin))

exports.stringToBase64 = (str) ->
  return null unless str?
  return bufferToBase64(stringToBuffer(str))

exports.base64ToString = (base64) ->
  return null unless base64?
  return bufferToString(base64ToBuffer(base64))

exports.random = random = (max, min = 0) -> # [min, max)
  throw new Error('min must be a number') unless isNumber(min)
  throw new Error('max must be a number') unless isNumber(max)
  min = parseFloat(min)
  max = parseFloat(max)
  throw new Error('max must not be less than min') unless min <= max

  return Math.random() * (max - min) + min

# randomly select count elements from list, with uniform probability distribution
exports.randomSelect = (list, count) ->
  throw new Error('list must be an array') unless Array.isArray(list)
  throw new Error('count must be an integer') unless isInteger(count)
  count = parseInt(count)
  throw new Error('count must be a non-negative integer') unless count >= 0

  len = list.length
  return list if count >= len
  return [] if count == 0

  remaining = count
  result = new Array(count)

  for e, i in list
    if random(len - i) < remaining
      result[count - remaining] = e
      if --remaining == 0
        break

  return result

exports.randomSelectWeighted = (list, weight) ->
  throw new Error('list must be an array') unless Array.isArray(list)
  throw new Error('weight must be an array') unless Array.isArray(weight)
  throw new Error('list and weight must correspond') unless list.length == weight.length

  return null if list.length == 0

  logger.debug('Input list:', list)
  logger.debug('Input weight:', weight)

  total = weight.reduce((sum, value) -> sum + value)
  value = total * Math.random()

  logger.debug('Total weight =', total)
  logger.debug('Tossed weight =', value)

  index = -1

  for w, i in weight
    value -= w
    if value < 0
      index = i
      break

  if index < 0
    logger.info('Every weight in list', list, 'is zero')
    index = Math.floor(exports.random(weight.length))

  logger.debug('Total count =', list.length)
  logger.debug('Selected index =', index)

  return list[index]

exports.randomShuffle = (list = [], count = list.length) ->
  throw new Error('list must be an array') unless Array.isArray(list)
  throw new Error('count must be an integer') unless isInteger(count)
  count = parseInt(count)
  throw new Error('count must be a non-negative integer') unless count >= 0

  len = list.length
  count = len if count > len

  return list if count == 0

  count--
  for e, i in list
    index = Math.floor(exports.random(len, i))
    list[i] = list[index]
    list[index] = e
    break if i >= count

  return list

exports.uniqueFilter = (value, index, self) ->
  return self.indexOf(value) == index

formulate = exports.formulate = (obj = {}, variables, rel = 'AND') ->
  if not Array.isArray(obj)
    if obj.var of variables
      name = variables[obj.var]
      parts = []
      if 'val' of obj
        if Array.isArray(obj.val)
          parts.push("#{name} IN (#{obj.val.join(',')})")
        else
          parts.push("#{name}=#{obj.val}")
      else
        if 'min' of obj
          parts.push("#{name}>=#{obj.min}")
        if 'max' of obj
          parts.push("#{name}<=#{obj.max}")
      if parts.length > 0
        return "(#{parts.join(' AND ')})"
    return ''
  else
    formula = (formulate(condition, variables) for condition in obj).filter((s) -> s).join(obj.rel ? rel)
    if formula
      return "(#{formula})"
    else
      return ''

jsonp = /^\s*[a-zA-Z_$]+[a-zA-Z0-9_$]*\s*\(\s*(.*)\s*\)[\s;]*$/
exports.jsonp = (str) ->
  return null if typeof str != 'string'
  match = jsonp.exec(str)
  return match[1] if match

exports.normalizeCurrency = (str, precision, min, max) ->
  return null if typeof str != 'string'
  return null if not isNumber(str)
  str = str.trim().replace(/^0*/g, '')
  str = "0#{str}" if str.length == 0 or str[0] == '.'
  pos = str.indexOf('.')
  if pos > 0
    str = str.replace(/0*$/g, '')
    str = str.substring(0, pos) if pos == str.length - 1
  if precision?
    return null if pos > 0 and str.length - pos - 1 > precision
  if min? or max?
    value = parseFloat(str)
    return null if min? and value < min or max? and value > max
  return str

exports.replyWithFile = (path, callback) ->
  return callback() if not path
  return JSON.parse(fs.readFileSync(path, 'utf8')) if not callback
  fs.readFile(path, 'utf8', (err, data) ->
    error = new Error('Read json file fail') if err
    callback(error, null) if error

    obj = JSON.parse(data)
    callback(null, obj)
  )

exports.validateRegId = (regid, failureCallback) ->
  regid = regid?.trim()
  #TODO regid length长度需要改变
  if not regid or regid.length < 63
    error = new Error("validateRegId failed #{regid}")
    logger.error(error)
    failureCallback?(error)
    return false
  return true

exports.validateDeviceToken = (apsToken, failureCallback) ->
  apsToken = apsToken?.trim()
  if not apsToken or apsToken?.length != 64
    error = new Error("validateDeviceToken failed #{apsToken}")
    logger.error(error)
    failureCallback?(error)
    return false
  return true

# return NaN or True or False
exports.versionValid = (version, minVersion, maxVersion, options) ->
  options = extend({
    lexicographical: false
    zeroExtend: true
  }, options or {})
  minVersion = version if not minVersion?
  maxVersion = version if not maxVersion?
  lexicographical = options.lexicographical
  zeroExtend = options.zeroExtend
  version = version.toString()
  minVersion = minVersion.toString()
  maxVersion = maxVersion.toString()

  versionParts = version.split('.') or []
  minVersionParts = minVersion.split('.') or []
  maxVersionParts = maxVersion.split('.') or []

  _isValidPart = (x) ->
    reg = if lexicographical then /^\d+[A-Za-z]*$/ else /^\d+$/
    return reg.test(x)

  if not versionParts.every(_isValidPart) or not minVersionParts.every(_isValidPart) or not maxVersionParts.every(_isValidPart)
    logger.error("Invalid version supported", version)
    return false

  if zeroExtend
    max = Math.max(versionParts.length, minVersionParts.length, maxVersionParts.length)
    versionParts.push('0') while max - versionParts.length > 0
    minVersionParts.push('0') while max - minVersionParts.length > 0
    maxVersionParts.push('0') while max - maxVersionParts.length > 0

  if not lexicographical
    versionParts = versionParts.map(Number)
    minVersionParts = minVersionParts.map(Number)
    maxVersionParts = maxVersionParts.map(Number)

  #return true if v1 >= v2
  _versionCompare = (v1, v2) ->
    for i, v of v1
      if v == v2[i]
        continue
      else if v > v2[i]
        return true
      else
        return false
    return true

  if _versionCompare(versionParts, minVersionParts) and _versionCompare(maxVersionParts, versionParts)
    return true
  else
    return false

exports.channelFilter = (context = {}, boolFilter, versionExclude) ->
  channel = context.channel if context.channel?
  version = context.version.toString() if context.version?
  if boolFilter
    switch parseInt(channel)
      when 1000
        return if version in versionExclude then true else false
      else
        return false
  else
    return false

exports.normalizeObjectId = (id, failureCallback = null) ->
  id = id.toString().trim().replace(/^0+/g, '')
  return id if mongoose.Types.ObjectId.isValid(id)

  if failureCallback?
    logger.warn("validateObjectId failed [%s]", id)
    logger.warn(new Error('validateObjectId failed').stack)
    failureCallback?(new Error('Bad Object id'))
  return false
