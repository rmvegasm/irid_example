<!-- agents: coding conventions, r box modules, js code and styles -->

## JavaScript conventions

### No TypeScript — use JSDoc

All JS files are plain JavaScript with JSDoc type annotations. This
avoids a build step for shared logic while preserving type information
for editors and AI agents.

```js
/**
 * @typedef {Object} User
 * @property {string} id
 * @property {string} username
 * @property {string | null} email
 * @property {string | null} name
 * @property {string | null} password_hash
 * @property {'admin' | 'team' | 'guest' | 'monitor'} role
 * @property {boolean} is_active
 * @property {string} created_at
 * @property {string} updated_at
 */

/**
 * Get a user by username.
 * @param {import('postgres').Sql} sql — database connection
 * @param {string} username
 * @returns {Promise<User | null>}
 */
export async function getUser(sql, username) { ... }
```

### Module layout

- `irid/assets/js/` — organised into subdirectories by domain (`auth/`,
  `db/`, `markdown/`, `profile/`). Each subdirectory has an `index.js` barrel that
  re-exports the public API; consumers never import a source file
  directly.

### Imports

- Use ES module syntax (`import` / `export`)
- Import from `irid/assets/js/` directly

### Styling

- Tailwind CSS v4 utility classes only
- No CSS modules, no inline styles
- Dark mode supported via `dark:` variants on all components
- Use the project's color palette (gray, blue, red, green, yellow)

## R conventions

### Box modules

Every R module lives in a subdirectory of `irid/r/` with an
`__init__.r` reexport file:

```
irid/r/db/
├── __init__.r      # reexports all public functions
├── connect.r       # open_con(), close_con()
└── users.r         # get_user(), create_user(), hash_password(), check_password()
```

Import pattern:
```r
box::use(db[open_con, close_con, get_user, create_user])
```

### Coding style

- Explicit imports: `box::use(pkg[fn1, fn2])`
- No `box::use(pkg)` with `pkg$fn()` access
- Packages first, local modules second, each in separate `box::use()`
  calls
- Alphabetical order within each group

### Database

- No inline SQL in R code. Queries use parameterized
  `DBI::dbGetQuery()`
- Connections opened via `open_con()` and closed via `close_con()` or
  `on.exit()`
- Environment variables: `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`,
  `PGDATABASE`

## SQL conventions

### Init scripts

Scripts in `db/pginit/` run in alphabetical order (`.sh` scripts
are executed by bash; `.sql` scripts are piped to `psql`).

- `00_*.sql` — local overrides (run before shared)
- `01_*.sql` – `09_*.sql` — shared schema (from `shared/sql/init/`)
- `10_*.sql` and above — nut-specific schema

Always use `IF NOT EXISTS` / `IF EXISTS` guards so scripts are
idempotent.

### Column conventions

- Primary keys: `UUID DEFAULT gen_random_uuid()` for users, `SERIAL`
  for data tables
- Timestamps: `TIMESTAMPTZ NOT NULL DEFAULT now()`
- All tables have `created_at` and `updated_at`
- Foreign keys use `ON DELETE` clauses explicitly

## Testing

- JS tests: `vitest` in `irid/assets/js/` (run: `npm test`)
- R tests: `testthat` with `box::use()`
