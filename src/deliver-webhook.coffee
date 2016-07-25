_ = require 'lodash'
TokenManager = require 'meshblu-core-manager-token'
http = require 'http'

class MessageWebhook
  constructor: (options, dependencies={}) ->
    {datastore,pepper,uuidAliasResolver,@privateKey} = options
    { @request } = dependencies
    @request ?= require 'request'
    @tokenManager = new TokenManager {datastore, pepper, uuidAliasResolver}
    @HTTP_SIGNATURE_OPTIONS =
      keyId: 'meshblu-webhook-key'
      key: @privateKey
      headers: [ 'date', 'X-MESHBLU-UUID' ]

  _doCallback: (responseId, code, callback) =>
    response =
      metadata:
        responseId: responseId
        code: code
        status: http.STATUS_CODES[code]
    callback null, response

  _doRequestErrorCallback: (responseId, requestError, callback) =>
    response =
      metadata:
        responseId: responseId
        code: 400
        status: http.STATUS_CODES[400]
        error:
          message: requestError.message
    callback null, response

  do: (request, callback) =>
    {auth, forwardedRoutes, messageType, options, route, responseId} = request.metadata
    {uuid} = auth
    message = JSON.parse request.rawData

    @_send {forwardedRoutes, message, messageType, options, route, responseId, uuid}, callback

  _send: ({forwardedRoutes, message, messageType, options, route, responseId, uuid}, callback=->) =>
    deviceOptions = _.omit options, 'generateAndForwardMeshbluCredentials', 'signRequest'
    if options.generateAndForwardMeshbluCredentials
      @tokenManager.generateAndStoreToken {uuid}, (error, token) =>
        bearer = new Buffer("#{uuid}:#{token}").toString('base64')
        options =
          auth:
            bearer: bearer
        @_doRequest {deviceOptions, forwardedRoutes, message, messageType, options, route, uuid}, (requestError) =>
          @tokenManager.revokeToken {uuid, token}, (error) =>
            return callback error if error?
            return @_doRequestErrorCallback responseId, requestError, callback if requestError?
            return @_doCallback responseId, 204, callback
      return

    if @privateKey? && options.signRequest
      options = {httpSignature: @HTTP_SIGNATURE_OPTIONS}
      @_doRequest {deviceOptions, forwardedRoutes, message, messageType, options, route, uuid}, (requestError) =>
        return @_doRequestErrorCallback responseId, requestError, callback if requestError?
        return @_doCallback responseId, 204, callback
      return

    @_doRequest {deviceOptions, forwardedRoutes, message, messageType, route, uuid}, (requestError) =>
      return @_doRequestErrorCallback responseId, requestError, callback if requestError?
      return @_doCallback responseId, 204, callback

  _doRequest: ({deviceOptions, forwardedRoutes, message, messageType, options, route, uuid}, callback) =>
    message ?= {}
    defaultOptions =
      json: message
      forever: true
      gzip: true
    options = _.defaults defaultOptions, deviceOptions, options
    options.headers ?= {}

    options.headers['X-MESHBLU-MESSAGE-TYPE'] = messageType
    options.headers['X-MESHBLU-ROUTE'] = JSON.stringify(route) if route?
    options.headers['X-MESHBLU-FORWARDED-ROUTES'] = JSON.stringify(forwardedRoutes) if forwardedRoutes?
    options.headers['X-MESHBLU-UUID'] = uuid

    @request options, callback

module.exports = MessageWebhook
