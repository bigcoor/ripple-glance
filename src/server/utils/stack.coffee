module.exports = ->
  array = []

  return {
    push: ->
      cb = arguments[arguments.length - 1]
      throw new Error('Missing callback') if typeof cb != 'function'
      elem = Array.prototype.slice.call(arguments, 0, -1)
      params = [null].concat(elem)
      array.push(elem)
      cb.apply(this, params)
    pop: ->
      cb = arguments[arguments.length - 1]
      throw new Error('Missing callback') if typeof cb != 'function'
      params = [null].concat(array.pop())
      cb.apply(this, params)
    popBefore: ->
      cb = arguments[arguments.length - 1]
      throw new Error('Missing callback') if typeof cb != 'function'
      params = [null].concat(array.pop(), Array.prototype.slice.call(arguments, 0, -1))
      cb.apply(this, params)
    popAfter: ->
      cb = arguments[arguments.length - 1]
      throw new Error('Missing callback') if typeof cb != 'function'
      params = [null].concat(Array.prototype.slice.call(arguments, 0, -1), array.pop())
      cb.apply(this, params)
  }
