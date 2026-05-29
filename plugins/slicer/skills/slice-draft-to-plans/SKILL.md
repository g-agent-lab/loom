---
name: slice-draft-to-plans
description: Use when the user asks to slice a ready draft into ralphex-executable iteration plans, says "slice this draft", "нарезать draft", "сделать ralphex план", "create iteration plan", "prepare ralphex". Loads the canonical template, the verified parser contract (`### Task N:` / `### Iteration N:` tokens), sizing rules (3-7 tasks per plan), and the pre-slicing checklist.
---

# Slice Draft → Ralphex Iteration Plans

> Runs when the user asks to slice a draft (`docs/plans/drafts/NN-<topic>.md`) into
> executable ralphex iteration plans. Goal — split into 1-N packs, each pack obeying the
> parser contract + sizing.
> Bundled template: `ralphex-plan-template.md` (sibling of this file).
> Parser contract below is **verified against the real ralphex engine**
> (`umputun/ralphex`, `pkg/plan/parse.go`) — not a guess.

## Шаг 1. Pre-slicing checklist (ОБЯЗАТЕЛЬНО до slicing)

- [ ] Все blocker'ы Codex review (если был) закрыты в draft'е
- [ ] Draft содержит explicit scope, acceptance criteria, sequencing (если series)
- [ ] API surface (interfaces, signatures) verified против реального кода
- [ ] Architecture constraints проверены для затрагиваемых файлов
- [ ] User authorize'ил slicing (это не самостоятельное решение LLM)

Если хоть один «нет» — **stop**. Дописать draft, потом slice.

## Шаг 2. Determine pack split

Прочитать draft. Решить: один pack достаточно или нужно несколько?

| Признак | Один pack | Несколько packs |
|---|---|---|
| Total estimated tasks ≤ 7 | ✅ один | — |
| Total estimated tasks 8-14 | — | ✅ split 2 packs |
| Total estimated tasks ≥ 15 | — | ✅ split 3+ packs |
| Linear chain dependencies | ✅ один | — |
| Несколько independent subgroups | — | ✅ separate packs |
| Optional/conditional parts | — | ✅ optional packs separate |

Если split — каждый pack имеет свой `<pack-id>-<slug>`.

## Шаг 3. Use template

Скопировать `ralphex-plan-template.md` (лежит рядом с этим SKILL.md) как стартовый
skeleton для каждого pack'а. Заполнить:

1. **Header**: title, source draft link, pack label (если series), architecture constraints reference
2. **Overview**: 1-3 sentences
3. **Context**: files involved, related patterns, dependencies
4. **Development Approach**:
   - Testing approach
   - CI gates (commands из stack overlay / project conventions)
   - 3-5 CRITICAL statements pack-specific
5. **Implementation Steps**: 3-7 tasks (см. Шаг 4)

## Шаг 4. Parser-strict task format

Каждый task ОБЯЗАН следовать parser contract:

```markdown
### Task N: <english title>
**Files:**
- Modify: `<path>`
- Create: `<path>`

- [ ] step 1
- [ ] step 2
- [ ] add/update tests for <scope>
- [ ] run full test suite
```

### Parser rules (verified against `pkg/plan/parse.go`)

Движок распознаёт задачи и чекбоксы двумя регэкспами:

```go
taskHeaderPattern = `^###\s+(?:Task|Iteration)\s+([^:]+?):\s*(.*)$`
checkboxPattern   = `^\s*-\s+\[([ xX])\]\s*(.*)$`
```

| Token | Rule (что РЕАЛЬНО требует движок) |
|---|---|
| `### Task N:` / `### Iteration N:` | Ровно три `#`, пробел(ы), **литеральное `Task` ИЛИ `Iteration`** (оба валидны), пробел(ы), идентификатор задачи, двоеточие. Ключевое слово `Task`/`Iteration` — английское, **не переводить**: иначе header не распознаётся и задача исчезает из плана. |
| `N` (номер) | `strconv.Atoi`. Целое (`1`, `2`, …) даёт номер задачи. **Нецелое** (`2.5`, `2a`) не ломает парсинг — задача получает номер `0`. То есть «число от 1» — это **конвенция порядка**, а не жёсткое требование парсера. Держи целые по возрастанию ради читаемости. |
| `<title>` | Свободный текст, парсеру **безразличен** (может быть пустым). По конвенции проекта title — английский, но это стиль, не parser rule. |
| `- [ ]` / `- [x]` / `- [X]` | Checkbox state. **Допускается leading whitespace** (`^\s*`) — вложенные подпункты валидны. Ralphex флипает `[ ]`→`[x]` после iteration commit; LLM не редактирует чекбоксы во время run. |

### Поведение движка, которое надо учитывать

- **`##` (h2) закрывает текущую задачу.** Также `#` (h1) после того, как у плана уже есть title. `###`/`####` — это подсекции, они **не** закрывают задачу и не «отвязывают» чекбоксы. То есть чекбоксы под `#### Sub` всё ещё принадлежат задаче.
- **Format-in-text исключение:** чекбокс, в тексте которого есть `[ ]` или `[x]`, считается примером/описанием формата и **игнорируется** при проверке завершённости. Благодаря этому в плане можно безопасно держать пояснительные примеры.

### Anti-patterns parser'а

- ❌ `### Task N.` (без colon) — header не матчится
- ❌ `### Шаг N:` (перевод ключевого слова) — `Шаг ≠ Task/Iteration`, задача исчезает
- ❌ `### Task N - Title` (dash вместо colon)
- ❌ `#### Task N:` (4 hash вместо 3)
- ❌ Слить 2 `### Task N:` в один большой

## Шаг 5. Sizing rules

| Constraint | Value |
|---|---|
| Tasks per plan | **3-7** (если оценено >10 — split на 2 packs) |
| Task body | **30-150 LOC** (<30 — мало контекста, >150 — слишком крупно) |
| Task dependencies | Linear (Task N → 1..N-1, не наоборот) |
| Tests per task | Mandatory (no «tests later») |
| Done-criteria | Только automatable (✅ `npm test green`, ❌ `manually verified`) |

## Шаг 6. Required final tasks

Каждый план ОБЯЗАТЕЛЬНО имеет последние 2 task'а:

```markdown
### Task N-1: Verify acceptance criteria
- [ ] run full test suite
- [ ] run linter
- [ ] run <stack-specific arch guard>
- [ ] verify <project acceptance criterion 1>
- [ ] verify <project acceptance criterion 2>

### Task N: Update documentation
- [ ] update CLAUDE.md if patterns changed
- [ ] run docs lint
- [ ] if data model added/removed: update reference/data-model.md
- [ ] if controller added: update reference/api-endpoints.md
- [ ] if env var added: update reference/env-variables.md
- [ ] if interface added: update reference/contracts.md
- [ ] if plan lifecycle changed: update ROADMAP.md
- [ ] NOTE: do NOT move plan file manually (ralphex auto-moves on success)
```

## Шаг 7. File naming + placement

File path: `docs/plans/active/<pack-id>-<slug>.md`

- `<pack-id>`: sortable (e.g. `01-name`, `pack-a-name`, `feature-3.2`)
- `<slug>`: kebab-case short description

## Шаг 8. Update ROADMAP.md

Добавить ссылку на новый pack в section «В работе» с link на `docs/plans/active/<pack-id>-<slug>.md`.

## Шаг 9. Verify

- [ ] Каждый pack соответствует template (`ralphex-plan-template.md`)
- [ ] Parser tokens (`### Task N:` / `### Iteration N:`) на месте и не модифицированы
- [ ] 3-7 tasks per pack
- [ ] Все tasks 30-150 LOC body
- [ ] Last 2 tasks = Verify + Update documentation
- [ ] ROADMAP.md обновлён
- [ ] Files в plan'е точно existing files (проверены grep / find)

## Антипаттерны slicing

- ❌ **Slicing без pre-flight** (draft не готов → ralphex обнаружит проблемы по ходу = expensive)
- ❌ **Большие packs >10 tasks** (LLM устаёт, review pipeline зашкаливает)
- ❌ **Маленькие packs <3 tasks** (нет смысла — overhead pipeline'а превышает payoff)
- ❌ **Backward dependencies** (Task 2 использует результат Task 5 → невозможно линейно исполнить)
- ❌ **Done-criteria non-automatable** (`✅ manually tested` → ralphex Phase 2 не валидирует)
- ❌ **Fix задачи в Verify acceptance criteria task** (verify ≠ fix)
- ❌ **Manual move в `completed/`** в plan'е (ralphex auto-moves)

## Companion skills (внутри llm-kit проекта)

Если этот skill используется в проекте, забутстрапленном через `kit` / llm-kit, рядом
обычно есть:

- `route-new-logic` — где должна жить логика плана
- `add-new-module` — если plan создаёт новый module
- `facade-decomposition` — если plan декомпозирует существующий сервис
- `docs-sync-after-change` — для финального Update documentation task
