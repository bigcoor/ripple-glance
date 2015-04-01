mongoose = require('mongoose')
commons = require('mongoose-commons')

Schema = mongoose.Schema
SchemaTypes = Schema.Types

PaymentSchema = new Schema({
  userId: {type: Schema.ObjectId, ref: 'users'}
  currency: {type: String, trim: true}
  value: {type: Number}
  issuer: {type: String, trim: true}
  sourceAccount: {type: String, trim: true}
  destinationAccount: {type: String, trim: true}
  direction: {type: String, trim: true}
  timestamp: {type: Date}
  fee: {type: Number}
  ledger: {type: Number}
  hash: {type: String, trim: true}
  status: {type: Number}
}, {
  toObject: {virtuals: true}
  toJSON: {virtuals: true}
})

PaymentSchema.plugin(commons)

module.exports = mongoose.model('payment', PaymentSchema)

