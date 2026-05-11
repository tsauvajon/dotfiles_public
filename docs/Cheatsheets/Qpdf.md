# Qpdf Cheatsheet

`qpdf` reads an input PDF, applies transformations, and writes an output PDF. It does not edit files in place.

| Task                             | Command                                                |
| -------------------------------- | ------------------------------------------------------ |
| Show help                        | `qpdf --help`                                          |
| Check PDF validity               | `qpdf --check file.pdf`                                |
| Show encryption info             | `qpdf --show-encryption file.pdf`                      |
| Linearize for web viewing        | `qpdf --linearize in.pdf out.pdf`                      |
| Decrypt with known password      | `qpdf --password=PASSWORD --decrypt in.pdf out.pdf`    |
| Remove restrictions when allowed | `qpdf --decrypt in.pdf out.pdf`                        |
| Compress object streams          | `qpdf --object-streams=generate in.pdf out.pdf`        |
| Preserve pages 1 through 3       | `qpdf in.pdf --pages . 1-3 -- out.pdf`                 |
| Extract pages 1, 3, and 5        | `qpdf in.pdf --pages . 1,3,5 -- out.pdf`               |
| Drop first page                  | `qpdf in.pdf --pages . 2-z -- out.pdf`                 |
| Merge PDFs                       | `qpdf --empty --pages a.pdf b.pdf c.pdf -- merged.pdf` |
| Merge selected ranges            | `qpdf --empty --pages a.pdf 1-3 b.pdf 4-z -- out.pdf`  |
| Rotate all pages clockwise       | `qpdf in.pdf --rotate=+90 -- out.pdf`                  |
| Rotate page 1 clockwise          | `qpdf in.pdf --rotate=+90:1 -- out.pdf`                |

Notes:

- Page ranges use `z` for the last page.
- The `--` separates page-selection input from the output filename.
- Use a new output filename, then replace the original after checking the result.
