# Working on Task Switcher

How the app works: [docs/architecture.md](docs/architecture.md). Configuring, generating and running it:
[README.md](README.md).

## Changes reach `main` only through pull requests

`main` is protected on GitHub: no direct pushes, no force-pushes, squash merges only.

1. Start a new branch from an up-to-date `main`, named after the task (`fullscreen-switching`, `icon-cache`).
2. Make the changes and commit them on that branch.
3. Push the branch and open a pull request with `gh pr create`.
4. The maintainer reviews it and squash-merges it. Don't merge it yourself.

The squash commit on `main` takes the pull request's title and description, so write both for someone
using the app: what changes for them, not which files were edited. The same goes for commit messages.
No `Co-Authored-By` or other attribution lines.

## Build number

The build number (`CURRENT_PROJECT_VERSION` in `project.yml`) identifies one build. Settings shows it as
"Version 1.0.2 (17)", so the maintainer can tell which build is running.

- Raise it by one every time you hand over a build to run, before handing it over. Two different builds
  must never carry the same number.
- Take the next number after the highest one in use on any branch, not just the current one.
- Say the new number when you hand the build over.
- After changing it, regenerate the project (`make`) so Xcode picks it up.
- Change the version (`MARKETING_VERSION`) only when asked.
