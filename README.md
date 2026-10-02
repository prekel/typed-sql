# typed-sql

`typed-sql` — backend-independent typed relational query DSL для OCaml.
`Statement.t` служит единым объектом выполнения. Фиксированная форма SQL
проверяется и компилируется при инициализации OCaml-модуля; динамическая форма
может безопасно строиться из типизированного input при каждом вызове.

Текущий срез поддерживает типизированные `SELECT` с joins, derived tables,
CTE, `VALUES` relations, portable set operations, expressions, aggregates,
`GROUP BY`, correlated subqueries, `EXISTS` в проекции и вложенными
коллекциями, calendar date, timestamp и UUID. Результат set operation можно
упорядочить по выбранным выходным полям. Рекурсивные CTE поддерживают
структурные поля, выведенные из anchor.
PostgreSQL-вариант query builder включает `FETCH FIRST ... WITH TIES`. DML
включает multi-row `INSERT`, `INSERT ... SELECT`, portable UPSERT, scoped
`UPDATE`/`DELETE`, `DEFAULT`, `UPDATE FROM`, условные assignments и `RETURNING`.
Пакеты `typed-sql-caqti-lwt` и `typed-sql-pgocaml-lwt` выполняют запросы
через Caqti и PG'OCaml. Отдельный `typed-sql-schema` содержит schema IR,
snapshot и codegen, а `typed-sql-schema-caqti-lwt` и
`typed-sql-schema-pgocaml-lwt` читают схему базы. Приложению достаточно
query-пакета и выбранного execution-адаптера. Поддерживаются PostgreSQL 15–18.
Полный набор интеграционных тестов пройден на PostgreSQL 15.19 и 18.6 через
оба адаптера; версии 16 и 17 отдельно пока не проверялись.

```ocaml
open Typed_sql
open Infix

module Person = struct
  type row

  let table : row Table.t = Table.v_exn "people"
  let id_col = Column.v_exn table "id" Db_type.int64
  let name_col = Column.v_exn table "name" Db_type.text
  let id row = Expr.column row id_col
  let name row = Expr.column row name_col
end

type find_people =
  { name : string
  ; maximum_rows : int
  }

let find_people =
  Statement.Portable.query_many_exn (fun params ->
    let name = params.column Person.name_col ~get:(fun input -> input.name) in
    let maximum_rows =
      params.non_negative_int
        ~name:"maximum_rows"
        ~get:(fun input -> input.maximum_rows)
    in
    Query.(
      from Person.table
      |> where (fun person -> Person.name person =. name)
      |> order_by (fun person -> Person.id person) `Asc
      |> limit_param maximum_rows
      |> select (fun person ->
        Projection.pair (Person.id person) (Person.name person))))
```

`Query.(...)` локально открывает только query-builder и сохраняет видимой
границу DSL. `select` ставится последним: он задаёт projection и превращает
builder в готовый `Result_query.t`.

Callback `query_many_exn` вызывается один раз во время создания значения.
`params.column` выводит SQL-тип из descriptor колонки, поэтому отдельный
аппликативный список параметров не нужен. Для статического statement
`Statement.sql` возвращает канонический SQL без input: он читает заранее
скомпилированный template и не запускает parameter getters. Если передать
`~input`, getters и проверки параметров выполняются так же, как перед запуском
через adapter. Значения в SQL не интерполируются:

Операторы с `$`, `Expr.constant`, `Insert.set` и `Update.set` захватывают
константы времени создания statement. Меняющиеся между вызовами значения
вводятся через `params` и используются как expressions операторами с точкой.
Input может быть обычным кортежем, кортежем с метками или record; полные
варианты приведены в [документации](doc/statement_inputs.mld).

Если input задаёт саму структуру запроса, например рекурсивный язык предикатов
или список переменной длины для `IN`, используется
`Statement.Dynamic.Portable`. Callback получает input целиком; DSL всё равно
создаёт bind parameters и компилирует portable SQL для dialect соединения.
Подробный пример находится в
[документации динамических statements](doc/dynamic_statements.mld).

Если PostgreSQL и SQLite должны использовать разные SQL-запросы, готовые
статические ветки можно объединить через `Statement.choose_dialect`:

```ocaml
let statement =
  Statement.choose_dialect
    ~postgresql:postgresql_statement
    ~sqlite:sqlite_statement
```

Обе ветки должны иметь одинаковые типы input и output. Результат имеет
portable dialect и адаптер выбирает нужный заранее скомпилированный вариант
по dialect соединения.

```ocaml
let sql =
  Statement.sql
    ~dialect:Dialect.Postgresql
    find_people
```

```sql
SELECT
  t0."id",
  t0."name"
FROM "people" AS t0
WHERE
  (t0."name" = $1)
ORDER BY
  t0."id" ASC
LIMIT $2
```

Scalar subquery выражает возможное отсутствие строки через `option` и требует
явного доказательства cardinality: `LIMIT 0`/`LIMIT 1` либо aggregate без
`GROUP BY`. Например:

```ocaml
let department_name person =
  Expr.scalar_subquery
    Query.(
      from Department.table
      |> where (fun department -> Department.person_id department =. Person.id person)
      |> limit 1
      |> select_scalar Department.name)
```

Для уже nullable expression есть `Expr.scalar_subquery_nullable`: SQL не
различает отсутствие строки и строку с `NULL`, поэтому оба случая дают `None`.

`Query.exists_expr` превращает незавершённый SELECT в булево выражение для
проекции. Оно возвращает `false` для пустой выборки и допускает корреляцию с
внешним запросом:

```ocaml
let has_department person =
  Query.(
    from Department.table
    |> where (fun department ->
      Department.person_id department =. Person.id person)
    |> exists_expr)

let people_with_department =
  Query.(
    from Person.table
    |> select (fun person ->
      Projection.pair (Person.name person) (has_department person)))
```

## Вложенные коллекции

`Query.multiset` превращает завершённый SELECT в одну типизированную
projection со списком строк. Вложенный запрос может ссылаться на источники
внешнего запроса, а `Projection.map` продолжает декодировать каждый элемент:

```ocaml
let people_with_departments =
  Query.(
    from Person.table
    |> select (fun person ->
      let departments =
        Query.(
          from Department.table
          |> where (fun department ->
            Department.person_id department =. Person.id person)
          |> order_by Department.name `Asc
          |> select (fun department -> Projection.expr (Department.name department)))
      in
      Projection.both
        (Projection.expr (Person.name person))
        (Query.multiset departments)))
```

`Projection.multiset_agg` собирает строки текущей aggregate-группы. Его
`order_by` задаёт гарантированный порядок списка, а `filter` позволяет убрать
пустую сторону `LEFT JOIN`:

```ocaml
Projection.multiset_agg
  ~filter:(Comment.article_id comment =. Article.id article)
  ~order_by:[ Aggregate_order.asc (Comment.created_at comment) ]
  (Comment.projection comment)
```

Обе операции возвращают пустой список при отсутствии строк и поддерживают
рекурсивные коллекции. JSON-массивы используются только как переносимый
внутренний формат между PostgreSQL или SQLite и decoder. Для ordered
`multiset_agg` требуется SQLite 3.45 или новее. Бинарные поля пока не
поддерживаются внутри коллекций.

## Составные отношения, операции множеств и CTE

Для промежуточной relation её SQL-поля можно описать прямо в завершающем
`Query.select_relation`. Типы выводятся из expressions, SQL-имена назначаются
детерминированно, а `Query.from_relation` возвращает expressions той же
структуры:

```ocaml
let active_people =
  Query.(
    from Person.table
    |> where (fun person -> Person.name person =$ "Ada")
    |> select_relation (fun person ->
      Derived_table.Fields.pair (Person.id person) (Person.name person)))

let query =
  Query.(
    from_relation active_people
    |> where (fun (id, _name) -> id >$ 10L)
    |> select (fun (id, name) -> Projection.pair id name))
```

`Derived_table.Fields` намеренно не имеет аналога `Projection.map`: результат
произвольного OCaml-преобразования нельзя снова представить как SQL-поля.
`Fields.expr` и `Fields.both` позволяют собирать структурные описания большей
глубины. Такие relation также принимают `Query.inner_join_relation`,
`Query.left_join_relation` и `Update.from_relation`.

`Values.create` строит виртуальную relation из типизированных строк. Дескрипторы
задают имена и типы её колонок; таблица с таким именем в базе не требуется.
`Values.create_dynamic` принимает строки переменной формы и сообщает ошибку
компиляции при несовпадении ширины или database types. Доступны
`Query.from_values`, `Query.inner_join_values` и `Query.left_join_values`:

```ocaml
module Selected_id = struct
  type row

  let table : row Table.t = Table.v_exn "selected_ids"
  let id_col = Column.v_exn table "id" Db_type.int64
  let id row = Expr.column row id_col
end

let selected_ids =
  Values.create
    ~table:Selected_id.table
    ~columns:(fun row -> Projection.expr (Selected_id.id row))
    ~first:(Values.Row.expr (Expr.constant Db_type.int64 1L))
    ~rest:[ Values.Row.expr (Expr.constant Db_type.int64 3L) ]

let selected_people =
  Query.(
    from_values selected_ids
    |> select (fun row -> Projection.expr (Selected_id.id row)))
```

Когда нужны заданные вручную SQL-имена и descriptors, низкоуровневый
`Derived_table.create` связывает готовый `SELECT` с `Table.t` и `Column.t`.
Такой результат передаётся в `Query.from_derived`, join-варианты или
`Update.from_derived`. Компилятор проверяет прямые колонки descriptor,
уникальность имён и совпадение database-типов с projection внутреннего
`SELECT`.

`Query.union`, `Query.union_all`, `Query.intersect` и `Query.except` работают
для двух завершённых `SELECT` с одинаковой последовательностью database-типов.
Операции portable для PostgreSQL и SQLite. PostgreSQL-варианты
`Postgresql.Query.intersect_all` и `Postgresql.Query.except_all` добавляют
требование PostgreSQL к statement. Каждый operand set operation renderer
оборачивает в derived branch, поэтому локальные `ORDER BY`, `LIMIT` и `OFFSET`
сохраняют семантику до объединения результатов. Финальную сортировку общего
результата задаёт необязательный аргумент `~order_by` у функций объединения.
Ключ — checked identifier выходного поля, например:

```ocaml
Query.union
  ~order_by:[ (Column.name Book.id_column, `Asc) ]
  first_ids
  second_ids
```

Поле должно быть выбрано ровно один раз простой колонкой в левой ветви
объединения. Пустой `order_by` не добавляет финальную сортировку.

`Cte.select` создаёт именованную relation из derived table, а
`Cte.with_result` и `Cte.with_command` делают её handle видимым только внутри
callback внешнего `SELECT`, DML с `RETURNING` или команды. Handle используется
через `Query.from_cte`/join-варианты и `Update.from_cte`. `Cte.recursive`
задаёт anchor и recursive step с единственной типизированной self-reference;
вариант рекурсии выбирается через `` `Union`` или `` `Union_all``.

Для рекурсивной relation с выводимыми структурными полями есть
`Cte.recursive_relation`. Anchor и step строятся через `Query.select_relation`
с `Derived_table.Fields`; compiler требует одинаковую форму полей и проверяет
их database types. `Query.select_one_relation` создаёт anchor из одного
выражения без `FROM`, а `Query.from_cte_relation` и рекурсивные JOIN-варианты
возвращают поля той же структуры:

```ocaml
let numbers =
  Cte.recursive_relation
    ~union:`Union_all
    ~anchor:(Query.select_one_relation (Expr.constant Db_type.int 1))
    ~step:(fun numbers ->
      Query.(
        from_cte_relation numbers
        |> where (fun number -> number <$ 5)
        |> select_relation (fun number ->
          Derived_table.Fields.expr
            Expr.Int.Infix.(number +. Expr.constant Db_type.int 1))))

let number_query =
  Cte.with_result numbers ~f:(fun numbers ->
    Query.(from_cte_relation numbers |> select Projection.expr))
```

Для нескольких полей используйте вложенные `Derived_table.Fields.both` и
`Query.inner_join_cte_relation` или `Query.left_join_cte_relation`.

PostgreSQL поддерживает `FETCH FIRST ... WITH TIES` через
`Postgresql.Query.fetch_with_ties` и `fetch_with_ties_param`. Все ключи
`ORDER BY` определяют равенство строк на границе страницы; результат может
содержать больше строк, чем заданный размер. Поэтому операция требует хотя бы
один ключ порядка и возвращает кардинальность `many`. Параметр размера
проверяется на неотрицательность:

```ocaml
let tied_people =
  Statement.For_dialect.query_many_exn ~dialect:Dialect.postgresql (fun parameters ->
    let page_size =
      parameters.non_negative_int ~name:"page_size" ~get:Fn.id
    in
    Query.(
      from Person.table
      |> order_by Person.name `Asc
      |> Postgresql.Query.fetch_with_ties_param page_size
      |> select (fun person ->
        Projection.pair (Person.id person) (Person.name person))))
```

Вызов `limit`, `limit_param` или `fetch_with_ties` позже в pipeline заменяет
предыдущий row limit; `OFFSET` сохраняется. SQLite эту операцию не поддерживает.

Для конкурентной очереди PostgreSQL используйте
`Postgresql.Query.for_update ~skip_locked:true` внутри транзакции. Необязательный
`~of_:(fun row -> [Postgresql.Query.target row])` ограничивает блокировку
выбранными источниками JOIN. Вызов можно поставить до или после `order_by` и
`limit`: SQL всегда помещает `FOR UPDATE` в конце SELECT. Сортируйте по
уникальному ключу, если нужен предсказуемый выбор строк. `OFFSET` тоже
блокирует пропущенные строки; `SKIP LOCKED` несовместим с `FETCH WITH TIES`.

Для non-recursive SELECT CTE `Cte.select` принимает hints
`` `Materialized`` и `` `Not_materialized``. Они доступны в PostgreSQL и в
SQLite версии 3.35 или новее; более старый SQLite эти hints не поддерживает.
Data-modifying CTE оформляются только через `Postgresql.Cte.returning` и
`Postgresql.Cte.command`, поэтому требуют PostgreSQL уже в типе statement и не
имеют SQLite-замены. Первый вариант открывает relation из `RETURNING` внешнему
statement, второй выполняется только ради эффекта.

DML строится так же через локальное открытие соответствующего builder:

```ocaml
let insert =
  Insert.(
    rows
      Person.table
      [ (fun row -> row |> set Person.id_col 1L |> set Person.name_col "Ada")
      ; (fun row -> row |> set Person.id_col 2L |> set Person.name_col "Grace")
      ]
    |> command)

let rename =
  Update.(
    table Person.table
    |> set Person.name_col "Ada Lovelace"
    |> where (fun person -> Person.id person =$ 1L)
    |> command)
```

Для `INSERT ... SELECT` задайте целевые колонки в порядке проекции источника.
Компилятор сверяет их принадлежность таблице и точные database types, включая
`NULL` и mapped codecs. Источником может быть SELECT с CTE или операцией
множеств; `ON CONFLICT` и `RETURNING` доступны как для обычного `INSERT`:

```ocaml
module Archive = struct
  type row

  let table : row Table.t = Table.v_exn "people_archive"
  let id_col = Column.v_exn table "id" Db_type.int64
  let name_col = Column.v_exn table "name" Db_type.text
end

let archive_people =
  Statement.Portable.command_exn (fun _ ->
    let source =
      Query.(
        from Person.table
        |> select (fun person ->
          Projection.pair (Person.id person) (Person.name person)))
    in
    let columns = Insert.Columns.(column Archive.id_col |> add Archive.name_col) in
    Insert.(
      into Archive.table
      |> from_select columns source
      |> on_conflict_do_nothing
      |> command))
```

Идемпотентная вставка для поддерживаемых dialect записывается в основном API:

```ocaml
let insert_once =
  Statement.Portable.command_exn (fun _ ->
    Insert.(
      into Person.table
      |> set Person.id_col 1L
      |> set Person.name_col "Ada"
      |> on_conflict_do_nothing
      |> command))
```

Для атомарного insert-or-update задаётся непустой conflict target. Callback
получает типизированные ссылки на существующую строку и на предложенную SQL
строку `excluded`:

```ocaml
let upsert_person id name =
  let target = Insert.Conflict_target.column Person.id_col in
  Insert.(
    into Person.table
    |> set Person.id_col id
    |> set Person.name_col name
    |> on_conflict target
    |> do_update (fun ~existing ~excluded ->
      Conflict_update.(
        empty
        |> set_expr Person.name_col (Person.name excluded)
        |> where (Person.name existing <>. Person.name excluded)))
    |> returning (fun person ->
      Projection.pair (Person.id person) (Person.name person)))
```

Составной target записывается как
`Insert.Conflict_target.(column first_col |> add second_col)`. Вместо
`do_update` можно завершить target-specific политику через `do_nothing`.

`Conflict_update.where` ограничивает обновление при конфликте; обычную вставку
он не фильтрует. Повторные условия объединяются через `AND`. Если условие
ложно или равно SQL NULL, строка не обновляется и не попадает в `RETURNING` —
для одной строки используйте `Statement.Portable.expect_optional_exn`. Без
`where` обновляется каждая
конфликтующая строка. `set_opt` и `set_expr_opt` пропускают `None`;
`set_opt nullable_col (Some None)` записывает NULL.

Conflict target описывает колонки уникального ключа. Наличие подходящего
ограничения проверяет БД; partial indexes и именованные constraints пока не
входят в этот API. Compiler дополнительно проверяет, что target и update
assignments принадлежат таблице INSERT, даже если разные descriptors используют
один phantom-тип. В multi-row UPSERT не следует повторять один конфликтующий
ключ: PostgreSQL отклоняет повторное обновление одной строки в одном запросе.

Операции, семантика которых отсутствует в выбранном dialect, возвращают
`Compile_error.Unsupported_operation` до rendering.

`Statement` не содержит connection или `Lwt.t`. Выполнение имеет один API для
любой cardinality и для команд:

```ocaml
Typed_sql_caqti_lwt.run
  ~conn
  find_people
  { name = "Ada"; maximum_rows = 100 }
```

Чтобы найти запросы, на которых заметна стоимость DSL compilation, Caqti
adapter принимает необязательный observer. Встроенный profiler ограничивает
число хранимых SQL shapes и строит отчёт по суммарному времени локальной
подготовки:

```ocaml
let profiler = Typed_sql_caqti_lwt.Profiler.create ()
let observer = Typed_sql_caqti_lwt.Profiler.observer profiler

let fetch_people conn input =
  Typed_sql_caqti_lwt.run
    ~observer
    ~name:"people.by_name"
    ~conn
    find_people
    input

let print_profile () =
  Stdlib.Format.printf
    "%a%!"
    Typed_sql_caqti_lwt.Profiler.pp
    (Typed_sql_caqti_lwt.Profiler.snapshot profiler)
```

Событие измеряет подготовку Caqti request, database round trip и декодирование.
Для dynamic statement построение DSL и compilation происходят до начала
события и поэтому в него не входят. Большое время `database` следует разбирать
через план SQL и индексы.

Транзакционная граница также принадлежит adapter:

```ocaml
Typed_sql_caqti_lwt.transaction ~conn ~f:(fun conn ->
  Typed_sql_caqti_lwt.run ~conn insert_once ()
  |> Lwt.map (Result.map ~f:(fun _ -> ())))
```

Чтобы получить OCaml-код из живой PostgreSQL-базы, задайте параметры
подключения через `PGHOST`, `PGPORT`, `PGUSER`, `PGDATABASE` (или передайте URI)
и выполните:

```sh
typed-sql-schema-dump --exclude-table public.audit postgresql:// > schema.json
typed-sql-codegen --type-rules type-rules.json schema.json > schema.ml
```

`typed-sql-schema-dump` устанавливается с `typed-sql-schema-caqti-lwt`.
Второй дампер устанавливается с `typed-sql-schema-pgocaml-lwt` и создаёт тот
же snapshot:

```sh
typed-sql-pgocaml-schema-dump --exclude-table public.audit postgresql:// > schema.json
```

Оба дампера можно вызвать без URI: по умолчанию используется `postgresql://`
и параметры подключения из окружения. PG’OCaml дампер принимает в URI host,
port, user, password и имя базы, а также `?host=/path/to/socket` для Unix socket;
остальные URI-параметры возвращают явную ошибку.
Dump фильтрует результат introspection перед записью snapshot; сам запрос
каталогов PostgreSQL по-прежнему видит всю доступную схему.
`--exclude-table SCHEMA.TABLE` можно повторять в обеих командах. Имена
сопоставляются точно и с учётом регистра; для имён с точками, кавычками или
пробелами используйте quoted SQL identifiers, например
`'public."USER PROFILE"'`. Отсутствующая таблица завершает команду ошибкой.
Исключение удаляет таблицу из snapshot или сгенерированного модуля, сохраняя
FK-метаданные оставшихся таблиц даже при ссылке на исключённую таблицу.
Если snapshot уже исключает таблицу, не передавайте это же имя повторно в
codegen: отсутствующая в snapshot таблица считается ошибкой. Для фильтра только
при генерации опустите `--exclude-table` в команде dump.
Тот же snapshot можно получить из OCaml-кода:

```ocaml
Typed_sql_schema_caqti_lwt.introspect ~conn
|> Lwt.map
     (Result.map ~f:(fun schema ->
        Stdlib.Out_channel.with_open_bin "schema.json" (fun channel ->
          Stdlib.output_string channel
            (Typed_sql_schema.Schema_snapshot.to_string schema))))
```

Для PG’OCaml соединения доступен
`Typed_sql_schema_pgocaml_lwt.introspect ~conn`. Если приложение использует
свой `module Pgocaml = PGOCaml_generic.Make (Thread)`, создайте
`module Schema = Typed_sql_schema_pgocaml_lwt.Make (Pgocaml)` и вызовите
`Schema.introspect ~conn`; тип соединения останется тем же.

Snapshot хранится в репозитории. Установленный вместе с `typed-sql-schema` CLI читает
его без подключения к базе и выводит OCaml source:

```sh
typed-sql-codegen schema.json > schema.ml
typed-sql-codegen - < schema.json > schema.ml
typed-sql-codegen --type-rules type-rules.json schema.json > schema.ml
```

`schema.ml` хранится в исходном каталоге и компилируется Dune как обычный
модуль. После изменения схемы или правил запустите CLI повторно и сохраните
обновлённый файл. Пример проекта —
[`test/schema/regenerate.sh`](test/schema/regenerate.sh): он записывает
`schema_fixture.json` и `generated_schema.ml` непосредственно в `test/schema/`.
`make test` сравнивает сохранённые файлы с результатом генератора.
`make test-postgres` применяет единственную
[SQL-миграцию](test/schema/schema_fixture.sql) к чистой PostgreSQL-базе,
запускает интроспекцию и сравнивает полученный JSON с `schema_fixture.json`
побайтно.

Библиотека, компилирующая `schema.ml`, должна зависеть от `base`, `typed-sql`,
`yojson` при JSON-колонках и библиотек пользовательских codecs
и использовать `(preprocess (pps ppx_let))`. Generator добавляет необходимые
`open`, а совпавшие после нормализации OCaml-имена получают стабильные суффиксы
`_2`, `_3` в порядке schema IR.

Формат JSON и обработка ошибок описаны в
[doc/schema_snapshot.md](doc/schema_snapshot.md). Получение схемы и применение
миграций запускаются отдельно от обычной сборки.

PostgreSQL introspection сохраняет enum, domain, массивы, JSON, interval,
timestamp без часового пояса и остальные именованные типы в snapshot.
Для enum и domain generator создаёт отдельные модули; для массива сохраняет
размерности, границы и `NULL`-элементы. Для `inet`, `geometry`, `rational` и
других типов без встроенного codec настройте правила генератора. Ими же можно
переопределить базовый SQL-тип или конкретную колонку, например представить
`timestamp without time zone` как прикладной `float` с собственным
`Db_type.map`. Формат правил описан в
[doc/schema_snapshot.md](doc/schema_snapshot.md). Неизвестный тип без правила
вызывает ошибку генерации.

Встроенный codec `Local_timestamp` ожидает PostgreSQL `DateStyle` с ISO-выводом,
а `Interval` — стандартный `IntervalStyle = postgres`. Для других настроек
формата используйте пользовательский codec через те же правила.

API запросов находится в [`lib/typed_sql.mli`](lib/typed_sql.mli), а API
генерации — в [`schema/typed_sql_schema.mli`](schema/typed_sql_schema.mli).
Прежние `Typed_sql.Schema_*` и `Typed_sql_*_lwt.Schema` заменены модулями
новых пакетов.

Авторы адаптеров используют отдельную библиотеку `typed-sql.backend` и
[`backend/typed_sql_backend.mli`](backend/typed_sql_backend.mli): параметры,
codec, шаблоны, shape и декодеры. Она разрешает `Statement.t` для dialect
соединения и получает план с текущими bind values.

Почему `Statement` стал единственным execution API и какие варианты
рассматривались, описано в
[`doc/adr/0001-static-statement-api.md`](doc/adr/0001-static-statement-api.md).

Внутренняя `typed-sql.private` содержит реализацию только в `.ml`, включая AST
и этапы compiler. White-box тесты используют её напрямую; этот интерфейс не
имеет гарантий совместимости.

## Сборка

Минимальная поддерживаемая версия — OCaml 4.14.1. По умолчанию проект
создаёт локальный switch OCaml 5.1.1:

```sh
make create_switch
make deps_all
make check
make release-check
make coverage
make coverage-all
make coverage-mega
```

Для нового клона с OCaml 4.14.1:

```sh
make create_switch OCAML_VERSION=4.14.1
make deps_all
make check
```

Если OCaml 4.14.1 собирается из исходников с GCC 15 и сборка компилятора
завершается ошибкой о числе аргументов C-функции, установите зависимости через
`CC='gcc -std=gnu17' make deps_all`: этому компилятору нужен режим C17.

`make deps` устанавливает зависимости сборки, а `make deps_all` — также
зависимости тестов, документации и разработки. Обе команды используют
закоммиченные `.opam`-файлы и не требуют заранее установленного Dune.
Библиотека `str` поставляется с OCaml и не требует отдельного opam-пакета.

Benchmark compiler для маленького запроса и shapes с 20/100 условиями или
сортировками запускается отдельно:

```sh
opam exec -- dune exec benchmark/query_bench.exe
```

SQLite integration tests используют `sqlite3::memory:`. Отдельный
`make test-postgres` создаёт временный кластер PostgreSQL 15–18 на локальном Unix
socket, запускает Caqti и PG'OCaml integration tests, включая общие SQL golden
cases на PostgreSQL и SQLite, и удаляет кластер после прогона. Версию сервера
задаёт `pg_config` из `PATH`; для другого установленного сервера укажите путь:

```sh
TYPED_SQL_PG_CONFIG=/path/to/postgresql-15/bin/pg_config make test-postgres
```

Нужны утилиты выбранной версии (`pg_config`, `initdb`, `pg_ctl`, `createdb`,
`psql`), opam-пакет `caqti-driver-postgresql` и системная библиотека
разработки `libpq`.
На Ubuntu для сборки SQLite driver нужен системный пакет `libsqlite3-dev`.

Проверены PostgreSQL 15.19 и 18.6. Nullable scalar subquery возвращает `None`
как при отсутствии строки, так и при SQL `NULL` в найденной строке.
PG'OCaml сообщает число затронутых строк как `Affected_rows.Unknown`. Native
PostgreSQL JSON и array codecs остаются за пределами portable API; вложенные
коллекции проходят через JSON transport адаптера.

### Prepared statements

`Statement.t` хранит скомпилированную форму SQL в OCaml; подготовленный запрос
базы данных живёт отдельно на конкретном connection. Caqti adapter создаёт
`Request.Dynamic`: драйвер PostgreSQL подготавливает SQL при первом вызове и
повторно использует его через кэш connection. Драйвер SQLite аналогично
сохраняет `sqlite3_stmt` и выполняет его повторно после reset. Кэш Caqti
ограничен: его стандартная ёмкость для dynamic requests — 32, она настраивается
через `Caqti.Connect.Config.dynamic_prepare_capacity`.

PG'OCaml `run` по умолчанию вызывает `prepare` для каждого выполнения.
Если приложение уже использует собственный Lwt-модуль
`Pgocaml = PGOCaml_generic.Make(Thread)` и пул его соединений, создайте адаптер
для этого же модуля:

```ocaml
module Adapter = Typed_sql_pgocaml_lwt.Make (Pgocaml)

let result = Adapter.run ~conn statement input
```

`conn` сохраняет тип `Pgocaml.t` из приложения; преобразование типов не нужно.
Транзакции и пул могут оставаться в приложении.

Для часто вызываемого statement можно создать явный кэш на одном connection:

```ocaml
let open Lwt.Syntax in
let module Adapter = Typed_sql_pgocaml_lwt in
let cache =
  match Adapter.Prepared_cache.create ~capacity:32 ~conn () with
  | Ok cache -> cache
  | Error error -> failwith (Adapter.error_to_string error)
in
Lwt.finalize
  (fun () -> Adapter.Prepared_cache.run cache statement input)
  (fun () ->
    let* closed = Adapter.Prepared_cache.close cache in
    match closed with
    | Ok () -> Lwt.return_unit
    | Error error -> Lwt.fail_with (Adapter.error_to_string error))
```

Ключ кэша включает SQL и упорядоченные PostgreSQL-типы параметров. При
вытеснении и `close` адаптер закрывает именованные statements на сервере.
После изменения схемы создайте новый кэш; для нового connection также нужен
новый кэш. Временный PostgreSQL 18.6 дал 1,96× для 2000 повторов простого
запроса через PG'OCaml adapter (0,510 с без кэша, 0,260 с с кэшем). Повторить
замер можно командой `TYPED_SQL_PREPARE_BENCH=1 make test-postgres`.

`make coverage` измеряет query core и перенесённые чистые модули схемы через
публичные API: запускает inline tests, QCheck properties и SQLite `:memory:`
integration tests. White-box tests и backend-контракты в этот прогон не
входят. Порог равен 96,5%, HTML-отчёт создаётся в
`_coverage/public/html/index.html`.

`make coverage-all` добавляет backend и private suites, требует не менее 99% и
пишет отчёт в `_coverage/all/html/index.html`. Для локального switch с OCaml
5.1.1 `make deps_all` закрепляет `bisect_ppx` на upstream commit, совместимом с
используемым `ppxlib`.

`make coverage-mega` отдельно измеряет, какие ветви компилятора проходит один
сложный PostgreSQL-запрос из `test/mega_coverage_test.ml`. Этот диагностический
прогон требует не менее 67,7% и не заменяет `make coverage` или
`make coverage-all`; отчёт находится в `_coverage/mega/html/index.html`.
`make check` запускает форматирование, сборку, тесты, все три проверки покрытия,
генерацию документации и проверку пакетов.
