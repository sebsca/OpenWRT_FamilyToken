#!/bin/sh

PASSWORD_FILE="/mnt/sda1/allowed_passwords.txt"
LOG_FILE="/mnt/sda1/firewall_time_control.log"

# Aktuelle Zeit in Sekunden seit Unix Epoch
NOW_TS="$(date +%s)"

# Starte neuen Logeintrag
echo "$(date +"%Y-%m-%d %H:%M:%S") - Starte Firewall-Überprüfung" >> "$LOG_FILE"

# Jede Zeile verarbeiten
while IFS=',' read -r RULE_NAME PASSWORD ALLOWED_MINUTES START_TIME; do
    # Überspringen, wenn Zeile leer oder Kommentar
    [ -z "$RULE_NAME" ] && continue
    [ "${RULE_NAME#\#}" != "$RULE_NAME" ] && continue

    # Aktuellen Status der Firewall-Rule lesen
    RULE_ID=$(uci show firewall | grep ${RULE_NAME} | awk -F'.' '{ print $2 }')

    if [ -z "$RULE_ID" ]; then
        echo "$(date +"%Y-%m-%d %H:%M:%S") - Fehler: Firewall-Rule $RULE_NAME existiert nicht." >> "$LOG_FILE"
        continue
    else
        CURRENT_STATUS="$(uci get firewall.${RULE_ID}.enabled 2>/dev/null)"
        # Wenn "enabled" nicht gesetzt ist, dann ist default enabled="1"
        if [ -z "$CURRENT_STATUS" ]; then CURRENT_STATUS="1"
        fi
    fi

    TARGET_STATUS=0

    if [ -z "$START_TIME" ]; then
        # Keine Startzeit → Regel aktivieren
        echo "$(date +"%Y-%m-%d %H:%M:%S") - Keine Startzeit → Regel aktivieren" >> "$LOG_FILE"
        TARGET_STATUS=1
    else
        # Startzeitpunkt umwandeln
        START_TS="$(date -d "$START_TIME" +%s 2>/dev/null)"
        if [ -z "$START_TS" ]; then
            echo "$(date +"%Y-%m-%d %H:%M:%S") - Fehler: Ungültiger Startzeitpunkt bei $RULE_NAME: $START_TIME" >> "$LOG_FILE"
            # Im Fehlerfall lieber aktiv lassen
            TARGET_STATUS=1
        else
            # Ablaufzeitpunkt berechnen
            ALLOWED_SECONDS=$((ALLOWED_MINUTES * 60))
            EXPIRE_TS=$((START_TS + ALLOWED_SECONDS))
            
            echo "$(date +"%Y-%m-%d %H:%M:%S") - Rule $RULE_NAME: Now:$NOW_TS Start:$START_TS Allowed:$ALLOWED_SECONDS Expire:$EXPIRE_TS" Remaining:$((EXPIRE_TS - NOW_TS)) >> "$LOG_FILE"

            if [ "$NOW_TS" -ge "$EXPIRE_TS" ]; then
                # Zeit abgelaufen → Regel aktivieren
                TARGET_STATUS=1
            else
                TARGET_STATUS=0
            fi
        fi
    fi

    # Nur ändern, wenn sich Status ändert
    if [ "$CURRENT_STATUS" -ne "$TARGET_STATUS" ]; then
        uci set firewall.${RULE_ID}.enabled="$TARGET_STATUS"
        echo "$(date +"%Y-%m-%d %H:%M:%S") - Setze $RULE_NAME auf enabled=$TARGET_STATUS" >> "$LOG_FILE"
        FIREWALL_CHANGED=1
    fi

done < "$PASSWORD_FILE"

# Firewall neu laden, wenn Änderungen erfolgt sind
if [ "$FIREWALL_CHANGED" = "1" ]; then
    uci commit firewall >> "$LOG_FILE" 2>&1
    /etc/init.d/firewall reload >> "$LOG_FILE" 2>&1
    SCRIPT_DIR="$(dirname "$0")"
    "$SCRIPT_DIR/connkill.sh" Kinder >> "$LOG_FILE" 2>&1
    echo "$(date +"%Y-%m-%d %H:%M:%S") - Firewall neu geladen" >> "$LOG_FILE"
else
    echo "$(date +"%Y-%m-%d %H:%M:%S") - Keine Änderungen nötig" >> "$LOG_FILE"
fi
