---
name: paper-write
description: "Draft LaTeX paper section by section from an outline. Use when user says \"写论文\", \"write paper\", \"draft LaTeX\", \"开始写\", or wants to generate LaTeX content from a paper plan."
argument-hint: [venue-or-section]
allowed-tools: Bash(*), Read, Write, Edit, Grep, Glob, Agent, WebSearch, WebFetch, mcp__codex__codex, mcp__codex__codex-reply
---

# Paper Write: Section-by-Section LaTeX Generation

Draft a LaTeX paper based on: **$ARGUMENTS**

## Constants

- **REVIEWER_MODEL = `gpt-5.4`** — Model used via Codex MCP for section review. Must be an OpenAI model.
- **TARGET_VENUE = `ICLR`** — Default venue. Supported: `ICLR`, `NeurIPS`, `ICML`. Determines style file and formatting.
- **ANONYMOUS = true** — If true, use anonymous author block. Set `false` for camera-ready.
- **MAX_PAGES = 9** — Main body page limit (excluding references and appendix).

## Inputs

1. **PAPER_PLAN.md** — outline with claims-evidence matrix, section plan, figure plan (from `/paper-plan`)
2. **Generated figures** — PDF/PNG files in `figures/` (from `/paper-figure`)
3. **LaTeX includes** — `figures/latex_includes.tex` (from `/paper-figure`)
4. **Bibliography** — existing `.bib` file, or will create one

If no PAPER_PLAN.md exists, ask the user to run `/paper-plan` first or provide a brief outline.

## Templates

### Venue-Specific Setup

The skill includes conference templates. Select based on TARGET_VENUE:

**ICLR:**
```latex
\documentclass{article}
\usepackage{iclr2026_conference,times}
% \iclrfinalcopy  % Uncomment for camera-ready
```

**NeurIPS:**
```latex
\documentclass{article}
\usepackage[preprint]{neurips_2025}
% \usepackage[final]{neurips_2025}  % Camera-ready
```

**ICML:**
```latex
\documentclass[accepted]{icml2025}
% Use [accepted] for camera-ready
```

### Project Structure

Generate this file structure:

```
paper/
├── main.tex                    # master file (includes sections)
├── iclr2026_conference.sty     # or neurips_2025.sty / icml2025.sty
├── math_commands.tex           # shared math macros
├── references.bib              # bibliography
├── sections/
│   ├── 0_abstract.tex
│   ├── 1_introduction.tex
│   ├── 2_related_work.tex
│   ├── 3_method.tex            # or preliminaries, setup, etc.
│   ├── 4_experiments.tex
│   ├── 5_conclusion.tex
│   └── A_appendix.tex
└── figures/                    # symlink or copy from project figures/
```

## Workflow

### Step 1: Initialize Project

1. Create `paper/` directory
2. Copy venue style file (from templates/ or download)
3. Generate `main.tex` master file with:
   - Document class and packages
   - Anonymous author block (or placeholder)
   - `\input{sections/X.tex}` for each section
   - Bibliography setup

**Author block (anonymous mode):**
```latex
\author{Anonymous Authors}
```

**Author block (camera-ready mode):**
```latex
% Author information to be filled by the user
\author{
  [Author Name] \\
  [Affiliation] \\
  \texttt{[email]} \\
}
```

### Step 2: Generate math_commands.tex

Create shared math macros based on the paper's notation:

```latex
% math_commands.tex — shared notation
\newcommand{\R}{\mathbb{R}}
\newcommand{\E}{\mathbb{E}}
\newcommand{\N}{\mathcal{N}}
\DeclareMathOperator*{\argmin}{arg\,min}
\DeclareMathOperator*{\argmax}{arg\,max}
% Add paper-specific notation here
```

### Step 3: Write Each Section

Process sections in order. For each section:

1. **Read the plan** — what claims, evidence, citations belong here
2. **Draft content** — write complete LaTeX (not placeholders)
3. **Insert figures/tables** — use snippets from `figures/latex_includes.tex`
4. **Add citations** — use `\citep{}` / `\citet{}` (all three venues use `natbib`)

#### Section-Specific Guidelines

**§0 Abstract:**
- Must be self-contained (understandable without reading the paper)
- Structure: problem → approach → key result → implication
- Include one concrete quantitative result
- 150-250 words (check venue limit)
- No citations, no undefined acronyms

**§1 Introduction:**
- Open with a compelling hook (1-2 sentences, problem motivation)
- State the gap clearly ("However, ...")
- List contributions as a numbered or bulleted list
- End with a brief roadmap ("The rest of this paper is organized as...")
- Include the main result figure if space allows
- Target: 1.5 pages

**§2 Related Work:**
- Organize by category, not chronologically
- Each category: 1 paragraph summarizing the line of work + 1 sentence positioning this paper
- Use `\paragraph{Category Name.}` for subsections within related work
- Do NOT just list papers — synthesize and compare
- Target: 1 page

**§3 Method / Preliminaries / Setup:**
- Define notation early (reference math_commands.tex)
- Use `\begin{definition}`, `\begin{theorem}` environments for formal statements
- Include algorithm pseudocode if applicable (`algorithm2e` or `algorithmic`)
- Target: 1.5-2 pages

**§4 Experiments:**
- Start with experimental setup (datasets, baselines, metrics, implementation details)
- Main results table/figure first
- Then ablations and analysis
- Every claim from the introduction must have supporting evidence here
- Target: 2.5-3 pages

**§5 Conclusion:**
- Summarize contributions (NOT copy-paste from intro — rephrase)
- Limitations (be honest — reviewers appreciate this)
- Future work (1-2 concrete directions)
- Target: 0.5 pages

**Appendix:**
- Proof details, additional experiments, implementation details
- Full hyperparameter tables
- Additional visualizations

### Step 4: Build Bibliography

1. Scan all `\citep{}` and `\citet{}` references in the drafted sections
2. For each citation key:
   - Check existing `.bib` files in the project
   - If not found, search arXiv/Scholar for correct BibTeX
   - **NEVER fabricate BibTeX entries** — mark unknown ones as `[VERIFY]`
3. Write `references.bib`

**Citation verification rules:**
1. Every BibTeX entry must have: author, title, year, venue/journal
2. Prefer published venue versions over arXiv preprints (if published)
3. Use consistent key format: `{firstauthor}{year}{keyword}` (e.g., `ho2020denoising`)
4. Double-check year and venue for every entry

### Step 5: Cross-Review Draft

Send the complete draft to REVIEWER_MODEL:

```
mcp__codex__codex:
  model: gpt-5.4
  config: {"model_reasoning_effort": "xhigh"}
  prompt: |
    Review this [VENUE] paper draft. Focus on:
    1. Does each claim have supporting evidence?
    2. Is the writing clear and concise?
    3. Any logical gaps or unclear explanations?
    4. Does it fit within [MAX_PAGES] pages?
    5. Missing related work?

    [paste full draft text]
```

Apply feedback and iterate.

### Step 6: Final Checks

Before declaring done:

- [ ] All `\ref{}` and `\label{}` match (no undefined references)
- [ ] All `\citep{}` / `\citet{}` have corresponding BibTeX entries
- [ ] No author information in anonymous mode
- [ ] Figure/table numbering is correct
- [ ] Page count within MAX_PAGES
- [ ] No TODO/FIXME/XXX markers left in the text
- [ ] Abstract is self-contained (understandable without reading the paper)
- [ ] Title is specific and informative (not generic)

## Key Rules

- **Do NOT generate author names, emails, or affiliations** — use anonymous block or placeholder
- **Write complete sections, not outlines** — the output should be compilable LaTeX
- **One file per section** — modular structure for easy editing
- **Every claim must cite evidence** — cross-reference the Claims-Evidence Matrix
- **Compile-ready** — the output should compile with `latexmk` without errors (modulo missing figures)
- **No over-claiming** — use hedging language ("suggests", "indicates") for weak evidence
- **Venue style matters** — all three venues (ICLR/NeurIPS/ICML) use `natbib` (`\citep`/`\citet`)

## Writing Quality Reference

Principles borrowed from [Research-Paper-Writing-Skills](https://github.com/Master-cai/Research-Paper-Writing-Skills):

1. **One message per paragraph** — each paragraph makes exactly one point
2. **Topic sentence first** — the first sentence states the paragraph's message
3. **Explicit transitions** — connect paragraphs with logical connectors
4. **Reverse outline test** — after writing, extract topic sentences; they should form a coherent narrative

## Acknowledgements

Writing methodology adapted from [Research-Paper-Writing-Skills](https://github.com/Master-cai/Research-Paper-Writing-Skills) (CCF award-winning methodology). Citation verification framework from [claude-scholar](https://github.com/Galaxy-Dawn/claude-scholar). Modular LaTeX structure inspired by real ICLR submissions.
