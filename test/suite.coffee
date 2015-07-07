assert = require 'assert'
request = require 'request'

process.env.SILENT = 'true'
process.env.SH2_API_URL = 'http://foo/'
process.env.SH2_API_KEY = '123'
process.env.NTB_API_URL = 'http://bar/'
process.env.NTB_API_KEY = 'abc'

sentry    = require '../src/sentry'
librato   = require '../src/librato'
postgres  = require '../src/postgres'
changelog = require '../src/changelog'

exports.queue = []

before (done) ->
  @timeout 10000
  postgres.on 'ready', done

beforeEach ->
  request.del = -> throw new Error 'DELETE not implemented'
  request.get = -> throw new Error 'GET not implemented'
  request.post = -> throw new Error 'POST not implemented'
  request.put = -> throw new Error 'put not implemented'

  sentry.captureMessage = -> return

  exports.queue = []

describe 'changelog', ->
  log = (action) ->
    return {
      act: action, sh2_type: 'trip', sh2_id: '127792'
      ntb_id: '5454ed6db67078876c002b88'
    }

  task = (method) ->
    return {
      retries: 5, method: method, errors: []
      from: id: '127792', type: 'trip'
      to: id: '5454ed6db67078876c002b88', type: 'turer'
    }

  describe 'setLastId()', ->
    it 'should set last id', (done) ->
      changelog.setLastId 40000600, (err) ->
        assert.ifError err
        done()

  describe 'getLastId()', ->
    it 'should get last id', (done) ->
      changelog.getLastId (err, id) ->
        assert.ifError err
        assert.equal id, 40000600
        done()

  describe 'act2method()', ->
    it 'delete => delete', ->
      assert.equal changelog.act2method('delete'), 'delete'

    it 'update => put', ->
      assert.equal changelog.act2method('update'), 'put'

    it 'insert => put', ->
      assert.equal changelog.act2method('insert'), 'put'

  describe 'sh2ntb()', ->
    it 'cabin2 => steder', ->
      assert.equal changelog.sh2ntb('cabin2'), 'steder'

    it 'trip => turer', ->
      assert.equal changelog.sh2ntb('trip'), 'turer'

    it 'location2 => områder', ->
      assert.equal changelog.sh2ntb('location2'), 'omr%C3%A5der'

    it 'image => bilder', ->
      assert.equal changelog.sh2ntb('image'), 'bilder'

  describe 'taskify()', ->
    it 'should return correct task for log', ->
      l = log 'update'
      t = task 'put'

      assert.deepEqual changelog.taskify(l), t

  describe 'logsToTasks()', ->
    it 'should return task for log', ->
      logs = [log('update')]
      tasks = [task('put')]

      assert.deepEqual changelog.logsToTasks(logs), tasks

    it 'should return tasks for logs', ->
      logs = [
        act: 'update', sh2_type: 'trip', sh2_id: '127792'
        ntb_id: '5454ed6db67078876c002b88'
      ,
        act: 'insert', sh2_type: 'cabin2', sh2_id: '133453'
        ntb_id: '5454ed6db67078876c002b89'
      ]

      tasks = [
        retries: 5, method: 'put', errors: []
        from: id: '127792', type: 'trip'
        to: id: '5454ed6db67078876c002b88', type: 'turer'
      ,
        retries: 5, method: 'put', errors: []
        from: id: '133453', type: 'cabin2'
        to: id: '5454ed6db67078876c002b89', type: 'steder'
      ]

      assert.deepEqual changelog.logsToTasks(logs), tasks

    it 'delete after delete => delete', ->
      logs = [log('delete'), log('delete')]
      tasks = [task('delete')]

      assert.deepEqual changelog.logsToTasks(logs), tasks

    it 'delete after update => delete', ->
      logs = [log('update'), log('delete')]
      tasks = [task('delete')]

      assert.deepEqual changelog.logsToTasks(logs), tasks

    it 'delete after insert => delete', ->
      logs = [log('insert'), log('delete')]
      tasks = [task('delete')]

      assert.deepEqual changelog.logsToTasks(logs), tasks

    it 'update after delete => delete', ->
      logs = [log('delete'), log('update')]
      tasks = [task('delete')]

      assert.deepEqual changelog.logsToTasks(logs), tasks

    it 'update after update => put', ->
      logs = [log('update'), log('update')]
      tasks = [task('put')]

      assert.deepEqual changelog.logsToTasks(logs), tasks

    it 'update after insert => put', ->
      logs = [log('insert'), log('update')]
      tasks = [task('put')]

      assert.deepEqual changelog.logsToTasks(logs), tasks

    it 'insert after delete => delete', ->
      logs = [log('delete'), log('insert')]
      tasks = [task('delete')]

      assert.deepEqual changelog.logsToTasks(logs), tasks

    it 'insert after update => put', ->
      logs = [log('update'), log('insert')]
      tasks = [task('put')]

      assert.deepEqual changelog.logsToTasks(logs), tasks

    it 'insert after insert => put', ->
      logs = [log('insert'), log('insert')]
      tasks = [task('put')]

      assert.deepEqual changelog.logsToTasks(logs), tasks

  describe 'getTasks()', ->
    it 'should return empty array for no results', (done) ->
      @timeout 10000
      changelog.getTasks 9999999, (err, tasks, max) ->
        assert.ifError err
        assert.deepEqual tasks, []
        done()

    it 'should return the input id for no results', (done) ->
      @timeout 10000
      changelog.getTasks 9999999, (err, tasks, max) ->
        assert.ifError err
        assert.equal max, 9999999
        done()

    it 'should return tasks since last log id', (done) ->
      @timeout 50000
      changelog.getTasks 1670648, (err, tasks, max) ->
        assert.ifError err
        assert tasks.length > 256
        done()

describe 'worker', ->
  task = worker = null

  before ->
    worker = require '../src/worker'

  beforeEach ->
    task =
      errors: []
      method: 'put'
      retries: 5
      from: id: 123, type: 'trip2'
      to: id: 'abc', type: 'turer'

  it 'should add to and from url to task', (done) ->
    task.retries = 1

    worker task, (err) ->
      assert.ifError err
      assert.equal typeof task.to.url, 'string'
      assert.equal typeof task.from.url, 'string'

      done()

  it 'should give up after 5 failed attempts', (done) ->
    task.retries = 1

    sentry.captureMessage = (message, options) ->
      assert.equal message, 'Retries exceeded for trip2:123'
      assert.equal options.level, 'error'
      assert.deepEqual options.extra.task, task

    worker task, (err) ->
      assert.ifError err
      assert.equal exports.queue.length, 0

      done()

  describe 'DELETE', ->
    beforeEach ->
      task.method = 'delete'

    it 'should send propper DELETE request', (done) ->
      request.del = (opts) ->
        assert.deepEqual opts, url: 'http://bar/turer/abc/?api_key=abc'
        setTimeout done, 0
        return on: -> return

      worker task

    it 'should handle request error', (done) ->
      request.del = (opts, cb) ->
        error = new Error 'HTTP FAKE ERROR'
        error.code = 'FAKE_ERR'

        setTimeout ->
          cb error
        , 0

        return on: -> return

      worker task, (err) ->
        assert.ifError err
        assert.equal task.errors[0], 'DELETE from NTB returned FAKE_ERR'
        assert.equal exports.queue.length, 1

        done()

    it 'should handle non 404 and 204 response code', (done) ->
      request.del = (opts, cb) ->
        setTimeout ->
          cb null, {statusCode: 500}, {}
        , 0

        return on: -> return

      worker task, (err) ->
        assert.ifError err
        assert.equal task.errors[0], 'DELETE from NTB returned 500'
        assert.equal exports.queue.length, 1

        done()

    it 'should log non 404 and 204 response code to Sentry', (done) ->
      request.del = (opts, cb) ->
        setTimeout ->
          cb null, {statusCode: 500}, {message: 'Inernal Server Error'}
        , 0

        return on: -> return

      sentry.captureMessage = (message, opts) ->
        assert.equal message, 'DELETE failed for trip2:123'
        assert.equal opts.level, 'error'
        assert.deepEqual opts.extra.task, task
        assert.deepEqual opts.extra.body, message: 'Inernal Server Error'
        assert.equal opts.extra.status, 500

      worker task, (err) ->
        assert.ifError err
        done()

    it 'should ignore 404 response code', (done) ->
      request.del = (opts, cb) ->
        setTimeout ->
          cb null, {statusCode: 404}, {message: 'Not Found'}
        , 0

        return on: -> return

      worker task, (err) ->
        assert.equal task.errors.length, 0
        assert.equal exports.queue.length, 0

        done()

    it 'should handle 204 response code', (done) ->
      request.del = (opts, cb) ->
        setTimeout ->
          cb null, {statusCode: 204}, {}
        , 0

        return on: -> return

      worker task, (err) ->
        assert.equal task.errors.length, 0
        assert.equal exports.queue.length, 0

        done()

  describe 'GET', ->
    it 'should decrement remaining retries', (done) ->
      request.get = ->
        assert.equal task.retries, 4
        setTimeout done, 0
        return on: -> return

      worker task

    it 'should send propper GET request', (done) ->
      request.get = (opts, cb) ->
        assert.equal opts.url, 'http://foo/trip2/123/?api_key=123'
        assert.equal opts.json, true
        setTimeout done, 0
        return on: -> return

      worker task

    it 'should handle request error', (done) ->
      request.get = (opts, cb) ->
        error = new Error 'HTTP FAKE_ERR'
        error.code = 'FAKE_ERR'

        setTimeout ->
          cb error, {}, {}
        , 0

        return on: -> return

      worker task, (err) ->
        assert.ifError err
        assert.equal task.errors[0], 'GET from sherpa2 returned FAKE_ERR'
        assert.equal exports.queue.length, 1

        done()

    it 'should handle response without body', (done) ->
      request.get = (opts, cb) ->
        setTimeout ->
          cb null, {}, {}
        , 0
        return on: -> return

      worker task, (err) ->
        assert.ifError err
        assert.equal task.errors[0], 'GET from sherpa2 returned no body'
        assert.equal exports.queue.length, 1

        done()

    it 'should handle 404 response code', (done) ->
      request.get = (opts, cb) ->
        setTimeout ->
          cb null, {statusCode: 404}, {err: 'NotFound'}
        , 0
        return on: -> return

      worker task, (err) ->
        assert.ifError err
        assert.equal task.errors.length, 0, 'there should be no errors'
        assert.equal exports.queue.length, 0, 'there should be no queue'

        done()

    it 'should handle non 200 response code', (done) ->
      request.get = (opts, cb) ->
        setTimeout ->
          cb null, {statusCode: 502}, {err: 'ProxyTimeout'}
        , 0
        return on: -> return

      worker task, (err) ->
        assert.ifError err
        assert.equal task.errors[0], 'GET from sherpa2 returned 502'
        assert.equal exports.queue.length, 1

        done()

  describe 'POST', ->
    beforeEach ->
      request.get = (opts, cb) ->
        setTimeout ->
          cb null, {statusCode: 200}, {foo: 'bar'}
        , 0
        return on: -> return

      task.method = 'post'

    it 'should send propper POST request', (done) ->
      request.post = (opts) ->
        assert.deepEqual opts,
          url: 'http://bar/turer/?api_key=abc'
          json: true
          body: foo: 'bar'

        setTimeout done, 0
        return on: -> return

      worker task

    it 'should handle 500 response code', (done) ->
      request.post = (opts, cb) ->
        setTimeout ->
          cb null, {statusCode: 500}, {message: 'KeyError'}
        , 0
        return on: -> return

      worker task, (err) ->
        assert.ifError err
        assert.deepEqual task.errors, [
          'post to NTB returned 500'
          'KeyError'
        ]
        assert.equal exports.queue.length, 0
        done()

    it 'should log 500 responses to Sentry', (done) ->
      request.post = (opts, cb) ->
        setTimeout ->
          cb null, {statusCode: 500}, {message: 'KeyError'}
        , 0
        return on: -> return

      sentry.captureMessage = (message, opts) ->
        assert.equal message, 'POST failed for trip2:123'
        assert.equal opts.level, 'error'
        assert.deepEqual opts.extra.task, task
        assert.deepEqual opts.extra.body, message: 'KeyError'
        assert.equal opts.extra.status, 500

      worker task, (err) ->
        assert.ifError err
        done()

    it 'should handle 200 response code', (done) ->
      request.post = (opts, cb) ->
        assert.equal opts.url, 'http://bar/turer/?api_key=abc'
        assert.equal opts.json, true
        assert.deepEqual opts.body, foo: 'bar'

        setTimeout done, 0
        return on: -> return

      worker task

  describe 'PUT', ->
    doc = null

    beforeEach ->
      doc = foo: 'bar'
      request.get = (opts, cb) ->
        setTimeout ->
          cb null, {statusCode: 200}, doc
        , 0
        return on: -> return

    it 'should send propper PUT request', (done) ->
      request.put = (opts, cb) ->
        assert.deepEqual opts,
          url: 'http://bar/turer/abc/?api_key=abc'
          json: true
          body: foo: 'bar'

        setTimeout done, 0
        return on: -> return

      worker task

    it 'should handle request error', (done) ->
      request.put = (opts, cb) ->
        error = new Error 'HTTP FAKE ERROR'
        error.code = 'FAKE_ERR'

        setTimeout ->
          cb error, {}, {}
        , 0

        return on: -> return

      worker task, (err) ->
        assert.ifError err
        assert.equal task.errors[0], 'put to NTB returned FAKE_ERR'
        assert.equal exports.queue.length, 1

        setTimeout done, 0
        return on: -> return

    it.skip 'should handle 403 response code'

    it 'should handle 404 response code', (done) ->
      request.put = (opts, cb) ->
        setTimeout ->
          cb null, {statusCode: 404}, {err: 'NotFound'}
        , 0
        return on: -> return

      worker task, (err) ->
        assert.ifError err

        assert.equal task.method, 'post'
        assert.equal task.errors[0], 'put to NTB returned 404'
        assert.equal exports.queue.length, 1

        done()

    it 'should handle 422 response code', (done) ->
      request.put = (opts, cb) ->
        setTimeout ->
          cb null, {statusCode: 422}, {message: 'Validation Error'}
        , 0
        return on: -> return

      worker task, (err) ->
        assert.ifError err

        assert.deepEqual task.errors, [
          'put to NTB returned 422'
          'Validation Error'
        ]
        assert.equal exports.queue.length, 0

        done()

    it 'should log validation errors to Sentry', (done) ->
      request.put = (opts, cb) ->
        setTimeout ->
          cb null, {statusCode: 422}, {message: 'Validation Error'}
        , 0
        return on: -> return

      sentry.captureMessage = (message, opts) ->
        assert.equal message, 'Validation failed for trip2:123'
        assert.equal opts.level, 'error'
        assert.deepEqual opts.extra.body, message: 'Validation Error'
        assert.equal opts.extra.status, 422

      worker task, (err) ->
        assert.ifError err
        done()

    it 'should handle 501 response code', (done) ->
      request.put = (opts, cb) ->
        setTimeout ->
          cb null, {statusCode: 501}, {message: 'HTTP method not implmented'}
        , 0
        return on: -> return

      worker task, (err) ->
        assert.ifError

        assert.equal task.method, 'post'
        assert.equal task.errors[0], 'put to NTB returned 501'
        assert.equal exports.queue.length, 1

        done()

    it 'should handle non 20x response code', (done) ->
      request.put = (opts, cb) ->
        setTimeout ->
          cb null, {statusCode: 502}, {err: 'ProxyTimeout'}
        , 0
        return on: -> return

      worker task, (err) ->
        assert.ifError

        assert.equal task.errors[0], 'put to NTB returned 502'
        assert.equal exports.queue.length, 1

        done()

    it 'should add any images to top of queue', (done) ->
      doc = bilder: [1, 2]

      request.put = (opts, cb) ->
        setTimeout ->
          cb null, {statusCode: 200}, {}
        , 0
        return on: -> return

      worker task, (err) ->
        assert.ifError

        assert.equal task.errors.length, 0
        assert.deepEqual exports.queue, [
          {
            retries: 5
            errors: []
            method: 'put'
            from: id: 2, type: 'image'
            to: id: 2, type: 'bilder'
          },{
            retries: 5
            errors: []
            method: 'put'
            from: id: 1, type: 'image'
            to: id: 1, type: 'bilder'
          }
        ]

        done()

    it 'should complete successfull', (done) ->
      request.put = (opts, cb) ->
        setTimeout ->
          cb null, {statusCode: 200}, {}
        , 0
        return on: -> return

      worker task, (err) ->
        assert.ifError

        assert.equal task.errors.length, 0
        assert.equal exports.queue.length, 0

        done()

