module.exports.responseMiddleware = responseMiddleware(req, res, next) ->
  res.apiSuccess = (result) ->
    res.json({ error: null, result: result })

  res.apiError = (exception) ->
    res.json({ error: exception, result: null })

  next();







