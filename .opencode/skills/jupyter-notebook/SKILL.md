---
name: jupyter-notebook
description: Use when creating, editing, or refactoring Jupyter notebooks (.ipynb) in the INADC Piksel project — Earth Observation tutorials and case studies using Open Data Cube.
---

# Jupyter Notebook Skill

Create and edit `.ipynb` notebooks for the Piksel Sandbox — an Earth Observation learning platform using Open Data Cube for the Indonesian region.

## When to Use

- Create a new `.ipynb` notebook from scratch
- Edit or refactor an existing notebook
- Convert scripts or rough notes into a structured notebook
- Bilingual notebooks exist (English and Indonesian); create in whichever language the user requests

## Project Conventions

### Directory Layout

```
notebooks/
├── English/
│   ├── Beginners_Guide/     # Tutorial-style: Jupyter 101, getting started guides
│   └── Case_Studies/        # Analysis-style: water detection, coastal change, ML
├── Indonesia/
│   └── 01-Panduan-Pengguna/ # Indonesian-language tutorials
└── assets/                  # Shared images and resources
```

### Naming

- English notebooks: `NN_DescriptiveName.ipynb` (zero-padded number, underscores)
  - Example: `01_Jupyter_101.ipynb`, `04_Sentinel-2_GettingStarted.ipynb`
- Indonesian notebooks: `NN_descriptive-name.ipynb` (zero-padded number, hyphens)
  - Example: `00-About.ipynb`, `04_Membuka_data.ipynb`
- Pick the next number in sequence for new notebooks in the target directory

### Notebook Kinds

| Kind | Directory | Description |
|------|-----------|-------------|
| **Beginners Guide** | `Beginners_Guide/` / `Panduan-Pengguna/` | Teaching-oriented: prerequisites, step-by-step, exercises |
| **Case Study** | `Case_Studies/` | Analysis-oriented: hypothesis, data loading, analysis, results, conclusions |

## Workflow

1. **Identify kind.** Beginners Guide or Case Study. If editing existing, preserve intent.
2. **Choose path.** `notebooks/English/` or `notebooks/Indonesia/` based on user request.
3. **Pick number.** Next in sequence within the target directory.
4. **Write notebook.** Use small focused cells. Pair each code cell with a markdown cell explaining purpose and expected result.
5. **Validate.** Run top-to-bottom if the environment allows. Otherwise state explicitly what to validate locally.

## Notebook Structure

Every notebook follows this cell order:

1. **Title cell** — `# Title` markdown
2. **Background** — `## Background` markdown: context and motivation
3. **Description** — `## Description` markdown: what the notebook covers as a numbered list of steps, ending with `***`
4. **Getting started** — `## Getting started` markdown
5. **Load packages** — `### Load packages` markdown + code cell with imports
6. **Main content** — alternating markdown explanations and code cells
7. **Conclusion / Next steps** — summary or follow-up ideas

## Patterns

### Beginners Guide

- State prerequisites and learning goals up front
- Step-by-step flow: short markdown explanation → small runnable code cell → brief interpretation
- Include at least one exercise reinforcing the key concept
- Call out common mistakes and how to fix them

### Case Study

- State the question and success criteria
- Keep configuration (area of interest, time range, product) in one cell near the top
- Start with smallest runnable example before adding complexity
- Summarize findings in markdown near the relevant code
- End with conclusions and next steps

## Editing Rules

- Preserve cell order unless it improves the top-to-bottom narrative
- Prefer targeted edits over full rewrites
- Keep `execution_count` as `null` and `outputs` as `[]` for new or cleaned cells
- Remove large noisy outputs; replace with short summaries when possible
- Avoid hidden state: ensure early cells set all required imports and config
- When adding imports, check existing notebooks for the import style used in this project

## Quality Checklist

- Every code cell runs independently given the cells above it
- No giant outputs — prefer tables, key metrics, or short printouts
- Narrative is skimmable: headings and short bullets, not long paragraphs
- Configuration (AOI, dates, product) is centralized, not scattered
- Relative links to other notebooks use correct paths (e.g., `../Beginners_Guide/01_Jupyter_101.ipynb`)

## Stack Reference

This project uses Python 3.12 with `uv` for dependency management.

**Core geospatial:**
`datacube`, `odc.stac`, `odc.geo`, `odc.algo`, `odc.ui`, `dea-tools`, `eo-tides`, `pystac`, `pystac-client`, `planetary-computer`

**Data & viz:**
`numpy`, `pandas`, `xarray`, `matplotlib`, `scipy`, `scikit-image`, `scikit-learn`, `folium`, `geopandas`, `ipyleaflet`

**Compute:**
`dask[distributed]`, `bokeh`

**Cloud/IO:**
`boto3`, `s3fs`, `s3path`

**Jupyter:**
`jupyterlab`, `ipykernel`, `ipywidgets`, `jupyterlab-myst`, `nbconvert`, `jupyter-resource-usage`

Install extras via: `uv sync --extra notebooks` or `uv sync --extra jupyter`
