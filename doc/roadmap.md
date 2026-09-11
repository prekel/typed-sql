# Дорожная карта

Состояние проекта на 11 сентября 2026 года. Этот документ сопоставляет
реализацию с планом в [first_plan.md](first_plan.md), фиксирует результаты
аудита и задаёт порядок следующей работы.

## Статус текущего среза

P0 и выбранный P1-срез реализованы. Ядро теперь имеет отдельные этапы
normalization, validation, lowering и rendering; `Shape.t` учитывает identity
codec и layout projection. Основной API скрывает внутренние constructors;
отдельная внутренняя библиотека `typed_sql_private` открывает AST и этапы
compiler для white-box тестов. Это нестабильный интерфейс с явным обходом
ограничений DSL.

Контракт приложения и его документация собраны в `typed_sql.mli`,
а `Typed_sql` реэкспортирует их из внутренней библиотеки `typed_sql_private`.
Модули реализации имеют только `.ml` и обычные внутренние функции. Абстракция
типов задаётся на границе центрального facade. Адаптеры используют отдельный
`typed-sql.backend` с контрактом в `backend/typed_sql_backend.mli`. Общими
остаются только непрозрачные compiled query/command; параметры и декодеры
доступны через backend API.

Реализованы arbitrary `INNER JOIN` и `LEFT JOIN` с deterministic aliases,
несколькими visible sources и compiler validation. Тип колонки разделён на
base type и schema value type. Для правой стороны `LEFT JOIN` используется
`Nullable_table_ref`, а `Expr.nullable_column` даёт flattened `option`.

Есть single-row `INSERT`, `UPDATE`, `DELETE`, `RETURNING`, `Command.t` и
`Result_query.t`. `UPDATE` и `DELETE` нельзя превратить в command без
`where` или явного `all_rows`. Caqti adapter выполняет команды и сообщает
`Affected_rows.Known`, если это поддержано driver. Новый
`typed-sql-pgocaml-lwt` adapter использует PG'OCaml только через общий
compiled contract; его `execute` возвращает `Unknown`, поскольку low-level
PG'OCaml API не предоставляет affected-row count.

## Что уже сделано

Код начинался как первый вертикальный срез и теперь включает:

- `Db_type<'a>` с базовыми типами, `option`, mapped-типа́ми, encode/decode и
  existential packed values;
- проверенные и экранируемые identifiers, table descriptors, typed columns и
  generative `Table_ref`;
- typed `Expr<'a>` и отдельный `Condition.t` с равенством, неравенством,
  сравнениями, `LIKE`, проверками `NULL` и трёхзначной логикой условий;
- `Projection<'a>` с полным `Base.Applicative.S`, `Let_syntax` и интерпретатором
  `Projection.Make` для декодеров адаптеров;
- immutable deferred `SELECT` с `FROM`, `WHERE`, `where_opt`, `INNER JOIN`,
  `LEFT JOIN`, `ORDER BY`, `LIMIT` и `OFFSET`; завершающий `select` задаёт
  projection и возвращает `Result_query.t`;
- `INSERT`, scoped `UPDATE`/`DELETE`, `RETURNING`, commands и результат
  affected rows;
- проверка принадлежности колонок всем visible sources на этапе compiler;
- нормализация `AND`/`OR`/`NOT`, удаление тривиального `WHERE`, стабильный
  порядок bind-параметров и `Shape.t`, не зависящий от значений параметров и
  generative source IDs;
- PostgreSQL и SQLite rendering с quoting identifiers и отдельными
  placeholder-синтаксисами;
- backend-independent `Template`, `Compiled_query`, parameters и projection
  plan, после чего Caqti/Lwt адаптер преобразует descriptors в Caqti types;
- `fetch`, `fetch_one`, `fetch_opt`, `execute`, mapped-типы и SQLite `:memory:`
  integration test;
- compile-only PG'OCaml/Lwt adapter без сетевого PostgreSQL integration test;
- expect snapshots, QCheck-проверки bind parameters и SQL injection, три
  compile-fail fixture, измерение покрытия через публичный API и package/doc
  checks.

## Чем реализация отличается от `first_plan.md`

### Объём первого среза

План описывал почти полный typed jOOQ-подобный DSL. Реализация расширила
первоначальный `SELECT` core portable JOIN и базовым DML. В коде пока нет
`IN`, арифметических выражений, функций,
подзапросов, `EXISTS`, CTE, `GROUP BY`, aggregates, schema introspection,
codegen, raw SQL escape hatch, compilation cache и PPX.

### Порядок dialect'ов

В плане сначала предполагался PostgreSQL compiler, а SQLite — после JOIN и
portable query suite. Реализация включила PostgreSQL и SQLite уже в первом
срезе. Это дало раннюю проверку quoting, placeholder rendering и Caqti
adapter, но пока не является полноценным cross-backend compatibility suite:
интеграционный запуск есть только для SQLite.

### Source safety

Выбран предусмотренный планом промежуточный вариант V1: публичный DSL выдаёт
`Table_ref` только callback'ам, в AST сохраняется `source_id`, а compiler
отклоняет escaped reference. Type-level witnesses `There`/`Skip` и PPX не
вводились. Context теперь растёт вложенными парами при JOIN; compiler
проверяет набор visible sources.

### Граница compiler и backend

Типизированная граница теперь используется двумя adapter'ами: ядро не зависит
от Caqti/Lwt/PG'OCaml, а adapters получают только compiled template,
parameters и projection. Отдельный public backend interface и first-class
decoder IR по-прежнему не введены: это следующий этап, если понадобится третий
backend или общий lifecycle prepared statements.

### Compiler pipeline

`Normalizer`, `Validator`, `Lower` и `Renderer` разделены. `Lower` пока
сохраняет portable semantic AST без dialect-specific преобразований; это
явная точка для будущих capability checks и vendor-specific операций.

### Projection и query cache

`Projection` одновременно описывает SELECT/RETURNING expressions и decoding
plan. `Shape.t` содержит fingerprint mapped codec и projection type layout.
Собственного LRU compilation cache и explicit parameter slots пока нет;
compiled values по-прежнему содержат реальные parameters.

API приложения не содержит codec views, packed values, шаблонов, shape и
интерпретатора projection. Они доступны адаптерам через `Typed_sql_backend`;
конструкторы `view` и packed values разрешены только для pattern matching.
Адаптеры используют `Projection.Make` и `Template.map` из backend API.
`Projection.return` заменяет `pure`,
а `map`, `map2`, `map3` принимают именованный `~f` согласно Base.
Монадическая обёртка Lwt в PG'OCaml использует `Base.Monad.Make`.

## Результаты аудита

### Проверки

На текущем состоянии проходят:

- `make build`;
- `make test`;
- `make coverage` — 97,88% (599 из 612 точек) по реализации `Typed_sql`;
- `make check`, включая форматирование, сборку, tests, odoc, install smoke и
  `opam lint`.

Тесты покрывают PostgreSQL/SQLite SQL snapshots, source validation, empty
projection и negative limits, identifier quoting, bind parameter properties,
compile-fail cases и SQLite execution. Подключения к PostgreSQL в репозитории
нет, поэтому его driver/runtime compatibility этим набором не подтверждается.

Покрытие считается без suppression и только через API приложения: public
inline tests, QCheck и Caqti/SQLite `:memory:`. Coverage runner не запускает
white-box и backend test libraries. Оставшиеся 13 точек относятся к закрытым
query/expr constructors, shape accessors для адаптеров и защитным ветвям
validator/renderer, которые корректный публичный DSL устраняет до rendering.
Их покрытие потребовало бы тестировать private/backend API или расширить
публичный контракт только ради тестов, поэтому текущие 97,88% являются честным
пределом выбранного режима.

### Сильные стороны

- backend-independent core действительно не тянет Caqti или Lwt;
- пользовательские значения не вставляются в SQL template;
- identifiers проходят через validated descriptor и renderer quoting;
- phantom row type ловит несовместимые columns на compile time, а compiler
  дополнительно проверяет escaped references;
- query остаётся immutable deferred value и не содержит connection или effect;
- mapped domain types проходят через typed codec boundary;
- результат query имеет typed projection и проверенный decoder;
- portable surface пока маленький, поэтому его семантику легко проверять
  golden и integration tests.

### Долги и риски

Приоритеты ниже означают: `P0` — закрыть до расширения публичного AST, `P1` —
следующий функциональный слой, `P2` — последующие возможности.

#### P0: архитектурная основа — сделано

Semantic AST, normalization, validation, lowering и rendering разделены.
`Result_query`/`Command` и compiled counterparts образуют общий backend-neutral
контракт. Shape включает identity codec и типы projection. Тестовый интерфейс
выделен во внутреннюю библиотеку `typed_sql_private`; основной API не
раскрывает constructors AST.
Regression tests покрывают bind count, source scope, shape,
JOIN, DML, public API boundary и SQLite execution.

Отдельные тесты private API проверяют нормализацию и её идемпотентность,
ошибочные assignments и projections, ссылку на ещё не видимый source в JOIN ON,
а также порядок и значения bind parameters после lowering/rendering.
White-box tests остаются отдельным regression-набором и не влияют на метрику
публичного API. `make coverage` проверяет порог 97% и сохраняет подробный HTML
report в `_coverage/html/index.html`.

Остаётся только уточнить capability errors одновременно с первой
vendor-specific возможностью: пока все реализованные конструкции portable для
PostgreSQL и SQLite.

#### P1: portable SELECT — JOIN сделан, выражения остаются

`INNER JOIN`, `LEFT JOIN`, arbitrary `ON`, повторные table occurrences и
несколько visible sources реализованы. Aliases назначаются renderer'ом, а
SQLite integration test проверяет nullable правую сторону outer join.
Comparison и logical predicates теперь строятся через общий публичный `Infix`;
функциональные `and_`, `or_`, `all` и `any` скрыты из API.

Следующие portable выражения:

1. Добавить portable scalar expressions: typed literals, арифметику,
   `IN`/`NOT IN`, `BETWEEN`, `IS DISTINCT FROM` с capability policy, `CASE` и
   базовые string/date functions. Каждое выражение должно сохранять
   `Db_type` и проверяться compile-fail тестом.
2. Расширять общую PostgreSQL/SQLite golden suite для каждой новой portable
   feature. PostgreSQL integration scenario добавлять только вместе с
   локальной test infrastructure, не требующей внешнего сервиса по умолчанию.

#### P1: DML и execution API — базовый слой сделан

Single-row `INSERT`, scoped `UPDATE`/`DELETE`, assignments, `RETURNING` и
`execute` реализованы. SQLite integration test проверяет `INSERT RETURNING`,
UPDATE с known affected count и DELETE. Caqti errors и PG'OCaml codec errors
имеют отдельные adapter-level варианты.

Остаются multi-row insert, defaults, `ON CONFLICT`, `UPDATE ... FROM` и
переносимость affected-row count между drivers.

Отдельно нужно уточнить ошибочный путь mapped codec в Caqti adapter. Сейчас
отказ `Db_type.map.encode/decode` внутри `Caqti.Template.Row_type.custom` может
выйти как исключение `Reject`, минуя публичный `Typed_sql_caqti_lwt.error`.
Перед расширением codec API следует либо преобразовывать этот отказ в явный
adapter error, либо точно документировать контракт Caqti.

#### P1: второй backend — сделан без подключения

`typed-sql-pgocaml-lwt` компилируется и реализует codec/connection boundary,
но PostgreSQL runtime integration test намеренно отсутствует: задача запрещает
подключение к серверу. Caqti поддерживает PostgreSQL и SQLite; PG'OCaml —
PostgreSQL. Prepared statement cache остаётся ответственностью adapter'а.

#### P2: сложные запросы

1. Добавить scalar subquery, `EXISTS`, `IN (subquery)`, derived tables и CTE.
2. Добавить aggregates, `GROUP BY`, `HAVING` и validator для допустимых
   non-aggregate expressions. Более строгий `Grouped_query` можно вводить
   после проверки практического API.
3. Развести portable API и PostgreSQL extensions (`ILIKE`, `DISTINCT ON`,
   `ON CONFLICT`, JSON, arrays и т. п.) через явные namespaces и capability
   errors. SQLite lowering не должен обещать эквивалентность, которой нет.

#### P2: schema и ergonomics

1. Ввести dialect-neutral `Schema_ir`, introspection PostgreSQL/SQLite и
   генератор table/column/projection/codec descriptors.
2. Сгенерировать metadata для nullable, defaults, generated columns, PK, FK и
   unique constraints. `join_fk` может быть sugar поверх arbitrary joins.
3. Добавить dynamic filter registry только после появления стабильного
   descriptor/codegen API; строковые имена фильтров должны проходить через
   validated descriptors и typed parsing.

#### P2: производительность и расширения

1. Добавить compilation cache по полному normalized shape и explicit compiled
   queries с typed parameter slots. Не смешивать его с prepared statement
   cache Caqti или PG'OCaml.
2. Добавить безопасный `Raw_sql`/`Unsafe` escape hatch с отдельным API для
   bind fragments и явной маркировкой риска.
3. Оптимизировать построение больших lists в AST (`order_by`, condition
   lists), если benchmark покажет проблему.
4. Добавить PPX только после стабилизации ручного API и schema generator.

## Definition of done для следующего релизного среза

Следующим срезом должны стать portable scalar expressions и DML completion:

- typed `IN`, `BETWEEN`, arithmetic, `CASE` и базовые string/date functions;
- capability policy для semantic differences PostgreSQL и SQLite;
- multi-row insert, defaults и explicit portable/non-portable граница;
- golden и compile-fail cases для каждого нового expression;
- обновлённые public API docs и SQLite integration scenarios.

PPX, schema codegen и vendor-specific SQL остаются после стабилизации этого
ручного expression API.
