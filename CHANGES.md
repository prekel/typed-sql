# История изменений

## 0.1.0 — 15 сентября 2026

### Добавлено

- Portable expressions: `IN`/`NOT IN`, `BETWEEN`, `IS DISTINCT FROM`,
  арифметика, `CASE`, string functions и concatenation.
- `DISTINCT`, `COUNT`, `COUNT DISTINCT`, `GROUP BY`, `HAVING` и
  aggregate validation.
- Correlated `EXISTS`, scalar subqueries и `IN (subquery)`.
- Timestamp with time zone через `Ptime.t` и `CURRENT_TIMESTAMP`.
- Отдельный SQL `DATE` через абстрактный `Date.t`, включая Caqti/PG'OCaml
  codecs, schema introspection и codegen.
- Валидируемый `Uuid.t` и нативный UUID codec для core, Caqti, PG'OCaml,
  introspection и codegen.
- Multi-row `INSERT`, SQL `DEFAULT`, `UPDATE ... FROM`, условные assignments
  и portable `Insert.on_conflict_do_nothing` для PostgreSQL/SQLite.
- Transaction helpers и portable constraint classification в Caqti и PG'OCaml
  adapters.
- Явная ошибка `Codec of string` для отказов mapped codec на encode и decode.
- Dialect-neutral `Schema_ir`, PostgreSQL/SQLite introspection через Caqti и
  generator OCaml table/column/projection descriptors с relational metadata.
- Сгенерированный schema source теперь компилируется downstream-тестом;
  коллизии нормализованных имён разрешаются стабильными числовыми суффиксами.
- `Schema_snapshot` сохраняет schema IR в JSON версии 1; `typed-sql-codegen`
  генерирует OCaml из snapshot без БД. Добавлена зависимость от Yojson.
- Отдельные `make coverage` для публичного API и `make coverage-all` для
  полного набора ядра. Релизные результаты — 97,85% и 100,00% соответственно.
- PostgreSQL/SQLite golden tests, compile-fail fixtures и расширенный SQLite
  `:memory:` integration test для новых SQL-возможностей.
- Compiler benchmark теперь отдельно измеряет маленькие запросы и shapes с
  20/100 условиями `WHERE` или выражениями `ORDER BY`.
- Полная odoc-документация интерфейсов приложения, backend-контракта и
  Caqti/PG'OCaml execution adapters.
- Адаптер `typed-sql-pgocaml-lwt`, собираемый без подключения к PostgreSQL.

### Изменено

- Полный интерфейс приложения и документация находятся в одном
  `lib/typed_sql.mli`. Реализации ядра собраны без отдельных `.mli`, а facade
  реэкспортирует только пользовательский контракт.
- `typed-sql.backend` предоставляет авторам adapters codec views, packed
  parameters, projection decoder, templates и shape. Конструкторы доступны
  только для pattern matching.
- `typed-sql.private` используется отдельными white-box тестами и не влияет на
  метрику покрытия публичного API.
- `Projection` реализует `Base.Applicative.S` и `Let_syntax`; Lwt-обёртка
  PG'OCaml реализует `Base.Monad.S`.
- `Query.from` начинает builder, а `Query.select` завершает его. В README,
  документации и тестах SELECT/DML используют локальные `Query.(...)`,
  `Insert.(...)`, `Update.(...)` и `Delete.(...)`.
- Compiler разделён на normalization, validation, dialect lowering и rendering.
  Unsupported operations завершаются capability error до генерации SQL.
- Renderer строит канонический многострочный SQL как документ с отдельными
  текстовыми фрагментами, bind slots, переносами и отступами. `sql`, `pp` и
  execution adapters используют один formatter-based путь.
- Shape учитывает identity mapped codec и projection layout, но не parameter
  values, generated source IDs, aliases или connections.
