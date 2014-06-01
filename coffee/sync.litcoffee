    request = require 'request'
    async = require 'async'
    changelog = require './changelog'

Sherpa2 and Turbasen API configurations.

    sh2 =
      url: process.env.SH2_API_URL
      key: process.env.SH2_API_KEY

    ntb =
      url: process.env.NTB_API_URL
      key: process.env.NTB_API_KEY

## exports.toTurbasen()

Syncronize change from Sherpa2 to Nasjonal Turbase.

### Params

* `object` item - Row from the changelog.
* `function` cb - Async.js callback function (`Error` err).

### Return

Return `undefined`.

    exports.toTurbasen = (item, cb) ->
      c = ++module.parent.exports.counter

      console.log c, item.act, item.sh2_type, item.sh2_id, item.time

      if item.act is 'delete'
        return deleteFromTurbasen changelog.sh2ntb(item.sh2_type), item.ntb_id, cb

      if item.ntb_id in module.parent.exports.updated
        console.log 'DUPLICATE', item.sh2_type, item.sh2_id
        return cb()

      module.parent.exports.updated.push item.ntb_id
      syncItemFromSherpa item.sh2_type, item.sh2_id, cb

## handleError()

Becuase UT-rivers are kicking of importing everything we sync as soon as it
happens the API exeriences a huge surge in traffic. This results in some
connections being reset by peer (`ECONNRESET`) and a few connection timeouts
(`ETIMEDOUT`).

This is not a problem in it self and we just need to wait a coupple of seconds
for the API to catch up with the traffic. We deal with this by suspending the
worker before restarting it.

The worker is suspended for `N * 2` seconds (where `N` is number of workers
currently suspended.

### Params

* `Error` err - error returned from [Request](https://github.com/mikeal/request).
* `function` fn - function where the error originated.
* `Array` args - function parameters for the original function.

### Return

Returns `undefined`.

    queue = 0
    handleError = (err, cb, fn, args) ->
      # return cb(err) if err.code not in ['ECONNRESET', 'ETIMEDOUT']
      module.parent.exports.sentry.captureError err, level: 'warning'
      console.error err
      console.error "#{err.code}: #{++queue} workers currently suspended."
      return setTimeout ->
        console.error "#{err.code}: Restarting worker. #{--queue} workers suspended."
        fn.apply null, args
      , (2000 * queue)

## syncItemFromSherpa()

Post item (not images) from Sherpa2 to Nasjonal Turbase.

This method is used to post new (insert) og changed (update) items from Sherpa2
to Nasjonal Turbase. This will also syncronize all images for the item.

### Params

* `string` type - Sherpa2 data-type.
* `Integer` id - Sherpa2 id.
* `function` cb - Async.js callback function (`Error` err).

### Return

Returns `undefined`.

    syncItemFromSherpa = (type, id, cb) ->
      from = sh2.url + type + '/' + id + '?api_key=' + sh2.key
      tooo = ntb.url + changelog.sh2ntb(type) + '?api_key=' + ntb.key

      errorHandler = (err) -> handleError err, cb, syncItemFromSherpa, [type, id, cb]

      request url: from, json: true, (err, res, body) ->
        return errorHandler err if err
        return cb() if not body # item not found

        request.post url: tooo, json: body, (err, res) ->
          return errorHandler err if err
          return cb(new Error('Post Failed')) if res.statusCode isnt 201
          return cb() if not body.bilder
          return async.eachLimit body.bilder, 3, syncImageFromSherpa, cb

## syncImageFromSherpa()

Post image from Sherpa2 to Nasjonal Turbase.

### Params

* `string` id - Nasjonal Turbase ObjectID.
* `function` cb - Async.js callback function (`Error` err).

### Return

Returns `undefined`.

    syncImageFromSherpa = (id, cb) ->
      from = sh2.url + 'image/' + id + '?api_key=' + sh2.key
      tooo = ntb.url + 'bilder/?api_key=' + ntb.key

      errorHandler = (err) -> handleError err, cb, syncImageFromSherpa, [id, cb]

      request(from)
        .on('error', errorHandler)
        .pipe(request.post(tooo))
        .on('error', errorHandler)
        .on('end', cb)

## deleteFromTurbasen()

Delete any item from Nasjonal Turbase.

### Params

* `string` type - Nasjonal Turbase object-type.
* `string` id - Nasjonal Turbase ObjectID.
* `function` cb - Async.js callback function (`Error` err).

### Return

Returns `undefined`.

    deleteFromTurbasen = (type, id, cb) ->
      url = ntb.url + type + '/' + id + '?api_key=' + ntb.key
      request.del url: url, json: true, (err, res, body) ->
        return handleError err, cb, deleteFromTurbasen, [type, id, cb] if err
        if not res.statusCode in [404, 204]
          return cb new Error("Unknown HTTP Status '#{res.statusCode}'")
        return cb()

