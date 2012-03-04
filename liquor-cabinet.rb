$LOAD_PATH << File.join(File.expand_path(File.dirname(__FILE__)), 'lib')

require "json"
require "sinatra/base"
require "sinatra/reloader"
require 'haml'

require "remote_storage/backend_interface"
require "remote_storage/riak"
require "remote_storage/couch_db"

class LiquorCabinet < Sinatra::Base
  BACKENDS = {
    :riak => ::RemoteStorage::Riak,
    :couchdb => ::RemoteStorage::CouchDB
  }

  class InvalidConfig < RuntimeError ; end

  def self.config=(config)
    @config = config
  end

  def self.config
    return @config if @config
    config = File.read(File.expand_path('config.yml', File.dirname(__FILE__)))
    @config = YAML.load(config)[ENV['RACK_ENV']]
  end

  configure :development do
    register Sinatra::Reloader
    enable :logging
  end

  configure :production do
    disable :logging
  end

  configure do
    backend = config['backend']
    unless backend
      raise InvalidConfig.new("backend not given for environment #{ENV['RACK_ENV']}")
    end
    backend_implementation = BACKENDS[backend.to_sym]
    unless backend_implementation
      raise InvalidConfig.new("Invalid backend: #{backend}. Valid options are: #{BACKENDS.keys.join(', ')}")
    end

    include(backend_implementation)
  end

  before "/:user/:category/:key" do
    headers 'Access-Control-Allow-Origin' => '*',
            'Access-Control-Allow-Methods' => 'GET, PUT, DELETE',
            'Access-Control-Allow-Headers' => 'Authorization, Content-Type, Origin'
    headers['Access-Control-Allow-Origin'] = env["HTTP_ORIGIN"] if env["HTTP_ORIGIN"]

    @user, @category, @key = params[:user], params[:category], params[:key]
    token = env["HTTP_AUTHORIZATION"] ? env["HTTP_AUTHORIZATION"].split(" ")[1] : ""

    authorize_request(@user, @category, token) unless request.options?
  end

  get "/ohai" do
    "Ohai."
  end

  get '/authenticate/:user' do
    @user = params[:user]
    @redirect_uri = params[:redirect_uri]
    haml :authenticate
  end

  post '/authenticate/:user' do
    if token = get_auth_token(params[:user], params[:password])
      redirect(build_redirect_uri(token))
    else
      @error = "Failed to authenticate! Please try again."
      haml :authenticate
    end
  end

  get "/:user/:category/:key" do
    content_type 'application/json'
    get_data(@user, @category, @key)
  end

  put "/:user/:category/:key" do
    data = request.body.read
    put_data(@user, @category, @key, data)
  end

  delete "/:user/:category/:key" do
    delete_data(@user, @category, @key)
  end

  options "/:user/:category/:key" do
    halt 200
  end

  helpers do
    def build_redirect_uri(token)
      [params[:redirect_uri],
       params[:redirect_uri].index('?') ? '&' : '?',
       'token=',
       URI.encode_www_form_component(token)].join
    end
  end

end
