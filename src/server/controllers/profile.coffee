_ = require 'underscore'

format = require '../utils/format'
config = require '../utils/config'

class Profile
  constructor: ->

  #TODO build super class
  buildRequestOption: (type, queryStr) ->
    if queryStr?
      _url = "#{@lmApi[type]}?#{queryString.stringify(queryStr)}"
    else
      _url = @lmApi[type]
    {
      url: _url
      headers:
        'content-type': 'application/json'
    }

  getBlacklistInfo: (queryStr, context = {}, callback) ->
    request.get @buildRequestOption('getBlacklistInfo', queryStr), callback

profile = new Profile(config)