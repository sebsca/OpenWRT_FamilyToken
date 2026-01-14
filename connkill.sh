#!/bin/sh

# Usage: flush-fw4-macset.sh SETNAME
SET="$1"

LEASES="/tmp/dhcp.leases"

if [ -z "$SET" ]; then
  echo "Usage: $0 <fw4-mac-set-name>"
  exit 1
fi

if ! nft list set inet fw4 "$SET" >/dev/null 2>&1; then
  echo "Set '$SET' wurde nicht gefunden (table inet fw4)."
  exit 2
fi

echo "Verarbeite MAC-Set: $SET"

# MACs aus dem Set holen
MACS=$(nft list set inet fw4 "$SET" | awk '
  /elements/ {inset=1; next}
  inset {
    gsub(/[{},]/,"");
    if ($0 ~ /^[[:space:]]*$/) next;
    if ($0 ~ /}/) {inset=0; next}
    print tolower($0)
  }')

for mac in $MACS; do
  echo "  -> MAC $mac"

  IPs=""

  # 1) IPs aus ARP/Neighbor-Cache (IPv4 + IPv6)
  IPs="$IPs $(ip neigh show | awk -v m="$mac" 'tolower($0) ~ m {print $1}')"

  # 2) DHCP-Leases (falls vorhanden)
  if [ -f "$LEASES" ]; then
    IPs="$IPs $(awk -v m="$mac" 'tolower($2)==m {print $3}' "$LEASES")"
  fi

  # Duplikate entfernen
  IPs=$(echo "$IPs" | tr ' ' '\n' | sort -u | grep -v '^$')

  if [ -z "$IPs" ]; then
    echo "     (keine aktive IP zu dieser MAC gefunden)"
    continue
  fi

  for ip in $IPs; do
    echo "     -> lösche conntrack für IP $ip"
    case "$ip" in
      *:*)
        conntrack -f ipv6 -D -s "$ip" 2>/dev/null
        conntrack -f ipv6 -D -d "$ip" 2>/dev/null
        ;;
      *)
        conntrack -f ipv4 -D -s "$ip" 2>/dev/null
        conntrack -f ipv4 -D -d "$ip" 2>/dev/null
        ;;
    esac
  done
done

echo "Fertig."

