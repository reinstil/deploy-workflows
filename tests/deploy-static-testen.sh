#!/usr/bin/env bash
# Testet Zielpfad-Prüfung und rsync-Regeln aus .github/workflows/deploy-static.yml.
# Die Skripte werden mit yq direkt aus dem Workflow gelesen, damit Test und Workflow nicht auseinanderlaufen.
# Braucht: bash, yq (mikefarah, auf GitHub-Runnern vorhanden), rsync.
# Aufruf: bash tests/deploy-static-testen.sh
# "test && ok || fehl" ist gewollt (ok endet nie mit Fehler); '$(id)' soll nicht expandieren
# shellcheck disable=SC2015,SC2016
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
WORKFLOW=.github/workflows/deploy-static.yml
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fehler=0
tests=0
ok()   { tests=$((tests + 1)); echo "ok   $1"; }
fehl() { tests=$((tests + 1)); fehler=$((fehler + 1)); echo "FEHL $1"; }

schritt() {
  yq -e ".jobs.deploy.steps[] | select(.name == \"$1\") | .run" "$WORKFLOW"
}

schritt "Zielpfad bestimmen" > "$TMP/zielpfad.sh" || { echo "Schritt 'Zielpfad bestimmen' fehlt"; exit 1; }
schritt "rsync-Regeln schreiben" > "$TMP/regeln.sh" || { echo "Schritt 'rsync-Regeln schreiben' fehlt"; exit 1; }

# Zielpfad-Skript so aufrufen wie GitHub (bash -e -o pipefail), Ergebnis: Pfad oder "FEHLER"
zielpfad() {
  local umgebung=$1 wert=$2 ausgabe="$TMP/output"
  : > "$ausgabe"
  if [ "$umgebung" = production ]; then
    env ENVIRONMENT=production PROD_PATH="$wert" STAGING_PATH= STAGING_SSH_USER= PROD_URL= STAGING_URL= \
      SSH_USER=test SSH_HOST=host GITHUB_OUTPUT="$ausgabe" \
      bash --noprofile --norc -eo pipefail "$TMP/zielpfad.sh" >/dev/null 2>&1 || { echo FEHLER; return; }
  else
    env ENVIRONMENT=staging STAGING_PATH="$wert" STAGING_SSH_USER=test PROD_PATH= PROD_URL= STAGING_URL= \
      SSH_USER=test SSH_HOST=host GITHUB_OUTPUT="$ausgabe" \
      bash --noprofile --norc -eo pipefail "$TMP/zielpfad.sh" >/dev/null 2>&1 || { echo FEHLER; return; }
  fi
  sed -n 's/^path=//p' "$ausgabe"
}

echo "# Zielpfad: erlaubt"
for p in public_html public_html/ public_html/relaunch kunde.de www.kunde-a.de/public_html public_html/kunde.de/sub_1; do
  for u in staging production; do
    erwartet=${p%/}
    [ "$(zielpfad "$u" "$p")" = "$erwartet" ] && ok "$u '$p'" || fehl "$u '$p' abgelehnt"
  done
done

echo "# Zielpfad: abgelehnt"
for p in "" . ./. ./ .. ../x / /home public_html/.. public_html/. public_html/.git public_html/.well-known \
         .ssh mail etc tmp ssl public_html//x "public_html/a b" "public_html/x'y" 'public_html/$(id)' \
         public_html/cgi-bin -rf kunde. .kunde.de Public_html public_html/x/../../.ssh public_htmlx; do
  [ "$(zielpfad production "$p")" = FEHLER ] && ok "production '$p'" || fehl "production '$p' durchgelassen"
done
# Staging ohne STAGING_PATH, aber mit Konto: Standard public_html
ausgabe="$TMP/output"; : > "$ausgabe"
env ENVIRONMENT=staging STAGING_PATH= STAGING_SSH_USER=test PROD_PATH= PROD_URL= STAGING_URL= SSH_USER=test SSH_HOST=host \
  GITHUB_OUTPUT="$ausgabe" bash --noprofile --norc -eo pipefail "$TMP/zielpfad.sh" >/dev/null 2>&1
[ "$(sed -n 's/^path=//p' "$ausgabe")" = public_html ] && ok "staging ohne STAGING_PATH → public_html" || fehl "staging Standardpfad"

echo "# rsync-Regeln"
env RUNNER_TEMP="$TMP" GITHUB_ENV="$TMP/env" bash --noprofile --norc -eo pipefail "$TMP/regeln.sh"
regeln="$TMP/rsync-regeln"
[ -s "$regeln" ] && ok "Regeldatei geschrieben" || fehl "Regeldatei fehlt"

quelle="$TMP/quelle"; ziel="$TMP/ziel"
mkdir -p "$quelle/sub" "$ziel/sub" "$ziel/.well-known/acme-challenge" "$ziel/altordner"
echo neu        > "$quelle/index.html"
echo neu        > "$quelle/neu.html"
echo ANGRIFF    > "$quelle/.htaccess"
echo ANGRIFF    > "$quelle/sub/.htaccess"
echo ANGRIFF    > "$quelle/.reinstil-deploy"
echo quelltext  > "$quelle/README.md"
ln -s /etc        "$quelle/link-raus"
ln -s index.html  "$quelle/link-rein"

echo alt        > "$ziel/index.html"
# Älter als die Quelle, sonst hält rsync gleich große Dateien aus derselben Sekunde für gleich
touch -d 2020-01-01 "$ziel/index.html"
echo alt        > "$ziel/alt.html"
echo SCHUTZ     > "$ziel/.htaccess"
echo SCHUTZ     > "$ziel/sub/.htaccess"
echo MARKE      > "$ziel/.reinstil-deploy"
echo token      > "$ziel/.well-known/acme-challenge/x"
echo SCHUTZ     > "$ziel/altordner/.htaccess"

# Gleiche Optionen wie im Schritt "Upload per rsync" (dort zusätzlich -e ssh)
rsync -rlptz --delete --safe-links --filter="merge $regeln" "$quelle/" "$ziel/" >"$TMP/rsync.log" 2>&1
rc=$?
[ $rc -eq 0 ] && ok "rsync endet mit 0" || { fehl "rsync endet mit $rc"; cat "$TMP/rsync.log"; }

[ "$(cat "$ziel/index.html")" = neu ]                 && ok "index.html ersetzt"               || fehl "index.html nicht ersetzt"
[ -f "$ziel/neu.html" ]                               && ok "neu.html hochgeladen"             || fehl "neu.html fehlt"
[ ! -e "$ziel/alt.html" ]                             && ok "alt.html gelöscht"                || fehl "alt.html noch da"
[ "$(cat "$ziel/.htaccess")" = SCHUTZ ]               && ok ".htaccess im Ziel nicht überschrieben" || fehl ".htaccess überschrieben"
[ "$(cat "$ziel/sub/.htaccess")" = SCHUTZ ]           && ok "sub/.htaccess nicht überschrieben" || fehl "sub/.htaccess überschrieben"
[ "$(cat "$ziel/altordner/.htaccess")" = SCHUTZ ]     && ok ".htaccess in altem Ordner bleibt"  || fehl ".htaccess in altem Ordner gelöscht"
[ "$(cat "$ziel/.reinstil-deploy")" = MARKE ]         && ok "Markierung nicht überschrieben"   || fehl "Markierung überschrieben"
[ -f "$ziel/.well-known/acme-challenge/x" ]           && ok ".well-known bleibt"               || fehl ".well-known gelöscht"
[ ! -e "$ziel/README.md" ]                            && ok "README.md nicht hochgeladen"      || fehl "README.md hochgeladen"
[ ! -e "$ziel/link-raus" ] && [ ! -L "$ziel/link-raus" ] && ok "Symlink nach außen übersprungen" || fehl "Symlink nach außen hochgeladen"
[ -L "$ziel/link-rein" ]                              && ok "Symlink im Upload bleibt"         || fehl "Symlink im Upload fehlt"

echo
echo "$tests Tests, $fehler Fehler"
[ $fehler -eq 0 ]
