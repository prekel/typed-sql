# Дорожная карта PPX, совместимого с pgocaml_ppx

Состояние на 14 октября 2026 года. Реализован экспериментальный
`typed-sql-pgocaml-ppx`: SELECT одной таблицы с расширенным WHERE,
ORDER BY, LIMIT/OFFSET, tuples/objects и scalar-типами PG’OCaml. Enum/domain
и одномерные native arrays используют вложенные metadata snapshot v3. Поддержаны
также INSERT/UPDATE/DELETE, RETURNING, несколько VALUES, DEFAULT и обычный
ON CONFLICT с DO NOTHING/DO UPDATE. Подключение и
точные ограничения описаны в [руководстве PPX](ppx.md). Отмеченные пункты
проверены offline fixtures и PostgreSQL-тестами; остальные остаются планом.
Общая работа над DSL описана в
[дорожной карте проекта](roadmap.md).

## Цель и границы совместимости

Сохранить `[%pgsql ...]` и `[%pgsql.object ...]` в существующих приложениях,
проверять SQL по сохранённой схеме без подключения к БД во время компиляции и
позволить постепенно переписывать отдельные запросы на query builder.

Для поддержанных запросов переход должен требовать замены PPX в Dune и
настройки snapshot схемы. Исходные quotations, OCaml-типы параметров и
результатов, модуль `PGOCaml`, соединения и способ выполнения сохраняются.
Обновление snapshot после миграций остаётся отдельным действием.

Текущая версия поддерживает явно перечисленное подмножество PostgreSQL SQL.
Полная замена любого приложения с `pgocaml_ppx` — долгосрочная цель; её нельзя
обещать на основании совместимого синтаксиса. Неизвестная конструкция,
неподдержанный тип или неоднозначный вывод типов завершают компиляцию с
diagnostic. Подключения к БД и автоматического online fallback нет.

Эталон совместимости —
[pgocaml_ppx 4.4.0](https://github.com/darioteixeira/pgocaml/tree/v4.4.0/ppx).
Его [реализация](https://github.com/darioteixeira/pgocaml/blob/v4.4.0/ppx/ppx_pgsql.ml)
отправляет SQL в PostgreSQL через `prepare` и `describe_statement`, получает
типы параметров и выходных колонок, затем обращается к каталогам для
nullability и пользовательских типов. Схема содержит описание таблиц, но для
произвольного запроса нужен также разбор SQL и вывод типов выражений.

Этот PPX имеет собственную цель совместимости. Возможный будущий PPX для
сокращения ручного DSL-кода остаётся отдельным направлением после проверки
API внешним RealWorld-приложением.

## Архитектура и metadata

Реализован отдельный пакет `typed-sql-pgocaml-ppx`. Работа с PostgreSQL SQL,
`ppxlib` и генерацией совместимого кода находится за пределами `lib/`;
backend-independent ядро не получает новых зависимостей от драйвера или Lwt.

Конвейер PPX:

1. Прочитать SQL literal и разобрать OCaml-подстановки.
2. Разобрать SQL, сохранив позиции для diagnostics.
3. Разрешить таблицы, колонки и области видимости по snapshot.
4. Определить PostgreSQL-типы параметров и результата.
5. Выбрать совместимые serializers/decoders и сгенерировать OCaml-код.

Входом служит файл snapshot, общий с генератором descriptors. PPX не загружает
сгенерированный OCaml-модуль и не требует его выполнения во время сборки.
Обычный PPX работает до typechecking приложения и не может получить metadata
из произвольных OCaml-значений descriptors.

[Snapshot версии 3](schema_snapshot.md) сохраняет точное PostgreSQL-имя типа
каждой колонки. Версия 2 по-прежнему читается для codegen, но не содержит этих
metadata. Portable PostgreSQL-интроспекция объединяет `int2` и `int4` в `Int`,
`float4` и `float8` в `Float`, а `text`, `varchar` и `bpchar` в `Text`.
Совместимость требует сохранять точные PostgreSQL-типы, даже если они имеют
одинаковое переносимое представление в DSL. Вывод типов выражений также
потребует правил PostgreSQL для literals, операторов и casts; наличие SQL
parser само по себе этих правил не даёт.

Представления PG’OCaml и codegen различаются:

| PostgreSQL-тип | Контракт совместимого PPX | Текущий codegen typed-sql |
| --- | --- | --- |
| `smallint` | `int` (`PGOCaml.int16`) | `int` |
| `integer` | `int32` | `int` |
| `bigint` | `int64` | `int64` |
| `numeric` | `string` | `Decimal.t` |
| `date` | Представление PG’OCaml/CalendarLib | `Date.t` |
| `timestamp` | Представление PG’OCaml/CalendarLib | `Local_timestamp.t` |
| `timestamptz` | Представление PG’OCaml/CalendarLib | `Ptime.t` |
| enum | `string`, если не задан custom converter | Сгенерированный variant |
| domain | Представление базового типа или custom converter | Отдельный тип-обёртка |

Совместимый PPX сохраняет контракт PG’OCaml. Правила codecs генератора
typed-sql нельзя автоматически применять вместо custom converters PG’OCaml.

Сгенерированный код продолжает выполнять SQL через выбранный приложением
модуль `PGOCaml`, сохраняя его monad и исключения. Пользовательские значения
передаются bind parameters. Перевод quotation в `Statement.t` не является
условием первого выпуска; существующий semantic AST DSL остаётся прежним.

Если синтаксис и генератор OCaml заимствуются из upstream, для них сохраняются
copyright notices, происхождение и применимая
[лицензия upstream](https://github.com/darioteixeira/pgocaml/blob/v4.4.0/LICENSE.txt).
Лицензия MIT основного проекта не заменяет лицензию заимствованных файлов.

## Этапы

Custom Type Conversions отложены до последнего этапа. Общий запрос выполнить
весь roadmap не включает эту работу: перед её началом нужно отдельно спросить
«Custom Type Conversions тоже?» и дождаться явного согласия. Это правило
закреплено в [AGENTS.md](../AGENTS.md).

### 1. Зафиксировать контракт совместимости

- [x] Зафиксировать матрицу поддержанного синтаксиса и flags в руководстве:
  поддержанные scalar quotations и явные diagnostics для остальных возможностей.
- [ ] Расширить проверяемый контракт до всего синтаксиса upstream 4.4.0:
  tuples, objects, `$name`, `$?name`, `${...}`, list-подстановки,
  `nullable-results`, source comments и параметры подключения. Custom Type
  Conversions и связанные flags проверяются отдельно на последнем этапе.
- [x] Перенести и адаптировать
  [upstream PR #80](https://github.com/darioteixeira/pgocaml/pull/80): поддержку
  OCaml quoted strings `{|...|}` и `{sql|...|sql}` при разборе аргументов PPX.
  Добавить regression fixtures для многострочного SQL, обоих видов quotations
  (`pgsql` и `pgsql.object`), обычных строк и подстановок внутри quoted strings.
- [x] Зафиксировать для поддержанного SELECT OCaml-типы, output names, порядок
  строк, NULL и работу prepared statements в downstream fixtures.
- [ ] Расширить эти fixtures вместе с поддержкой остального SQL.
- [x] Описать судьбу каждого flag: поддержка или явный diagnostic. В первой
  версии отклонять compile-time `execute` и flags подключения к БД.
- [x] Реализовать небольшой parser SELECT с комментариями, quoted identifiers
  и byte offsets diagnostics; грамматика полностью проверяет входной SQL.
- [ ] Расширить parser до SQL expressions/literals и PostgreSQL dollar quoting.
- [x] При заимствовании кода выделить файлы с лицензией и указать tag/commit
  upstream, чтобы изменения можно было сверять с исходной реализацией.

Критерий завершения: для каждого проверяемого элемента контракта есть fixture
и указан этап поддержки либо явное ограничение.

### 2. Подготовить общий источник схемы

- [x] Сохранять точное имя native type каждой колонки, включая `int2`/`int4`
  и имена enum/domain/array; оба дампера создают одинаковый snapshot.
- [x] Сохранять точные native types domain bases и array elements, сверх
  portable nested descriptors, как необязательное расширение snapshot v3.
  Сохранять attribute NOT NULL для совместимого чтения domain-колонок.
- [x] Зафиксировать новую версию snapshot и поведение reader/codegen для
  старых файлов. Потерянные сведения нельзя восстанавливать догадкой;
  совместимый PPX должен требовать достаточно полный snapshot.
- [x] Сохранить единый источник для PPX и генератора DSL descriptors, с
  отдельным выбором OCaml-представлений для каждого потребителя.
- [x] Описать настройку schema file и разрешение неквалифицированных имён.
  Одинаковые имена в разных схемах не должны разрешаться случайным порядком.
- [x] Описать и проверить пересборку Dune при изменении snapshot. Файлы
  metadata не содержат credentials.

Критерий завершения: round-trip snapshot сохраняет необходимые точные типы,
а PPX и codegen читают одну схему без доступа к БД.

### 3. Выпустить минимальный offline PPX

- [x] Поддержать SELECT одной таблицы, columns/projection aliases, `*`, WHERE
  `column = parameter`, AND со скобками и ORDER BY исходным колонкам.
- [x] Добавить NOT/AND/OR, comparisons, IS NULL, LIKE/ILIKE, BETWEEN,
  фиксированный IN/NOT IN, ANY/ALL и literals в predicates; LIMIT/OFFSET.
  Остальные expressions и операторы вне подмножества по-прежнему отклонять.
- [x] Поддержать базовые INSERT/UPDATE/DELETE по одной таблице, включая
  RETURNING, несколько VALUES, DEFAULT и ON CONFLICT по колонкам ключа с
  DO NOTHING/DO UPDATE и EXCLUDED. Operators и statements вне заявленного
  подмножества отклонять.
- [x] Проверить DML offline fixtures и выполнением в PostgreSQL: unit без
  RETURNING, scalar/tuple/object results, NULL, defaults, обе ветви upsert,
  пустой RETURNING и порядок bind parameters.
- [x] Сохранить scalar/optional подстановки и `${...}`, вывод типов
  параметров по контексту запроса, tuples, objects и порядок строк.
- [x] Сохранить nullability прямых колонок и flag `nullable-results`.
- [ ] Добавить nullability вычисляемых expressions при расширении projection;
  отсутствие подтверждённого column origin учитывать по upstream-контракту.
- [x] Сохранить PG’OCaml serializers/decoders для поддержанных типов.
  Неподдержанные converters и flags сопровождать отдельными diagnostics.
- [x] Добавить пакет через `dune-project` и руководство подключения с
  точным перечнем поддержанного SQL и примером изменения Dune.

Критерий завершения: downstream fixtures собираются без доступной БД,
совпадают с upstream по OCaml-типам и дают те же результаты при отдельной
проверке выполнения в PostgreSQL.

### 4. Расширять SQL и совместимость

- [ ] Добавлять отдельными проверяемыми группами JOIN, aggregates/GROUP BY,
  casts, CASE, подзапросы, CTE и set operations.
- [ ] Расширять правила PostgreSQL type inference вместе с поддержкой
  операторов, функций и implicit coercions; неоднозначные случаи отклонять.
- [x] Добавить enum/domain codecs и одномерные native arrays поддержанных
  scalar-типов, включая enum/domain combinations, NULL и escaping.
- [ ] Добавить динамическую форму SQL и list-подстановки `$@...` отдельным
  этапом. Пока поддерживается только статическая форма: SQL, число
  placeholders и result shape известны при компиляции. Native array
  остаётся одним параметром независимо от длины и не относится к этому этапу.
  Для lists проверить runtime numbering, cache по итоговому SQL, несколько
  длин и совместимое поведение пустого списка; кодировки параметров не
  включать в SQL или cache key.
- [ ] Поддержать source comments с отдельной проверкой совместимости.
- [ ] Отдельно разобрать upstream-эвристику NULL для outer JOIN и выражений.
  Улучшение nullability, меняющее OCaml-тип результата, документировать как
  изменение контракта; не выдавать его за прозрачную замену.
- [ ] Для views и пользовательских функций определить, какие дополнительные
  сведения нужны snapshot. Отсутствующие metadata не заменять предположением.

Критерий каждого расширения: обновлённая матрица поддержки, положительные и
compile-fail fixtures, сравнение типов и выполнения с upstream. Универсальная
совместимость не объявляется до проверки соответствующих SQL-возможностей.

### 5. Statement quotations через raw SQL API и миграция на query builder

Новый режим `[%pgsql.statement ...]` должен возвращать `Statement.t` через
будущий [raw SQL API](adr/0002-raw-sql-escape-hatch.md). Реализация этого API —
предварительное условие этапа. PPX выводит типы по snapshot и описывает raw
statement; перевод SQL в DSL для этого режима не требуется. Существующие
`[%pgsql ...]` и `[%pgsql.object ...]` сохраняют выполнение через PG’OCaml.

Input задаётся binder-pattern внутри quotation. Эскиз синтаксиса для таблицы
`people`, где `id` имеет тип `integer`, а `name` — `text NOT NULL`:

```ocaml
let find =
  [%pgsql.statement
    fun id ->
      "SELECT name FROM people WHERE id = $id"]
(* find : (int32, string list, [`Postgresql]) Statement.t *)

let find_two =
  [%pgsql.statement
    fun (first, second) ->
      "SELECT name FROM people WHERE id IN ($first, $second)"]
(* find_two : (int32 * int32, string list, [`Postgresql]) Statement.t *)
```

Lambda описывает input: PPX извлекает SQL literal и генерирует getters
параметров из pattern. Значение quotation — готовый `Statement.t`; getters
получают input при выполнении через adapter. Соединение в определение не
входит. Обычно statement создаётся один раз при загрузке модуля и затем
исполняется с разными input. Его можно создать и внутри функции: статичность
означает фиксированную форму SQL, а не обязательное время создания.
Третий параметр `Statement.t` задаёт поддерживаемые диалекты: здесь
``[`Postgresql]``; ``[`Not_sqlite]`` относится к требованиям DSL.

- [ ] Реализовать режим через raw SQL API со статическим SQL, фиксированными
  placeholders и offline-выводом типов input/output по snapshot.
- [ ] Поддержать scalar, tuple и record binder-patterns с типизированными
  getters; значения input остаются bind parameters. Динамические lists и
  Custom Type Conversions остаются отдельными отложенными этапами.
- [ ] Определить мост между выведенными PG’OCaml-типами, их codecs и
  backend-neutral описаниями raw statement, сохранив независимость ядра от
  PG’OCaml. Выявлять несовместимые типы параметров при компиляции.

- [ ] Подготовить пример приложения со смешанными quotations и DSL-запросами,
  использующими одну схему и соединение через существующий `Make` в
  `typed-sql-pgocaml-lwt`.
- [ ] Дать парные примеры SELECT и DML с одинаковой прикладной операцией и
  результатом; DSL записывать через локальное открытие соответствующего
  модуля, с завершающим `select` или `command`.
- [ ] Показать явные преобразования между `int32` и `int`, CalendarLib и
  временными типами typed-sql, `string` и enum/domain/numeric.
- [ ] Описать адаптацию ошибок: quotations сохраняют исключения PG’OCaml,
  а `Statement` выполняется через adapter с его `Result.t`. Для DML без
  `RETURNING` учесть переход от `unit` к `Affected_rows.t`.
- [ ] Показать путь от выполняющей quotation к raw statement quotation, затем
  к DSL statement. При последнем переходе сохранить input и слой выполнения;
  необходимые преобразования PG’OCaml-типов показать явно.

Критерий завершения: отдельный запрос в примере можно заменить на raw, затем
DSL statement без одновременной миграции остальных quotations или смены пула
соединений. Regression и compile-fail fixtures проверяют выведенные input/output
и несовместимые параметры. Определение statement не вызывает getters;
повторное выполнение с разными input сохраняет SQL и placeholders. Парные
raw/DSL запросы возвращают одинаковые результаты.

### 6. Custom Type Conversions — последний этап, по отдельному согласию

Выполняется после остальных незавершённых пунктов roadmap, включая поддержку
PG’OCaml 4.3.0 и PostgreSQL 15. Пока не поддерживать sexp config и quotations
с `load_custom_from=...`, в том числе в сочетании с `show`. Текущие diagnostics
для этих возможностей сохраняются до отдельно согласованной реализации.

Даже при поручении «сделай всё из roadmap» сначала спросить
«Custom Type Conversions тоже?» и дождаться ответа. Отдельный явный запрос
пользователя на Custom Type Conversions или уже полученное согласие разрешает
работу без повторного вопроса.

- [ ] Добавить sexp config и выбор файла через `load_custom_from=...` или
  `PGCUSTOM_CONVERTERS_CONFIG`, с совместимым выбором serializers/decoders.
- [ ] Добавить config в Dune dependencies и проверить пересборку после его
  изменения, сохранив offline-компиляцию.
- [ ] Поддержать `show`/`show=...` и сочетание object quotations с custom
  converters, включая пример с `load_custom_from=tests_ppx/config.sexp`.
- [ ] Добавить отдельные regression, compile-fail и PostgreSQL-проверки
  converters, некорректного config и совместимости OCaml-типов с upstream.

Критерий завершения: отдельно согласованные custom conversions работают по
upstream-контракту; конфигурация не требует доступа к БД при компиляции.

## Проверки и критерии выпуска

- [ ] Поддержать PG’OCaml 4.3.0 и PostgreSQL 15 как минимальную совместимую
  связку: проверить сборку PPX и generated-кода, scalar codecs, bind parameters,
  NULL, prepared cache и одинаковые snapshots обоих дамперов. Текущий пакет
  требует PG’OCaml 4.4.0; PostgreSQL-проверки выполнены на 18.6. После проверки
  связки 4.3.0/15 снизить нижнюю границу `pgocaml` в `dune-project` до 4.3.0,
  сохранив regression-проверки на 4.4.0 и PostgreSQL 18.
- [x] Compile-time fixtures запускаются с недоступным PostgreSQL; переменные
  окружения `PG*` не включают скрытый online fallback. Отсутствующий snapshot
  даёт diagnostic.
- [x] Fixtures фиксируют OCaml-типы upstream для параметров/результата, включая
  `option`, tuples и object methods поддержанного SELECT.
- [ ] Расширить сравнение на enum/domain и остальной SQL. Проверки custom
  converters относятся к отдельно согласованному последнему этапу.
- [x] Compile-fail сценарии покрывают неизвестные таблицы и колонки,
  неверные source references, несовместимые типы и неподдержанные SQL/flags.
- [x] Небольшие отдельные expect snapshots проверяют diagnostics и
  bind SQL; offline assertions проверяют результаты генерации. Значения
  никогда не интерполируются в SQL.
- [x] Отдельные PostgreSQL-тесты сравнивают результаты, NULL, порядок строк,
  WHERE и повторное выполнение в рамках зафиксированного upstream-контракта.
  Они не становятся условием обычной компиляции приложения.
- [x] Расширить PostgreSQL-проверки на RETURNING, predicates, pagination и
  native codecs; добавить fixtures сравнения с upstream 4.4.0.
- [ ] Проверить динамические list-подстановки и последующие SQL-возможности.
- [x] Проверки Dune подтверждают пересборку после изменения metadata и
  воспроизводимость генерации при неизменном input.

Обычные offline проверки не требуют внешнего сервиса. Проверки соответствия
PostgreSQL запускаются отдельно: SQLite не заменяет PostgreSQL для проверки
вывода типов и поведения совместимого PPX.
