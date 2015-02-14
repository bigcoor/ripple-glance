mongoose = require('mongoose')
commons = require('mongoose-commons')
bcrypt = require('bcrypt')

logger = require('../utils/log').getLogger('USER')

require('mongoose-long')(mongoose)

Schema = mongoose.Schema
SchemaTypes = Schema.Types

AccessToken = new Schema({
  token: String
  lastView: Date
})

UserSchema = new Schema({
  wallet: {type: String, trim: true}
  password: {type: String, trim: true}
  phone: {type: String, trim: true}
  nick: {type: String, trim: true}
  icon: {type: String, trim: true}
  description: {type: String}
  lastSeen: {type: Date, default: new Date()}
  status: {type: Number, default: 0}
  accessTokens: [ AccessToken ]
}, {
  toObject: {virtuals: true}
  toJSON: {virtuals: true}
})

UserSchema.plugin(commons)

UserSchema.pre('save', (next) ->
  return next() if not @isModified('password')

  bcrypt.genSalt(SALT_WORK_FACTOR, (err, salt) ->
    return next(err) if err
  )
  bcrypt.hash(@password, salt, (err, hash) ->
    return next(err) if err
  )
  @password = hash
  next()
)

UserSchema.methods.generateAccessToken = (attrs, callback) ->
  token = crypto.randomBytes(24).toString('hex')

  accessToken = _.extend(attrs, { token: token, lastView: new Date().getTime()})

  @accessTokens = [] if not @accessTokens
  @accessTokens.push(accessToken)
  @save((err, user) ->
    callback(err, accessToken)
  )

module.exports = mongoose.model('users', UserSchema)