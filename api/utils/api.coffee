_                = require 'underscore'
Doc              = require './doc'
config           = require '../config'
userAuth         = require './user_auth'
parameterChecker = require './parameter_checker'
actionFilter     = require './action_filter'
apiResponse      = require './api_response'

module.exports = (app, version) ->
  self = {}
  path = null

  self.version = version
  self.doc = new Doc()
  self.logUserAction = (req, res, next) ->
    return next() if not req.user

  date = new Date()
  cloneHash = null

  cloneHash = (obj) ->
    res = {}
    for k, v of obj
      res[k] = v

    delete res.password
    delete res.confirmPassword

    return res

#update lastSeen
#we have to do this synchronously, otherwise there's a race condition due to Mongoose versioning
#if req.user.lastSeeen is updated first, it'll bump up the __version.
#subsequent operations on the user will throw a version error (since req.user is then outdated)

  req.user.lastSeen = date
  req.user.save (err, user) ->
    req.user = user
    next()

  self.printJsonResultMiddleware = (req, res, next) ->
  oldJson = res.json

  res.json = ->
    if arguments.length == 2
      code = arguments[0]
      data = arguments[1]
    else
      code = 200
      data = arguments[0]

    console.log('res.json')
    console.log(' > ' + code);
    console.log(data);

    oldJson.apply(res, [ code, data ])

    next()

  self.printRequestParamsMiddleware = (req, res, next) ->
    console.log(req.method + ' ' + req.url)
    if req.user
      console.log(' * user   : ' + req.user.id)
      console.log(' * token  : ' + req.header('token'))

    if req.params
      console.log(' * params : ')
      console.log(req.params)

    if req.body
      console.log(' * body   : ')
      console.log(req.body)

    next()

  _.each([ 'get', 'post', 'put', 'delete' ], (verb) ->
    self[verb] = ->
      route = arguments[0]
      options = {}
      handler = null
      middleware = []

      if arguments.length == 2
        handler = arguments[1]
      else if arguments.length == 3
        options = arguments[1]
        handler = arguments[2]

    middleware.push(self.printJsonResultMiddleware) if config.get('VERBOSE')
    middleware.push(apiResponse.responseMiddleware)
    middleware.push(userAuth.setUserFromToken)
    middleware.push(userAuth.requireUser) if options.requireUser
    middleware.push(new parameterChecker(options.requireParameters)) if options.requireParameters
    middleware.push(self.logUserAction)
    middleware.push(self.printRequestParamsMiddleware) if config.get('VERBOSE')

    path = if self.version? then "/#{self.version}#{route}" else route

    app[verb](path, middleware, handler)

    self.doc.endpoint(verb.toUpperCase(), self.version + route, options)
  )

  self.group = ->
    name = arguments[0]
    options = null
    block = null
    groupDoc = new Doc()
    oldDoc = self.doc

    if arguments.length == 2
      block = arguments[1];
    else if arguments.length == 3
      options = arguments[1]
      block = arguments[2]

    self.doc = groupDoc
    block(self)

    self.doc = oldDoc

    self.doc.section(name, groupDoc)

  return self