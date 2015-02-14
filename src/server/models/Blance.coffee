mongoose = require('mongoose')
commons = require('mongoose-commons')

require('mongoose-long')(mongoose)

Schema = mongoose.Schema
SchemaTypes = Schema.Types

BalanceSchema = new Schema({
  userId: {type: Schema.ObjectId, ref: 'users'}
  currency: {type: String, trim: true}
  counterparty: {type: String, trim: true}
  value: {type: SchemaTypes.Long}
  time: {type: Date, default: new Date()}
}, {
  toObject: {virtuals: true}
  toJSON: {virtuals: true}
})

BalanceSchema.plugin(commons)

module.exports = mongoose.model('balances', BlanceSchema)