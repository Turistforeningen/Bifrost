    postgres = require './postgres'
    redis = require './redis'

## exports.getLastId()

    exports.getLastId = (cb) ->
      redis.get 'lastid', (err, id) ->
        cb err, id or 1852000

## exports.setLastId()

    exports.setLastId = (id, cb) ->
      redis.set 'lastid', id, cb

## exports.getTasks()

    exports.getTasks = (lid, cb) ->
      sql = "SELECT
              l.lg_id         AS lid,
              l.lg_object     AS sh2_type,
              l.lg_object_id  AS sh2_id,
              l.lg_action     AS act,
              ntb.oid         AS ntb_id
            FROM
              log AS l
            LEFT JOIN
              ntb_id AS ntb
                ON ntb.type = upper(substring(l.lg_object from 1 for 1))
                  AND ntb.id = l.lg_object_id::int
            WHERE
              l.lg_id > #{lid}
              AND (
                l.lg_object IN ('#{['cabin2', 'location2'].join("','")}')
                OR (l.lg_object = 'image' AND l.lg_action = 'delete')
              )
            ORDER
              BY l.lg_id ASC"

      postgres.client.query sql, (err, res) ->
        return cb err if err
        return cb null, [], lid if not res or not res.rows or not res.rows.length
        return cb null, exports.logsToTasks(res.rows), res.rows[res.rows.length-1].lid


## exports.logsToTasks()

    exports.logsToTasks = (rows) ->
      cache = {}

      for log in rows
        task = exports.taskify log
        key = "#{task.from.type}:#{task.from.id}"

        if not cache[key]
          cache[key] = task

        else
          if task.method is 'delete'
            cache[key] = task

      tasks = []
      tasks.push task for key, task of cache

      return tasks

## exports.taskify()

    exports.taskify = (log) ->
      return {
        retries: 5
        method: exports.act2method log.act
        errors: []
        from: id: log.sh2_id, type: log.sh2_type
        to: id: log.ntb_id, type: exports.sh2ntb log.sh2_type
      }

## exports.act2method()

    exports.act2method = (act) ->
      {
        delete: 'delete'
        update: 'put'
        insert: 'put'
      }[act]


## exports.sh2ntb()

    exports.sh2ntb = (type) ->
      {
        cabin2    : 'steder'
        trip      : 'turer'
        location2 : encodeURIComponent('områder')
        image     : 'bilder'
      }[type]

