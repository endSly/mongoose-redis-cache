# Some module requires
redis = require "redis"
_ = require "underscore"

# Begin the happy thing!
# How we do it: 
# We cache the original mongoose.Query.prototype.execFind function, 
# and replace it with this version that utilizes Redis caching. 
# 
# How to use: 
# 1. Setup mongoose connect as usual: 
#
#   mongoose = require("mongoose");
#   mongoose.connect("mongodb://localhost/mongoose-redis-test")
#
# 2. Create your schemas as usual: 
#
#   var ExampleSchema = new Schema(function(){
#      field1: String
#      field2: Number
#      field3: Date
#   });
# 
# 3. Enable redisCache on the schema! 
#   
#   REQUIRED: Enable Redis caching on this schema by specifying
#
#       ExampleSchema.set('redisCache', true)
#
#   OPTIONAL: Change the time for the cache of this schema. Defaults to 60 seconds. 
# 
#       ExampleSchema.set('expires', 30)
#
# 4. Register the schema as usual: 
#     
#     Example = mongoose.model('Example', ExampleSchema)
#
# 5. Setup your mongooseCache options
#
#    mongooseRedisCache = require("mongoose-redis-cache");
#    mongooseRedisCache(mongoose, {
#       host: "redisHost",
#       port: "redisPort",
#       pass: "redisPass",
#       options: "redisOptions"
#     })
# 
# 6. Make a query! 
#     
#    query = Example.find({}) 
#    query.where("field1", "foo")
#    query.where("field2").gte(30)
#    query.lean() # REQUIRED, Redis cache only works for query.lean() queries!
#    query.exec(function(err, result){
#       # Do whatever here! 
#    });


# Let's start the party!

mongooseRedisCache = (mongoose, options) ->
  options ?= {}

  # Setup redis with options provided
  host = options.host || ""
  port = options.port || ""
  pass = options.pass || ""
  redisOptions = options.options || {}

  mongoose.redisClient = client = redis.createClient host, port, redisOptions

  if pass.length > 0
    client.auth pass

  # Cache original execFind function so that 
  # we can use it later
  mongoose.Query::_execFind = mongoose.Query::execFind

  # Replace original function with this version that utilizes
  # Redis caching when executing finds. 
  # Note: We only use this version of execution if it's a lean call, 
  # meaning we don't cast each object to the Mongoose schema objects! 
  # Also this will only enabled if user had specified cache: true option 
  # when creating the Mongoose Schema object! 

  mongoose.Query::execFind = (callback) ->
    self = this    
    model = @model
    query = @_conditions
    options = @_optionsForExec(model)
    fields = _.clone @_fields

    schemaOptions = model.schema.options
    expires = schemaOptions.expires || 60

    # We only use redis cache of user specified to use cache on the schema, 
    # and it will only execute if the call is a lean call. 
    if not schemaOptions.redisCache and options.lean
      return mongoose.Query::_execFind.apply self, arguments

    key = JSON.stringify(query) + JSON.stringify(options) + JSON.stringify(fields)
    
    arr = []
    
    cb = (err, result) ->
      if not result
        # If the key is not found in Redis, executes Mongoose original 
        # execFind() function and then cache the results in Redis

        mongoose.Query::_execFind.call self, (err, docs) ->
          if err then return callback err
          str = JSON.stringify docs
          client.set key, str
          client.expire key, expires
          callback null, arr
      else
        # Key is found, yay! Return the baby! 
        docs = JSON.parse(result)
        return callback null, arr
      
    client.get key, cb

    return @

  return

# Just some exports, hah. 
module.exports = mongooseRedisCache