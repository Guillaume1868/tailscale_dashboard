# Tailscale Container Dashboard (v1.1.0)

A lightweight Sinatra-based web app that displays all Tailscale devices tagged with `tag:container`, and links them to their Tailnet DNS addresses.

Each container is displayed as a clickable link pointing to its FQDN:  
`<hostname>.your-tailnet.ts.net`

## Features

- **Responsive Grid Dashboard**: Minimal UI, looks great on desktop and mobile.
- **Connection Status**: Real-time online/offline indicator for each container.
- **Tailscale IPs**: Displays IPv4 and IPv6 addresses for quick reference.
- **Custom Ports**: Assign tags like `tag:port-8080` to automatically link directly to the correct port.
- **Search & Filter**: Real-time JavaScript search bar to filter nodes by name, hostname, or IP.
- **System Information**: Quickly displays the OS and Tailscale client version for each node.
- **Robust Error Handling**: Clean UI responses when the Tailscale API hits a rate limit or credentials are wrong.
- **Auto-Refresh**: Dashboard automatically updates every 60 seconds.

## Requirements

- Docker & Docker Compose

## Setup

### 1. Create Tailscale OAuth Client

Go to [Tailscale OAuth Settings](https://login.tailscale.com/admin/settings/oauth) and create a new client with the `devices:core:read` scope.  
Copy the **Client ID** and **Client Secret**.

### 2. Configure `.env`

Create a `.env` file in the project root:

```env
TS_CLIENT_ID=client-xxxxxxxxxxxxxx
TS_CLIENT_SECRET=tskey-client-xxxxxxxxxxxxxxxx
TAILNET_NAME=your-tailnet-name.ts.net
```

### 3. Start Docker Container
`docker compose up -d`

### 4. (Optional) Serve the App via Tailscale

If you want to access this dashboard **securely through your Tailnet**, you can use [`tailscale serve`](https://tailscale.com/kb/1223/tailscale-serve/):

#### Serve locally over Tailscale:

```bash
tailscale serve -bg http://localhost:4567
```

This will expose the app on your Tailnet with an HTTPS link like:  
`https://<machine-name>.your-tailnet.ts.net`

Tailscale will remember this configuration across reboots.

#### To disable:

```bash
tailscale serve --https=443 off
```
