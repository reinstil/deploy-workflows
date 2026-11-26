# deploy-workflows

[Deutsch](#deutsch) · [English](#english)

## Deutsch

Kein Website-Projekt. Das Repo enthält den wiederverwendbaren Workflow `.github/workflows/deploy-static.yml`, über den alle Website-Repos von reinstil deployen. Jedes Projekt-Repo ruft ihn aus seiner eigenen `.github/workflows/deploy.yml` auf, heute noch mit `@main` und `secrets: inherit`. Der empfohlene Aufruf steht unten unter „Aufruf aus dem Projekt-Repo“.

**Was der Workflow macht**

- Zwei Jobs. `build` checkt das Projekt aus, führt `npm ci` und den Build aus und legt den Upload als Artifact ab. Dieser Job sieht keine Secrets und hat nur Leserechte. `deploy` holt das Artifact und lädt es per SSH hoch, ohne Checkout und ohne npm. So laufen npm-Pakete nie im selben Job wie der SSH-Schlüssel.
- Build-Erkennung: Gibt es eine `package.json` mit `build`-Script, laufen `npm ci` und `npm run build`, hochgeladen wird `dist/`. Sonst wird der Repo-Inhalt ohne Build hochgeladen. `build_command` und `output_dir` in der `deploy.yml` überschreiben die Erkennung.
- Upload per SSH mit `rsync --delete`. Das Ziel wird exakt zum Inhalt des Uploads. Stehen bleiben nur: jede `.htaccess` (wird nie hochgeladen und nie überschrieben, auch nicht in Unterordnern), `.well-known` und die Markierung `.reinstil-deploy`. Symlinks, die aus dem Upload hinauszeigen, überspringt rsync.
- Staging bei jedem Push auf `main`, Production bei einem veröffentlichten Release. Welche Umgebung gilt, legt die aufrufende `deploy.yml` über den Input `environment` fest.
- Staging und Production haben getrennte cPanel-Konten und SSH-Schlüssel. Ohne `PROD_PATH` laufen bei einem Release beide Jobs nicht („skipped“).
- Zielordner: `STAGING_PATH` und `PROD_PATH` müssen mit `public_html` oder einem Domain-Ordner (`kunde.de`) beginnen. Darunter sind weitere Ordner erlaubt, aber keiner darf mit einem Punkt beginnen. `.`, `./.`, `..`, `.ssh`, `mail` oder absolute Pfade bricht der Deploy ab, bevor er sich am Server anmeldet.
- Schutz für Production: Das Release muss auf einem Commit aus `main` liegen. Jeder Deploy legt im Ziel die Markierung `.reinstil-deploy` ab. Fehlt sie in einem nicht leeren Production-Ziel, etwa bei einer alten Website im Kundenkonto, bricht der Deploy ab und listet, was rsync löschen würde. Freigabe nach Prüfung und Backup über die Variable `PROD_ERSTER_DEPLOY=ja`, danach wieder löschen.

**Was er aus dem Projekt-Repo liest**

| | |
|---|---|
| Variablen Staging | `STAGING_SSH_USER`, `STAGING_PATH`, `STAGING_URL` |
| Variablen Production | `PROD_SSH_USER`, `PROD_PATH`, `PROD_URL`, optional `PROD_SSH_HOST`, `PROD_SSH_PORT`, `PROD_ERSTER_DEPLOY` |
| Variablen Server | `SSH_HOST`, `SSH_PORT` (Standard 1988) |
| Secrets | `STAGING_SSH_PRIVATE_KEY`, `PROD_SSH_PRIVATE_KEY`, `SSH_KNOWN_HOSTS`, `PROD_KNOWN_HOSTS` (alle unter `workflow_call.secrets` deklariert) |
| Alte Einrichtung (nur Staging) | Variable `SSH_USER`, Secret `SSH_PRIVATE_KEY` |
| Inputs | `environment`, `ssh_host`, `ssh_user`, `ssh_port`, `build_command`, `output_dir`, `node_version` (Standard 24) |

Die Staging-Werte legt `reinstil/projekt-anlage` beim Anlegen eines Projekts an, die Production-Werte `produktion-einrichten` beim Go-live.

**Aufruf aus dem Projekt-Repo**

Heute rufen alle Projekte `deploy-static.yml@main` mit `secrets: inherit` auf. Damit gilt: Wer `main` in diesem öffentlichen Repo ändern kann, bestimmt beim nächsten Push den Code, der in jedem Projekt mit allen Secrets läuft, auch mit Secrets, die mit dem Deploy nichts zu tun haben (z. B. `REDAKTION_APP_PRIVATE_KEY` in firstaudit-relaunch). Empfohlen ist deshalb dieser Aufruf:

```yaml
permissions:
  contents: read

jobs:
  deploy:
    if: ${{ !github.event.repository.is_template }}
    # Voller Commit-SHA statt @main; der Kommentar nennt die Version
    uses: reinstil/deploy-workflows/.github/workflows/deploy-static.yml@<40-stelliger-sha> # v1.0.0
    with:
      environment: ${{ github.event_name == 'release' && 'production' || 'staging' }}
    # Nur die Secrets, die der Deploy braucht, und den Production-Schlüssel nur bei einem Release
    secrets:
      STAGING_SSH_PRIVATE_KEY: ${{ github.event_name != 'release' && secrets.STAGING_SSH_PRIVATE_KEY || '' }}
      PROD_SSH_PRIVATE_KEY: ${{ github.event_name == 'release' && secrets.PROD_SSH_PRIVATE_KEY || '' }}
      SSH_KNOWN_HOSTS: ${{ secrets.SSH_KNOWN_HOSTS }}
      PROD_KNOWN_HOSTS: ${{ secrets.PROD_KNOWN_HOSTS }}
```

Projekte mit der alten Einrichtung (nur `SSH_PRIVATE_KEY`) geben zusätzlich `SSH_PRIVATE_KEY: ${{ secrets.SSH_PRIVATE_KEY }}` mit. `deploy-static.yml` funktioniert mit beiden Aufrufen, die Umstellung kann also Repo für Repo erfolgen. Ablauf:

1. Nach dem Merge setzt ein Mensch auf dem Merge-Commit ein Release `v1.0.0` in diesem Repo (nur als Bezeichnung, gepinnt wird auf den SHA, weil sich ein Tag verschieben lässt).
2. Zuerst `static-site-template`, dann jedes Projekt-Repo per Pull Request umstellen. Pro Repo nach dem Merge den Staging-Deploy prüfen.
3. Neue Versionen dieses Workflows erreichen ein Projekt erst, wenn dort der SHA per Pull Request angehoben wird. Dependabot (`package-ecosystem: github-actions`) kann diese Pull Requests anlegen.

**Wichtig:** Das Repo ist öffentlich. Hier stehen nie Zugangsdaten oder Schlüssel; alles kommt als Variable oder Secret aus dem jeweiligen Projekt-Repo. Solange Projekte `@main` aufrufen, wirkt jede Änderung an `deploy-static.yml` sofort auf den nächsten Deploy aller dieser Projekte, Staging wie Production. Änderungen deshalb nur per Pull Request; `main` sollte geschützt sein (Pull Request mit Freigabe, Prüfung `pruefen` grün, kein Force-Push).

**Prüfung:** `.github/workflows/pruefen.yml` läuft bei jedem Pull Request ohne Secrets: actionlint mit shellcheck und `tests/deploy-static-testen.sh`. Der Test liest die Skripte für Zielpfad und rsync-Regeln direkt aus `deploy-static.yml` und prüft sie gegen erlaubte und gefährliche Pfade sowie gegen einen Testordner (`.htaccess` bleibt, alte Dateien verschwinden, Symlinks nach außen nicht).

Stand 2026-11-26: in Gebrauch, aufgerufen von den Projekt-Repos über `@main`; dieses Repo hat noch keine Releases. Build und Upload getrennt, Zielpfade per Positivliste.

## English

Not a website project. This repo holds the reusable workflow `.github/workflows/deploy-static.yml` that every reinstil website repo deploys through. Each project repo calls it from its own `.github/workflows/deploy.yml`, today still via `@main` and `secrets: inherit`. The recommended call is described below under "Calling it from a project repo".

**What the workflow does**

- Two jobs. `build` checks out the project, runs `npm ci` and the build, and stores the upload as an artifact. This job sees no secrets and only has read access. `deploy` fetches the artifact and uploads it over SSH, with no checkout and no npm. npm packages therefore never run in the same job as the SSH key.
- Build detection: if there is a `package.json` with a `build` script, it runs `npm ci` and `npm run build` and uploads `dist/`. Otherwise it uploads the repo content without a build. `build_command` and `output_dir` in `deploy.yml` override the detection.
- Upload over SSH with `rsync --delete`. The target ends up exactly matching the upload. Only these stay: every `.htaccess` (never uploaded and never overwritten, subfolders included), `.well-known` and the marker `.reinstil-deploy`. rsync skips symlinks that point outside the upload.
- Staging on every push to `main`, production on a published release. The calling `deploy.yml` picks the environment through the `environment` input.
- Staging and production use separate cPanel accounts and SSH keys. Without `PROD_PATH`, both jobs are skipped on a release.
- Target folders: `STAGING_PATH` and `PROD_PATH` must start with `public_html` or a domain folder (`client.com`). Subfolders are allowed, but none may start with a dot. For `.`, `./.`, `..`, `.ssh`, `mail` or absolute paths the deploy stops before it connects to the server.
- Production safeguards: the release must point to a commit on `main`. Every deploy writes the marker `.reinstil-deploy` to the target. If it is missing from a non-empty production target, for example an old website in the client's account, the deploy stops and lists what rsync would delete. After review and a backup, set the variable `PROD_ERSTER_DEPLOY=ja` to allow it, then delete the variable again.

**What it reads from the project repo**

| | |
|---|---|
| Staging variables | `STAGING_SSH_USER`, `STAGING_PATH`, `STAGING_URL` |
| Production variables | `PROD_SSH_USER`, `PROD_PATH`, `PROD_URL`, optional `PROD_SSH_HOST`, `PROD_SSH_PORT`, `PROD_ERSTER_DEPLOY` |
| Server variables | `SSH_HOST`, `SSH_PORT` (default 1988) |
| Secrets | `STAGING_SSH_PRIVATE_KEY`, `PROD_SSH_PRIVATE_KEY`, `SSH_KNOWN_HOSTS`, `PROD_KNOWN_HOSTS` (all declared under `workflow_call.secrets`) |
| Old setup (staging only) | variable `SSH_USER`, secret `SSH_PRIVATE_KEY` |
| Inputs | `environment`, `ssh_host`, `ssh_user`, `ssh_port`, `build_command`, `output_dir`, `node_version` (default 24) |

`reinstil/projekt-anlage` creates the staging values when a project is set up; `produktion-einrichten` adds the production values at go-live.

**Calling it from a project repo**

Today every project calls `deploy-static.yml@main` with `secrets: inherit`. Whoever can change `main` in this public repo therefore decides, on the next push, which code runs in every project with all of its secrets, including secrets unrelated to deploying (for example `REDAKTION_APP_PRIVATE_KEY` in firstaudit-relaunch). The recommended call pins a full commit SHA and passes only the secrets the deploy needs, with the production key only on a release. See the YAML block in the German section; it is the same for both languages.

Projects on the old setup (only `SSH_PRIVATE_KEY`) also pass `SSH_PRIVATE_KEY: ${{ secrets.SSH_PRIVATE_KEY }}`. `deploy-static.yml` works with both forms, so repos can switch one at a time:

1. After the merge, a person publishes release `v1.0.0` on the merge commit in this repo (as a label only; projects pin the SHA because a tag can be moved).
2. Switch `static-site-template` first, then each project repo, each through a pull request. Check the staging deploy after each merge.
3. New versions of this workflow reach a project only when its SHA is raised through a pull request. Dependabot (`package-ecosystem: github-actions`) can open those pull requests.

**Important:** this repo is public. It never contains credentials or keys; everything comes in as a variable or secret from the calling project repo. As long as projects call `@main`, any change to `deploy-static.yml` takes effect on the next deploy of all of them, staging and production alike. Change it only through a pull request; `main` should be protected (pull request with approval, `pruefen` check green, no force push).

**Checks:** `.github/workflows/pruefen.yml` runs on every pull request without secrets: actionlint with shellcheck, and `tests/deploy-static-testen.sh`. The test reads the target-path and rsync-rule scripts straight from `deploy-static.yml` and runs them against allowed and dangerous paths and against a test folder (`.htaccess` stays, old files go, outward symlinks are skipped).

Status 2026-11-26: in use, called by the project repos via `@main`; this repo has no releases yet. Build and upload split into separate jobs, target paths checked against an allowlist.
