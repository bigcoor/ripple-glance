mongoose = require('mongoose')
commons = require('mongoose-commons')

require('mongoose-long')(mongoose)

Schema = mongoose.Schema
SchemaTypes = Schema.Types

BalanceSchema = new Schema({
  userId: {type: Schema.ObjectId, ref: 'users'}
  ledger: {type: Number} #TODO, 可以移到用户表
  address: {type: String, trim: true}
  currency: {type: String, trim: true}
  counterParty: {type: String, trim: true}
  value: {type: String, trim: true}
  time: {type: Date, default: new Date()}
}, {
  toObject: {virtuals: true}
  toJSON: {virtuals: true}
})

#TODO, 用户可以拥有多个账号，但一个账号只属于一个用户；以后增加申请关注某账号的balance
BalanceSchema.index({address: 1, userId: -1}, {unique: true})
BalanceSchema.plugin(commons)

module.exports = mongoose.model('balances', BalanceSchema)