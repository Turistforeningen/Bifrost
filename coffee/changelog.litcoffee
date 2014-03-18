## exports.get()

Get changelogs since given date.

### Params

* `Moment` since - changelogs to fetch since date.
* `function` cb - callback function (`Error` err, `Object` res).

### Return

Returns `undefined`.

    exports.get = (since, cb) ->
      pg = require 'pg'

      client = new pg.Client process.env.SH2_PG_CON
      client.connect (err) ->
        return cb err if err

        sql = "SELECT l.lg_object AS sh2_type, l.lg_object_id AS sh2_id,
                l.lg_action AS act, ntb.oid AS ntb_id, l.lg_timestamp AS time
              FROM log AS l
              LEFT JOIN ntb_id AS ntb
                ON ntb.type = upper(substring(l.lg_object from 1 for 1))
                  AND ntb.id = l.lg_object_id::int
              WHERE
                (l.lg_object IN ('#{['cabin2', 'group', 'location2', 'trip'].join("','")}')
                  OR (l.lg_object = 'image' AND l.lg_action = 'delete'))
                AND l.lg_timestamp > '#{since.zone('+02:00').format("YYYY-MM-DD HH:mm:ss")}'
              ORDER BY l.lg_timestamp ASC"

        console.log sql
        module.parent.exports.sentry.captureQuery sql, 'psql', level: 'debug'

        client.query sql, (err, res) ->
          cb err, res?.rows or null
          client.end()

## exports.sh2ntb()

Get Nasjonal Turbase data type for Sherpa2 data type.

### Params

* `string` type - Sherpa2 data type.

### Return

Returns a `String` with corresponding type if found; otherwise `undefined`.


    exports.sh2ntb = (type) ->
      {
        cabin2    : 'steder'
        trip      : 'turer'
        location2 : encodeURIComponent('områder')
        group     : 'grupper'
        image     : 'bilder'
      }[type]

