express = require('express')
mongoose = require('mongoose')
path = require('path')
bodyParser = require('body-parser')
morgan = require('morgan')
cookieParser = require('cookie-parser')
methodOverride = require('method-override')
cookieSession  = require('cookie-session')
stylus = require('stylus')
serveStatic = require('serve-static')
app = express()
router = express.Router()
config = require './utils/config'

config.setModuleDefaults('Web', {
  sizeLimit: '8kb'
})

sizeLimit = config['Web']?.sizeLimit
config.on('change', (newConfig) ->
  sizeLimit = config['Web']?.sizeLimit
)

app.set('views', __dirname + '/views')
app.set('view engine', 'jade')

app.use bodyParser.json()
app.use morgan('dev')
app.use bodyParser.urlencoded({ extended: false })
app.use cookieParser()
app.use methodOverride()
app.use cookieSession({secret: "qwertyuopkjsdfm", cookie: {maxAge: 1000 * 60 * 60 * 24}})
app.use serveStatic(path.join(__dirname + '/../web'))
app.use router

require('./api-authless')(app)
require('./api-private')(app)

# redis
require './cores/scheduler'

mongoConn = config['MongoDB'].mongo
mongoOpt = config['MongoDB'].options

if mongoConn?
  mongoose.connect(mongoConn, mongoOpt ? {})

module.exports = app