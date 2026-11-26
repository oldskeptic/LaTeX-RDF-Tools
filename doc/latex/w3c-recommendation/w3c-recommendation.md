# W3C recommendation header reference
Author: Robert Warren

`w3c-recommendation.sty` provides a W3C Recommendations-style masthead for
both PDF output and HTML output produced through make4ht. The package keeps
the document source semantic while changing the presentation:

- PDF output uses a conventional title block, metadata, and table of contents.
- HTML output uses a title masthead, responsive table-of-contents rail, status
  ribbon, semantic metadata elements, and a collapsible details block.

## Minimal setup

Load the package and provide the document metadata before `\begin{document}`:

```latex
\documentclass[11pt,letterpaper]{article}
\usepackage{w3c-recommendation}

\WThreeCSetup{
  title={A Recommendation},
  status={Working Draft},
  date={11 September 2026},
  version={https://example.org/TR/example/},
  editors={An Editor (Example Organization)}
}

\begin{document}
\WThreeCStart
\maketitle
\WThreeCContents

\WThreeCAbstract{Summary of the document.}
\WThreeCStatus{Publication status and feedback instructions.}

\section{Introduction}
Document content goes here.

\WThreeCEnd
\end{document}
```

Use `\WThreeCStart` before `\maketitle` and `\WThreeCEnd` after the final
content. In HTML, those commands open and close the navigation shell. In PDF,
they do not add visible wrapper markup.

## `\WThreeCSetup{...}`

`\WThreeCSetup` accepts a comma-separated list of key-value pairs. Put braces
around values that contain commas.

```latex
\WThreeCSetup{
  title={RDF 1.2 Concepts and Abstract Data Model},
  subtitle={A technical specification},
  status={W3C Candidate Recommendation Draft},
  date={15 November 2022},
  version={https://www.w3.org/TR/2022/CRD-rdf12-concepts-20221115/},
  latest={https://www.w3.org/TR/rdf12-concepts/},
  editors={First Editor (Organization), Second Editor (Another Organization)},
  feedback={\href{https://github.com/example/spec/issues}{GitHub issue tracker}},
  organization={World Wide Web Consortium},
  documentnumber={W3C Recommendation 2026/01},
  copyright={Copyright © 2026 World Wide Web Consortium.},
  logo={figures/organization-logo.png},
  shortname={example}
}
```

### Header fields

| Key | Default | Where it appears | Guidance |
| --- | --- | --- | --- |
| `title` | `Untitled Recommendation` | Main title and document title metadata | The primary document title. It is also registered with LaTeX's standard `\title` command for TeX4ht compatibility. |
| `subtitle` | Empty | Below the title | Optional secondary title or publication label. |
| `status` | `Working Draft` | Below the title and in the HTML status ribbon | Use the publication status, such as `W3C Recommendation`, `Working Draft`, or `Candidate Recommendation Draft`. |
| `date` | `\today` | Below the status | Supply the publication date as display text, for example `15 November 2022`. |
| `version` | Empty | Below the date | URL for this exact version. Pass the bare URL; the package creates the link. |
| `latest` | Empty | Below the version | Optional URL for the latest published version. It is prefixed with `Latest published version:`. |
| `editors` | Empty | Metadata block | Editor names and affiliations. Use `\\` for separate lines when needed. |
| `feedback` | Empty | Metadata block | Feedback instructions, email address, issue tracker, or a `\href{...}{...}` link. |
| `organization` | Empty | Metadata block | Working group, organization, or other sponsoring body. |
| `documentnumber` | Empty | Metadata block | Optional document identifier, such as an OGC or W3C document number. |
| `copyright` | Empty | Below the metadata and in the HTML footer | Copyright and licensing notice. It is printed as supplied. |
| `logo` | Empty | Right side of the masthead | Path to an image file. If the path does not exist, the value is shown as text. With no value, the masthead uses a text `W3C` mark. |
| `shortname` | Empty | Reserved metadata setting | Accepted for compatibility with W3C naming conventions, but it is not currently rendered by the package. |

### URLs and links

`version` and `latest` are automatically passed through `\url`, so provide
plain URL values:

```latex
version={https://example.org/TR/example/}
```

For a labeled link in another field, use `\href`:

```latex
feedback={\href{mailto:comments@example.org}{comments@example.org}}
```

The `hyperref` package is loaded by `w3c-recommendation.sty`, so `\href` and
`\url` are available without loading it separately.

## Babel language profiles

Load Babel before the style package and define one W3C metadata profile for
each document language:

```latex
\usepackage[english,french]{babel}
\usepackage{w3c-recommendation}

\WThreeCLanguageSetup{english}{
  title={RDF 1.2 Concepts and Abstract Data Model},
  status={Working Draft},
  language-code={en},
  abstract-label={Abstract},
  status-label={Status of This Document}
}

\WThreeCLanguageSetup{french}{
  title={Concepts et modèle de données abstrait RDF 1.2},
  status={Brouillon de travail},
  language-code={fr},
  abstract-label={Résumé},
  status-label={État de ce document}
}

\selectlanguage{french}
```

`\WThreeCLanguageSetup{<babel-language>}{<fields>}` stores a complete
language-specific override for the same fields accepted by
`\WThreeCSetup`. The language name must match Babel's language name, such as
`english`, `french`, `german`, or `spanish`.

At `\begin{document}`, the style reads Babel's active `\languagename` and
selects the matching profile automatically. To select a profile explicitly,
use the optional language argument:

```latex
\WThreeCSelectLanguage[french]
```

The explicit form is useful when the language is changed after the document
has begun. If no matching profile exists, the base values from
`\WThreeCSetup` remain active.

### Language-specific header keys

Language profiles accept all normal header keys plus these optional keys:

| Key | Purpose |
| --- | --- |
| `language-code` | Adds an HTML `lang` attribute to the W3C content shell, such as `en`, `fr`, or `fr-CA`. |
| `toc-label` | Label for the HTML table-of-contents rail. |
| `abstract-label` | Heading and table-of-contents label for the abstract. |
| `status-label` | Heading and table-of-contents label for the document status. |
| `latest-label` | Label before the latest-version URL. |
| `details-label` | Label for the supplementary details block. |
| `editors-label` | Metadata label for editors. |
| `feedback-label` | Metadata label for feedback. |
| `organization-label` | Metadata label for the organization. |
| `documentnumber-label` | Metadata label for the document number. |
| `language-links-label` | Accessible label for the language-version links. |

The labels default to English unless overridden in the selected profile.

### Links to other HTML language editions

Add one or more optional language links with:

```latex
\WThreeCLanguageLink{English}{rdf12-en.html}
\WThreeCLanguageLink{Français}{rdf12-fr.html}
```

These links are rendered in the HTML title header as an accessible navigation
group. They are intentionally omitted from PDF output. The command does not
generate the other files; each language edition must be built separately with
the corresponding Babel language active.

### Editors and multiple lines

Use `\\` inside a field when the value should have separate lines:

```latex
editors={%
  First Editor (Example Organization)\\
  Second Editor (Another Organization)
}
```

Values containing commas must be enclosed in an additional pair of braces so
the comma is not interpreted as the separator between setup keys:

```latex
editors={{First Editor, Ph.D.} (Example Organization)}
```

## Document commands

These are the public commands used to place the header and front matter.

### `\WThreeCStart`

Starts the W3C document layout.

```latex
\WThreeCStart
```

In HTML, this emits the status ribbon, table-of-contents sidebar, and main
content container. In PDF, it is intentionally invisible.

Call it once, before `\maketitle`.

### `\maketitle`

The package replaces the standard article title rendering with the W3C
masthead:

```latex
\maketitle
```

The masthead prints the configured title, subtitle, status, date, version,
latest-version link, logo, metadata fields, and copyright notice.

### `\WThreeCContents`

Adds the table of contents in PDF output:

```latex
\WThreeCContents
```

In HTML, the table of contents is already placed in the left navigation rail
by `\WThreeCStart`, so this command has no additional visible effect.

Call it after `\maketitle` when producing PDF output.

### `\WThreeCAbstract{...}`

Adds an `Abstract` heading and body text:

```latex
\WThreeCAbstract{%
  This specification defines the abstract data model and terminology
  used by the language.
}
```

The abstract is added to the table of contents. In HTML, it is emitted as a
semantic `<section>` with an `h2` heading.

### `\WThreeCStatus{...}`

Adds a `Status of This Document` heading and body text:

```latex
\WThreeCStatus{%
  This section describes the status of this document at the time of its
  publication.
}
```

The status section is added to the table of contents. In HTML, it is emitted
as a semantic `<section>` with an `h2` heading.

### `\WThreeCMoreDetails{...}`

Adds supplementary document metadata or publication links:

```latex
\WThreeCMoreDetails{%
  This document is maintained in the
  \href{https://github.com/example/spec}{project repository}.
  Previous versions are listed in the publication history.
}
```

In HTML, the content is placed inside an expandable `<details>` element. In
PDF, it is displayed as a labeled blockquote so the information remains
available even though PDF does not have the same native disclosure control.

### `\WThreeCEnd`

Closes the W3C document layout:

```latex
\WThreeCEnd
```

In HTML, this emits the copyright footer and closes the main content and
navigation containers. In PDF, it is intentionally invisible. Call it once,
after the final section, figure, table, or bibliography content.

## Complete header template

The following is a complete front matter template that can be copied into a
new document:

```latex
\documentclass[11pt,letterpaper]{article}
\usepackage{w3c-recommendation}

\WThreeCSetup{
  title={RDF 1.2 Concepts and Abstract Data Model},
  subtitle={Abstract Data Model},
  status={W3C Recommendation},
  date={11 September 2026},
  version={https://www.w3.org/TR/rdf12-concepts/},
  latest={https://www.w3.org/TR/rdf12-concepts/},
  editors={%
    Example Editor (Example Organization)\\
    Second Editor (Another Organization)
  },
  feedback={%
    \href{https://github.com/example/rdf12-concepts/issues}{GitHub issue tracker}
  },
  organization={World Wide Web Consortium},
  documentnumber={W3C RDF 1.2},
  copyright={%
    Copyright © 2026 World Wide Web Consortium.
  },
  logo={figures/w3c-logo.png}
}

\begin{document}
\WThreeCStart
\maketitle
\WThreeCMoreDetails{%
  This document is part of the RDF 1.2 publication family.
}
\WThreeCContents

\WThreeCAbstract{%
  The abstract appears here.
}

\WThreeCStatus{%
  The publication status appears here.
}

\section{Introduction}
The document body begins here.

\WThreeCEnd
\end{document}
```

## Output differences

The same source supports both output modes:

| Feature | PDF | make4ht HTML |
| --- | --- | --- |
| Masthead | Title, metadata, logo, and copyright block | Same information with semantic header and metadata elements |
| Table of contents | Normal table of contents after the masthead | Responsive left navigation rail |
| Status | Normal document metadata and status section | Metadata plus vertical status ribbon |
| More details | Always visible labeled blockquote | Expandable `<details>` element |
| Sections | Blue LaTeX headings | Blue responsive HTML headings |
| Footer | Page numbers | Copyright footer |
