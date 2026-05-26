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

  service["ports"].each do |port_value|
    if port_value.is_a?(Hash) && port_value["port"].to_s.match?(/^\d+$/)
      return port_value["port"].to_i
    end

    # Handle strings like "443", "tcp:443", or "443/tcp"
    if port_value.to_s.match(/(\d+)/)
      return port_value.to_s.match(/(\d+)/)[1].to_i
    end
  end

  nil
end

def build_service_url(clean_target, protocol, port)
  return "#" if clean_target.to_s.strip.empty?

  port_suffix = port && port.positive? && clean_target !~ /:\d+\z/ ? ":#{port}" : ""
  "#{protocol}#{clean_target}#{port_suffix}"
end

def build_tailnet_service_url(hostname, protocol, port)
  return "#" if hostname.to_s.strip.empty?
  # If hostname already looks like a full domain, use it; otherwise append the tailnet.
  host = hostname.include?('.') ? hostname : "#{hostname}.#{TAILNET}"
  port_suffix = port && port.positive? && host !~ /:\d+\z/ ? ":#{port}" : ""
  "#{protocol}#{host}#{port_suffix}"
end

def normalize_service(service)
  hostname = first_present(service["hostname"], service["name"], "Service").to_s
  raw_target = first_present(service["dnsName"], service["tailnetTarget"], service["name"], service["hostname"]).to_s

  # Strip leading svc: prefix for nicer display (case-insensitive)
  hostname = hostname.sub(/\Asvc:/i, '').strip
  raw_target = raw_target.sub(/\Asvc:/i, '').strip
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

  # Build link targeting the tailnet domain and respect the advertised port
  service_host = hostname
  service_url = build_tailnet_service_url(service_host, protocol, port)

  {
    "hostname" => hostname,
    "name" => service_host,
    "addresses" => addresses,
    "tags" => [],
    "lastSeen" => Time.now.utc.iso8601,
    "os" => "Service",
    "clientVersion" => service["protocol"].to_s.empty? ? "Published" : service["protocol"].to_s.upcase,
    "isService" => true,
    "servicePort" => port,
    "serviceUrl" => service_url
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

    # Use only VIP-style services returned under "vipServices" for the dashboard.
    services_raw = []
    if services_data["vipServices"].is_a?(Array)
      services_raw = services_data["vipServices"].map do |vip|
        {
          "name" => vip["name"],
          "hostname" => vip["name"],
          "ports" => (vip["ports"] || []).map { |p| p.to_s.match(/(\d+)/) ? p.to_s.match(/(\d+)/)[1] : p },
          "addresses" => vip["addrs"] || vip["addresses"] || vip["address"],
          "tags" => vip["tags"] || []
        }
      end
    end

    services = (services_raw || []).map { |service| normalize_service(service) }.sort_by do |service|
      service["hostname"].to_s.downcase
    end

    @vip_services = services
    @error = nil
  rescue => e
    @vip_services = []
    @error = e.message
  end

  erb :index
end
