#https://github.com/konklone/konklone.com
#https://demo.yubico.com/u2f?
require 'sinatra'
require 'sinatra/base'
require "sinatra/reloader"
require 'u2f'
require 'pp'
require 'erb'
require 'base64'
require 'mongoid'


def javascript_include_tag(filename)
 return '<script src="/javascripts/' + filename +'.js?'+ rand.to_s[2..11]  +'" type="text/javascript"></script>'
end


  use Rack::Session::Cookie,
    key: 'rack.session',
    path: '/',
    expire_after: (60 * 60 * 24 * 30),
    secret: "joeyoung"


Mongoid.load!("mongoid.yml", :development)


class Device
  include Mongoid::Document
  include Mongoid::Timestamps
  field :key_handle
  field :certificate
  field :public_key
  field :counter
  validates_presence_of :key_handle
  validates_presence_of :certificate
  validates_presence_of :public_key
  validates_presence_of :counter
  index key_handle: 1
end



def u2f
  @u2f ||= U2F::U2F.new(request.base_url)
end

configure :development do
    register Sinatra::Reloader
  end

enable :sessions
set :views, File.dirname(__FILE__) + '/views'
set :public_folder, File.dirname(__FILE__) + '/public'

get '/' do
	pp File.dirname(__FILE__) + '/public'
  send_file  'public/index.html'
end

get '/registrations/new' do

	puts u2f.registration_requests.to_json_without_active_support_encoder
	@registration_requests = u2f.registration_requests
	session[:challenges] = @registration_requests.map(&:challenge)
	#puts "session chal-->"
	#pp session[:challenges]
	devices = Device.all
  	key_handles = devices.map &:key_handle
    @sign_requests = u2f.authentication_requests(key_handles)
	erb :'register'

end


post '/registrations' do




	response = U2F::RegisterResponse.load_from_json(params[:response])
	puts "session chal<--"
	pp session[:challenges]
	puts "=---------="
	reg = begin
      u2f.register!(session[:challenges], response)
    rescue U2F::Error => e
      @error_message = "Unable to register: #{e.class.name}"
    ensure
      session.delete(:challenges)
    end

    Device.create!(
      certificate: reg.certificate,
      key_handle:  reg.key_handle,
      public_key:  reg.public_key,
      counter:     reg.counter)


erb :'registerindex'
 end







get '/authentication/new' do

	devices = Device.all
  	key_handles = devices.map &:key_handle
	return 'Need to register first' if key_handles.empty?
	@sign_requests = u2f.authentication_requests(key_handles)
    session[:challenges] = @sign_requests.map(&:challenge)


erb :'authenication'
end



 post '/authentications' do
    response = U2F::SignResponse.load_from_json(params[:response])

#    registration = Registration.first(key_handle: response.key_handle)
	device = Device.where(key_handle: response.key_handle).first
    return 'Need to register first' unless device

    begin
      u2f.authenticate!(session[:challenges], response,
                        Base64.decode64(device.public_key),
                        device.counter)
    rescue U2F::Error => e
      @error_message = "Unable to authenticate: #{e.class.name}"
    ensure
      session.delete(:challenges)
    end
    @counter = device.counter
    #registration.update(counter: response.counter)
    device.update(counter: response.counter)
    erb :'authenticationsindex'
  end








