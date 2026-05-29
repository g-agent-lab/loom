# Ralphex Iteration Plan Template

> Canonical template для нарезки draft → iteration plans (`docs/plans/active/<pack-id>-<slug>.md`).
> Parser contract — **verified против реального движка** (`umputun/ralphex`, `pkg/plan/parse.go`).
> Sizing — 3-7 tasks per plan, 30-150 LOC body per task.

---

## Naming

File path: `docs/plans/active/<pack-id>-<slug>.md`

- `<pack-id>`: sortable, например `01-pack-name`, `pack-a-name`, `feature-X.1`. Используется для ordering.
- `<slug>`: kebab-case short description.

Примеры: `01-auth-foundation.md`, `pack-a-thread-binding.md`, `feature-3.2-attachment-upload.md`.

---

## Required header

```markdown
# <Plan Title>

> **Source draft:** [link to docs/plans/drafts/NN-<topic>.md]
> **Pack:** <Pack A / Pack 1 / etc., если есть series>
> **Architecture constraints:** см. CLAUDE.md § Architecture invariants
```

---

## Required sections (в этом порядке)

### `## Overview`

1-3 sentences: что плана делает и зачем. Без implementation details.

### `## Context`

```markdown
## Context

- **Files involved:**
  - `<path>` — <brief role>
  - `<path>` — <brief role>
- **Related patterns:**
  - <existing pattern в репо, на который опираемся>
- **Dependencies:**
  - <external deps: services, APIs, libraries>
```

### `## Development Approach`

```markdown
## Development Approach

- **Testing approach:** Test-first | Regular | Mixed
- **Architecture constraints:** CLAUDE.md § Architecture invariants
- **CI gates (must pass after each task):**
  - <stack-specific commands из overlays/<stack>.md § "Command map">
- **CRITICAL:**
  - <3-5 statements специфичных для Pack'а, e.g. "must not modify public API of X module">
  - <e.g. "preserve backward-compat for clients using v1">
```

### `## Implementation Steps`

Tasks 1..N следуют parser-strict format.

---

## Task structure (parser-strict)

### `### Task N: <english title>` (или `### Iteration N:`)

Parser contract (verified against `pkg/plan/parse.go`):

- Ровно три `#`, пробел(ы), литеральное **`Task` ИЛИ `Iteration`** (оба валидны), пробел(ы), идентификатор, двоеточие.
- Ключевое слово `Task`/`Iteration` не переводить — иначе header не распознаётся.
- Номер: целое даёт порядковый номер; нецелое (`2.5`, `2a`) не ломает парсинг, но получает номер `0`. Держи целые по возрастанию.
- Title — свободный текст, парсеру безразличен; по конвенции — английский.
- Без вариаций: ❌ `### Task N.` (без colon), ❌ `### Шаг N:` (translation), ❌ `### Task N - Title` (dash вместо colon), ❌ `#### Task N:` (4 hashes)

#### Task body

```markdown
### Task N: <english title>
**Files:**
- Modify: `<path>`
- Create: `<path>`
- Delete: `<path>` (если применимо)

- [ ] <concrete step 1>
- [ ] <concrete step 2>
- [ ] add/update tests for <scope>
- [ ] run full test suite
```

Чекбоксы: `- [ ]` / `- [x]`, допускается leading whitespace для вложенных подпунктов.

#### Body size (30-150 lines)

- <30 lines → недостаточно контекста для LLM, лучше merge с другой task
- >150 lines → слишком крупно для одного fresh-session tick, лучше split

#### Linear dependencies

Task N может зависеть от 1..N-1. Task N-1 НЕ может зависеть от Task N. Никаких backward refs.

---

## Required final tasks

Каждый план ОБЯЗАТЕЛЬНО имеет последние 2 task'а:

```markdown
### Task N-1: Verify acceptance criteria
- [ ] run full test suite
- [ ] run linter
- [ ] run <stack-specific architecture guard, e.g. `cd api && npm run lint:arch:diff`>
- [ ] verify <project-specific acceptance criterion 1>
- [ ] verify <project-specific acceptance criterion 2>

### Task N: Update documentation
- [ ] update CLAUDE.md if patterns changed
- [ ] run docs lint
- [ ] if Prisma model added/removed (or equivalent): update reference/data-model.md
- [ ] if controller added: update reference/api-endpoints.md
- [ ] if env var added: update reference/env-variables.md
- [ ] if interface added: update reference/contracts.md
- [ ] if plan lifecycle changed: update docs/plans/ROADMAP.md
- [ ] NOTE: do NOT move plan file manually — ralphex CLI auto-moves successful plans into docs/plans/active/completed/
- [ ] NOTE: move the draft to docs/plans/drafts/done/ only when no active iterations remain (manual; ralphex does not manage drafts)
```

---

## Sizing rules summary

| Constraint | Value |
|---|---|
| Tasks per plan | **3-7** (если >10 — split на 2+ packs) |
| Body per task | **30-150 LOC** |
| Task dependencies | Linear (Task N → 1..N-1, не наоборот) |
| Tests per task | Mandatory (no «tests later») |
| Done-criteria | Только automatable (✅ `test green`, ❌ `manually verified`) |

---

## Pre-slicing checklist

Прежде чем создавать iteration plan:

- [ ] Все blockers Codex review закрыты в draft'е
- [ ] Каждый pack имеет explicit Files list (конкретные пути)
- [ ] Acceptance criteria (3-5 пунктов) для каждого pack'а
- [ ] Sequencing между packs задокументирован (если series)
- [ ] API surface (interfaces, signatures) verified против реального кода
- [ ] Architecture constraints проверены для каждого затрагиваемого файла

---

## Anti-patterns (нарушают parser или sizing)

- ❌ `### Task N.` (без colon) — parser не найдёт task
- ❌ `### Шаг N:` или другой translated header — parser не найдёт
- ❌ `### Task N - Title` (dash вместо colon)
- ❌ `#### Task N:` (4 hash вместо 3)
- ❌ Перевод/перефразировка `Task`/`Iteration` keyword
- ❌ Слить 2 `### Task` headers в один большой («сэкономлю iteration»)
- ❌ Положить fixes в `Verify acceptance criteria` task (verify ≠ fix)
- ❌ Manual `git mv` plan в `completed/` (ralphex auto-moves)
- ❌ Done-criteria формата «manually tested» (non-automatable)
- ❌ Linear dependency нарушение: Task 2 trying to use результат Task 5
- ❌ Task body <30 LOC: «add a getter» — мало контекста для fresh session
- ❌ Task body >150 LOC: «refactor service A to facade + 5 sub-services» — split
```
