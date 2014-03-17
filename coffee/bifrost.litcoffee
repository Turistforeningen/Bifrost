    async     = require 'async'
    raven     = require 'raven'
    moment    = require 'moment'

    changelog = require './changelog'
    sync      = require './sync'

Configure the Raven client to connect to our
[Sentry](https://sentry.turistforeningen.no/turistforeningen/bifrost/) instance.

    client = new raven.Client process.env.SENTRY_DNS
    client.captureMessage 'Bifröst is running', level: 'debug'

Patch global exceptions. This way if something unanticipated happens we can log
it and hopefully fix it.

    client.patchGlobal (isError, err) ->
      console.error err
      process.exit 1

Get timestamp for when Bifröst was last run. We are only interesed in what has
changed in mean time. If the file does not exist, set the date to some time this
year.

    try
      lastrun = new Date parseInt require('fs').readFileSync 'LASTUPDATE', encoding: 'utf8'
    catch e
      lastrun = '2014-03-01'

Make [Moment.js](https://github.com/moment/moment) date objects for the date
stamps to make them easier to handle.

    lastrun = moment(lastrun).zone('+01:00')
    nextrun = moment().zone('+01:00')

Fetch a list of changed items from the `sherpa2.changelog` postgres table. We
are interested in items `inserted`, `update`, and `deleted` since last run.

    changelog.get lastrun, (err, logs) ->

In case the changelog retrival failed; log this to Sentry and exit with code
`1`.

      if err
        client.captureError err
        console.error err
        process.exit 1

Everything looks fine, lets just log the numnber of logs in queue for debug
purposes.

      client.captureMessage "There are #{logs.length} new logs", level: 'debug'
      console.log "There are #{logs.length} new logs"

We use [async](https://github.com/caolan/async) for congestion control when
syncronizing the changed items to Nasjonal Turbase. We are only processing `5`
items at the same time.

      async.eachLimit logs, 5, sync.toTurbasen, (err) ->

In case the syncronization to Nasjonal Turbase failed; log this to Sentry and
exit with code `1`.

        if err
          client.captureError err
          console.error err
          process.exit 1

Before exiting we update the `LASTRUN` file with the current timestamp so we
wont have to syncronize the same items next run.

        require('fs').writeFileSync 'LASTUPDATE', nextrun.valueOf(),
          encoding: 'utf8'
          flag: 'w+'

Lets log that Bifröst finished correctly and exit with code `0`.

        client.captureMessage 'Bifröst is finished', level: 'debug'
        console.log 'Bifröst is finished'
        process.exit 0
