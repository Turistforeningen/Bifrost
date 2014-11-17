EventEmitter = require('events').EventEmitter
PostgresClient = require('pg').Client
inherits = require('util').inherits

Postgres = (uri) ->
  EventEmitter.call @

  @client = new PostgresClient uri

  @client.connect (err) =>
    throw err if err

    @emit 'ready'

  @

inherits Postgres, EventEmitter

module.exports = new Postgres process.env.SH2_PG_CON

