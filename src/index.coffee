# Some module requires
redis = require "redis"
_ = require "underscore"

# Begin the happy thing!
# How we do it: 
# We cache the original mongoose.Query.prototype.execFind function, 
# and replace it with this version that utilizes Redis caching. 
# 
# For more information, get on to the readme.md! 


# Let's start the party!

mongooseRedisCache = (mongoose, options, callback) ->
  options ?= {}

  # Setup redis with options provided
  host = options.host || ""
  port = options.port || ""
  pass = options.pass
  database = options.database
  redisOptions = options.options || {}

  mongoose.redisClient = client = redis.createClient port, host, redisOptions

  client.auth(pass, callback) if pass
  client.select(database) if database

  # Cache original exec function so that 
  # we can use it later
  mongoose.Query::_uncachedExec = mongoose.Query::exec

  # Replace original function with this version that utilizes
  # Redis caching when executing finds. 
  # Note: We only use this version of execution if it's a lean call, 
  # meaning we don't cast each object to the Mongoose schema objects! 
  # Also this will only enabled if user had specified cache: true option 
  # when creating the Mongoose Schema object! 

  mongoose.Query::exec = (callback) ->
    self = this
    model = @model
    query = @_conditions
    options = @_optionsForExec(model)
    fields = _.clone @_fields

    schemaOptions = model.schema.options
    expires = schemaOptions.expires || 60

    # We only use redis cache of user specified to use cache on the schema,
    # and it will only execute if the call is a lean call.
    if !schemaOptions.redisCache || options.nocache
      return mongoose.Query::_uncachedExec.apply(self, arguments)

    delete options.nocache

    key = @model.modelName + JSON.stringify(query) + JSON.stringify(options) + JSON.stringify(fields || '*')

    client.get key, (err, result) ->
      return callback(err) if err

      if result
        # Key is found, yay! Return the baby!
        docs = JSON.parse(result)
        return callback(null, docs)

      # If the key is not found in Redis, executes Mongoose original
      # exec() function and then cache the results in Redis

      mongoose.Query::_uncachedExec.call self, (err, docs) ->
        return callback(err) if err
        str = JSON.stringify(docs)
        client.setex(key, expires, str)
        callback(null, docs)

    return @

  return

# Just some exports, hah.
module.exports = mongooseRedisCache
