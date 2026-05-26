# Tailscale Container Dashboard (v2.0.0)

Each service is displayed as a clickable link pointing to its Tailnet FQDN and advertised port (when provided):

`https://<service-host>.<your-tailnet>.ts.net:PORT`

## Features

- **Responsive Grid Dashboard**: Minimal UI, looks great on desktop and mobile.
- **VIP Services Only**: Displays services returned in the `vipServices` payload from the Tailscale API.
- **Links Respect Advertised Port**: Service links are built using the advertised port when present.
- **Search & Filter**: Real-time JavaScript search bar to filter services by name, hostname, or IP.
- **System Information**: Displays the OS and Tailscale client/version metadata when available.
- **Robust Error Handling**: Clean UI responses when the Tailscale API hits a rate limit or credentials are wrong.
- **Auto-Refresh**: Dashboard automatically updates every 60 seconds.

## Requirements

- Docker & Docker Compose

## Setup

### 1. Create Tailscale OAuth Client

Go to [Tailscale OAuth Settings](https://login.tailscale.com/admin/settings/oauth) and create a new client with the `devices:core:read` and the `servives:read` scope.  
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

## Legacy note

This repository previously listed devices discovered by tag (`tag:container`). That behavior is available on the branch named `device-list`. If you rely on the older device-discovery behavior, check out that branch:

```bash
git checkout device-list
```

The current default branch focuses on published VIP services and will only display services present under the Tailscale API's `vipServices` response.
