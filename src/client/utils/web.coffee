exports.getAjaxErrorHandler = (callback, context) ->
    return (request, type, errorThrown) ->
      switch type
        when 'timeout'
          message = "The request timed out."
          break
        when 'notmodified'
          message = "The request was not modified but was not retrieved from the cache."
          break
        when 'parsererror'
          message = "XML/Json format is bad."
          break
        else
          message = "HTTP Error #{request.status} #{request.statusText}."

      callback new Error(message)