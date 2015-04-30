    async     = require 'async'

    librato   = require './librato'
    sentry    = require './sentry'

    changelog = require './changelog'
    worker    = require './worker'


    exports.queue = null

Get last log ID since Bifröst was las run.

    changelog.getLastId (err, min) ->
      throw err if err
      console.log "Read lastid=#{min} from Redis"

Get new tasks since the last log processed.

      changelog.getTasks min, (err, tasks, max) ->
        throw err if err

        console.log "#{tasks.length} new tasks"
        librato.measure 'tasks.new', tasks.length, {}

Make a queue and add the new tasks to it.

        exports.queue = async.queue worker, process.env.WORKERS or 4
        exports.queue.push tasks

This part is executed as soon as the last task in the queue has been completed.

        exports.queue.drain = (err) ->
          throw err if err

          console.log "Queue finsihed successfully!"
          console.log "Writing lastid=#{max} to Redis"
          changelog.setLastId max, (err) ->
            throw err if err

            console.log "Shutting down in #{process.env.UPDATE_INTERVAL} seconds..."
            return setTimeout ->
              console.log 'Shutting down!'
              process.exit 1
            , process.env.UPDATE_INTERVAL * 1000
