require 'sinatra'
require 'net/http'
require 'json'
require 'dotenv/load'
require 'time'

TAILNET = ENV.fetch('TAILNET_NAME', '').to_s.strip
TS_CLIENT_ID = ENV['TS_CLIENT_ID']
TS_CLIENT_SECRET = ENV['TS_CLIENT_SECRET']
AUTH_SCHEME = 'Bearer'

$access_token = nil
$token_expires_at = Time.at(0)

set :host_authorization, permitted_hosts: []

def fetch_oauth_token
  return $access_token if Time.now < ($token_expires_at - 60)

  uri = URI('https://api.tailscale.com/api/v2/oauth/token')
  req = Net::HTTP::Post.new(uri)
  req.set_form_data(
    'grant_type' => 'client_credentials',
    'client_id' => TS_CLIENT_ID,
    'client_secret' => TS_CLIENT_SECRET,
    'scope' => 'read:devices'
  )

  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
  raise "Token fetch failed: #{res.code} #{res.message}: #{res.body}" unless res.is_a?(Net::HTTPSuccess)

  body = JSON.parse(res.body)
  $access_token = body['access_token']
  $token_expires_at = Time.now + body.fetch('expires_in', 0).to_i
  $access_token
end

def fetch_vip_services(access_token)
  uri = URI("https://api.tailscale.com/api/v2/tailnet/#{TAILNET}/services")
  req = Net::HTTP::Get.new(uri)
  req['Authorization'] = "#{AUTH_SCHEME} #{access_token}"

  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
  raise "Services fetch failed: #{res.code} #{res.message}: #{res.body}" unless res.is_a?(Net::HTTPSuccess)

  JSON.parse(res.body)
end

def service_port(ports)
  values = Array(ports).map do |entry|
    match = entry.to_s.match(/(\d+)/)
    match && match[1].to_i
  end.compact

  return 443 if values.include?(443)
  return 80 if values.include?(80)
  values.first
end

def magicdns_host(service_name)
  clean_name = service_name.to_s.sub(/\Asvc:/i, '').strip
  return clean_name if clean_name.empty? || TAILNET.empty?

  "#{clean_name}.#{TAILNET}"
end

def build_service_url(service_name, ports)
  host = magicdns_host(service_name)
  return '#' if host.empty?

  port = service_port(ports)
  protocol = port == 80 ? 'http://' : 'https://'
  suffix = port && !((protocol == 'http://' && port == 80) || (protocol == 'https://' && port == 443)) ? ":#{port}" : ''
  "#{protocol}#{host}#{suffix}"
end

def normalize_service(vip)
  name = vip['name'].to_s
  {
    'title' => (vip['comment'].to_s.strip.empty? ? name.sub(/\Asvc:/i, '') : vip['comment'].to_s),
    'host' => magicdns_host(name),
    'name' => name,
    'ports' => Array(vip['ports']),
    'url' => build_service_url(name, vip['ports']),
    'port' => service_port(vip['ports'])
  }
end

get '/' do
  begin
    payload = fetch_vip_services(fetch_oauth_token)
    @services = Array(payload['vipServices']).map { |vip| normalize_service(vip) }
    @error = nil
  rescue => e
    @services = []
    @error = e.message
  end

  erb :index
end
