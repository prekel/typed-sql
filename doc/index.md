# typed-sql

`typed-sql` — backend-independent typed relational query DSL. Публичные типы
не позволяют сравнить выражения с разными OCaml-типами или применить колонку к
ссылке другой таблицы. Query остаётся immutable значением до явного вызова
execution adapter.

Текущий срез включает:

- типы БД, table/column descriptors, константы statement и runtime-параметры;
- статические statements с общим input и аппликативным связыванием параметров;
- typed witnesses для portable и concrete диалектов, а также dynamic statements;
- отдельные scalar expressions и SQL conditions;
- applicative projections произвольного OCaml-типа;
- `SELECT`, joins, filtering, ordering, pagination, grouping и aggregates;
- PostgreSQL `FETCH FIRST ... WITH TIES`, который сохраняет строки на границе
  страницы и требует явный `ORDER BY`;
- PostgreSQL `FOR UPDATE` с `OF` и `SKIP LOCKED` для конкурентного выбора строк;
- типизированные derived tables, portable set operations и non-recursive/recursive CTE;
- portable lists, arithmetic, string functions, `CASE`, date, UUID, timestamp и correlated
  subqueries;
- multi-row `INSERT`, conflict ignore, scoped `UPDATE`/`DELETE`, `UPDATE FROM`
  и `RETURNING`;
- PostgreSQL 17+ `MERGE` с условными ветвями, CTE-источниками и `RETURNING`;
- PostgreSQL и SQLite compiler;
- Lwt execution через `typed-sql-caqti-lwt` и PostgreSQL execution через
  `typed-sql-pgocaml-lwt`.

`Query.select_relation` вместе с `Derived_table.Fields` выводит типы полей
промежуточной relation из expressions и автоматически назначает им SQL-имена;
`Query.from_relation` возвращает expressions той же структуры. У
`Derived_table.Fields` нет произвольного `Projection.map`, поскольку результат
OCaml-преобразования нельзя представить как SQL-поля. `Derived_table.create`
остаётся API с явными descriptors и именами для `FROM`, JOIN и `UPDATE FROM`.
`Query.union`, `Query.union_all`, `Query.intersect` и
`Query.except` portable; `Postgresql.Query.intersect_all` и
`Postgresql.Query.except_all` требуют PostgreSQL. Renderer оборачивает operand
каждой set operation, поэтому локальные `ORDER BY`, `LIMIT` и `OFFSET` не
теряют семантику. Необязательный `order_by` у функций объединения задаёт
финальную сортировку общего результата по выбранному выходному полю; поле
должно встречаться ровно один раз в левой projection.

`Cte.select` и `Cte.recursive` создают relation, доступную только в callback
`Cte.with_result` или `Cte.with_command`. Hints `MATERIALIZED` и
`NOT MATERIALIZED` для SELECT CTE требуют SQLite 3.35 или новее. Data-modifying
CTE доступны только через `Postgresql.Cte`: `Postgresql.Cte.returning`
открывает relation из `RETURNING`, а `Postgresql.Cte.command` выполняется ради
эффекта. SQLite-эквивалента нет. `Cte.recursive_relation` выводит вложенную
структуру полей из anchor и проверяет, что recursive step возвращает ту же
форму и database types; `Query.select_one_relation` позволяет задать anchor
одним выражением без `FROM`.

`Statement.choose_dialect` объединяет PostgreSQL и SQLite statements с
одинаковыми типами input и output. Adapter выбирает заранее скомпилированную
ветку по dialect соединения.

Схема и генерация descriptors вынесены в `typed-sql-schema`. Интроспекция
доступна через `typed-sql-schema-caqti-lwt` и
`typed-sql-schema-pgocaml-lwt`; эти пакеты не нужны приложению для выполнения
запросов. Сгенерированный модуль зависит только от `typed-sql`.

Начать работу можно с [быстрого старта](quickstart.md). Варианты входного типа
для statement собраны в [руководстве по входным значениям](statement_inputs.md).
Запросы, чья форма зависит от input, описаны в
[разделе о динамических statements](dynamic_statements.md). Границы между DSL,
compiler и Caqti описаны в [обзоре архитектуры](architecture.md).

Решение сделать `Statement` единственным API выполнения и отвергнутые варианты
записаны в [ADR 0001](adr/0001-static-statement-api.md). Выбранные рамки и
открытые вопросы Raw SQL escape hatch записаны в
[ADR 0002](adr/0002-raw-sql-escape-hatch.md). Выводы эксперимента по
типизированным нарушениям ограничений и варианты будущего API собраны в
[ADR 0003](adr/0003-constraint-errors.md).

Как получить SQL со значениями и выполнить запрос во время разработки,
показано в [руководстве по запросам во время разработки](development_workflow.md).

API запросов описан в [lib/typed_sql.mli](../lib/typed_sql.mli), а API схемы —
в [schema/typed_sql_schema.mli](../schema/typed_sql_schema.mli). Для авторов
execution adapters есть отдельная библиотека `typed-sql.backend` и контракт
[backend/typed_sql_backend.mli](../backend/typed_sql_backend.mli).
