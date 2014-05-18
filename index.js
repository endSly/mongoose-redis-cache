// Generated by CoffeeScript 1.6.3
(function() {
  var mongooseRedisCache, redis, _;

  redis = require("redis");

  _ = require("underscore");

  mongooseRedisCache = function(mongoose, options, callback) {
    var client, host, pass, port, redisOptions;
    if (options == null) {
      options = {};
    }
    host = options.host || "";
    port = options.port || "";
    pass = options.pass;
    redisOptions = options.options || {};
    mongoose.redisClient = client = redis.createClient(port, host, redisOptions);
    if (pass) {
      client.auth(pass, callback);
    }
    mongoose.Query.prototype._uncachedSearch = mongoose.Query.prototype.exec;
    mongoose.Query.prototype.exec = function(callback) {
      var cb, expires, fields, key, model, query, schemaOptions, self;
      self = this;
      model = this.model;
      query = this._conditions;
      options = this._optionsForExec(model);
      fields = _.clone(this._fields);
      schemaOptions = model.schema.options;
      expires = schemaOptions.expires || 60;
      if (!(schemaOptions.redisCache && !options.nocache && options.lean)) {
        return mongoose.Query.prototype._uncachedSearch.apply(self, arguments);
      }
      delete options.nocache;
      key = JSON.stringify(query) + JSON.stringify(options) + JSON.stringify(fields);
      cb = function(err, result) {
        var docs;
        if (err) {
          return callback(err);
        }
        if (!result) {
          return mongoose.Query.prototype._uncachedSearch.call(self, function(err, docs) {
            var str;
            if (err) {
              return callback(err);
            }
            str = JSON.stringify(docs);
            client.setex(key, expires, str);
            return callback(null, docs);
          });
        } else {
          docs = JSON.parse(result);
          return callback(null, docs);
        }
      };
      client.get(key, cb);
      return this;
    };
  };

  module.exports = mongooseRedisCache;

}).call(this);
