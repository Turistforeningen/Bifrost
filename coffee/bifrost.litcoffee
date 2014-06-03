    async     = require 'async'
    raven     = require 'raven'
    moment    = require 'moment'

    changelog = require './changelog'
    sync      = require './sync'

Configure the Raven client to connect to our
[Sentry](https://sentry.turistforeningen.no/turistforeningen/bifrost/) instance.

    exports.updated = []
    exports.counter = 0
    exports.sentry = sentry = new raven.Client process.env.SENTRY_DNS,
      stackFunction: Error.prepareStackTrace

Patch global exceptions. This way if something unanticipated happens we can log
it and hopefully fix it.

    sentry.patchGlobal (isError, err) ->
      console.error err
      console.error err.stack
      process.exit 1

Get timestamp for when Bifröst was last run. We are only interesed in what has
changed in mean time. If the file does not exist, set the date to some time this
year.

    try
      lastrun = new Date parseInt require('fs').readFileSync 'data/LASTUPDATE', encoding: 'utf8'
    catch e
      lastrun = '2014-03-01'

Make [Moment.js](https://github.com/moment/moment) date objects for the date
stamps to make them easier to handle.

    lastrun = moment(lastrun)

Ok, we are done with the setup. Now, run this part forever.

    async.forever (next) ->

Fetch a list of changed items from the `sherpa2.changelog` postgres table. We
are only interested in items `inserted`, `updated`, and `deleted` for the data
types in Nasjonal Turbase since last run.

      console.log '-------------------'
      console.log "Fetching logs since #{lastrun.format('YYYY-MM-DD HH:mm:ss')}"
      changelog.get lastrun, (err, logs) ->

In case the changelog retrival failed; log this to Sentry and exit with code
`1`.

        return next err if err

Everything looks fine, lets just log the numnber of logs in queue for debug
purposes.

        sentry.captureMessage 'Bifröst is running', level: 'debug', logs: logs.length
        console.log "There are #{logs.length} new logs"

We use [Async.js](https://github.com/caolan/async) for congestion control when
syncronizing the changed items to Nasjonal Turbase. We are only processing `3`
items at the same time.

        async.eachLimit logs, 3, sync.toTurbasen, (err) ->

In case the syncronization to Nasjonal Turbase failed; log this to Sentry and
exit with code `1`.

          return next err if err

Before exiting we update the `LASTRUN` file with the current timestamp so we
wont have to syncronize the same items next run.

          if logs.length > 0
            lastrun = moment(moment(logs[logs.length-1].time).valueOf()+1)

          console.log "Writing to file: #{lastrun.format('YY-MM-DD HH.mm:ss')}"
          require('fs').writeFileSync 'data/LASTUPDATE', lastrun.valueOf(),
            encoding: 'utf8'
            flag: 'w+'

This is to prevent memmory leakage. Whenever things are updated. Restart the
process so that we can free some memory.

          if exports.counter > 0
            console.log "Updated #{exports.counter} items."
            console.log "Shutting down in #{process.env.UPDATE_INTERVAL} seconds..."
            return setTimeout ->
              console.log 'Shutting down!'
              process.exit 1
            , process.env.UPDATE_INTERVAL * 1000

Before we run this again, lest reset the update cache and the counter.

          exports.updated = []
          exports.counter = 0

Now, sleep for `X` seconds before running again. The sleep time is defined by
the environment variable `UPDATE\_INTERVAL`.

          console.log "Sleeping #{process.env.UPDATE_INTERVAL} seconds..."
          setTimeout next, process.env.UPDATE_INTERVAL * 1000

This is the `async.forever` callback handler. This is only run if the block
above crashed or experienced some kind of error. Here we just log the error and
then exits. Supervisor will restart this.

    , (err) ->
      sentry.captureError err
      console.error err
      console.log "Shutting down in #{process.env.UPDATE_INTERVAL * 5} seconds..."
      return setTimeout ->
        console.log 'Shutting down!'
        process.exit 1
      , process.env.UPDATE_INTERVAL * 5 * 1000

