# Project conventions

- Read `README.md` for the project overview.
- Documentation lives in `docs/`. Always consult relevant docs before
  making changes. Build a light doc index with:
  `head -n 1 docs/**/*.md`
- For online documentation links for the stack, see `docs/_web_docs.md`.
- When work touches shared components, read `shared/AGENTS.md`.
- Design docs for new features live in `docs/_dev/`.
- for the `irid` package you can access the source code in `../irid/`.

**⛔ NEVER delete the database.** Do not run `rm -rf db/pgdata/`,
`DROP TABLE`, `DROP SCHEMA`, `TRUNCATE`, or any other destructive
operation on the database under any circumstances. The `pgdata/`
directory contains the live PostgreSQL data files — removing it
destroys all application data irreversibly.

If you suspect the database needs to be reset (e.g. stale init
state during early development), **ask the user to do it** and
explain exactly which command you believe is necessary and why.
Never take destructive action on the database yourself.
