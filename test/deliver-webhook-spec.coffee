mongojs   = require 'mongojs'
async     = require 'async'
RedisNS   = require '@octoblu/redis-ns'
Redis     = require 'ioredis'
Datastore = require 'meshblu-core-datastore'

{beforeEach, context, describe, it, sinon} = global
{expect} = require 'chai'

DeliverWebhook = require '../'

describe 'DeliverWebhook', ->
  beforeEach (done) ->
    client = new Redis 'localhost', dropBufferSupport: true
    client.on 'ready', =>
      @redis = new RedisNS 'test-webhooker', client
      @redis.del 'webhooks', done

  beforeEach (done) ->
    client = new Redis 'localhost', dropBufferSupport: true
    client.on 'ready', =>
      @redisClient = new RedisNS 'test-webhooker', client
      @redisClient.del 'webhooks', done

  beforeEach ->
    @datastore = new Datastore
      database: mongojs 'token-manager-test'
      collection: 'things'
    @pepper = 'im-a-pepper'
    @privateKey = 'private-key'
    @uuidAliasResolver = resolve: (_uuid, callback) => callback(null, _uuid)

    options = {
      @privateKey,
      @datastore
      @uuidAliasResolver
      @pepper
      @redisClient
    }

    @sut = new DeliverWebhook options

  describe '->do', ->
    context 'when given webhook when the queue length is too long', ->
      beforeEach (done) ->
        async.times 1001, (n, next) =>
          @redis.lpush 'webhooks', '{"some":"thing"}', next
        , done

      beforeEach (done) ->
        request =
          metadata:
            responseId: 'its-electric'
            auth: uuid: 'electric-eels'
            messageType: 'received'
            options:
              url: "http://example.com"
          rawData: '{"devices":"*"}'

        @sut.do request, (error, @response) => done error

      it 'should return a 503', ->
        expectedResponse =
          metadata:
            responseId: 'its-electric'
            code: 503
            status: 'Service Unavailable'

        expect(@response).to.deep.equal expectedResponse

    context 'when given a valid webhook', ->
      beforeEach (done) ->
        request =
          metadata:
            responseId: 'its-electric'
            auth: uuid: 'electric-eels'
            messageType: 'received'
            options:
              url: "http://example.com"
          rawData: '{"devices":"*"}'

        @sut.do request, (error, @response) => done error

      it 'should return a 204', ->
        expectedResponse =
          metadata:
            responseId: 'its-electric'
            code: 204
            status: 'No Content'

        expect(@response).to.deep.equal expectedResponse

      describe 'when pulling out the job', ->
        beforeEach (done) ->
          @redis.brpop 'webhooks', 1, (error, result) =>
            return done error if error?
            return done new Error 'request timeout' unless result?
            @data = JSON.parse result[1]
            done null
          return # redis fix

        it 'should have the request options', ->
          expect(@data.requestOptions).to.deep.equal
            url: 'http://example.com'
            headers:
              'X-MESHBLU-MESSAGE-TYPE': 'received'
              'X-MESHBLU-UUID': 'electric-eels'
            json: devices: '*'
            forever: true
            gzip: true

        it 'should have a revokeOptions.uuid', ->
          expect(@data.revokeOptions.uuid).to.exist

        it 'should not have a revokeOptions.token', ->
          expect(@data.revokeOptions.token).to.not.exist

        it 'should not have signRequest', ->
          expect(@data.signRequest).to.be.false

    context 'when given a route and forwardedRoutes', ->
      beforeEach (done) ->
        request =
          metadata:
            responseId: 'its-electric'
            auth: uuid: 'electric-eels'
            messageType: 'message.received'
            route: [{from: 'electric-eels', to: 'electric-feels', type: 'message.received'}]
            forwardedRoutes: []
            options:
              url: "http://example.com"
          rawData: '{"devices":"*"}'

        @sut.do request, (error, @response) => done error

      it 'should return a 204', ->
        expectedResponse =
          metadata:
            responseId: 'its-electric'
            code: 204
            status: 'No Content'

        expect(@response).to.deep.equal expectedResponse

      describe 'when pulling out the job', ->
        beforeEach (done) ->
          @redis.brpop 'webhooks', 1, (error, result) =>
            return done error if error?
            return done new Error 'request timeout' unless result?
            @data = JSON.parse result[1]
            done null
          return # redis fix

        it 'should have the request options', ->
          expect(@data.requestOptions).to.deep.equal
            url: 'http://example.com'
            headers:
              'X-MESHBLU-MESSAGE-TYPE': 'message.received'
              'X-MESHBLU-ROUTE': '[{"from":"electric-eels","to":"electric-feels","type":"message.received"}]'
              'X-MESHBLU-FORWARDED-ROUTES': '[]'
              'X-MESHBLU-UUID': 'electric-eels'
            json: devices: '*'
            forever: true
            gzip: true

        it 'should have a revokeOptions.uuid', ->
          expect(@data.revokeOptions.uuid).to.exist

        it 'should not have a revokeOptions.token', ->
          expect(@data.revokeOptions.token).to.not.exist

        it 'should not have signRequest', ->
          expect(@data.signRequest).to.be.false

    context 'when generating credentials', ->
      beforeEach (done) ->
        request =
          metadata:
            responseId: 'its-electric'
            auth: uuid: 'electric-eels'
            messageType: 'received'
            options:
              url: "http://example.com"
              generateAndForwardMeshbluCredentials: true
          rawData: '{"devices":"*"}'

        @sut.tokenManager._generateToken = sinon.stub().returns 'abc123'

        @sut.do request, (error, @response) => done error

      it 'should return a 204', ->
        expectedResponse =
          metadata:
            responseId: 'its-electric'
            code: 204
            status: 'No Content'

        expect(@response).to.deep.equal expectedResponse

      describe 'when pulling out the job', ->
        beforeEach (done) ->
          @redis.brpop 'webhooks', 1, (error, result) =>
            return done error if error?
            return done new Error 'request timeout' unless result?
            @data = JSON.parse result[1]
            done null
          return # redis fix

        it 'should have the request options', ->
          expect(@data.requestOptions).to.deep.equal
            auth:
              bearer: "ZWxlY3RyaWMtZWVsczphYmMxMjM="
            url: 'http://example.com'
            headers:
              'X-MESHBLU-MESSAGE-TYPE': 'received'
              'X-MESHBLU-UUID': 'electric-eels'
            json: devices: '*'
            forever: true
            gzip: true

        it 'should have a revokeOptions.uuid', ->
          expect(@data.revokeOptions.uuid).to.exist

        it 'should have a revokeOptions.token', ->
          expect(@data.revokeOptions.token).to.deep.equal 'abc123'

        it 'should not have signRequest', ->
          expect(@data.signRequest).to.be.false

    context 'when signRequest', ->
      beforeEach (done) ->
        request =
          metadata:
            responseId: 'its-electric'
            auth: uuid: 'electric-eels'
            messageType: 'received'
            options:
              url: "http://example.com"
              signRequest: true
          rawData: '{"devices":"*"}'

        @sut.tokenManager._generateToken = sinon.stub().returns 'abc123'

        @sut.do request, (error, @response) => done error

      it 'should return a 204', ->
        expectedResponse =
          metadata:
            responseId: 'its-electric'
            code: 204
            status: 'No Content'

        expect(@response).to.deep.equal expectedResponse

      describe 'when pulling out the job', ->
        beforeEach (done) ->
          @redis.brpop 'webhooks', 1, (error, result) =>
            return done error if error?
            return done new Error 'request timeout' unless result?
            @data = JSON.parse result[1]
            done null
          return # redis fix

        it 'should have the request options', ->
          expect(@data.requestOptions).to.deep.equal
            url: 'http://example.com'
            headers:
              'X-MESHBLU-MESSAGE-TYPE': 'received'
              'X-MESHBLU-UUID': 'electric-eels'
            json: devices: '*'
            forever: true
            gzip: true

        it 'should have a revokeOptions.uuid', ->
          expect(@data.revokeOptions.uuid).to.exist

        it 'should not have a revokeOptions.token', ->
          expect(@data.revokeOptions.token).to.not.exist

        it 'should have signRequest true', ->
          expect(@data.signRequest).to.be.true
