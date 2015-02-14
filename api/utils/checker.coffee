_  = require('underscore')

module.exports =  ParameterChecker(requiredParameters) ->
  return (req, res, next) ->

  requiredParameterKeys =
    if requiredParameters instanceof Array then requiredParameters else _.keys(requiredParameters)

  passedParams = _.union(_.keys(req.params), _.keys(req.query), _.keys(req.body))
  unpassedParams = _.difference(requiredParameterKeys, passedParams)

  if unpassedParams.length > 0
    res.json(400, {error: 'missing parameters ' + unpassedParams})
  else
    next()