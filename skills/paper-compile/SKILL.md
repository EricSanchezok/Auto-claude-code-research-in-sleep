---
name: paper-compile
description: "Compile LaTeX paper to PDF, fix errors, and verify output. Use when user says \"编译论文\", \"compile paper\", \"build PDF\", \"生成PDF\", or wants to compile LaTeX into a submission-ready PDF."
argument-hint: [paper-directory]
allowed-tools: Bash(*), Read, Write, Edit, Grep, Glob
---

# Paper Compile: LaTeX to Submission-Ready PDF

Compile the LaTeX paper and fix any issues: **$ARGUMENTS**

## Constants

- **COMPILER = `latexmk`** — LaTeX build tool. Handles multi-pass compilation automatically.
- **ENGINE = `pdflatex`** — LaTeX engine. Options: `pdflatex` (default), `xelatex` (for CJK/custom fonts), `lualatex`.
- **MAX_COMPILE_ATTEMPTS = 3** — Maximum attempts to fix errors and recompile.
- **PAPER_DIR = `paper/`** — Directory containing LaTeX source files.

## Workflow

### Step 1: Verify Prerequisites

Check that the compilation environment is ready:

```bash
# Check LaTeX installation
which pdflatex && which latexmk && which bibtex

# If not installed, provide instructions:
# macOS: brew install --cask mactex-no-gui
# Ubuntu: sudo apt-get install texlive-full
# Server: conda install -c conda-forge texlive-core
```

Verify all required files exist:

```bash
# Must exist
ls $PAPER_DIR/main.tex

# Should exist
ls $PAPER_DIR/references.bib
ls $PAPER_DIR/sections/*.tex
ls $PAPER_DIR/figures/*.pdf 2>/dev/null || ls $PAPER_DIR/figures/*.png 2>/dev/null
```

### Step 2: First Compilation Attempt

```bash
cd $PAPER_DIR

# Clean previous build artifacts
latexmk -C

# Full compilation (pdflatex + bibtex + pdflatex × 2)
latexmk -pdf -interaction=nonstopmode -halt-on-error main.tex 2>&1 | tee compile.log
```

### Step 3: Error Diagnosis and Auto-Fix

If compilation fails, read `compile.log` and fix common errors:

**Missing packages:**
```
! LaTeX Error: File `somepackage.sty' not found.
```
→ Install via `tlmgr install somepackage` or remove the `\usepackage` if unused.

**Undefined references:**
```
LaTeX Warning: Reference `fig:xyz' on page 3 undefined
```
→ Check `\label{fig:xyz}` exists in the correct figure environment.

**Missing figures:**
```
! LaTeX Error: File `figures/fig1.pdf' not found.
```
→ Check if the file exists with a different extension (.png vs .pdf). Update the `\includegraphics` path.

**Citation undefined:**
```
LaTeX Warning: Citation `smith2024' undefined
```
→ Add the missing entry to `references.bib` or fix the citation key.

**`[VERIFY]` markers in text:**
→ Search for `[VERIFY]` markers left by `/paper-write`. These indicate unverified citations. Search for the correct BibTeX entry or flag to the user.

**Overfull hbox:**
```
Overfull \hbox (12.5pt too wide) in paragraph at lines 42--45
```
→ Minor: usually ignorable. If severe (>20pt), rephrase the text or adjust figure width.

**BibTeX errors:**
```
I was expecting a `,' or a `}'---line 15 of references.bib
```
→ Fix BibTeX syntax (missing comma, unmatched braces, special characters in title).

### Step 4: Iterative Fix Loop

```
for attempt in 1..MAX_COMPILE_ATTEMPTS:
    compile()
    if success:
        break
    parse_errors()
    auto_fix()
```

For each error:
1. Read the error message from `compile.log`
2. Locate the source file and line number
3. Apply the fix
4. Recompile

### Step 5: Post-Compilation Checks

After successful compilation, verify the output:

```bash
# Check PDF exists and has content
ls -la main.pdf
# Check page count
pdfinfo main.pdf | grep Pages

# macOS: open for visual inspection
# open main.pdf
```

**Automated checks:**

- [ ] PDF file exists and is > 100KB (not empty/corrupt)
- [ ] Page count is within MAX_PAGES + appendix
- [ ] No "??" in the PDF (undefined references — grep the log)
- [ ] No "[?]" in the PDF (undefined citations — grep the log)
- [ ] Figures are rendered (not missing image placeholders)

```bash
# Check for undefined references
grep -c "LaTeX Warning.*undefined" compile.log

# Check for missing citations
grep -c "Citation.*undefined" compile.log
```

### Step 6: Submission Readiness

For conference submission, additional checks:

- [ ] **Anonymous**: no author names, affiliations, or self-citations that reveal identity
- [ ] **Page limit**: main body within MAX_PAGES (check with `\usepackage{ruler}` if needed)
- [ ] **Font embedding**: all fonts embedded in PDF
  ```bash
  pdffonts main.pdf | grep -v "yes"  # should return nothing
  ```
- [ ] **No supplementary mixed in**: appendix clearly after `\newpage\appendix`
- [ ] **File size**: reasonable (< 50MB for most venues, < 10MB preferred)

### Step 7: Output Summary

```markdown
## Compilation Report

- **Status**: SUCCESS / FAILED
- **PDF**: paper/main.pdf
- **Pages**: X (main body) + Y (appendix) + Z (references)
- **Errors fixed**: [list of auto-fixed issues]
- **Warnings remaining**: [list of non-critical warnings]
- **Undefined references**: 0
- **Undefined citations**: 0

### Next Steps
- [ ] Visual inspection of PDF
- [ ] Run `/paper-write` to fix any content issues
- [ ] Submit to [venue] via OpenReview / CMT / HotCRP
```

## Key Rules

- **Never delete the user's source files** — only modify to fix errors
- **Keep compile.log** — useful for debugging
- **Don't suppress warnings** — report them, let the user decide
- **If LaTeX is not installed**, provide clear installation instructions rather than failing silently
- **Font embedding is critical** — some venues reject PDFs with non-embedded fonts

## Common Venue Requirements

| Venue | Style File | Citation | Page Limit | Submission |
|-------|-----------|----------|------------|------------|
| ICLR 2026 | `iclr2026_conference.sty` | `natbib` (`\citep`/`\citet`) | 9 pages + unlimited appendix | OpenReview |
| NeurIPS 2025 | `neurips_2025.sty` | `natbib` (`\citep`/`\citet`) | 9 pages + unlimited appendix | OpenReview |
| ICML 2025 | `icml2025.sty` | `natbib` (`\citep`/`\citet`) | 8 pages + unlimited appendix | OpenReview |
