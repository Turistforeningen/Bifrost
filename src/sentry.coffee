Sentry = require('raven').Client

module.exports = new Sentry process.env.SENTRY_DNS,
  stackFunction: Error.prepareStackTrace

module.exports.patchGlobal (isError, error) ->
  console.error error.message
  console.error error.stack
  process.exit 1

