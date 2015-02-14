module.exports = ->
  @data = []

  @section = (name, children) ->
    @data.push
      type: "section"
      name: name
      children: children

  @endpoint = (method, path, options) ->
    @data.push
      type: "endpoint"
      method: method
      path: path
      options: options or {}
