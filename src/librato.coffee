Librato = require 'librato'

module.exports = new Librato process.env.LIBRATO_USER, process.env.LIBRATO_TOKEN,
  prefix: process.env.LIBRATO_PREFIX
  source: process.env.DOTCLOUD_SERVICE_ID or 'test'

