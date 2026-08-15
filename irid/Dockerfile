# ─────────────────────────────────────────────────────────────────────
# irid/Dockerfile — irid Shiny app with ggplot2 (Tailwind v4)
#
# Multi-stage build:
#   1. css     — Compile Tailwind CSS v4 from source classes in R modules
#   2. renv    — Restore R packages from renv.lock (the slow, cached layer)
#   3. runtime — Inherits system deps + renv pkg from stage 2, copies the
#                pre-built library, adds app code (fast rebuild)
#
# Rebuild when:
#   - irid/assets/css/input.css changes (stage 1)
#   - irid/renv.lock changes         (stage 2)
#   - irid/*.r or irid/r/ changes    (stage 3)
#
# ─────────────────────────────────────────────────────────────────────

# ── Stage 1: Tailwind CSS compilation ───────────────────────────
#
# Scans R source files for Tailwind utility classes and compiles
# the final CSS. The compiled output is a build artifact — it is
# never checked into version control (see .gitignore).
#
# During local development without Docker, compile manually:
#   bash irid/assets/css/build.sh
# ─────────────────────────────────────────────────────────────────
FROM node:22-alpine AS css
WORKDIR /build

RUN npm init -y && npm install @tailwindcss/cli@^4

# Preserve the project directory structure so @source paths work.
# input.css lives at irid/assets/css/input.css and its @source
# directives point to ../../r/ and ../ relative to itself.
COPY irid/ ./irid/

RUN npx tailwindcss \
  -i irid/assets/css/input.css \
  -o irid/assets/css/app.css

# ── Stage 2: renv — restore R packages from lockfile ────────────
#
# Installs system build dependencies, renv itself, and the full R
# package library.  The library is placed outside the project
# directory (/renv/lib) so it can be explicitly copied into the
# runtime stage without being tangled with application code.
#
# Rebuilt only when renv.lock changes.
# ─────────────────────────────────────────────────────────────────
FROM posit/r-base:4.5.3-trixie AS renv

# System dependencies. Most are build deps for compiling R packages;
# gdal-bin (ogr2ogr), curl, and unzip are also runtime deps for the
# data-raw geo loader (data-raw/generate_geo.R).
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      cmake \
      curl \
      gdal-bin \
      libcurl4-openssl-dev \
      libfontconfig1-dev \
      libfreetype-dev \
      libgit2-dev \
      libicu-dev \
      libpq-dev \
      libsodium-dev \
      libssl-dev \
      libuv1-dev \
      libxml2-dev \
      unzip \
    && rm -rf /var/lib/apt/lists/*

RUN R -s -e "install.packages('renv', repos = 'https://cloud.r-project.org')"

WORKDIR /app/irid

# Minimal renv infrastructure — only what restore() needs
COPY irid/renv.lock .

# Store the library outside the project tree so it survives
# independent of app-code COPY instructions in downstream stages.
ENV RENV_PATHS_LIBRARY=/renv/lib

# Packages must be copied, not symlinked, into the project library.
# By default renv symlinks into its cache (~/.cache/R/renv), but
# that cache is under /root and inaccessible to the non-root user
# who runs the app at runtime.
ENV RENV_CONFIG_CACHE_SYMLINKS=FALSE

# .Rprofile sources renv/activate.R at startup, which sets up library
# paths (including RENV_PATHS_LIBRARY).  restore() then fills the
# library with packages.
RUN R -s -e "renv::restore(prompt = FALSE)"

# ── Stage 3: runtime ───────────────────────────────────────────
#
# Inherits system deps and the renv package from the renv stage.
# Copies the pre-built library (fast — already compiled) and the
# application code.  Only rebuilt when R sources change.
# ─────────────────────────────────────────────────────────────────
FROM renv AS runtime

# Carry forward the library path so renv/activate.R finds packages
ENV RENV_PATHS_LIBRARY=/renv/lib

# Copy the pre-built R package library from the renv stage.
# This is the expensive artifact — it only changes when renv.lock
# changes, so Docker's layer cache keeps it fresh across code-only
# rebuilds.
COPY --from=renv /renv/lib /renv/lib

# Non-root user (matches host UID/GID for volume mounts)
ARG UID=1000
ARG GID=1000
RUN groupadd --gid $GID nut \
    && useradd --uid $UID --gid $GID --create-home nut \
    && mkdir -p /logs \
    && chown nut:nut /logs

# Application code
COPY --chown=nut:nut irid/ /app/irid/

# Compiled CSS from stage 1
COPY --chown=nut:nut --from=css \
  /build/irid/assets/css/app.css \
  /app/irid/assets/css/app.css

EXPOSE 3839

USER nut:nut
CMD ["Rscript", "-e", "shiny::runApp(port = 3839, host = '0.0.0.0')"]
