_ = require 'lodash'

class MessageWebhook
  constructor: (options, dependencies={}) ->
    {@uuid, @options, @type, @privateKey, @tokenManager} = options
    {@request} = dependencies
    @request ?= require 'request'
    @HTTP_SIGNATURE_OPTIONS =
      keyId: 'meshblu-webhook-key'
      key: @privateKey
      headers: [ 'date', 'X-MESHBLU-UUID' ]

  generateAndForwardMeshbluCredentials: (callback=->) =>
    @tokenManager.generateAndStoreTokenInCache {@uuid}, callback

  send: (message, callback=->) =>
    if @options.signRequest && @privateKey?
      options =
        headers:
          'X-MESHBLU-UUID': @uuid
        httpSignature: @HTTP_SIGNATURE_OPTIONS
      @doRequest options, message, callback
      return

    if @options.generateAndForwardMeshbluCredentials
      @generateAndForwardMeshbluCredentials (error, token) =>
        bearer = new Buffer("#{@uuid}:#{token}").toString('base64')
        @doRequest auth: bearer: bearer, message, (error) =>
          @removeToken(token)
          callback error

      return

    @doRequest {}, message, callback

  doRequest: (options, message={}, callback) =>
    deviceOptions = _.omit @options, 'generateAndForwardMeshbluCredentials', 'signRequest'
    options = _.defaults json: message, deviceOptions, options
    options.headers ?= {}

    options.headers['X-MESHBLU-MESSAGE-TYPE'] = @type

    @request options, (error, response) =>
      return callback error if error?
      return callback new Error "HTTP Status: #{response.statusCode}" unless _.inRange response.statusCode, 200, 300
      callback()

  removeToken: (token) =>
    @token.removeTokenFromCache {@uuid, token}, (error) =>

module.exports = MessageWebhook
