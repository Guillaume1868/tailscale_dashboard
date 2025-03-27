require 'sinatra'
require 'net/http'
require 'json'
require 'dotenv/load'

TAILNET = ENV['TAILNET_NAME']
TS_CLIENT_ID = ENV['TS_CLIENT_ID']
TS_CLIENT_SECRET = ENV['TS_CLIENT_SECRET']

# Token cache
$access_token = nil
$token_expires_at = Time.now - 60  # Expired by default

def fetch_oauth_token
  # Return cached token if it's still valid
  return $access_token if Time.now < $token_expires_at - 60  # Refresh 1 min early

  uri = URI("https://api.tailscale.com/api/v2/oauth/token")
  req = Net::HTTP::Post.new(uri)
  req.set_form_data(
    'grant_type' => 'client_credentials',
    'client_id' => TS_CLIENT_ID,
    'client_secret' => TS_CLIENT_SECRET,
    'scope' => 'read:devices'
  )

  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }

  raise "Token fetch failed: #{res.body}" unless res.is_a?(Net::HTTPSuccess)

  body = JSON.parse(res.body)
  $access_token = body["access_token"]
  $token_expires_at = Time.now + body["expires_in"].to_i

  $access_token
end

get '/' do

  access_token = fetch_oauth_token

  uri = URI("https://api.tailscale.com/api/v2/tailnet/#{TAILNET}/devices")
  req = Net::HTTP::Get.new(uri)
  req['Authorization'] = "Bearer #{access_token}"

  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }

  data = JSON.parse(res.body)
  @devices = data["devices"].select do |device|
    device["tags"]&.include?("tag:container")
  end

  erb :index
end