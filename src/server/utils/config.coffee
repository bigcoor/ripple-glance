fs = require('fs')
nconf = require('nconf')
_ = require("underscore")

config = new nconf.Provider()

config
.argv()
.env()

console.log("Loading configs...")

configPath = __dirname + '/../configs/' + (config.get("NODE_ENV") || 'dev') + '.json'
console.log(configPath)
if fs.existsSync configPath
  console.log("Using json from " + configPath)
  config.file file: configPath
else
  console.log("No file at " + configPath)

config.defaults
  'NODE_ENV': 'dev'
  'VERBOSE': true
  'PORT': 3000

_.each(['API', 'NODE_ENV', 'PORT'], (ele) ->
  process.stdout.write("  " + ele + ": ")
  console.log(config.get(ele))
)

module.exports = config