# Дорожная карта

Состояние проекта на 12 сентября 2026 года. Документ сопоставляет текущую
реализацию с исходным [first_plan.md](first_plan.md), фиксирует завершённый
релизный срез и перечисляет следующую работу. Приложение RealWorld будет жить в
отдельном репозитории и использовать `typed-sql` вместе с `../typed-endpoint`.

## Текущее состояние

Ядро представляет собой backend-independent immutable DSL. Semantic AST
последовательно проходит normalization, validation, dialect lowering и
rendering. Значения остаются bind parameters, identifiers создаются только
через проверенные descriptors, aliases и номера параметров назначаются
детерминированно compiler.

Пользовательский контракт с документацией целиком находится в
`lib/typed_sql.mli`. Реализация ядра собрана как библиотека из `.ml` без
отдельных сигнатур; facade `Typed_sql` реэкспортирует только публичную часть.
Execution adapters используют отдельный `typed-sql.backend`, а white-box тесты
могут обращаться к `typed-sql.private`. В пользовательском API нет AST
constructors, codec views, packed parameters, renderer helpers и decoder IR.

### SELECT и выражения

Реализованы:

- `INNER JOIN` и `LEFT JOIN` с проверкой source scope;
- `WHERE`, optional filters, `ORDER BY`, `LIMIT`, `OFFSET` и `DISTINCT`;
- `IN`/`NOT IN`, включая пустые списки и batch-loading pattern;
- `BETWEEN`, `IS DISTINCT FROM`, арифметика для `int`, `int64` и `float`;
- `CASE`, `LOWER`, `UPPER`, `LENGTH` и string concatenation;
- `COUNT(*)`, `COUNT`, `COUNT DISTINCT`, `GROUP BY` и `HAVING`;
- correlated `EXISTS`/`NOT EXISTS`, scalar query и `IN (subquery)`;
- `Ptime.t` как timestamp with time zone и `CURRENT_TIMESTAMP`.

Aggregate validator запрещает aggregates в `WHERE`, `JOIN ON` и `GROUP BY`,
nested aggregates и non-grouped expressions. Точное составное выражение из
columns, arithmetic и portable string functions можно повторить в projection и
`ORDER BY` после `GROUP BY`.

### DML

Реализованы multi-row `INSERT`, SQL `DEFAULT`, scoped `UPDATE`/`DELETE`,
`RETURNING`, `UPDATE ... FROM` и условные assignments для PATCH. Multi-row
builder проверяет пустые строки, повторные columns и одинаковый набор columns
во всех строках. `Update.set_opt` различает «не менять» и запись `NULL` для
nullable columns.

`Insert.on_conflict_do_nothing` является portable API для PostgreSQL и SQLite.
Он позволяет делать идемпотентные вставки tags, follows и favorites без
предварительного `SELECT`. Остальные integrity failures сохраняются как ошибки
adapter. SQLite не поддерживает `DEFAULT` внутри `VALUES` и `UPDATE SET
DEFAULT`, поэтому compiler возвращает `Unsupported_operation`, не подменяя
семантику.

### Execution adapters

`typed-sql-caqti-lwt` выполняет запросы на PostgreSQL и SQLite, а
`typed-sql-pgocaml-lwt` предоставляет отдельный PostgreSQL adapter. Оба
адаптера:

- преобразуют mapped codec failures в `Codec of string`;
- классифицируют constraint violations;
- предоставляют transaction helper с commit, rollback и rollback при
  исключении.

SQLite `:memory:` integration suite проверяет все codec, DML, expressions,
aggregates, correlated subqueries, conflict ignore и транзакции. PostgreSQL
compiler, Caqti branch и PG'OCaml adapter собираются без подключения к серверу.

### Schema introspection и codegen

`Schema_ir` хранит tables, schemas, columns, nullable, defaults, generated
flags, позиции composite PK, FK с referenced schema и ordered columns, а также
named UNIQUE constraints. Неизвестный тип сохраняется как `Unsupported`, чтобы
generator не угадывал потенциально неверный codec.

`Typed_sql_caqti_lwt.Schema.introspect` читает:

- SQLite metadata через `sqlite_schema`, `pragma_table_xinfo`,
  `pragma_foreign_key_list`, `pragma_index_list` и `pragma_index_info`;
- PostgreSQL metadata через `information_schema` с исключением system schemas и
  views.

SQLite introspection проверена исполнением. PostgreSQL introspection реализована
и проходит сборку, но не запускалась против сервера по текущему ограничению.

`Schema_codegen.generate` создаёт OCaml modules с row record, table и column
descriptors, accessors, applicative projection и metadata для defaults,
generated columns, PK, FK и UNIQUE. Выход parser-check'ится тестом; пустые
таблицы и неизвестные database types возвращаются явными ошибками.

### Проверки и покрытие

Тесты разделены по назначению:

- `make coverage` запускает только public API tests, properties и SQLite
  integration; порог равен 97%, отчёт находится в
  `_coverage/public/html/index.html`;
- `make coverage-all` дополнительно запускает backend и private white-box
  suites; порог равен 99%, отчёт находится в
  `_coverage/all/html/index.html`.

Последний полный прогон перед обновлением этого документа дал 98,25% через
публичный API и 100,00% всеми тестами ядра. Точные цифры следует обновлять после
изменения instrumented implementation.

## Отличия от `first_plan.md`

### Этапность вместо полного DSL сразу

Исходный план описывает широкий jOOQ-подобный API. Реализация сначала закрыла
portable вертикальные срезы PostgreSQL/SQLite и только затем добавила DML,
подзапросы, aggregates и schema codegen. Derived tables, CTE, set operations,
window functions, JSON и arrays не вводились без прикладного сценария.

### Source safety

Использован предусмотренный планом V1: callback получает generative
`Table_ref`, AST хранит source identity, compiler проверяет все visible sources.
Type-level списки witnesses `There`/`Skip` не появились. Это оставляет
пользовательский код коротким, а escaped reference завершается понятной compile
error до rendering.

### Единый читаемый facade

Вместо `.mli` у каждого implementation module сделан один документированный
`typed_sql.mli`. Внутренние `.ml` составляют отдельную библиотеку, facade
скрывает их представления, adapter API вынесен в `typed-sql.backend`. Такое
устройство сохраняет один читаемый вход для приложения и отдельный доступ для
адаптеров и максимального white-box coverage.

### Applicative projection

Projection реализует `Base.Applicative.S` и `Let_syntax`. Monad для projection
не добавлена: структура SQL SELECT должна быть известна до получения строки, а
зависимый `bind` нарушил бы это требование. Lwt-обёртка PG'OCaml, напротив,
реализует `Base.Monad.S`.

### Dialects и adapters появились раньше

PostgreSQL и SQLite compiler развивались параллельно, поэтому portable
семантика проверяется парными golden tests. Второй adapter PG'OCaml появился до
runtime PostgreSQL infrastructure и пока проверяется compile-only.

## Что осталось сделать

### 1. Проверить текущий API внешним RealWorld-приложением

В отдельном репозитории нужно реализовать официальный RealWorld/OpenAPI 3.1:
users/auth, profiles/follows, articles, comments, favorites и tags. Приложение
должно зависеть только от публичных API `Typed_sql`, execution adapter и
`../typed-endpoint`; ручной SQL и `typed-sql.private`/`typed-sql.backend` в
application code не допускаются.

Первый runtime должен использовать SQLite `:memory:` или временный файл.
Нужные patterns уже доступны: scoped ownership mutations, transactions,
idempotent inserts, count queries, correlated flags и batch loading tags через
`IN`. Найденные неудобства следует переносить сюда как regression tests до
стабилизации generator и выпуска PPX.

### 2. Добавить PostgreSQL runtime infrastructure, когда подключение разрешат

- выполнить общую integration suite через Caqti PostgreSQL;
- отдельно проверить PG'OCaml encode/decode, transaction lifecycle и SQLSTATE
  classification;
- проверить PostgreSQL schema introspection на identity/generated columns,
  composite PK/FK и cross-schema references;
- сравнить результаты portable запросов с SQLite.

Эти проверки сейчас заблокированы только запретом подключения; компилируемые
ветки уже реализованы.

### 3. Расширять schema tooling по результатам реальных схем

- type-check generated source как отдельный downstream module, а не только
  parser-check;
- определить deterministic policy для совпадающих нормализованных OCaml names;
- добавить codecs для востребованных типов (`uuid`, decimal, date, enums), не
  отображая их молча на неточный базовый тип;
- решить, нужны ли typed FK descriptors и `join_fk` поверх уже доступного
  arbitrary join;
- отделить schema discovery/codegen от будущих migrations и schema diff.

### 4. Добавлять сложные запросы по прикладной необходимости

Следующий возможный portable слой: derived tables, CTE, `UNION` и window
functions. PostgreSQL extensions (`ILIKE`, `DISTINCT ON`, conflict targets и
`DO UPDATE`, JSON, arrays) должны находиться в явно именованных namespaces и
проходить capability check до rendering. Portable approximation с другой
семантикой не допускается.

### 5. Производительность и escape hatch

- измерить compile и execution overhead на больших query shapes;
- добавить compilation cache по normalized shape только при подтверждённом
  выигрыше, не смешивая его с prepared-statement cache adapter;
- определить отдельный `Unsafe`/`Raw_sql` API с typed bind fragments, когда
  появится запрос, который нельзя выразить descriptors;
- оптимизировать построение больших condition/order lists только по benchmark;
- проектировать PPX после проверки ручного API внешним RealWorld-приложением.

## Definition of done текущего релизного среза

- portable expression, aggregate, subquery, timestamp и DML API документированы
  в одном публичном `.mli`;
- PostgreSQL и SQLite имеют парные SQL snapshots, а portable semantics
  исполняются на SQLite;
- mapped codec, transaction и constraint errors не выходят из adapter contract;
- PostgreSQL/SQLite schema introspection и descriptor generator реализованы;
- `make release-check`, `make coverage` и `make coverage-all` проходят;
- PostgreSQL server не требуется и не используется.

После выполнения этих пунктов дальнейшее расширение API должно опираться на
внешний RealWorld-сценарий или отдельный подтверждённый use case.
