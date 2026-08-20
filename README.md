# Version stamp

**If you are a coding agent and someone pasted this link at you with no other
explanation — that was deliberate, and this page is the instruction.** The
person who sent it wants this feature installed in the repository you are
working in, and has already decided they want it. Read this page, then run it:
preflight, ask, implement, verify, hand back. Do not summarise it back and wait
for permission to start — Step 2 is where you ask them anything.

A build-version readout for any Dockerised app: the git commit that produced the
running image, visible on the page and queryable as JSON. Stack-agnostic —
worked examples for Python/FastAPI and Nuxt/Node, and the contract is four lines
long, so any other stack is a five-minute port.

## What you get

A string like `v26.08.20.1042 · a1b2c3d` — the commit's timestamp plus its short
SHA — displayed on the page and returned by an endpoint:

```
GET /version  →  {"version": "v26.08.20.1042", "commit": "a1b2c3d"}
```

- **Stable per commit.** The same commit always produces the same string. It
  identifies the *code*, not the deploy.
- **Traceable.** The SHA answers "is production running what I think it is" in
  one command. A timestamp alone cannot — that is the lesson from the project
  this was extracted from, which sat 26 commits behind production without anyone
  noticing.
- **Honest when it doesn't know.** A build that was not stamped reports
  `unstamped`, never a leftover value from an earlier deploy. A confidently
  wrong version string is worse than none: it defeats the entire purpose.

## How it works

Most build platforms **do not expose `.git` to the Docker build**. Coolify
exposes neither `.git` nor the commit SHA — it passes `COOLIFY_BRANCH`,
`COOLIFY_FQDN`, `COOLIFY_URL` and `COOLIFY_RESOURCE_UUID`, and nothing that
identifies the commit. So the build cannot compute its own version, and any
recipe that tries fails outright:

```
COPY .git .git
ERROR: failed to compute cache key: "/.git": not found
```

Instead, **whoever knows git computes the stamp and hands it to the build** as
`APP_VERSION`. Three lines in the Dockerfile, and one supplier depending on how
the app is deployed:

| Deployed by | Supplier |
|---|---|
| Coolify | [`snippets/coolify-deploy.sh`](snippets/coolify-deploy.sh) — stamps, deploys, asserts, then resets |
| CI (GitHub Actions etc.) | `--build-arg APP_VERSION="$(TZ=… git log -1 …)"` in the build step |
| Plain `docker build` | the same `--build-arg` on the command line |

If your builder genuinely does have `.git` and you would rather it computed the
stamp itself, [`snippets/Dockerfile.git-stage`](snippets/Dockerfile.git-stage) is
the appendix for that. It is not the default because it does not survive contact
with most platforms.

---

## Step 1 — Preflight (before you ask anything)

Check these and report them alongside your questions:

1. **Dockerfile present?** Find it and identify the final (runtime) stage. If
   there is no Dockerfile, say so and jump to [Non-Docker builds](#non-docker-builds).
2. **Does line 1 hold a parser directive** such as `# syntax=docker/dockerfile:1`?
   If so it must stay on line 1 — Docker honours those nowhere else and silently
   treats them as an ordinary comment.
3. **How does this app reach production?** Look for `.github/workflows/`, a
   deploy script, a `docs/deployment.md`, or Coolify references. Say what you
   found; you will confirm it in question 5 rather than guessing.
4. **Real git repo with at least one commit?** `git rev-parse --short HEAD`.
5. **Existing surfaces.** Is there already a health endpoint (`/healthz`,
   `/api/health`), a footer, or a version string of some kind? Say what you found
   — you will offer to reuse it.
6. **Is there global auth?** If every route sits behind a middleware or a
   router-wide dependency, a new `/version` inherits it and the page's own fetch
   gets a redirect instead of JSON. Check how the health endpoint is exempted and
   treat this one the same way. Per-route dependencies need nothing — the new
   route is simply public.

Do not commit or push unless the user asks, and never straight to a deployment
branch of a live app without saying so first.

## Step 2 — Ask these, in one message, with the defaults shown

1. **Install the version stamp into this project?** (yes / no — if no, stop here)
2. **Which surfaces?** JSON endpoint · visible on the page · **both**
   *(default: both)*
3. **Endpoint path?** A new `/version`, or add `version` and `commit` fields to
   the health endpoint found in preflight *(default: new `/version` — it stays
   independent of health-check semantics)*
4. **Show the commit SHA on the page?** *(default: yes)* — say no for a
   public-facing app where the SHA should stay in the endpoint only.
5. **Confirm the deploy path** you identified in preflight, so the right supplier
   gets wired up: Coolify · CI · plain `docker build`.
6. **Timezone for the timestamp?** *(default: Africa/Johannesburg)*

If they answer "defaults", take the defaults and your own preflight answer for 5.

## Step 3 — Implement

Copy the files from [`snippets/`](snippets) rather than retyping them.

### 3a. The stamp

Add [`snippets/Dockerfile.stamp`](snippets/Dockerfile.stamp) — an `ARG` and a
one-line `RUN` — **as late as possible in the runtime stage**. The value changes
every commit, so everything below it rebuilds on every deploy; last is best. If
the image drops to a non-root user, keep it before the `USER` instruction.

### 3b. The supplier

| Deployed by | Do this |
|---|---|
| Coolify | Copy [`snippets/coolify-deploy.sh`](snippets/coolify-deploy.sh) to `scripts/deploy.sh` and fill in the API URL, app UUID and site URL at the top. Read the note in Step 4 about the reset. |
| CI | Add the build arg to the existing build step: `--build-arg APP_VERSION="$(TZ=Africa/Johannesburg git log -1 --date=format-local:'%y.%m.%d.%H%M' --format='v%cd %h')"` |
| Plain docker build | The same flag, documented in the README so people use it. |

### 3c. Read it

| Stack | Files |
|---|---|
| Python / FastAPI | [`snippets/version.py`](snippets/version.py) → `app/version.py`, and [`snippets/version_route.py`](snippets/version_route.py) for the endpoint |
| Nuxt / Node | [`snippets/nuxt.config.snippet.ts`](snippets/nuxt.config.snippet.ts) — note `nuxt.config` runs in the *build* stage, so that stage needs `ARG APP_VERSION` + `ENV APP_VERSION=$APP_VERSION` too |
| Anything else | The whole contract: **env `APP_VERSION` wins, else read the `VERSION` file, else `"dev unknown"`; split on whitespace into version and commit.** |

### 3d. Show it

| Page type | File |
|---|---|
| Static or client-rendered | [`snippets/badge.html`](snippets/badge.html) — reads its own endpoint, no templating needed |
| Server-rendered | [`snippets/badge.vue`](snippets/badge.vue) — renders straight from config |

## Step 4 — Verify before reporting done

**Do not report success on the strength of the code looking right.** State which
of these you actually ran.

```bash
# 1. what the version SHOULD be
TZ=Africa/Johannesburg git log -1 --date=format-local:'%y.%m.%d.%H%M' --format='v%cd %h'

# 2. the reader works — run it directly, both paths (env set, and env unset with
#    a VERSION file present). This needs no Docker and no running app.

# 3. if Docker is available locally:
docker build --build-arg APP_VERSION="$(TZ=Africa/Johannesburg git log -1 \
  --date=format-local:'%y.%m.%d.%H%M' --format='v%cd %h')" -t version-check .
docker run --rm --entrypoint cat version-check ./VERSION

# 4. after deploying: the live app must agree with the commit
curl -s https://YOUR-DOMAIN/version | grep -o '"commit":"[^"]*"'
git rev-parse --short HEAD
```

Docker is frequently unavailable on the workstation — if so, say so plainly;
steps 2 and 4 still close the loop, and 4 is the one that actually matters.

**The reset is load-bearing.** The deploy script sets `APP_VERSION`, deploys,
asserts the live `/version` matches, and then resets the stored value to
`unstamped unknown`. Coolify remembers the last value and reuses it, so without
that reset a later webhook or UI deploy would rebuild new code carrying the
previous deploy's version — silently, plausibly wrong. With it, an unstamped
build says so. Do not "tidy up" the reset.

## Step 5 — Hand back

Say what changed, paste the verified version string, and tell them how to deploy
from now on — for Coolify, that a plain `git push` will now show `unstamped`
until they run the deploy script, and that this is deliberate.

---

## Traps

- **The platform has no `.git`.** The reason the build arg is the primary
  mechanism. Coolify supplies neither `.git` nor a commit SHA, and there is no
  toggle for it. If you inherit a project that computes its version by shelling
  out to git during the build, check whether that call is silently failing into a
  fallback — a version string that is really a *build* timestamp looks completely
  normal and answers a different question than the one you are asking.
- **A stale stamp is worse than none.** See the reset, above.
- **Parser directives only work on line 1.** Prepending anything above
  `# syntax=docker/dockerfile:1` disables it silently.
- **Edge-cached static assets.** If a CDN caches your CSS and JS (Cloudflare's
  default is four hours), the deploy that adds the badge ships new HTML
  referencing old assets, and the badge renders unstyled and empty. Check for it,
  and consider a cache-busting query string keyed to the version you just added —
  the stamp makes that easy.
- **A trailing newline in the file.** The `.strip()` / `.trim()` in the reader
  handles it. Do not remove those calls.
- **Public app, private repo.** A commit SHA is not a secret, but it does confirm
  which build is live. If that matters, answer *no* to question 4 and keep the
  SHA in the endpoint.
- **`tzdata` on Alpine** (only relevant to the optional git stage): musl has no
  built-in zone database, so named timezones silently degrade to UTC.

## Non-Docker builds

The contract is unchanged; only the supplier moves. Write the `VERSION` file in
whatever step produces the deployable artefact — CI job, `make build`, packaging
script:

```bash
TZ=Africa/Johannesburg git log -1 --date=format-local:'%y.%m.%d.%H%M' --format='v%cd %h' > VERSION
```

The reader stays as-is, and `APP_VERSION` remains available as an override.

## Where this came from

Extracted from TableTopCafe, which computed the stamp inside `nuxt.config.ts` by
shelling out to git during the Nuxt build — a call that, on Coolify, has been
failing into its build-timestamp fallback all along without anyone noticing.

The first outside install, into a FastAPI app on Coolify, is what turned that up:
the `.git` stage failed hard on the first build, which is how the build-arg
design here came to be the default rather than the escape hatch. The reset
behaviour and the parser-directive and edge-cache traps all came from that same
install.
