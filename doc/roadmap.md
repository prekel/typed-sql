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
- expect snapshots, QCheck-проверки bind parameters и SQL injection, набор
  compile-fail fixtures, измерение покрытия через публичный API и package/doc
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

Capability errors реализованы вместе с первой vendor-specific возможностью.
Lowering возвращает `Unsupported_operation` с именем операции и dialect до
rendering; приблизительный SQL не генерируется.

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

#### P1: DML и execution API — сделано

Multi-row `INSERT`, scoped `UPDATE`/`DELETE`, `DEFAULT`, PostgreSQL
`ON CONFLICT DO NOTHING`, `UPDATE ... FROM`, условные assignments, `RETURNING`
и `execute` реализованы. Multi-row builder проверяет одинаковый набор columns и
нормализует их порядок по первой строке. `Update.set_opt` различает пропуск
assignment и запись `NULL`. SQLite integration test проверяет multi-row
`INSERT RETURNING`, conditional update и `UPDATE FROM`. PostgreSQL-only и
неподдерживаемые SQLite операции отклоняются capability layer.

Ошибочный путь mapped codec в Caqti adapter закрыт. Adapter выполняет
`Db_type.map.encode/decode` вокруг базового Caqti row type, поэтому отказ
возвращается как `Codec of string` и не пересекает Caqti в виде исключения.
SQLite `:memory:` проверяет encode, все три fetch-варианта decode и пригодность
соединения после отказа.

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
3. Добавить portable `DISTINCT` и `COUNT DISTINCT`: они нужны для запросов через
   many-to-many связи без дублирования корневых строк.
4. Развести portable API и PostgreSQL extensions (`ILIKE`, `DISTINCT ON`,
   `ON CONFLICT`, JSON, arrays и т. п.) через явные namespaces и capability
   errors. SQLite lowering не должен обещать эквивалентность, которой нет.

#### Внешний проверочный сценарий: RealWorld / Conduit

После малого среза выражений внешний backend по [официальному OpenAPI RealWorld
2.0](https://raw.githubusercontent.com/realworld-apps/realworld/main/specs/api/openapi.yml)
станет проверочным сценарием публичного API. Само приложение будет находиться в
отдельном репозитории и использовать `typed-sql` вместе с соседним проектом
`../typed-endpoint`. Его минимальная реляционная модель включает `users`,
`articles`, `comments`, `tags`, `article_tags`, `follows` и `favorites`.
Приложение должно зависеть только от публичного API `Typed_sql` и execution
adapter; private и backend API не должны проникать в его код.

Для полного контракта RealWorld потребуются следующие возможности:

1. Реализовать `COUNT` и `COUNT DISTINCT` для `favoritesCount` и
   `articlesCount`, включая отдельный count query с теми же фильтрами, но без
   `LIMIT` и `OFFSET`.
2. Реализовать `EXISTS` и scalar subquery. Они нужны для полей `following` и
   `favorited`, пользовательского feed и фильтров статей по tag, author и
   favorited без размножения строк результата.
3. Поддержать эффективную загрузку коллекций. `tagList` и другие one-to-many
   данные можно сначала собирать отдельным batch query через portable `IN`, а
   затем группировать в OCaml. Это позволит не вводить dialect-specific JSON или
   array aggregation в основной API и избежать N+1 запросов.
4. Добавить переносимое представление timestamp и выражение текущего времени
   либо ясно зафиксировать database defaults для `createdAt` и `updatedAt`.
   Сортировка и сравнение timestamp должны сохранять тип выражения.
5. Добавить условные assignments для частичных изменений, например
   `Update.set_opt`. Для nullable column внешний `None` означает «не менять», а
   `Some None` — записать SQL `NULL`. Пустой PATCH должен оставаться явной
   ошибкой до выполнения.
6. Определить транзакционную границу execution adapters. Создание или изменение
   статьи вместе с `article_tags`, а также follow/favorite должны завершаться
   атомарно. API может принимать уже транзакционный connection, но это нужно
   показать одинаковым lifecycle и тестом rollback для поддерживаемых adapters.
7. Поддержать идемпотентные записи в `tags`, `follows` и `favorites` через
   portable conflict policy либо через явно именованные dialect extensions.
   Уникальные пары и slug не должны проверяться только предварительным SELECT.
8. Сформировать adapter-level contract для constraint violations: unique
   username/email/slug должен преобразовываться в HTTP 409, нарушения внешних
   ключей и отсутствующие ресурсы — в предсказуемые ошибки приложения. Если
   единая классификация между drivers невозможна, различие должно быть явно
   отражено в adapter API.
9. Проверить ownership predicates для изменения и удаления articles/comments.
   Авторизация должна выражаться одним scoped `UPDATE`/`DELETE` по идентификатору
   ресурса и владельца, без разрыва между предварительной проверкой и mutation.

JWT, password hashing, HTTP routing, JSON validation и генерация slug относятся
к внешнему приложению и `typed-endpoint`, а не к SQL DSL. OpenAPI contract tests
также остаются в репозитории приложения и служат внешним критерием совместимости
для обоих библиотечных проектов.

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

## Порядок следующих работ

### 1. Ошибки mapped codec в Caqti — сделано

- добавлен `Typed_sql_caqti_lwt.Codec of string`;
- отказы `Db_type.map.encode` и `Db_type.map.decode` преобразуются в этот
  вариант без утечки `Reject`;
- encode и decode failures проверяются SQLite integration-тестами.

### 2. Малый законченный срез portable выражений

- добавить `IN`/`NOT IN`, `BETWEEN`, арифметику, `CASE` и базовые строковые
  функции;
- для каждой конструкции определить публичный typed API, semantic AST,
  normalization, validation, lowering и rendering;
- добавить одинаковые PostgreSQL/SQLite golden cases, SQLite execution и
  compile-fail проверки несовместимых типов;
- сохранить покрытие публичного API не ниже 97%.

### 3. Capability errors и граница dialect extensions — сделано

- определена отдельная ошибка с названием операции и выбранным dialect;
- capability check выполняется в lowering до rendering;
- этот механизм используется для PostgreSQL conflict policy и SQL `DEFAULT` и
  должен применяться до добавления `ILIKE`, `DISTINCT ON`,
  `ON CONFLICT`, JSON, arrays и других vendor-specific операций;
- приблизительный portable SQL с другой семантикой не генерируется.

### 4. Завершение DML — сделано

- добавлен multi-row `INSERT` с проверкой одинакового набора columns;
- SQL `DEFAULT` выражается без подмены nullable значением;
- conflict policy размещена в отдельном PostgreSQL namespace;
- добавлен `UPDATE ... FROM` вместе с source-scope validation;
- добавлены условные assignments для PATCH-запросов RealWorld.

### 5. Запросы, необходимые RealWorld

- добавить `EXISTS`, scalar subquery, `DISTINCT`, `COUNT`, `COUNT DISTINCT`,
  `GROUP BY` и минимальный validator aggregates;
- добавить typed timestamp/default current time;
- зафиксировать batch-loading pattern через `IN` для tags и других коллекций;
- проверить транзакции, idempotent follow/favorite и structured constraint
  errors на SQLite без внешней базы.

### 6. Schema codegen

После стабилизации expression и DML API добавить dialect-neutral `Schema_ir`,
introspection PostgreSQL/SQLite и генерацию table, column, nullable, projection
и codec descriptors. Генератор также должен знать defaults, generated columns,
PK, FK и unique constraints, используемые моделью RealWorld.

### 7. Подготовка к внешней проверке через RealWorld

- не добавлять RealWorld application, его HTTP endpoints и OpenAPI contract
  tests в этот репозиторий;
- держать `typed-sql` независимым от `typed-endpoint`: отдельное приложение
  будет зависеть от обеих библиотек и при локальной разработке использовать
  `../typed-endpoint`;
- предоставить стабильные публичные API expression, DML, schema codegen и
  execution adapters, необходимые внешнему приложению;
- переносить обнаруженные при реализации RealWorld неудобства в regression
  tests и изменения публичного API этого проекта;
- считать OpenAPI 3.1, schema/migrations, users/auth, profiles/follows,
  articles, comments, favorites, tags и их contract tests ответственностью
  отдельного репозитория RealWorld.

## Definition of done для следующего релизного среза

Ближайший срез заканчивается после этапов 1–3:

- ошибки mapped codec всегда возвращаются как
  `Typed_sql_caqti_lwt.Codec`;
- готовы typed `IN`/`NOT IN`, `BETWEEN`, arithmetic, `CASE` и базовые string
  functions;
- unsupported dialect operation возвращает явный capability error;
- PostgreSQL/SQLite golden, compile-fail и SQLite execution tests проходят;
- `make coverage` показывает не менее 97%, а public `.mli` и odoc обновлены.

DML completion, RealWorld query primitives и schema codegen выполняются
следующими срезами в указанном порядке. Само приложение RealWorld не входит в
этот репозиторий: оно отдельно проверит интеграцию `typed-sql` с
`../typed-endpoint`. PPX остаётся после стабилизации ручного API по результатам
этой внешней проверки.
