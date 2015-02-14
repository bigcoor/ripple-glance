fs = require('fs')
nconf = require('nconf')
_ = require("underscore")

config = new nconf.Provider()

config
.argv()
.env()

console.log("Loading configs...")

configPath = __dirname + '/configs/' + (config.get("NODE_ENV") || 'dev') + '.json'

if fs.existsSync configPath
  console.log("Using json from " + configPath)
  config.file file: configPath
else
  console.log("No file at " + configPath)

config.defaults
  'NODE_ENV': 'dev'
  'VERBOSE': true
  'ROOT_DIR': __dirname
  'PORT': 3000

_.each(['ROOT_DIR', 'NODE_ENV', 'PORT', 'MONGO'], (ele) ->
  process.stdout.write("  " + ele + ": ")
  console.log(config.get(ele))
)

module.exports = config