Sentry = require('raven').Client

module.exports = new Sentry process.env.SENTRY_DNS,
  stackFunction: Error.prepareStackTrace

if process.env.SENTRY_DNS
  module.exports.patchGlobal (isError, error) ->
    console.error error.message
    console.error error.stack
    process.exit 1
