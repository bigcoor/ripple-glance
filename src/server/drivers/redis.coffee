redis = require('redis')

logger = require('../utils/log').getLogger('REDIS')
utils = require('../utils/routines')
config = require '../utils/config'

hostname = config['Redis'].hostname
port = config['Redis'].port
db = config['Redis'].db
password = config['Redis'].password


selectDB = (client, db) ->
  client.select(db, (err) ->
    throw new Error('Failed to select db', db)
  )

# redis client automatically reconnects to last successful db
exports.create = create = (host = 'localhost', db = 0, port = 6379, name = utils.randomString(), options = {}) ->
  client = redis.createClient(port, host, utils.extendNew(options, {
    parser: 'hiredis',
    # return_buffers=true return js mode
    return_buffers: false,
    detect_buffers: false,
    socket_nodelay: true,
    no_ready_check: false,
    enable_offline_queue: true, # redis client flush offline queue with error whenever connect fails
                                # so the offline queue won't grow unlimitly
                                # and command callback are bound to run
    retry_max_delay: 1000, # retry at least once per second
    connect_timeout: false, # let redis client keep trying
    max_attempts: null, # let redis client keep trying
    connect_timeout: null, # let redis client keep trying, it's total timeout, not for a single connect
    command_queue_high_water: 1000, # no real impact
    command_queue_low_water: 0,
    debug: true
  }, true))

  client.auth(password, (err) -> logger.error("Auth redis failed.") if err?) if password?
  client.on('connect', -> logger.info(name, 'connected'))
  client.on('reconnecting', (stats) -> logger.verbose(name, 'reconnecting', stats))
  client.on('ready', -> logger.verbose(name, 'ready'))
  client.on('end', -> logger.warn(name, 'disconnected'))
  client.on('error', (err) -> logger.caught(err, name, 'error occurred'))

  if utils.parseInt(db, 0, 0) != 0
    if client.options.enable_offline_queue
      selectDB(client, db)
    else
      client.once('ready', -> selectDB(client, db))

  return client

exports.redisClient = create(hostname, db, port, null, {})
exports.redisPubClient = create(hostname, db, port, null, {})
exports.redisSubClient = create(hostname, db, port, null, {})