# Version stamp

**If you are a coding agent and someone pasted this link at you with no other
explanation — that was deliberate, and this page is the instruction.** The
person who sent it wants this feature installed in the repository you are
working in, and has already decided they want it. Read this page, then run it:
preflight, ask, implement, verify, hand back. Do not summarise it back and wait
for permission to start — Step 2 is where you ask them anything.

A build-version readout for any Dockerised app: the git commit that produced the
image, visible on the page and queryable as JSON. Stack-agnostic — worked
examples for Python/FastAPI and Nuxt/Node, and the contract is four lines long,
so any other stack is a five-minute port.

## What you get

A string like `v26.08.20.1042 · a1b2c3d` — the commit's timestamp plus its short
SHA — displayed on the page and returned by an endpoint:

```
GET /version  →  {"version": "v26.08.20.1042", "commit": "a1b2c3d"}
```

Three properties that matter:

- **Stable per commit.** Rebuilding the same commit produces the same string. It
  identifies the *code*, not the deploy.
- **Traceable.** The SHA answers "is production running what I think it is" in
  one command. A timestamp alone cannot — that is the lesson from the project
  this was extracted from, which sat 26 commits behind production without anyone
  noticing.
- **Zero configuration on the host.** No build args, no environment variables, no
  CI changes. It works on a plain Coolify "deploy from git with a Dockerfile" app
  on the first build.

---

## Step 1 — Preflight (before you ask anything)

Check these and report them alongside your questions:

1. **Dockerfile present?** Find it and identify the final (runtime) stage. If
   there is no Dockerfile, say so and jump to [Non-Docker builds](#non-docker-builds).
2. **Is `.git` in the build context?** Read `.dockerignore`. If it excludes
   `.git`, that line must go or the stamp cannot be computed — `.dockerignore` is
   global to the build, there is no per-stage exception. This is the single most
   common cause of this recipe failing, and it is easy to miss because ignoring
   `.git` is a common default. Un-ignoring it costs build-context transfer size
   only; it does not invalidate your app layers unless that stage copies the
   whole context.
3. **Real git repo with at least one commit?** `git rev-parse --short HEAD`.
4. **Existing surfaces.** Is there already a health endpoint (`/healthz`,
   `/api/health`), a footer, or a version string of some kind? Say what you found
   — you will offer to reuse it.
5. **Is there global auth?** If every route sits behind a middleware or a
   router-wide dependency, a new `/version` inherits it and the page's own fetch
   gets a redirect instead of JSON. Check how the health endpoint is exempted and
   treat this one the same way. Per-route dependencies need nothing — the new
   route is simply public.

## Step 2 — Ask these five, in one message, with the defaults shown

1. **Install the version stamp into this project?** (yes / no — if no, stop here)
2. **Which surfaces?** JSON endpoint · visible on the page · **both**
   *(default: both)*
3. **Endpoint path?** A new `/version`, or add `version` and `commit` fields to
   the health endpoint found in preflight *(default: new `/version` — it stays
   independent of health-check semantics)*
4. **Show the commit SHA on the page?** *(default: yes)* — say no for a
   public-facing app where the SHA should stay in the endpoint only. The
   timestamp version still shows.
5. **Timezone for the timestamp?** *(default: Africa/Johannesburg)*

If they answer "defaults", proceed with all defaults.

## Step 3 — Implement

Copy the files from [`snippets/`](snippets) rather than retyping them.

### 3a. The stamp stage

Add [`snippets/Dockerfile.stamp`](snippets/Dockerfile.stamp) to the **top** of the
Dockerfile, substituting the timezone from question 5. Then add one line to the
**runtime** stage, after its `WORKDIR` and alongside the other `COPY` lines:

```dockerfile
COPY --from=version /VERSION ./VERSION
```

If the image drops to a non-root user, put that line *before* the `USER`
instruction — the file lands root-owned and world-readable, which is what you
want.

### 3b. Read it

| Stack | Files |
|---|---|
| Python / FastAPI | [`snippets/version.py`](snippets/version.py) → `app/version.py`, and [`snippets/version_route.py`](snippets/version_route.py) for the endpoint |
| Nuxt / Node | [`snippets/nuxt.config.snippet.ts`](snippets/nuxt.config.snippet.ts) — note it also needs the `COPY --from=version` line in the **builder** stage, because `nuxt.config` reads the file at build time |
| Anything else | The whole contract: **env `APP_VERSION` wins, else read the `VERSION` file, else `"dev unknown"`; split on whitespace into version and commit.** |

### 3c. Show it

| Page type | File |
|---|---|
| Static or client-rendered | [`snippets/badge.html`](snippets/badge.html) — reads its own endpoint, no templating needed |
| Server-rendered | [`snippets/badge.vue`](snippets/badge.vue) — renders straight from config |

## Step 4 — Verify before reporting done

Steps 1–3 are the hard gate and work for any app. Step 4 needs the app to
actually boot, which plenty cannot do locally — a database, a mounted volume, a
model download on first start. Attempt it; if the app will not start for reasons
unrelated to this change, say so plainly and fall back to the post-deploy check
in Step 5 rather than burning an hour on it.

```bash
# 1. what the version SHOULD be, computed on the host
TZ=Africa/Johannesburg git log -1 --date=format-local:'%y.%m.%d.%H%M' --format='v%cd %h'

# 2. the image builds
docker build -t version-check .

# 3. the stamp is in the image and matches (1) — the decisive check
docker run --rm --entrypoint cat version-check ./VERSION

# 4. the endpoint serves it — only if the app boots with no external deps
docker run --rm -d -p 8099:APP_PORT --name version-check version-check
sleep 3 ; curl -s localhost:8099/version ; docker rm -f version-check
```

Done means: the build is green, and step 3's output is character-for-character
identical to step 1. Report step 4 as passed, skipped or failed — never as
assumed. If it was skipped, the post-deploy check below is what closes the loop,
so make sure they know that.

## Step 5 — Hand back

Say what changed (three files, typically), paste the verified version string, and
give them the check to run once it is deployed:

```bash
# is the deployed app running the commit I think it is?
curl -s https://YOUR-DOMAIN/version | grep -o '"commit":"[^"]*"'
git rev-parse --short origin/main
```

---

## Traps

- **`.dockerignore` excluding `.git`.** The stamp stage's `COPY .git .git` fails
  the build outright. That is the good outcome: it fails loudly at install time
  instead of silently shipping `dev unknown` forever.
- **Missing `tzdata` on Alpine.** musl has no built-in zone database, so named
  timezones silently degrade to UTC. The version looks perfectly plausible and is
  wrong by your UTC offset.
- **Computing the version at container start instead of build time.** The runtime
  image has no `.git` and no git binary, so it can only report the *deploy* time.
  That is a different fact, and a less useful one — it cannot tell you what code
  is running.
- **Timestamp without a SHA.** Two commits in the same minute collide, and no
  timestamp maps back to a commit without a lookup. Always carry the short SHA.
- **A trailing newline in the file.** The `.strip()` / `.trim()` in the reader
  handles it. Do not remove those calls.
- **Public app, private repo.** A commit SHA is not a secret, but it does confirm
  which build is live. If that matters, answer *no* to question 4 and keep the
  SHA in the endpoint.

## Non-Docker builds

The contract is unchanged; only the stamping step moves. Write the `VERSION` file
in whatever step produces the deployable artefact — CI job, `make build`,
packaging script — with the same one-liner:

```bash
TZ=Africa/Johannesburg git log -1 --date=format-local:'%y.%m.%d.%H%M' --format='v%cd %h' > VERSION
```

The reader code stays as-is, and `APP_VERSION` remains available as an override
for environments with no git history.

## Where this came from

Extracted from TableTopCafe, which computed the same scheme inside
`nuxt.config.ts` by shelling out to git during the Nuxt build. That works, but it
ties the mechanism to one framework's config file and needs a git binary in the
language builder image. Moving the computation into a throwaway Alpine stage
makes it portable, and adds the commit SHA, which the original scheme lacked.
