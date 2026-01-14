#!/bin/sh

# folgende CRON jobs sind zum Betrieb notwendig:
# jeden Tag die Kontingente neu auffüllen
# 0 2 * * * echo "Kindersperre,123456789,60," > /mnt/sda1/allowed_passwords.txt
#
# alle 5 Minuten prüfen, ob noch Zeitguthaben vorhanden ist
# */5 * * * * /wwwnds/cgi-bin/firewall_time_control.sh


PASSWORD_FILE="/mnt/sda1/allowed_passwords.txt"
LOG_FILE="/mnt/sda1/firewall_time_control.log"


# POST-Daten einlesen
read POST_DATA

# Passwort extrahieren und einfach URL-dekodieren
PASSWORD="$(echo "$POST_DATA" | sed -n 's/^password=\(.*\)/\1/p' | sed 's/%20/ /g; s/%3A/:/g; s/%2F/\//g; s/%40/@/g')"

# HTTP-Header ausgeben
echo "Content-Type: text/html; charset=utf-8"
echo ""

echo "<html><head><meta charset=\"utf-8\"><title>Ergebnis</title></head><body>"

# Prüfen ob Passwort angegeben
if [ -z "$PASSWORD" ]; then
    echo "<p>❗ Kein Passwort eingegeben.</p>"
elif [ ! -f "$PASSWORD_FILE" ]; then
    echo "<p>❌ Passwortdatei nicht gefunden!</p>"
else
    # Passwort in Datei suchen (jetzt an zweiter Stelle!)
    LINE="$(grep -m1 ",$PASSWORD," "$PASSWORD_FILE")"

    if [ -n "$LINE" ]; then
        RULE_NAME_FIELD="$(echo "$LINE" | cut -d',' -f1)"
        PASSWORD_FIELD="$(echo "$LINE" | cut -d',' -f2)"
        MINUTES_FIELD="$(echo "$LINE" | cut -d',' -f3)"
        TIMESTAMP_FIELD="$(echo "$LINE" | cut -d',' -f4)"

        if [ "$PASSWORD" = "$PASSWORD_FIELD" ]; then
            echo "$(date +"%Y-%m-%d %H:%M:%S") - Login: Password $PASSWORD_FIELD" >> "$LOG_FILE"
            # wenn noch kein Zeitstempel vorhanden = erster login des Tages -> Zeitstempel setzen
            if [ -z "$TIMESTAMP_FIELD" ]; then
                # Neuen UTC-Zeitstempel erstellen
#                CURRENT_TIME="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
                CURRENT_TIME="$(date +"%Y-%m-%d %H:%M:%S")"
                # Direkt in der Datei ersetzen
                sed -i "s|^$RULE_NAME_FIELD,$PASSWORD_FIELD,$MINUTES_FIELD,|$RULE_NAME_FIELD,$PASSWORD_FIELD,$MINUTES_FIELD,$CURRENT_TIME|" "$PASSWORD_FILE"
                TIMESTAMP_FIELD="$CURRENT_TIME"
                # Firewall aktualisieren
                echo "<p>✅ Passwort korrekt. Zeitstempel wurde neu gesetzt, Internetzugang ist frei!</p>"
            else
            # Aktuelle Zeit in Sekunden seit Unix Epoch
            	START_TS="$(date -d "$TIMESTAMP_FIELD" +%s 2>/dev/null)"
                NOW_TS="$(date +%s)"
                ALLOWED_SECONDS=$((MINUTES_FIELD * 60))
            	REMAINDER_TS=$((START_TS + ALLOWED_SECONDS - NOW_TS))
		REMAINDER_M=$((REMAINDER_TS / 60))
		# wenn Zeitguthaben noch vorhanden, Restguthaben abspeichern und timestamp entfernen
                if [ "$REMAINDER_TS" -ge 1 ]; then
                    sed -i "s|^$RULE_NAME_FIELD,$PASSWORD_FIELD,$MINUTES_FIELD,$TIMESTAMP_FIELD|$RULE_NAME_FIELD,$PASSWORD_FIELD,$REMAINDER_M,|" "$PASSWORD_FILE"
                    echo "<p>✅ Passwort korrekt. Zeitstempel war schon vorhanden, Restzeit $REMAINDER_M, Internetzugang ist gesperrt.</p>"
                # wenn kein Zeitguthaben mehr vorhanden, keine Änderung des Status vornehmen
                else
                    echo "<p>✅ Passwort korrekt. Zeitstempel war schon vorhanden, kein Restguthaben vorhanden. Internetzugang bleibt gesperrt.</p>"
                fi
            fi
            sh /wwwnds/cgi-bin/firewall_time_control.sh

            # ➡️ Online-Zeit, Startzeitpunkt und Firewall-Regel anzeigen
            echo "<h3>Details:</h3>"
            echo "<ul>"
            echo "<li>Firewall-Rule: <strong>$RULE_NAME_FIELD</strong></li>"
            echo "<li>Erlaubte Online-Zeit: <strong>$MINUTES_FIELD Minuten</strong></li>"
            echo "<li>Start-Zeitpunkt (UTC): <strong>$TIMESTAMP_FIELD</strong></li>"
            echo "</ul>"

        else
            echo "<p>❌ Passwort falsch.</p>"
        fi
    else
        echo "<p>❌ Passwort nicht gefunden.</p>"
    fi
fi

echo '<p><a href="/index.html">Zurück</a></p>'
echo "</body></html>"
