mongoose = require('mongoose')
commons = require('mongoose-commons')
bcrypt = require('bcrypt')

logger = require('../utils/log').getLogger('USER')

Schema = mongoose.Schema
SchemaTypes = Schema.Types

AccessToken = new Schema({
  token: String
  lastView: Date
})

UserSchema = new Schema({
  wallet: {type: String, trim: true}
  password: {type: String}
  email: {type: String, trim: true, unique: true}
  phone: {type: String, trim: true, unique: true}
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

module.exports = mongoose.model('users', UserSchema)