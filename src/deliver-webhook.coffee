_ = require 'lodash'
TokenManager = require 'meshblu-core-manager-token'
http = require 'http'

class MessageWebhook
  constructor: (options={},dependencies={}) ->
    {@cache,@datastore,pepper,uuidAliasResolver,@privateKey} = options
    {@request} = dependencies
    @request ?= require 'request'
    @tokenManager = new TokenManager {@cache, @datastore, pepper, uuidAliasResolver}
    @HTTP_SIGNATURE_OPTIONS =
      keyId: 'meshblu-webhook-key'
      key: @privateKey
      headers: [ 'date', 'X-MESHBLU-UUID' ]

  _doCallback: (request, code, callback) =>
    response =
      metadata:
        responseId: request.metadata.responseId
        code: code
        status: http.STATUS_CODES[code]
    callback null, response

  do: (request, callback) =>
    {auth, messageType, options, route} = request.metadata
    {uuid} = auth
    message = JSON.parse request.rawData

    @_send {uuid, messageType, options, message, route}, (error) =>
      return callback error if error?
      return @_doCallback request, 204, callback

  _send: ({uuid, messageType, options, message, route}, callback=->) =>
    deviceOptions = _.omit options, 'generateAndForwardMeshbluCredentials', 'signRequest'
    if options.generateAndForwardMeshbluCredentials
      @tokenManager.generateAndStoreTokenInCache uuid, (error, token) =>
        bearer = new Buffer("#{uuid}:#{token}").toString('base64')
        options =
          auth:
            bearer: bearer
        @_doRequest {deviceOptions, messageType, options, message, route, uuid}, (requestError) =>
          @tokenManager.removeTokenFromCache uuid, token, (error) =>
            return callback error if error?
            return callback requestError if requestError?
            callback()
      return

    @_doRequest {deviceOptions, messageType, message, route, uuid}, callback

  _doRequest: ({deviceOptions, messageType, options, message, route, uuid}, callback) =>
    message ?= {}
    options = _.defaults json: message, deviceOptions, options
    options.headers ?= {}
    options.httpSignature = @HTTP_SIGNATURE_OPTIONS if @privateKey? && !options.generateAndForwardMeshbluCredentials

    options.headers['X-MESHBLU-MESSAGE-TYPE'] = messageType
    options.headers['X-MESHBLU-ROUTE'] = JSON.stringify(route) if route?
    options.headers['X-MESHBLU-UUID'] = uuid

    @request options, (error) =>
      return callback error if error?
      callback()

module.exports = MessageWebhook
