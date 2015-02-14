express = require('express')
path = require('path')
bcrypt = require('bcrypt')
bodyParser = require('body-parser')
morgan = require('morgan')
cookieParser = require('cookie-parser')
methodOverride = require('method-override')
cookieSession  = require('cookie-session')
stylus = require('stylus')
serveStatic = require('serve-static')
app = express()
router = express.Router()

app.set('views', __dirname + '/views')
app.set('view engine', 'jade')

app.use(bodyParser.json())
app.use(morgan('dev'))
app.use(bodyParser.urlencoded({ extended: false }))
app.use(cookieParser())
app.use(methodOverride())
app.use(cookieSession({secret: "qwertyuopkjsdfm", cookie: { maxAge: 1000 * 60 * 60 * 24 }}))
app.use(require('stylus').middleware(__dirname + '/public'))
app.use(serveStatic(path.join(__dirname, '/public')))

app.use(router)

require('./routes')(app)

module.exports = app