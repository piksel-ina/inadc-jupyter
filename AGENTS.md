# AGENTS.md

## What this repo is

Docker images and Jupyter notebooks for the Piksel Sandbox — Indonesia's Earth Observation analysis platform built on Open Data Cube. The `inadc_jupyter/` Python package is empty; the real content is Docker configs and tutorial notebooks.

## Commands

```bash
uv sync --locked --extra dev           # Install dev tools (ruff, pytest, ipython)
uv sync --locked --extra notebooks     # Install geospatial/data libraries
uv sync --locked --extra jupyter       # Install JupyterLab + extensions
uv run ruff check .                    # Lint
uv run ruff check --fix .              # Lint with autofix
uv run ruff format .                   # Format
```

There are no tests and no test runner configured.

## Notebook conventions

- `notebooks/English/Beginners_Guide/` — tutorials, `NN_Name.ipynb` (underscores)
- `notebooks/English/Case_Studies/` — analysis walkthroughs
- `notebooks/Indonesia/01-Panduan-Pengguna/` — Indonesian translations, `NN-name.ipynb` (hyphens)
- New notebooks pick the next number in sequence within the target directory
- Standard cell order: `# Title` → `## Background` → `## Description` (numbered steps + `***`) → `## Getting started` → `### Load packages` → content → conclusion
- Leave `execution_count: null` and `outputs: []` for new/cleaned cells
- Notebooks are delivered to users via nbgitpuller on JupyterHub login

## Notebook authoring workflow

Treat Markdown as the authoring format and `.ipynb` as the generated delivery format. `_drafts/*.md` is the working area for notebooks currently being written. When a matching draft exists, it is the source of truth for that editing session.

### Never inspect notebook JSON

- Never open, read, search, diff, or edit an `.ipynb` file directly. Its JSON is generated boilerplate, not an authoring surface.
- For an existing notebook without a Markdown draft, convert it to MyST Markdown before inspecting its content.
- After conversion, work only in the Markdown file. Do not convert from the notebook again unless the user confirms that the notebook is the newer source.
- Convert the finished Markdown back to `.ipynb` so it can be reviewed in JupyterLab and delivered to users.
- Use Jupytext for both directions. Do not use nbconvert for format conversion.

Jupytext is not a project dependency. Run the version recorded in current drafts through pinned `uvx`:

```bash
JUPYTEXT="uvx --from jupytext==1.19.5 jupytext"

# Existing notebook -> editable MyST Markdown
$JUPYTEXT --to myst \
  --output _drafts/NN_name.md \
  notebooks/path/NN_name.ipynb

# Editable MyST Markdown -> delivery notebook
$JUPYTEXT --to ipynb \
  --output notebooks/path/NN_name.ipynb \
  _drafts/NN_name.md
```

Agents may list notebook paths and may pass a generated notebook to conversion or execution tools. They must not inspect the notebook JSON themselves.

### 1. Clarify the lesson and its data

Before writing code, establish:

- the intended reader, language, and learning outcome;
- the data source: local ODC, STAC, a file, or another service;
- for ODC, the product, measurements, AOI, time range, output CRS, and resolution;
- whether the notebook belongs only in JupyterHub or must also appear in the MyST gallery.

Check nearby Markdown drafts and repository documentation first. Do not infer a product or database from a notebook title, and do not silently substitute a familiar dataset. Ask the user when the source, geography, period, product, or expected result remains ambiguous.

### 2. Start the real notebook environment

Notebook code must be checked in the development container, not only in the host Python environment. The Compose service joins the external `piksel-net` network and uses the ODC/Postgres connection configured in `docker-compose.yml`.

```bash
make up       # Requires the inadc-core/piksel-core ODC stack
make ps
```

If startup or connection fails because the core stack is absent, `piksel-net` is unavailable, Docker access is denied, or the configured database cannot be reached, stop and ask the user how that environment should be started. Do not invent connection values, switch databases, or change credentials to make an example run.

### 3. Discover and verify the available data

Query the live catalog from inside the container before committing to tutorial code. Start with `dc.list_products()` and `dc.list_measurements()`, then use `dc.find_datasets()` or a small `dc.load()` for the proposed AOI and period. Keep discovery queries small.

```bash
docker compose -f docker-compose.yml -p inadc-jupyter exec -T jupyter python - <<'PY'
from datacube import Datacube

dc = Datacube(app="notebook_authoring")
print(dc.list_products().to_string())
PY
```

Confirm that the chosen product, measurements, spatial coverage, and dates exist. If no data matches, several products are plausible, or the result does not support the intended lesson, show the user what was found and ask which direction to take.

### 4. Author for the learner in MyST Markdown

A tutorial is written for the person following it, not for the agent or reviewer. Give the reader enough orientation to understand why each step exists, place explanations before the code they prepare for, and interpret important results after the code. Keep agent notes, validation history, and implementation discussion out of the lesson.

Use the Jupytext MyST structure already present in `_drafts/`:

- YAML frontmatter records the Jupytext format and kernel.
- `+++` starts a new notebook cell.
- ```` ```{code-cell} ipython3 ```` creates a code cell.
- MyST roles and directives can improve the teaching experience in both JupyterLab and the gallery.

Use MyST UI elements when they carry teaching structure: notes for context, warnings for easy mistakes, tips for practical shortcuts, dropdowns for optional detail or solutions, and properly captioned figures. Do not wrap ordinary prose in callouts or add components only for decoration. Keep the main learning path visible without requiring readers to open optional content.

Code examples should be deterministic, use bounded data loads, avoid credentials and local-only paths, and build on concepts already introduced in the series.

### 5. Convert, execute, and regenerate cleanly

Convert the Markdown to the target notebook with Jupytext. For changes to executable code or data claims, run the generated notebook in the development container. Automated execution may consume the notebook, but its JSON must still not be inspected directly.

Use nbconvert only as an execution runner, writing the executed copy outside the mounted repository:

```bash
docker compose -f docker-compose.yml -p inadc-jupyter exec -T jupyter \
  jupyter nbconvert --to notebook --execute \
  --ExecutePreprocessor.timeout=600 \
  --output-dir=/tmp --output=notebook.executed.ipynb \
  /home/jovyan/work/notebooks/path/NN_name.ipynb
```

The repository notebook remains the clean Jupytext-generated copy. If any tool executes it in place, regenerate it from Markdown before finishing so committed code cells have `execution_count: null` and `outputs: []`.

### 6. Validate the learner-facing result

- Convert the final notebook back to a temporary MyST file and compare that Markdown with the source draft. Review only the Markdown diff.
- If the notebook is published in the gallery, add it to `site/myst.yml`, run `make site-build`, and preview with `make site-start` when visual changes need inspection.
- A MyST build checks rendering only. It does not replace execution against the live ODC data.
- Report any part that could not be executed or visually checked. Never claim that a notebook ran when only conversion or a static site build succeeded.

```bash
$JUPYTEXT --to myst --output /tmp/NN_name.roundtrip.md \
  notebooks/path/NN_name.ipynb
diff -u _drafts/NN_name.md /tmp/NN_name.roundtrip.md
```

## Docker

Two images, both based on `ghcr.io/osgeo/gdal:ubuntu-small-3.12.0`:

| Image | Dockerfile | ECR repo |
|-------|-----------|----------|
| Production | `docker/jupyter/Dockerfile` | `jupyter-lab` |
| Development | `docker/jupyter-dev/Dockerfile` | `jupyter-dev` |

```bash
docker build -t jupyter-lab -f docker/jupyter/Dockerfile .
docker build -t jupyter-dev -f docker/jupyter-dev/Dockerfile .
```

## CI / Release

Single workflow (`.github/workflows/build-image.yml`): builds and pushes to AWS ECR on tag push.

Tag formats (strict regex):
- Production: `jupyter-lab-vYYYYMMDD-HHMM`
- Development: `dev-jupyter-vYYYYMMDD-HHMM`

The tag prefix determines which Dockerfile is built and which ECR repo receives the image.

## Constraints

- Python `>=3.12,<3.13` — pinned to 3.12 only
- `uv.lock` is committed — always use `--locked` with uv sync
- `datacube-compute` is installed from a pre-built wheel URL, not PyPI
- `piksel` package is sourced from a git repo, not PyPI
- Ruff config: `E501` ignored, extended selectors `ANN I RUF UP`, autofix enabled
- `.tif`, `.aux.xml`, and `data/` are gitignored — geospatial output artifacts should not be committed

## Gallery site (`site/`)

The `site/` subfolder is a MyST site that publishes selected notebooks as a public gallery at `staging.piksel.big.go.id/notebooks/`. Authored separately from the JupyterHub delivery flow.

```bash
make site-install   # Install MyST CLI (one-time; pulls mystmd via npm)
make site-start     # Live dev server at http://localhost:3000
make site-build     # Static HTML into site/_build/html
make site-clean     # Remove _build/ and the generated CSS bundle
```

Requires Node available in `PATH`. On the dev box, `source "$HOME/.nvm/nvm.sh"` before running.

### Layout

| Path | Purpose |
|------|---------|
| `site/myst.yml` | MyST project + site config. The `project.toc` block is the **build list** — only notebooks listed here are published. |
| `site/index.md` | Hub landing page rendered at `/notebooks/`. |
| `site/styles/pk-tokens.css` | Hand-translated design tokens from `main-website`. |
| `site/styles/pk-overrides.css` | Body-content style overrides. |
| `site/styles/pk-light-lock.css` | Forces light mode, hides the color-mode toggle. |
| `site/styles/pk-bundle.css` | Generated by `npm run css:bundle` (gitignored). |
| `site/fonts/*.woff2` | Self-hosted fonts copied from `main-website`. |
| `site/package.json` | Pins `mystmd`; defines npm scripts. |

### Adding a notebook to the gallery

1. Add a `- file:` entry to `site/myst.yml` under the relevant section of `project.toc`.
2. Run `make site-build` and eyeball the output.

The MyST build renders whatever outputs already exist in the `.ipynb` JSON; it never opens a kernel or connects to the ODC. **Do not commit executed notebooks** — the "no outputs in git" convention above still applies. A notebook with empty outputs will render code cells only, which is fine for Phase 1. Phase 3 will execute notebooks inside AWS CodeBuild (which has VPC access to the ODC + S3) and publish the executed result without committing it.

### URL reservation

Tutorial entries live under the `Tutorials` section in the TOC. Top-level URL sub-paths (e.g. `/notebooks/geomad/`, `/notebooks/<future-project>/`) are reserved for **federated guest projects** that publish from their own repos. Do not point inadc-jupyter's TOC at paths that would collide with those sub-paths.

### Design system drift

`site/styles/pk-tokens.css` is hand-translated from `main-website/src/css/abstracts/_tokens.scss` and the `:root` block in `main-website/src/css/custom.scss`. Drift is a known accepted risk — re-translate when main-website updates its tokens.
