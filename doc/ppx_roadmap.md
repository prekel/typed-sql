# Дорожная карта PPX, совместимого с pgocaml_ppx

Состояние на 15 октября 2026 года. Реализован экспериментальный
`typed-sql-pgocaml-ppx`: SELECT с JOIN, expressions, aggregates и вложенными запросами,
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

Следующий путь миграции — отдельный пакет `typed-sql-ppx` с будущими
`[%pgsql.query ...]` и `[%pgsql.query.object ...]`, возвращающими
`Result_query.t` через raw SQL API. Он не зависит от PG’OCaml и позволяет
выполнять запросы через Caqti. Это запланированное расширение; текущий
совместимый пакет и его выполняющие quotations сохраняются.
Вместе с query quotations предстоит рассмотреть `[%pgsql.statement ...]` и
`[%pgsql.statement.object ...]` для переиспользуемого `Statement.t` с input.

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
передаются bind parameters. Будущие query quotations будут создавать
`Result_query.t`, который приложение передаст конструкторам `Statement`.
Отдельно рассматривается генерация переиспользуемого `Statement.t` через PPX;
окончательный API этого режима ещё не выбран.

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
- [x] Расширить parser до поддержанных SQL expressions/literals и вложенных
  query blocks с сохранением offsets исходного SQL.
- [ ] Добавить PostgreSQL E-strings и dollar quoting.
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
- [x] Добавить nullability поддержанных вычисляемых expressions;
  отсутствие подтверждённого column origin учитывать по upstream-контракту.
- [x] Сохранить PG’OCaml serializers/decoders для поддержанных типов.
  Неподдержанные converters и flags сопровождать отдельными diagnostics.
- [x] Добавить пакет через `dune-project` и руководство подключения с
  точным перечнем поддержанного SQL и примером изменения Dune.

Критерий завершения: downstream fixtures собираются без доступной БД,
совпадают с upstream по OCaml-типам и дают те же результаты при отдельной
проверке выполнения в PostgreSQL.

### 4. Расширять SQL и совместимость

- [x] Добавить JOIN/INNER JOIN с ON, цепочками и self-JOIN, разрешением aliases,
  проверкой неоднозначных колонок, wildcard order и параметрами ON/WHERE.
  Сохранить PG’OCaml-типы, object output и исходную nullability колонок.
- [x] Добавить LEFT/RIGHT/FULL/CROSS, USING/NATURAL, скобки и запятые в FROM.
- [x] Добавить numeric expressions, CAST/`::`, CASE, COALESCE и NULLIF с
  контекстными типами параметров и сохранением column origin.
- [x] Добавить count/sum/avg/min/max, bool_and/bool_or, string_agg/array_agg,
  GROUP BY/HAVING, DISTINCT, FILTER и aggregate-local ORDER BY.
- [x] Добавить UNION/INTERSECT/EXCEPT с ALL/DISTINCT и правильными приоритетами.
- [x] Добавить derived tables, scalar/EXISTS/IN/ANY/ALL subqueries и
  корреляцию scalar/predicate subqueries.
- [x] Добавить обычные и recursive SELECT CTE, INSERT/UPDATE/DELETE CTE,
  INSERT SELECT и проверки побочных эффектов; сохранить snapshot v3.
- [ ] Расширять оставшиеся формы: LATERAL, window functions, функциональные
  зависимости GROUP BY, GROUPING SETS, SEARCH/CYCLE, mutual recursion и
  aggregates внешнего уровня. MERGE и UPDATE FROM/DELETE USING остаются вне
  поддержанного DML. Ограничения текущих групп перечислены в руководстве.
- [ ] Определить metadata typmod для точной эвристики origin same-type casts
  прямых varchar/bpchar/numeric и временных колонок; сейчас такие casts
  отклоняются, если нельзя гарантировать совместимый OCaml-тип результата.
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
- [x] Проверить upstream-эвристику NULL для outer JOIN и поддержанных expressions.
  Улучшение nullability, меняющее OCaml-тип результата, документировать как
  изменение контракта; не выдавать его за прозрачную замену.
- [ ] Для views и пользовательских функций определить, какие дополнительные
  сведения нужны snapshot. Отсутствующие metadata не заменять предположением.

Критерий каждого расширения: обновлённая матрица поддержки, положительные и
compile-fail fixtures, сравнение типов и выполнения с upstream. Универсальная
совместимость не объявляется до проверки соответствующих SQL-возможностей.

### 5. Query и statement quotations через raw SQL API и миграция на query builder

Запланированы `[%pgsql.query ...]` и `[%pgsql.query.object ...]`, возвращающие
`Result_query.t`. Реализация [raw SQL API](adr/0002-raw-sql-escape-hatch.md) —
предварительное условие этапа. PPX выводит типы по snapshot и описывает raw
query; перевод SQL в DSL не требуется. Вместе с ними предстоит рассмотреть
`[%pgsql.statement ...]` и `[%pgsql.statement.object ...]` для создания
переиспользуемого Statement с input. Существующие `[%pgsql ...]` и
`[%pgsql.object ...]` сохраняют выполнение через PG’OCaml.

Целевой синтаксис, ещё не реализованный:

```ocaml
let find ~status ~limit =
  [%pgsql.query.object
    "SELECT id, name FROM people WHERE status = $status LIMIT $limit"]
```

Именованные аргументы принадлежат обычной OCaml-функции. Каждый вызов создаёт
immutable deferred query с захваченными значениями bind parameters, без
соединения или обращения к БД. Тип результата описывает одну строку, для
`.object` — объект с методами выбранных колонок; список появляется при
выполнении через `Statement.query_many`. Статичны SQL, число placeholders и
result shape; значения параметров могут меняться между вызовами.

#### Рассмотреть query и statement quotations вместе

- [ ] Сравнить четыре формы: `%pgsql.query`, `%pgsql.query.object`,
  `%pgsql.statement` и `%pgsql.statement.object`. Query возвращает
  `Result_query.t` для композиции; statement должен позволять переиспользовать
  скомпилированный план с разными input. Для обоих режимов рассмотреть
  object output и совместимость с object → record converters приложения.
- [ ] Для query с захваченными values показать выполнение через
  `Statement.Dynamic` и создание обычного Statement при каждом вызове.
  Оба пути повторяют компиляцию. Смена values сама по себе не делает
  SQL shape динамической; динамическое построение и компиляция — отдельные
  свойства пути выполнения.
- [ ] Для statement рассмотреть компиляцию плана при определении, getters
  input при выполнении и повторные вызовы без компиляции. Сравнить способы
  задания input, включая binder-pattern и удобство именованных аргументов;
  окончательный синтаксис пока не утверждать.
- [ ] Проверить оба режима через общий raw SQL API в `typed-sql-ppx` без
  PG’OCaml dependencies, через Caqti PostgreSQL и PG’OCaml adapter. Для
  statement предусмотреть проверки времени вызова getters и переиспользования
  плана; object → record fixtures должны охватывать оба режима.

#### Raw query и композиция

- [ ] Реализовать raw SELECT с типизированными binds, output descriptors и
  decoder, возвращающий `Result_query.t`. PPX должен выводить типы параметров,
  колонок и nullability offline по snapshot v3 и генерировать этот API.
- [ ] Поддержать обычный результат и object output. SELECT использует kind
  `Result_query.select`, DML с `RETURNING` — `Result_query.returning`.
  DML без возвращаемых строк не выдавать за `Result_query.t`: он требует
  отдельного command-направления.
- [ ] Сохранить PostgreSQL requirements в типах; raw PostgreSQL SQL не
  становится portable из-за выбора другого adapter. Без доказательства
  кардинальности не приписывать запросу `exactly_one` или `at_most_one`.
- [ ] Проверить смешанные raw/DSL set operations, включая `Query.union_all`,
  derived tables и CTE через существующие descriptors колонок. Объект
  результата не заменяет описание SQL-полей; законченный `Result_query.t`
  не получает автоматически операции незавершённого `Query.t`.
- [ ] При вложении учитывать ограничения позиции SQL и совместимость
  выходных колонок, в том числе nullability и codecs. Неподдержанные случаи
  возвращают явную ошибку, а не приблизительный SQL.
- [ ] Обеспечить детерминированную нумерацию bind slots при объединении
  нескольких raw/DSL запросов, повторных подстановках и одинаковых именах
  параметров в независимых запросах. Значения не включать в SQL или shape.
- [ ] Описать создание обычного `Statement` из результата quotation и
  выполнение через adapters, в том числе через `Statement.Dynamic`.
  При создании Statement внутри функции происходит повторная компиляция;
  переиспользование готового плана для query с values не обещать.

#### Отдельный пакет без PG’OCaml

- [ ] Выпустить `typed-sql-ppx` для query quotations без зависимости от
  `pgocaml`, в том числе в generated-коде и его runtime dependencies.
- [ ] Вынести общий parser, разрешение схемы и PostgreSQL type inference в
  переиспользуемый frontend без драйвера. Совместимый
  `typed-sql-pgocaml-ppx` сохраняет выполняющие quotations и PG’OCaml codecs;
  ядро не получает зависимости от драйверов, Lwt или ppxlib.
- [ ] Для query quotations использовать descriptors/codecs typed-sql.
  Проверить поддержку scalar-типов, enum/domain и arrays на границе обоих
  adapters; документировать отличия от PG’OCaml и необходимые преобразования,
  включая `int32`/`int`, CalendarLib, numeric и пользовательские типы схемы.
- [ ] Проверить установку пакета и сборку приложения в окружении без
  `pgocaml`, с Caqti PostgreSQL driver. Проверки выполнения через Caqti и
  PG’OCaml проводить отдельно от обычной offline-компиляции.

#### Инструкция миграции с pgocaml_ppx

- [ ] Написать отдельную инструкцию с последовательными примерами перехода
  `pgocaml_ppx` → совместимый offline PPX → query quotations → DSL.
- [ ] Дополнить инструкцию сравнением query для композиции и рассматриваемого
  statement для переиспользования плана: захват values, передача input,
  повторная компиляция и сохранение object → record converters.
- [ ] На первом шаге сохранить `%pgsql.object`, прикладной deriving
  object → record и `List.map t_of_pgocaml results`. Затем показать
  `%pgsql.query.object`, создание Statement и выполнение через adapter.
- [ ] Переписать отдельный raw запрос на DSL, сохраняя object output и
  существующий converter там, где совпадают типы методов. Не обещать
  автоматическую совместимость различающихся PG’OCaml/typed-sql типов.
- [ ] Показать перенос object → record в decoder через `Projection.map`,
  затем возможное расширение deriving приложения для генерации record
  projection без промежуточного объекта.
- [ ] Подготовить парные SELECT и DML с `RETURNING` для raw/DSL и пример
  смешанного приложения с общей схемой и соединением через существующий
  `Make` в `typed-sql-pgocaml-lwt`. DSL записывать с завершающим `select`
  или `command` через локальное открытие соответствующего модуля.
- [ ] Описать переход с PG’OCaml adapter на Caqti: соединения, транзакции и
  ошибки. Учесть исключения старых quotations и `Result.t` adapters;
  для отдельного command-направления — `unit` и `Affected_rows.t`.

Критерий завершения: отдельный запрос можно заменить на query quotation,
затем на DSL без одновременной миграции остальных quotations. Offline и
compile-fail fixtures проверяют выведенные типы, несовместимые параметры и
колонки; object → record fixtures проверяют миграционный converter.
Golden cases покрывают композицию двух параметризованных raw/DSL запросов;
PostgreSQL-тесты подтверждают одинаковые результаты через Caqti и PG’OCaml.
Создание query не обращается к БД, разные bind values сохраняют SQL shape.

Ближайший технический шаг: минимальный raw SELECT API с typed binds и decoder,
возвращающий `Result_query.t`. Сначала проверить его вручную через Caqti и
в композиции с DSL, затем добавить генерацию query quotations. Динамические
lists и Custom Type Conversions остаются отдельными отложенными этапами.

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

- [x] Поддержать PG’OCaml 4.3.0: нижняя граница зависимости PPX снижена до
  4.3.0. Сборка и offline fixtures проверены на OCaml 4.14.1; scalar codecs,
  bind parameters, NULL, prepared cache и одинаковые snapshots обоих дамперов —
  на PostgreSQL 18.6. Сохранены проверки на OCaml 5.1.1 / PG’OCaml 4.4.0.
- [ ] Проверить PostgreSQL 15, в том числе в связке с PG’OCaml 4.3.0:
  повторить PostgreSQL-тесты codecs, prepared cache и schema dump. Проверки
  на PostgreSQL 18.6 не заменяют эту проверку минимальной версии сервера.
- [x] Проверить query builder и offline PPX в одной Lwt-транзакции на общем
  соединении через `Make (PGOCaml)`: оба направления чтения/записи,
  object → record, commit, явный rollback и rollback при исключении PPX.
  Второе соединение проверяет изоляцию до commit и отсутствие откатившихся
  записей; тест выполнен с PG’OCaml 4.3.0 и 4.4.0 на PostgreSQL 18.6.
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
- [x] Добавить offline, compile-fail и differential fixtures для outer JOIN,
  CASE/casts, агрегатов, set operations, подзапросов, recursive и DML CTE;
  проверить object → record и побочные эффекты на PostgreSQL.
- [ ] Проверить динамические list-подстановки и последующие SQL-возможности.
- [x] Проверки Dune подтверждают пересборку после изменения metadata и
  воспроизводимость генерации при неизменном input.

Обычные offline проверки не требуют внешнего сервиса. Проверки соответствия
PostgreSQL запускаются отдельно: SQLite не заменяет PostgreSQL для проверки
вывода типов и поведения совместимого PPX.
