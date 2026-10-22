# Scanno

Scanno is an on-device document library and reader built with Flutter.

## PDF reader

The PDF viewer uses Syncfusion Flutter PDF Viewer `35.1.41` (Android supported;
Flutter `>=3.35.1`, Dart `^3.7.0`). Syncfusion requires a commercial license or
eligibility for its Community License. Confirm that the app's distribution
continues to comply with the applicable Syncfusion license.

The reader provides page navigation, text search, text selection, and PDF text
markup annotations (highlight, underline, and strikethrough), sticky-note
comments. The three-dot PDF tools menu keeps annotation controls out of the
document viewport. Comments use the viewer's native sticky-note interaction.

Use **Save annotations to Scanno** in the tools menu to write markup and
comments into a new managed PDF copy. The existing export action exports the
saved copy. The originally imported source file is not modified.

The viewer does not provide OCR. Search can find text encoded in a PDF but
cannot search image-only scanned pages.

Text markup and sticky-note comments use the PDF viewer's native annotation
model and are embedded in the saved managed copy.

## Android Open With and multi-format reading

Scanno registers Android `ACTION_VIEW` and single-file `ACTION_SEND` handlers
for PDF, Office, text/CSV/Markdown, RTF, and common image MIME types. Incoming
`content://` streams are copied to a temporary private cache for viewing; the
sender's file is not modified. An incoming document is **not** added to the
library unless the user selects **Import**. Imports are streamed into Scanno's
managed storage and repeated imports of identical content reuse the existing
library record.

PDFs continue to use Syncfusion. DOCX, XLSX, PPTX, XLS, CSV, RTF, DOC, and PPT
use `offline_document_viewer` `0.1.0`, which renders offline on-device. DOCX,
XLSX, and PPTX are rendered with bundled engines; legacy DOC and PPT are
text-only, and legacy XLS values are shown without cell styling. Charts,
conditional formatting, pivot tables, and some presentation layout features
are not rendered. Markdown is shown as selectable plain text. Office previews
are read-only, and files larger than the viewer's 80 MiB input limit are
offered an external-app fallback before the viewer reads them into memory.
Scanno uses a local patch of the Office viewer so long DOCX files use layout
zoom instead of one transformed multi-page layer, avoiding blank later pages
in Android WebView. PPTX rendering now waits for the renderer's explicit
completion signal after asynchronous file reading, instead of treating a
briefly quiet DOM as completion. The workspace cache revision is bumped with
viewer changes. PPTX shapes that omit position or size transforms now inherit
available slide-layout/master geometry; when none is available, the renderer
falls back to a non-SVG representation while preserving associated text,
instead of aborting the full presentation render.

The Office viewer package is MIT-licensed, and its bundled engines and fonts
have separate licenses. Scanno includes the required
[third-party notices](assets/THIRD_PARTY_NOTICES.md), accessible in-app from
the library's information button, along with the bundled license texts.
`neo_office` was not selected because its published package page lists Android
support as planned despite conflicting release notes.
