require 'active_support/core_ext/hash/indifferent_access'
require 'active_support/core_ext/object/to_query'
require 'erb'
require 'http'
require 'jwt'
require 'openssl'
require 'securerandom'
require 'sinatra/base'
require 'time'

class OpenidConnectRelyingParty < Sinatra::Base
  SERVICE_PROVIDER = 'http://localhost:3000'

  CLIENT_ID = 'urn:gov:gsa:openidconnect:sp:sinatra'

  get '/' do
    authorization_url = openid_configuration[:authorization_endpoint] + '?' + {
      client_id: CLIENT_ID,
      response_type: 'code',
      acr_values: 'http://idmanagement.gov/ns/assurance/loa/1',
      scope: 'openid email',
      redirect_uri: "http://localhost:9292/auth/result",
      state: SecureRandom.urlsafe_base64,
      prompt: 'select_account',
    }.to_query

    erb :index, locals: { authorization_url: authorization_url }
  end

  get '/auth/result' do
    token_response = token(params[:code])
    userinfo_response = userinfo(token_response[:access_token])

    erb :userinfo, locals: { userinfo: userinfo_response }
  end

  private

  def openid_configuration
    @openid_configuration ||= begin
      json(HTTP.get(URI.join(SERVICE_PROVIDER, '/.well-known/openid-configuration')))
    end
  end

  def token(code)
    jwt_payload = {
      iss: CLIENT_ID,
      sub: CLIENT_ID,
      aud: openid_configuration[:token_endpoint],
      jti: SecureRandom.urlsafe_base64,
      exp: Time.now.to_i + 1000,
    }

    jwt = JWT.encode(jwt_payload, private_key, 'RS256')

    json HTTP.post(
      openid_configuration[:token_endpoint],
      json: {
        grant_type: 'authorization_code',
        code: code,
        client_assertion_type: 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer',
        client_assertion: jwt
      }
    )
  end

  def userinfo(access_token)
    json HTTP.auth("Bearer #{access_token}").get(openid_configuration[:userinfo_endpoint])
  end

  def json(response)
    JSON.parse(response.to_s).with_indifferent_access
  end

  def private_key
    @private_key ||= OpenSSL::PKey::RSA.new(File.read('config/demo_sp.key'))
  end
end

