express = require 'express'
https = require 'https'
http = require 'http'
fs = require 'fs'

app = express()
app.use (req, res, next) ->
  res.setHeader('Access-Control-Allow-Headers', 'X-Requested-With,content-type')
  res.setHeader('Access-Control-Allow-Methods', 'GET')
  res.setHeader('Access-Control-Allow-Credentials', true)
  # Pass to next layer of middleware
  next()

app.use express.static(__dirname + '/../build/web/')

http.createServer(app).listen(3000)
console.log('This server is for development only! Do not use in production!')