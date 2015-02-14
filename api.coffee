app = require './api/app'
server = require('http').createServer(app)
mongoose = require 'mongoose'
config = require './config'

config.get('MONGO') && mongoose.connect(config.get('MONGO'));
server.listen(config.get('PORT'));