# История изменений

## 0.4.1 — 3 октября 2026

### Добавлено

- Совместимость SQL-диалекта проверяется по типу statement: `Statement.sql` и
  `Statement.sql_exn` принимают верхнеуровневые селекторы `postgresql` и
  `sqlite`, а неподдерживаемый диалект нельзя передать при компиляции.
- `Dialect.supports` связывает исключённые диалекты (`Not_postgres` и
  `Not_sqlite`) с наборами планов, собранных для statement.
- `Statement.Sql_error` сообщает понятную причину ошибок из throwing-варианта
  SQL-рендеринга.

## 0.4.0 — 3 октября 2026

### Добавлено

- `Statement.with_parameters ~dialect` собирает несколько statements с общими
  параметрами и типом input. Callback возвращает аппликативное значение;
  методы `params.query_many`, `params.query_one`, `params.query_optional`,
  `params.expect_one`, `params.expect_optional` и `params.command` компилируют
  statements при создании модуля и сообщают об ошибке через
  `Statement.Definition_error`.
- `Dialect.portable`, `Dialect.postgresql` и `Dialect.sqlite` дают typed witness
  выбора диалектов для статических и динамических statements.
- `params.optional_expr` связывает nullable input с nullable и non-null views
  одного bind slot. PostgreSQL pagination принимает nullable runtime-параметры
  через `params.non_negative_int_opt`, `Postgresql.Query.limit_param_opt` и
  `offset_param_opt`; `None` передаётся как SQL `NULL`, а отрицательный `Some`
  отклоняется при binding до выполнения.
- Statements без runtime-параметров компилируются напрямую через
  `Statement.query_many`, `query_one`, `query_optional`, `expect_one`,
  `expect_optional` и `command`; их тип input равен `unit`.

### Изменено

- `Statement.Parameters.t` стал непрозрачным аппликативным типом. Значения
  параметров нужно объединять через `let%map`/`and` или `let+`/`and+`; прямое
  использование результата `params.expr` как `Expr.t` больше не компилируется.
- Типизированный `Dialect.witness` заменил `Dialect.kind` и plain `Dialect.t`
  в конструкторах. `Statement.Portable` и `Statement.For_dialect` удалены.
  Portable witness компилирует PostgreSQL и SQLite; concrete witness
  ограничивает statement одним диалектом.
- Удалены `Statement.no_params`, `Statement.map_input` и прежние статические
  `_exn`-конструкторы. `Statement.Dynamic` теперь требует `~dialect` и отклоняет
  неподдерживаемый dialect до вызова callback.
- `Statement.Dynamic` сохранён для формы SQL, зависящей от input. Каждый
  конструктор получает весь input; для вложенных inputs getters статических
  параметров явно читают нужные поля одного общего типа input.

## 0.3.8 — 2 октября 2026

### Добавлено

- `Statement.no_params` фиксирует тип входа статического statement как `unit`
  без объявления runtime-параметров.
- `Typed_sql_pgocaml_lwt.Make(Pgocaml)` подключает execution-адаптер к
  существующему Lwt-модулю PG’OCaml: `run`, кэш и транзакции принимают
  соединения приложения без приведения типов.
- `Typed_sql_schema_pgocaml_lwt.Make(Pgocaml)` подключает интроспектор к
  тому же соединению без приведения типов. CLI
  `typed-sql-pgocaml-schema-dump` и Caqti-дампер используют одни
  catalog-запросы и преобразование в `Schema_ir`, принимают повторяемый
  `--exclude-table` и создают одинаковый JSON snapshot.

### Изменено

- Schema IR, snapshot и codegen перенесены из `typed-sql` в отдельный пакет
  `typed-sql-schema`; интроспекция вынесена из execution-адаптеров в
  `typed-sql-schema-caqti-lwt` и `typed-sql-schema-pgocaml-lwt`.
  Прежние пути OCaml API удалены. Имена CLI и формат генерируемого кода не
  меняются; сгенерированный модуль зависит только от `typed-sql`.
- PostgreSQL integration suite принимает версии 15–18 и позволяет выбрать
  `pg_config` через `TYPED_SQL_PG_CONFIG`. Полный набор проверен на 15.19 и
  18.6, включая оба адаптера и дампера схемы.

### Исправлено

- Генератор корректно создаёт код для PostgreSQL enum с метками `Ok` и
  `Error`: конструкторы результата теперь указываются явно.
- При выводе `Statement.Definition_error` теперь отображаются диалект и причина
  ошибки компиляции, в том числе при запуске inline-тестов.

## 0.3.7 — 1 октября 2026

### Добавлено

- PostgreSQL `Postgresql.Expr.equals_any` и `equals_any_list` выполняют batch
  lookup одним array bind-параметром через `= ANY`. `Db_type.Postgresql.array`
  сохраняет размерности и `NULL`-элементы, а `array_list` предоставляет
  одномерный список без `NULL`; SQLite отклоняет PostgreSQL-only запросы.
- `typed-sql-schema-dump` и `typed-sql-codegen` поддерживают повторяемый
  `--exclude-table SCHEMA.TABLE` с точным сопоставлением имён, включая
  заключённые в кавычки идентификаторы. Отсутствующая таблица вызывает ошибку;
  внешние ключи оставшихся таблиц сохраняются.

### Изменено

- Минимальная версия OCaml снижена до 4.14.1 для ядра и обоих execution
  backend. `make create_switch OCAML_VERSION=4.14.1` создаёт switch с выбранной
  версией; по умолчанию используется 5.1.1.
- `make deps` и `make deps_all` используют сохранённые `.opam`-файлы всех трёх
  пакетов без предварительного запуска Dune. Зависимость `str` удалена из
  метаданных пакета: эта библиотека поставляется с OCaml.

## 0.3.6 — 1 октября 2026

### Добавлено

- PostgreSQL `Postgresql.Query.for_update` добавляет `FOR UPDATE`, адресное
  `OF` и `SKIP LOCKED`; SQL помещает блокировку после сортировки и пагинации,
  а конкурентный выбор проверен на двух транзакциях.
- Добавлена финальная сортировка результатов `UNION`, `UNION ALL`, `INTERSECT`
  и `EXCEPT` по выбранным выходным полям через необязательный аргумент
  `order_by` у существующих функций объединения. Поле должно быть выбрано
  ровно один раз простой колонкой в левой ветви.
- `Statement.choose_dialect` объединяет заранее скомпилированные PostgreSQL- и
  SQLite-варианты в один portable statement с одинаковыми типами input и
  output; адаптер выбирает вариант по dialect соединения.
- `Cte.recursive_relation` и `Query.from_cte_relation` позволяют строить
  рекурсивные CTE со структурными полями, выведенными из anchor. Добавлены
  рекурсивные JOIN и `Query.select_one_relation` для anchor-строки без `FROM`.
- PostgreSQL-only `Postgresql.Query.fetch_with_ties` и
  `fetch_with_ties_param` сохраняют все строки, равные граничной строке
  страницы. Операция требует `ORDER BY` и сбрасывает доказательство верхней
  границы кардинальности.
- Добавлены `Postgresql.string_agg` и вариант `Postgresql.string_agg_nullable`
  для nullable-входов. Оба объединяют текстовые значения заданным разделителем
  и поддерживают локальный `ORDER BY`.
- PostgreSQL introspection и snapshot версии 2 сохраняют `enum`, домены,
  массивы, `json`, `jsonb`, `interval`, `timestamp without time zone` и
  именованные типы, включая прямой `inet`. Чтение snapshot версии 1 сохранено.
- Добавлены PostgreSQL codecs для локального timestamp, interval, JSON и
  многомерных массивов с границами и `NULL`-элементами. Caqti и PG’OCaml
  поддерживают новые типы при выполнении запросов.
- Генератор схемы создаёт модули для `enum` и доменов. Правила типов позволяют
  подключить пользовательский codec к именованному, базовому типу или
  отдельной колонке, в том числе представить timestamp прикладным `float`.
- `typed-sql-schema-dump` сохраняет схему живой PostgreSQL-базы в JSON.
  SQL-миграция тестовой схемы проверяется живой интроспекцией; сохранённый
  snapshot и сгенерированный OCaml-модуль хранятся в `test/schema/`.

### Изменено

- `make check` теперь включает все три отчёта покрытия; порог отдельного
  `make coverage-mega` повышен с 60% до 67,7%. Отчёт mega-запроса проверяет
  модули построения запросов и рендеринга; новые модули схемы и PostgreSQL
  codecs проверяются в основных отчётах покрытия.
- Порог публичного `make coverage` установлен на 96,5% сырого покрытия.
- Некорректная таблица назначения DML теперь возвращает явную ошибку
  компиляции. Внутренние `assert false` заменены проверкой инвариантов с
  диагностикой.

## 0.3.5 — 30 сентября 2026

### Добавлено

- `Query.exists_expr` возвращает не допускающее `NULL` булево выражение для
  проекции. Коррелированный `EXISTS (SELECT 1 ...)` проверен на SQLite и
  PostgreSQL; пустая выборка даёт `false`.
- `Values.create` и `Values.create_dynamic` создают типизированный источник
  строк для `FROM`, `INNER JOIN` и `LEFT JOIN`. Компилятор проверяет дескрипторы,
  ширину и database types строк, а также отклоняет внешние ссылки и агрегаты.
- `Insert.Columns` и `Insert.from_select` добавляют `INSERT ... SELECT` с
  проверкой порядка, принадлежности и database types целевых колонок.
  Поддерживаются CTE, операции множеств, `RETURNING` и conflict actions;
  синтаксис SQLite для `ON CONFLICT` после `SELECT` разрешается явным `WHERE`.
- Регрессионные, compile-fail и интеграционные проверки новых операций для
  SQLite и PostgreSQL; примеры в обзоре query builders обновлены.
- Отдельный `make coverage-mega` измеряет покрытие от одного сложного
  PostgreSQL-запроса с порогом 60% и без влияния на основные отчёты покрытия.
- Mega-запрос проверяется expect snapshot и выполняется на временном сервере
  PostgreSQL 18; форматирование вложенных JSON-подзапросов стало читаемее.

## 0.3.4 — 25 сентября 2026

### Добавлено

- `Expr.coalesce` для замены SQL `NULL` значением по умолчанию и
  `Query.select_one` для scalar `SELECT` без `FROM` с кардинальностью
  `exactly_one`.
- Воспроизводимый PostgreSQL 18 integration suite через Caqti и PG’OCaml;
  portable SQL cases выполняются и сравниваются на PostgreSQL и SQLite.
- Ограниченный PG’OCaml `Prepared_cache` с ключом по SQL и типам параметров,
  LRU-вытеснением и явным освобождением statements на connection.
- Привязка типа параметра в PostgreSQL `IS NULL`, устраняющая ошибку
  `could not determine data type of parameter`.

### Изменено

- PostgreSQL 18.6 runtime-проверки и ограничения API задокументированы;
  остальные major versions PostgreSQL пока не проверялись.
- Повторное выполнение простого запроса через PG’OCaml `Prepared_cache` на
  PostgreSQL 18.6 показало 1,96× ускорение в локальном benchmark.

## 0.3.3 — 25 сентября 2026

### Добавлено

- `Query.Aggregate` и `Query.aggregate_one` для ungrouped aggregate-запросов с
  доказанной кардинальностью `exactly_one`. `Aggregate_projection` ограничивает
  результат агрегатными выражениями и их композициями.
- Portable `SUM(int)`, `SUM(float)`, `MIN` и `MAX` для типов с явным
  `Db_type.Orderable` witness. Пустая группа и набор из одних `NULL` дают
  `None` для `SUM`, `MIN` и `MAX`.
- Точный `Decimal.t` и PostgreSQL `numeric`: агрегаты `SUM(int64)`,
  `SUM(numeric)`, `MIN(numeric)` и `MAX(numeric)`, codecs обоих адаптеров,
  introspection, schema snapshot и generator. SQLite явно отклоняет
  `numeric`; JSON multiset не принимает numeric-поля.
- Примеры SQL для новых агрегатов в `query_test` и отдельные проверки
  разбора `Decimal`.
- `Aggregate_projection.Let_syntax` для сборки агрегатов через `let%map` и
  `and` с сохранением гарантии наличия агрегатного выражения.

### Изменено

- Локальный switch и `make create_switch` используют OCaml 5.1.1;
  `make deps_all` закрепляет совместимый с ним `bisect_ppx`.
- Разбор `Decimal` удаляет завершающие нули до создания большого числа;
  публичная сигнатура уточняет проверки локальности агрегатов и ограничения
  точных чисел.

### Ограничения

- SQLite сравнивает сохранённые timestamp-значения как текст. Для
  хронологического `MIN`/`MAX` значения, записанные вне адаптера, должны иметь
  согласованный формат UTC; смешанные смещения часового пояса меняют порядок.

## 0.3.2 — 24 сентября 2026

### Добавлено

- `Projection.multiset_agg` для сбора строк текущей aggregate-группы с
  поддержкой `FILTER`, aggregate-local `ORDER BY` и вложенных коллекций.
- Поддержка OCaml 5.1.1 для core и обоих execution backend; примеры и тесты
  именованных кортежей вынесены отдельно и собираются только на OCaml 5.5+.

## 0.3.1 — 23 сентября 2026

### Добавлено

- `Query.where_optional_param` для nullable expression в static statement.
  Комбинатор рендерит `(parameter IS NULL OR predicate)`, поэтому optional
  filter не меняет SQL shape и не требует dynamic statement.

## 0.3.0 — 23 сентября 2026

### Добавлено

- Типизированные derived tables: завершённый `SELECT` с проверяемыми
  table/column descriptors можно использовать в `FROM`, JOIN и `UPDATE ... FROM`.
- Структурные поля промежуточной relation через `Query.select_relation` и
  `Derived_table.Fields`: типы выводятся из expressions, SQL-имена назначаются
  автоматически, а внешний запрос получает типизированные expressions без
  повторного объявления phantom row, таблицы и колонок.
- Portable `UNION`, `UNION ALL`, `INTERSECT` и `EXCEPT`; PostgreSQL получает
  `INTERSECT ALL` и `EXCEPT ALL`. Renderer оборачивает каждую ветвь, сохраняя
  её локальные `ORDER BY`, `LIMIT` и `OFFSET`.
- Non-recursive и recursive typed CTE с лексически ограниченными handles для
  `SELECT`, DML с `RETURNING` и команд.
- Hints `MATERIALIZED` и `NOT MATERIALIZED` для SELECT CTE. В SQLite для них
  требуется версия 3.35 или новее.
- PostgreSQL-only data-modifying CTE через `Postgresql.Cte.returning` и
  `Postgresql.Cte.command`.
- `Statement.sql` и `Statement.sql_exn` позволяют получить SQL статического
  statement без input и без запуска parameter getters.

### Изменено

- Кардинальность SELECT стала частью типовой модели: `many`, `at_most_one` и
  `exactly_one` распространяются через query builder и проверяются при
  создании statement.
- Добавлены `Query.limit_one` и `Query.select_exactly_one`, а также строгие
  `query_one`/`query_optional` и runtime-конструкторы `expect_one`/
  `expect_optional` для случаев, где гарантия появляется только из схемы или
  бизнес-инварианта.
- Публичный контракт кардинальности и его ограничения полностью описаны в
  `lib/typed_sql.mli`; добавлены regression, compile-fail и adapter tests.

## 0.2.0 — 17 сентября 2026

### Добавлено

- Статические statements: запрос и его SQL-планы создаются один раз при
  инициализации OCaml-модуля, а выполнение принимает одно типизированное
  input-значение.
- `Statement.Dynamic.Portable` с `query_many`, `query_one`, `query_optional` и
  `command` для безопасной runtime-компиляции SQL-формы из input без cache.
- Явные ошибки runtime-компиляции dynamic statement в `Statement.sql`, Caqti
  Lwt и PG'OCaml Lwt adapters.
- Runtime slots через `params.column` и `params.expr` без отдельного
  аппликативного descriptor параметров.
- Примеры десятипараметрического input на обычном кортеже, labeled tuple и
  record. Для переиспользуемых statements рекомендуется модуль операции с
  вложенным `Input.t`, `statement` и getters от Jane Street `ppx_fields_conv`.
- Проверяемые runtime `LIMIT`/`OFFSET` и `Statement.choose` для конечного набора
  заранее скомпилированных SQL shapes.
- ADR с обоснованием статического API и рассмотренными альтернативами.

### Изменено

- Caqti Lwt и PG'OCaml Lwt предоставляют единый `run`; cardinality задаётся
  конструкторами `query_many`, `query_one`, `query_optional` и `command`.
- `Compiler`, `Compiled_query` и `Compiled_command` стали внутренней границей
  ядра и backend adapters.
- `Expr.param` переименован в `Expr.constant`: прямые OCaml-значения в DSL
  считаются константами времени создания statement, а runtime-значения входят
  только через `Statement.parameters`.
- Публичные `Dialect.t`, `Statement.binding_error` и `Statement.sql_error`
  больше не раскрывают равенство с типами внутренней библиотеки; backend
  преобразует dialect и ошибки явно.

### Удалено

- Публичные `fetch`, `fetch_one`, `fetch_opt`, `execute`, compiled-варианты и
  `Dialect_specific` в execution adapters.

## 0.1.2 — 16 сентября 2026

### Добавлено

- Статические dialect requirements для выражений, условий, projections,
  запросов и DML. Portable statements принимают PostgreSQL и SQLite witnesses,
  а dialect-specific операции отклоняются несовместимым compiler witness ещё
  при typechecking.
- `Postgresql.Query.having` для PostgreSQL `HAVING` без `GROUP BY` и
  compile-fail проверки распространения requirements через scalar subqueries,
  projections и assignments.
- `Typed_sql_caqti_lwt.Dialect_specific` для явного выполнения
  dialect-specific statements с проверкой dialect текущего connection.

### Изменено

- `Compiler.compile` и `Compiler.compile_command` принимают типизированные
  `Dialect.postgresql`/`Dialect.sqlite`; runtime-выбор для portable statements
  вынесен в `compile_portable` и `compile_portable_command`.
- Обычные функции Caqti adapter принимают только portable statements, а
  PG'OCaml adapter — statements, совместимые с PostgreSQL.
- `Insert.default`, `Update.default` и PostgreSQL `HAVING` накапливают
  PostgreSQL requirement вместо поздней ошибки SQLite compiler.
- `Projection` реализует `Base.Applicative.S2`, сохраняя dialect requirement
  при аппликативной композиции.

## 0.1.1 — 16 сентября 2026

### Добавлено

- Portable UPSERT с conflict target, `DO UPDATE`,
  типизированными ссылками на existing/excluded rows и `RETURNING`.
  `Insert.Conflict_update` строит assignments через pipeline, поддерживает
  optional fields и условие `DO UPDATE … WHERE`.
- Caqti adapter получил opt-in profiling событий, bounded top-K profiler и
  выполнение заранее созданных `Compiled_query`/`Compiled_command` с проверкой
  dialect.

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
