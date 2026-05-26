require 'sinatra'
require 'net/http'
require 'json'
require 'dotenv/load'
require 'time'

TAILNET = ENV['TAILNET_NAME']
TS_CLIENT_ID = ENV['TS_CLIENT_ID']
TS_CLIENT_SECRET = ENV['TS_CLIENT_SECRET']
AUTH_SCHEME = %w[Bearer].first

# Token cache
$access_token = nil
$token_expires_at = Time.now - 60  # Expired by default

set :host_authorization, { permitted_hosts: [] }

def fetch_tailnet_resource(access_token, resource, allow_not_found: false)
  uri = URI("https://api.tailscale.com/api/v2/tailnet/#{TAILNET}/#{resource}")
  req = Net::HTTP::Get.new(uri)
  req['Authorization'] = "#{AUTH_SCHEME} #{access_token}"

  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
  return {} if allow_not_found && res.code == "404"
  raise "API Error (#{resource}): #{res.code} - #{res.message}" unless res.is_a?(Net::HTTPSuccess)

  JSON.parse(res.body)
end

def first_present(*values)
  values.find { |value| !value.to_s.strip.empty? }
end

def extract_service_port(service)
  explicit_port = service["port"]
  return explicit_port if explicit_port.is_a?(Integer) && explicit_port.positive?
  return explicit_port.to_i if explicit_port.is_a?(String) && explicit_port.match?(/^\d+$/) && explicit_port.to_i.positive?
  return nil unless service["ports"].is_a?(Array)

  first_port = service["ports"].find do |port_value|
    port_value.to_s.match?(/^\d+$/) || (port_value.is_a?(Hash) && port_value["port"].to_s.match?(/^\d+$/))
  end

  return nil if first_port.nil?

  first_port.is_a?(Hash) ? first_port["port"].to_i : first_port.to_i
end

def build_service_url(clean_target, protocol, port)
  return "#" if clean_target.empty?

  port_suffix = port && port.positive? && clean_target !~ /:\d+\z/ ? ":#{port}" : ""
  "#{protocol}#{clean_target}#{port_suffix}"
end

def normalize_service(service)
  hostname = first_present(service["hostname"], service["name"], "Service").to_s
  raw_target = first_present(service["dnsName"], service["tailnetTarget"], service["name"], service["hostname"]).to_s
  clean_target = raw_target.sub(%r{\Ahttps?://}, "")
  protocol = if raw_target.start_with?("http://")
               "http://"
             elsif raw_target.start_with?("https://")
               "https://"
             elsif service["protocol"].to_s.downcase == "http"
               "http://"
             else
               "https://"
             end
  port = extract_service_port(service)

  # Handle current and legacy service payload field names.
  raw_addresses = service["addresses"] || service["addrs"] || service["address"]
  addresses = if raw_addresses.is_a?(Array)
                raw_addresses.map(&:to_s)
              elsif raw_addresses.to_s.empty?
                []
              else
                [raw_addresses.to_s]
              end

  {
    "hostname" => hostname,
    "name" => clean_target.empty? ? hostname : clean_target,
    "addresses" => addresses,
    "tags" => [],
    "lastSeen" => Time.now.utc.iso8601,
    "os" => "Service",
    "clientVersion" => service["protocol"].to_s.empty? ? "Published" : service["protocol"].to_s.upcase,
    "isService" => true,
    "servicePort" => port,
    "serviceUrl" => build_service_url(clean_target, protocol, port)
  }
end

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
  begin
    access_token = fetch_oauth_token

    services_data = fetch_tailnet_resource(access_token, 'services', allow_not_found: true)
    devices_data = fetch_tailnet_resource(access_token, 'devices')

    services = (services_data["services"] || []).map { |service| normalize_service(service) }.sort_by do |service|
      service["hostname"].to_s.downcase
    end

    tagged_devices = (devices_data["devices"] || []).select do |device|
      device["tags"].is_a?(Array) && device["tags"].include?("tag:container")
    end.sort_by do |device|
      first_present(device["hostname"], device["name"]).to_s.downcase
    end

    @devices = services + tagged_devices
    @error = nil
  rescue => e
    @devices = []
    @error = e.message
  end

  erb :index
end
