# OpenWRT_FamilyToken

Time-limit for internet access with OpenWRT routers.

These scripts for OpenWRT allow you to restrict internet access for certain users for a limited period of time.

## What it does

Users receive a token that they can use to activate access for a predefined period of time via a landing page.

- Enter token once → access is activated for the configured time
- Enter token again before time expires → access is blocked and remaining time is credited for later
- Time credit is reset daily (or depending on your reset configuration)

The scripts and landing page are located in the `wwwnds` directory, which is copied to the router’s root directory (`/`).

## Who is this for?

This is for parents who want local, cloud-free time limits for their Kids on OpenWRT routers.

## How it works (high level)

1. A firewall rule blocks internet access for specific MAC addresses.
2. A cron job checks every 5 minutes whether access is activated and toggles the firewall accordingly.
3. Users visit the landing page, enter the token, and the cron-controlled script disables the firewall rule.
4. Once the time expires, the cron-controlled script re-enables the firewall and interrupts existing connections.
5. A second cron job rewrites the password file at night to reset time credits.

## Requirements

- OpenWRT router
- `conntrack` package (needed to interrupt existing connections when time expires)

## Installation

### 1) Copy files to the router

Copy the `wwwnds` directory to the router root:

- Target: `/wwwnds`

### 2) Configure paths in `check_password.sh`

Set the password file and log file paths.

> If no USB stick is connected, use `/tmp` to avoid flash wear (continuous writes to persistent storage will wear it out).

Example:

```sh
PASSWORD_FILE="/tmp/allowed_passwords.txt"
LOG_FILE="/tmp/firewall_time_control.log"
```

### 3) Configure uHTTPd

Recommended setup:

- Landing page on port **80**
- Admin interface (LuCI/uHTTPd main) on port **81**

Edit `/etc/config/uhttpd` and change the default server port:

```conf
config uhttpd 'main'
	list listen_http '0.0.0.0:81'
	...
```

Add a second web server instance for the landing page:

```conf
config uhttpd 'nds'
	list listen_http '0.0.0.0:80'
	option redirect_https '0'
	option home '/wwwnds'
	option rfc1918_filter '1'
	option max_requests '3'
	option max_connections '100'
	option cgi_prefix '/cgi-bin'
	option script_timeout '60'
	option network_timeout '30'
	option http_keepalive '20'
	option tcp_keepalive '1'
```

### 4) Create firewall rule

Create a traffic rule in:

**Network → Firewall → Traffic Rules**

This rule should block internet access for the relevant MAC addresses (the script will toggle it).

### 5) Add cron jobs

Go to:

**System → Scheduled Tasks**

**a) Periodic check (every 5 minutes):**

```cron
*/5 * * * * /wwwnds/cgi-bin/firewall_time_control.sh
```

**b) Daily reset (example at 02:00):**

```cron
0 2 * * * echo -e "Kindersperre,123456789,60,
Seb,abc,5," > /mnt/sda1/allowed_passwords.txt
```

This overwrites the password file and therefore also defines users, tokens, and time limits.

Format per line:

```
<FirewallRuleName>,<Token>,<MaxMinutes>,
```

Example:

- `Kindersperre,123456789,60,`
  - Firewall rule name: `Kindersperre`
  - Token/password: `123456789`
  - Max usage time: `60` minutes

**Important:** Don’t forget the trailing comma at the end of each line.

### 6) Install `conntrack`

Install via:

**System → Software**

Package name:

- `conntrack`

This is required to interrupt active connections when time expires.

## Optional: Local domain for landing page

You can configure a domain via:

**Network → DHCP and DNS → General → Addresses**

So users can reach the landing page via a friendly name (example shown in the original notes).

## Notes / Tips

- Consider storing password/log files on a USB drive if available.
- If you store them on internal flash, avoid frequent writes outside `/tmp`.

---

