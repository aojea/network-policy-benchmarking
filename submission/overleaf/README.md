# Overleaf Working Draft

Self-contained copy of the network-policy paper draft, formatted using the
[official USENIX template](https://www.usenix.org/conferences/author-resources/paper-templates).
This remains an AI-generated, non-submission writing exercise. The manuscript's
editorial notice and evidence qualifications are preserved.

## Import

1. In Overleaf, select **New Project > Upload Project** and upload the supplied ZIP.
2. Set the main document to **main.tex** if it is not selected automatically.
3. Use **pdfLaTeX** and TeX Live **2025 or later**.
4. Select **Recompile**. Overleaf runs BibTeX automatically.

The ZIP places all project files at its root. No benchmark checkout, external
data files, shell escape, or additional downloads are needed to compile.

## Project Files

- [main.tex](main.tex): complete manuscript, including TikZ diagrams and PGFPlots figures.
- [references.bib](references.bib): bibliography using the standard `plain` style.
- [usenix2019_v3.sty](usenix2019_v3.sty): official USENIX conference-paper style.

The document follows the template's letter paper, two columns, 10-point type,
and 7-by-9-inch text block. Page numbers remain enabled for draft review.
The standard packages used by the manuscript are included in Overleaf's
TeX Live distribution.

## Local Build

Run from this project directory:

```sh
pdflatex -interaction=nonstopmode -halt-on-error main.tex
bibtex main
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
```

This folder is a standalone snapshot of the preparation draft. Changes here or
in Overleaf are not automatically synchronized with the original manuscript.
