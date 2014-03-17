    pg = require 'pg'

    exports.get = (time, cb) ->
      client = new pg.Client process.env.SH2_PG_CON
      client.connect (err) ->
        return cb err if err

        sql = "SELECT l.lg_object AS sh2_type, l.lg_object_id AS sh2_id,
                l.lg_action AS act, ntb.oid AS ntb_id
              FROM log AS l
              LEFT JOIN ntb_id AS ntb
                ON ntb.type = upper(substring(l.lg_object from 1 for 1))
                  AND ntb.id = l.lg_object_id::int
              WHERE
                (l.lg_object IN ('#{['cabin2', 'group', 'location2', 'trip'].join("','")}')
                  OR (l.lg_object = 'image' AND l.lg_action = 'delete'))
                AND l.lg_timestamp > '2014-03-01'
              ORDER BY l.lg_timestamp ASC"

        client.query sql, (err, res) ->
          cb err, res.rows
          client.end()

