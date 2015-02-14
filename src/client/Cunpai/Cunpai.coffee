
config = require "../utils/config.coffee"
webUtil = require "../utils/web.coffee"

class Cunpai
  constructor: ->
    @config = config

  getBlacklist: (url, callback) ->
    url = "/#{url}" if url?.indexOf('/') != 0

    $.ajax(
      url: @config.API + url
      dataType: 'json'
      timeout: 8000
    ).success((data) ->
      setImmediate( ->
        $scope.$apply(
          if data.success
            callback(null, data)
          else
            callback(new Error("Incorrect Ripple name or password."))
        )
      )
    ).error(webUtil.getAjaxErrorHandler(callback, "Cunpai Blacklist GET"))

module.exports = Cunpai