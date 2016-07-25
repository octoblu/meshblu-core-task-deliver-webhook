mongojs   = require 'mongojs'
Datastore = require 'meshblu-core-datastore'

{beforeEach, context, describe, it, sinon} = global
{expect} = require 'chai'

MessageWebhook = require '../'

describe 'MessageWebhook', ->
  beforeEach ->
    @request = sinon.stub().yields null, {statusCode: 200}
    @datastore = new Datastore
      database: mongojs 'token-manager-test'
      collection: 'things'
    @pepper = 'im-a-pepper'
    @privateKey = 'private-key'
    @uuidAliasResolver = resolve: (uuid, callback) => callback(null, uuid)

    options = {
      @privateKey,
      @datastore
      @uuidAliasResolver
      @pepper
    }

    dependencies = {@request}

    @sut = new MessageWebhook options, dependencies

  describe '->do', ->
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

      it 'should call request with whatever I want', ->
        expect(@request).to.have.been.calledWith
          url: 'http://example.com'
          headers:
            'X-MESHBLU-MESSAGE-TYPE': 'received'
            'X-MESHBLU-UUID': 'electric-eels'
          json: devices: '*'
          forever: true
          gzip: true

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

      it 'should call request with whatever I want', ->
        expect(@request).to.have.been.calledWith
          url: 'http://example.com'
          headers:
            'X-MESHBLU-MESSAGE-TYPE': 'message.received'
            'X-MESHBLU-ROUTE': '[{"from":"electric-eels","to":"electric-feels","type":"message.received"}]'
            'X-MESHBLU-FORWARDED-ROUTES': '[]'
            'X-MESHBLU-UUID': 'electric-eels'
          json: devices: '*'
          forever: true
          gzip: true

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

      it 'should call request with whatever I want', ->
        expect(@request).to.have.been.calledWith
          auth:
            bearer: "ZWxlY3RyaWMtZWVsczphYmMxMjM="
          url: 'http://example.com'
          headers:
            'X-MESHBLU-MESSAGE-TYPE': 'received'
            'X-MESHBLU-UUID': 'electric-eels'
          json: devices: '*'
          forever: true
          gzip: true

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

      it 'should call request with whatever I want', ->
        expect(@request).to.have.been.calledWith
          url: 'http://example.com'
          headers:
            'X-MESHBLU-MESSAGE-TYPE': 'received'
            'X-MESHBLU-UUID': 'electric-eels'
          httpSignature:
            keyId: 'meshblu-webhook-key'
            key: 'private-key'
            headers: [ 'date', 'X-MESHBLU-UUID' ]
          json: devices: '*'
          forever: true
          gzip: true

    context 'when the request yields an error', ->
      beforeEach (done) ->
        @request.yields new Error 'CONNECTION REFUSED'
        request =
          metadata:
            responseId: 'its-electric'
            auth: uuid: 'electric-eels'
            messageType: 'received'
            options:
              url: "http://example.com"
          rawData: '{"devices":"*"}'

        @sut.do request, (error, @response) => done error

      it 'should return a 422', ->
        expectedResponse =
          metadata:
            responseId: 'its-electric'
            code: 400
            status: 'Bad Request'
            error:
              message: 'CONNECTION REFUSED'

        expect(@response).to.deep.equal expectedResponse

      it 'should call request with whatever I want', ->
        expect(@request).to.have.been.calledWith
          url: 'http://example.com'
          headers:
            'X-MESHBLU-MESSAGE-TYPE': 'received'
            'X-MESHBLU-UUID': 'electric-eels'
          json: devices: '*'
          forever: true
          gzip: true
