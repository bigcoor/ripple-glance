express = require 'express'
https = require 'https'
http = require 'http'
fs = require 'fs'

app = require '../build/server/intranet'
config = require '../build/server/utils/config'

http.createServer(app).listen(3000)