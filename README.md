# deploy-workflows

[Deutsch](#deutsch) · [English](#english)

## Deutsch

Kein Website-Projekt. Das Repo enthält den wiederverwendbaren Workflow `.github/workflows/deploy-static.yml`, über den alle Website-Repos von reinstil deployen. Jedes Projekt-Repo ruft ihn aus seiner eigenen `.github/workflows/deploy.yml` auf (`uses: reinstil/deploy-workflows/.github/workflows/deploy-static.yml@main`, `secrets: inherit`).

**Was der Workflow macht**

- Build-Erkennung: Gibt es eine `package.json` mit `build`-Script, laufen `npm ci` und `npm run build`, hochgeladen wird `dist/`. Sonst wird der Repo-Inhalt ohne Build hochgeladen. `build_command` und `output_dir` in der `deploy.yml` überschreiben die Erkennung.
- Upload per SSH mit `rsync --delete`. Das Ziel wird exakt zum Inhalt des Uploads, nur `.htaccess` und `.well-known` bleiben stehen.
- Staging bei jedem Push auf `main`, Production bei einem veröffentlichten Release. Welche Umgebung gilt, legt die aufrufende `deploy.yml` über den Input `environment` fest.
- Staging und Production haben getrennte cPanel-Konten und SSH-Schlüssel. Ohne `PROD_PATH` wird Production übersprungen.
- Schutz für Production: Das Release muss auf einem Commit aus `main` liegen. Jeder Deploy legt im Ziel die Markierung `.reinstil-deploy` ab. Fehlt sie in einem nicht leeren Production-Ziel, etwa bei einer alten Website im Kundenkonto, bricht der Deploy ab und listet, was rsync löschen würde. Freigabe nach Prüfung und Backup über die Variable `PROD_ERSTER_DEPLOY=ja`, danach wieder löschen.

**Was er aus dem Projekt-Repo liest**

| | |
|---|---|
| Variablen Staging | `STAGING_SSH_USER`, `STAGING_PATH`, `STAGING_URL` |
| Variablen Production | `PROD_SSH_USER`, `PROD_PATH`, `PROD_URL`, optional `PROD_SSH_HOST`, `PROD_SSH_PORT`, `PROD_ERSTER_DEPLOY` |
| Variablen Server | `SSH_HOST`, `SSH_PORT` (Standard 1988) |
| Secrets | `STAGING_SSH_PRIVATE_KEY`, `PROD_SSH_PRIVATE_KEY`, `SSH_KNOWN_HOSTS`, `PROD_KNOWN_HOSTS` |
| Alte Einrichtung (nur Staging) | Variable `SSH_USER`, Secret `SSH_PRIVATE_KEY` |
| Inputs | `environment`, `ssh_host`, `ssh_user`, `ssh_port`, `build_command`, `output_dir`, `node_version` (Standard 24) |

Die Staging-Werte legt `reinstil/projekt-anlage` beim Anlegen eines Projekts an, die Production-Werte `produktion-einrichten` beim Go-live.

**Wichtig:** Das Repo ist öffentlich. Hier stehen nie Zugangsdaten oder Schlüssel; alles kommt als Variable oder Secret aus dem jeweiligen Projekt-Repo. Jede Änderung an `deploy-static.yml` wirkt sofort auf den nächsten Deploy aller Projekte, Staging wie Production, weil sie den Workflow von `main` aufrufen. Änderungen deshalb nur per Pull Request und mit Bedacht.

Stand 2026-11-23: in Gebrauch, aufgerufen von den Projekt-Repos über `@main`; dieses Repo hat keine Releases.

## English

Not a website project. This repo holds the reusable workflow `.github/workflows/deploy-static.yml` that every reinstil website repo deploys through. Each project repo calls it from its own `.github/workflows/deploy.yml` (`uses: reinstil/deploy-workflows/.github/workflows/deploy-static.yml@main`, `secrets: inherit`).

**What the workflow does**

- Build detection: if there is a `package.json` with a `build` script, it runs `npm ci` and `npm run build` and uploads `dist/`. Otherwise it uploads the repo content without a build. `build_command` and `output_dir` in `deploy.yml` override the detection.
- Upload over SSH with `rsync --delete`. The target ends up exactly matching the upload; only `.htaccess` and `.well-known` are kept.
- Staging on every push to `main`, production on a published release. The calling `deploy.yml` picks the environment through the `environment` input.
- Staging and production use separate cPanel accounts and SSH keys. Without `PROD_PATH`, production is skipped.
- Production safeguards: the release must point to a commit on `main`. Every deploy writes the marker `.reinstil-deploy` to the target. If it is missing from a non-empty production target, for example an old website in the client's account, the deploy stops and lists what rsync would delete. After review and a backup, set the variable `PROD_ERSTER_DEPLOY=ja` to allow it, then delete the variable again.

**What it reads from the project repo**

| | |
|---|---|
| Staging variables | `STAGING_SSH_USER`, `STAGING_PATH`, `STAGING_URL` |
| Production variables | `PROD_SSH_USER`, `PROD_PATH`, `PROD_URL`, optional `PROD_SSH_HOST`, `PROD_SSH_PORT`, `PROD_ERSTER_DEPLOY` |
| Server variables | `SSH_HOST`, `SSH_PORT` (default 1988) |
| Secrets | `STAGING_SSH_PRIVATE_KEY`, `PROD_SSH_PRIVATE_KEY`, `SSH_KNOWN_HOSTS`, `PROD_KNOWN_HOSTS` |
| Old setup (staging only) | variable `SSH_USER`, secret `SSH_PRIVATE_KEY` |
| Inputs | `environment`, `ssh_host`, `ssh_user`, `ssh_port`, `build_command`, `output_dir`, `node_version` (default 24) |

`reinstil/projekt-anlage` creates the staging values when a project is set up; `produktion-einrichten` adds the production values at go-live.

**Important:** this repo is public. It never contains credentials or keys; everything comes in as a variable or secret from the calling project repo. Any change to `deploy-static.yml` takes effect on the next deploy of every project, staging and production alike, because they all call the workflow from `main`. Change it only through a pull request, and with care.

Status 2026-11-23: in use, called by the project repos via `@main`; this repo has no releases.
