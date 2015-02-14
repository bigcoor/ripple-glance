module.exports = authenticate = (trust) ->
  return (req, res, next) ->
    return next() if trust
    uid = req.header('uid')
    token = req.header('token')
    limit = req.query.limit
    req.query.limit = utils.parseInt(limit, undefined, 0, 100) if limit?
    auth.validateSession(uid, token, (err, newToken) ->
      if err?
        res.setHeader('WWW-Authenticate', 'Credentials realm="bigcoor.com"')
        res.send(401)
      else
        res.once('header', -> res.setHeader('sessionToken', newToken))
        next()
    )