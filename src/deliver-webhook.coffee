_            = require 'lodash'
TokenManager = require 'meshblu-core-manager-token'
http         = require 'http'

class MessageWebhook
  constructor: (options) ->
    {datastore,@cache,pepper,uuidAliasResolver} = options
    @tokenManager = new TokenManager {datastore, pepper, uuidAliasResolver}

  _doCallback: (responseId, code, callback) =>
    response =
      metadata:
        responseId: responseId
        code: code
        status: http.STATUS_CODES[code]
    callback null, response

  do: (request, callback) =>
    {auth, forwardedRoutes, messageType, options, route, responseId} = request.metadata
    {uuid} = auth
    message = JSON.parse request.rawData

    @_send {forwardedRoutes, message, messageType, options, route, responseId, uuid}, callback

  _send: ({forwardedRoutes, message, messageType, options, route, responseId, uuid}, callback=->) =>
    { signRequest } = options
    deviceOptions = _.omit options, 'generateAndForwardMeshbluCredentials', 'signRequest'
    if options.generateAndForwardMeshbluCredentials
      @tokenManager.generateAndStoreToken {uuid}, (error, token) =>
        return callback error if error?
        delete options.generateAndForwardMeshbluCredentials
        @_doRequest {deviceOptions, forwardedRoutes, message, messageType, options, route, uuid, token}, (error) =>
          return callback error if error?
          @_doCallback responseId, 204, callback
      return

    @_doRequest {deviceOptions, forwardedRoutes, message, messageType, route, uuid, signRequest }, (error) =>
      return callback error if error?
      @_doCallback responseId, 204, callback

  _doRequest: ({deviceOptions, forwardedRoutes, message, messageType, options, route, uuid, token, signRequest }, callback) =>
    message ?= {}
    defaultOptions =
      json: message
      forever: true
      gzip: true

    requestOptions = _.defaults defaultOptions, deviceOptions, options
    requestOptions.headers ?= {}

    requestOptions.headers['X-MESHBLU-MESSAGE-TYPE'] = messageType
    requestOptions.headers['X-MESHBLU-ROUTE'] = JSON.stringify(route) if route?
    requestOptions.headers['X-MESHBLU-FORWARDED-ROUTES'] = JSON.stringify(forwardedRoutes) if forwardedRoutes?
    requestOptions.headers['X-MESHBLU-UUID'] = uuid

    _.set requestOptions, 'auth.bearer', new Buffer("#{uuid}:#{token}").toString('base64') if token?
    revokeOptions = { uuid }
    revokeOptions.token = token if token?
    signRequest ?= false
    data = JSON.stringify { requestOptions, revokeOptions, signRequest }
    @cache.lpush 'webhooks', data, callback

module.exports = MessageWebhook
