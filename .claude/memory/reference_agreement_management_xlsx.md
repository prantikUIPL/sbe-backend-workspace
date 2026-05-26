---
name: reference-agreement-management-xlsx
description: Source-of-truth requirements file for the Agreement Management feature (Create Agreement and related stories). Living document — re-read whenever working on agreement features.
metadata:
  type: reference
  scope: project-local
---

`Agreement Management.xlsx` lives at `/Users/uipl/Desktop/uipl/sbe/Agreement Management.xlsx` (one level above the `admin-backend-api` repo root). It is the requirements document for the Agreement Management feature in the SBE admin backend.

Contains user stories across multiple sheets covering Create / List / Edit / Delete / Activate-Deactivate / Default / Product Association workflows for product-type agreements. The active branch `feature/SBE-372-create-agreement` implements the Create Agreement story from this file.

Read it via openpyxl (Python) — `.xlsx` is binary so the Read tool will not give useful output. Example:

```python
from openpyxl import load_workbook
wb = load_workbook("/Users/uipl/Desktop/uipl/sbe/Agreement Management.xlsx", data_only=True)
for ws in wb.worksheets:
    print(ws.title)
```

Treat this file as the requirements source-of-truth — if you see a conflict between the xlsx and code/comments, the xlsx wins unless the user says otherwise. Re-read on demand rather than caching its contents into memory, since requirements can change.
