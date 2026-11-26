# LaTeX-RDF-Tools

**Author:** Robert Warren

LaTeX-RDF-Tools distributes the RDFTools and w3c-recommendation LaTeX packages. It includes their user documentation, examples, and a complete reference manual.

RDFTools lets you load vocabularies and refer to their terms directly in your LaTeX prose, showing names, language-aware definitions, URIs, and class or property hierarchies. It can also render RDF fragments as numbered, captioned listings, create glossaries from terms, and generate BIBO citations from RDF data.

If you write LaTeX papers about RDF / OWL datasets, this package is for you.

## License

The included package source and documentation are distributed under the LaTeX Project Public License, version 1.3c (LPPL 1.3c). See `LICENSE`.

## Included packages

- **RDFTools** — RDF fragment listings, vocabulary lookups, hierarchy commands, and optional glossaries and Bibtex integration.
- **w3c-recommendation** — LaTeX layout and metadata commands for W3C-style recommendation documents.

## External dependency

**Lua4HT** is an optional external dependency for the direct LuaLaTeX/TeX4ht HTML-conversion workflow documented in the reference and examples. It is not included in this archive; install it separately from [its upstream project](https://github.com/michal-h21/lua4ht). It is not required for PDF output or RDFTools lookups. TeX4ht is also needed for the HTML workflow.

## Archive layout

- `tex/latex/RDFTools/` — RDFTools style files and Lua helper.
- `tex/latex/w3c-recommendation/` — W3C recommendation style file.
- `doc/latex/RDFTools/` — RDFTools examples and sample RDF data.
- `doc/latex/w3c-recommendation/` — W3C package guide and examples.
- `doc/latex/lua4ht/` — example source for the optional external conversion workflow; no Lua4HT implementation files are bundled.
- `doc/latex/LaTeX-RDF-Tools/` — PDF reference, editable source, screenshots, and manual README.

## Requirements and installation

RDFTools requires `texlua`, LuaFileSystem (`lfs`), LuaSocket (`socket.url`), and trusted shell escape. HTTPS RDF sources also require `curl`. Glossary support requires the LaTeX `glossaries` package. The W3C style uses `xkeyval`, `geometry`, `graphicx`, `fancyhdr`, `hyperref`, `url`, and `xcolor`.

This archive uses TDS paths under the `LaTeX-RDF-Tools/` package directory. Extract it, then copy the `tex/` and `doc/` directories from `LaTeX-RDF-Tools/` to the root of a personal or system TeX tree. Add the TeX directory to the filename database if required. Alternatively, add the package directories to `TEXINPUTS`.

For PDFLaTeX, enable shell escape when using RDFTools:

```sh
pdflatex -shell-escape -interaction=nonstopmode document.tex
```

## Documentation

The reference PDF and source are in `doc/latex/LaTeX-RDF-Tools/`. From that directory, rebuild the manual with:

```sh
tectonic style-reference.tex
```

