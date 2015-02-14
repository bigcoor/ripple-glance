_                = require 'underscore'
Doc              = require './doc'
config           = require './config'
userAuth         = require './user_auth'
parameterChecker = require './parameter_checker'
apiResponse      = require './api_response'
authenticate = require './authenticate'

module.exports = (app, version) ->
  self = {}
  path = null

  self.version = version
  self.doc = new Doc()

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