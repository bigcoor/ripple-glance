utils = require './routines'

module.exports.parseText = parseText = (obj) ->
  try
    extra = JSON.parse(obj.text) ? {}
    extra.puid = utils.normalizeUserId(extra.puid) if extra.puid?
    for key in Object.keys(extra)
      val = extra[key]
      if val == undefined or val == null
        delete extra[key]
    return extra
  catch err
    return {}