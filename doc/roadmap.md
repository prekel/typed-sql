# Дорожная карта

Состояние проекта на 25 сентября 2026 года. Документ сопоставляет текущую
реализацию с исходным [first_plan.md](first_plan.md), фиксирует завершённый
релизный срез и перечисляет следующую работу. Приложение RealWorld будет жить в
отдельном репозитории и использовать `typed-sql` вместе с `../typed-endpoint`.

## Текущее состояние

Ядро представляет собой backend-independent immutable DSL. Semantic AST
последовательно проходит normalization, validation, dialect lowering и
rendering. Значения остаются bind parameters, identifiers создаются только
через проверенные descriptors, aliases и номера параметров назначаются
детерминированно compiler.

Renderer строит один канонический многострочный SQL template с фиксированными
двухпробельными отступами. `Statement.sql` и execution adapters используют одно
представление; отдельного compact SQL нет. Layout не входит в `Shape.t`, поэтому
форматирование не меняет идентичность плана или порядок bind parameters.

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
- correlated `EXISTS`/`NOT EXISTS`, nullable scalar query и `IN (subquery)`;
- derived tables в `FROM`/JOIN и `UPDATE ... FROM`;
- portable `UNION`, `UNION ALL`, `INTERSECT` и `EXCEPT`, а также PostgreSQL
  `INTERSECT ALL` и `EXCEPT ALL`;
- non-recursive и recursive CTE с лексически ограниченными typed handles;
- `Ptime.t` как timestamp with time zone, отдельный `Date.t` для SQL `DATE` и
  `CURRENT_TIMESTAMP`.

Aggregate validator запрещает aggregates в `WHERE`, `JOIN ON` и `GROUP BY`,
nested aggregates и non-grouped expressions. Portable `HAVING` доступен после
`GROUP BY`. PostgreSQL-вариант без `GROUP BY` строится явным
`Postgresql.Query.having` и требует PostgreSQL уже в типе statement. Точное составное выражение из
columns, arithmetic и portable string functions можно повторить в projection и
`ORDER BY` после `GROUP BY`.

Scalar subquery возвращает `option`: отсутствие строки не может быть decoded
как значение non-null column. Встраивание требует `LIMIT 0`/`LIMIT 1` либо
local aggregate без `GROUP BY`; иначе compiler возвращает
`Scalar_subquery_may_return_many_rows`. Для nullable expression отдельный
`scalar_subquery_nullable` не создаёт вложенный `option`.

Пустой `CASE` нормализуется в `else_`, поэтому не попадает в renderer как
некорректный `CASE ELSE ... END`.

### Derived tables, операции множеств и CTE

`Query.select_relation` принимает отдельное структурное описание
`Derived_table.Fields`: каждый leaf является SQL expression, поэтому типы
полей выводятся без повторных column descriptors. SQL-имена назначаются
детерминированно, а `Query.from_relation`, join-варианты и
`Update.from_relation` получают expressions в той же структуре. У `Fields`
нет произвольного `map`: декодирование в произвольный OCaml-тип остаётся
возможностью `Projection`, но не может быть автоматически превращено обратно
в SQL-поля.

`Derived_table.create` остаётся явным вариантом для заданных вручную relation
descriptors и SQL-имён. Compiler проверяет прямые output columns, отсутствие
повторяющихся имён и совпадение последовательности database-типов relation с
внутренней projection.

`Query.union`, `union_all`, `intersect` и `except` принимают завершённые
`SELECT` с одинаковым OCaml-типом результата. Compiler дополнительно требует
совпадения последовательностей fingerprints database-типов, включая identity
mapped codecs. Renderer оборачивает каждую ветвь set operation, поэтому её
`ORDER BY`, `LIMIT` и `OFFSET` применяются до объединения.

Текущий decoder set operation асимметричен: итоговый `Result_query` сохраняет
`Projection` левой ветви и декодирует им все строки объединённого результата.
Правая projection задаёт SQL expressions и проверяемую последовательность
database-типов своей ветви, но её преобразования `Projection.map` после этого
не используются. Поэтому одинаковый OCaml-тип результата и одинаковые
database-типы не доказывают, что обе projections одинаково интерпретируют
поля.

Точный публичный контракт остаётся открытым решением. Нужно выбрать один из
трёх вариантов:

1. **Закрепить decoder левой ветви.** Сохранить текущий API и совместимость,
   явно описав асимметрию в `typed_sql.mli`. Этот вариант самый простой, но
   допускает незаметно отбросить отличающееся преобразование правой projection.
2. **Объединять relations.** Выполнять set operation над структурными полями
   relation, а единый `select` и decoder применять снаружи к объединённому
   результату. Граница декодирования становится однозначной, но потребуется
   новый relation-level API и путь миграции с операций над `Result_query`.
3. **Передавать итоговый decoder явно.** Отделить projections SQL-ветвей от
   projection объединённого результата. Семантика будет явной без обязательной
   relation-обёртки, но вызов получит ещё один аргумент и потребует определить,
   как итоговая projection ссылается на поля compound query.

До подтверждённого прикладного сценария ни один вариант не выбран, а текущее
поведение считается деталью реализации, которую нельзя обещать как стабильный
контракт. Duplicate-preserving `INTERSECT ALL` и `EXCEPT ALL` находятся в
`Postgresql.Query`; SQLite их capability check отклоняет до rendering.

`Cte.select` и `Cte.recursive` дают handle, видимый только в callback
`Cte.with_result` или `Cte.with_command`. Non-recursive CTE можно пометить
`MATERIALIZED` или `NOT MATERIALIZED`; для SQLite необходима версия 3.35 или
новее. Recursive CTE содержит typed anchor и step, а compiler допускает ровно
одну top-level self-reference в step. `Postgresql.Cte.returning` и
`Postgresql.Cte.command` создают data-modifying CTE для outer `SELECT`, DML с
`RETURNING` или команды. `returning` открывает relation из `RETURNING`, а
`command` выполняется только ради эффекта; SQLite такие CTE не поддерживает.

### DML

Реализованы multi-row `INSERT`, SQL `DEFAULT`, scoped `UPDATE`/`DELETE`,
`RETURNING`, `UPDATE ... FROM` и условные assignments для PATCH. Multi-row
builder проверяет пустые строки, повторные columns и одинаковый набор columns
во всех строках. `Update.set_opt` различает «не менять» и запись `NULL` для
nullable columns.

Portable UPSERT API для PostgreSQL и SQLite поддерживает global и
target-specific `DO NOTHING`, составной conflict target и `DO UPDATE` с
типизированными ссылками на existing/excluded rows. В 0.2.0
`Insert.Conflict_update.(empty |> set_expr ... |> where ...)` задаёт
assignments и предикат обновления. Повторные предикаты объединяются через
`AND`; пропущенное обновление не возвращает строку в `RETURNING`.
Builder поддерживает `set_opt` и `set_expr_opt`. UPSERT совместим с
multi-row `VALUES` и `RETURNING`; пустые или повторные update assignments и
повторные target columns отклоняются compiler. SQLite не поддерживает
`DEFAULT` внутри `VALUES` и `UPDATE SET DEFAULT`. Эти builders добавляют
PostgreSQL requirement, поэтому SQLite witness и portable Caqti API отклоняют
такой statement при typechecking, не подменяя семантику.

### Requirements dialect

Публичные `Expr`, `Condition`, `Projection`, query и DML builders несут
covariant phantom requirement. `Statement.Portable` компилирует планы
PostgreSQL и SQLite при создании. PostgreSQL-only operation добавляет
[`Postgresql], а requirement проходит через subquery, projection, UPSERT и
assignments. `Statement.For_dialect` принимает статический witness, а adapter
при едином `run` сверяет сохранённый dialect с connection.

### Execution adapters

`typed-sql-caqti-lwt` выполняет запросы на PostgreSQL и SQLite, а
`typed-sql-pgocaml-lwt` предоставляет отдельный PostgreSQL adapter. Оба
адаптера:

- преобразуют mapped codec failures в `Codec of string`;
- классифицируют constraint violations;
- предоставляют transaction helper с commit, rollback, rollback при ошибке
  commit и rollback при исключении.

SQLite `:memory:` integration suite проверяет все codec, DML, expressions,
aggregates, correlated subqueries, conflict ignore и транзакции. PostgreSQL
compiler, Caqti branch и PG'OCaml adapter собираются без подключения к серверу.
Это не подтверждает runtime-корректность: PostgreSQL сейчас нельзя считать
поддерживаемой и проверенной базой до прохождения следующего этапа.

### Schema introspection и codegen

`Schema_ir` хранит tables, schemas, columns, nullable, defaults, generated
flags, позиции composite PK, FK с referenced schema и ordered columns, а также
named UNIQUE constraints. Неизвестный тип сохраняется как `Unsupported`, чтобы
generator не угадывал потенциально неверный codec.

SQL `DATE` отделён от timestamp на уровне типов, adapters и introspection;
SQLite `DATE` больше не отображается на неточный timestamp codec. UUID также
имеет отдельный валидируемый тип, native adapter codec и codegen mapping.

`Typed_sql_caqti_lwt.Schema.introspect` читает:

- SQLite metadata через `sqlite_schema`, `pragma_table_xinfo`,
  `pragma_foreign_key_list`, `pragma_index_list` и `pragma_index_info`;
- PostgreSQL metadata через `information_schema` с исключением system schemas и
  views.

SQLite introspection различает rowid alias `INTEGER PRIMARY KEY` и primary key,
который всё ещё допускает `NULL`; implicit FK без списка referenced columns
восстанавливает ordered primary key родительской таблицы. PostgreSQL introspection реализована
и проходит сборку, но не запускалась против сервера по текущему ограничению.

`Schema_codegen.generate` создаёт OCaml modules с row record, table и column
descriptors, accessors, applicative projection и metadata для defaults,
generated columns, PK, FK и UNIQUE. Выход parser-check'ится тестом; пустые
таблицы и неизвестные database types возвращаются явными ошибками. Отдельный
downstream test генерирует `.ml`, компилирует его и строит запросы через
полученные descriptors. Совпавшие после нормализации имена получают стабильные
суффиксы `_2`, `_3` с учётом служебных bindings generator. Generator экранирует
OCaml keywords и одиночный `_`, а ссылки на библиотечные модули использует через
свой alias, поэтому table и column names не могут их перекрыть.

`Schema_snapshot` сохраняет весь schema IR в JSON версии 1 с сохранением
порядка и metadata. CLI `typed-sql-codegen schema.json` или
`typed-sql-codegen -` генерирует OCaml без БД. Downstream-тест проходит весь
путь IR → JSON → CLI → компиляция и использование generated descriptors.
Формат описан в [schema_snapshot.md](schema_snapshot.md).

### Проверки и покрытие

Тесты разделены по назначению:

- `make coverage` запускает только public API tests, properties и SQLite
  integration; порог равен 97%, отчёт находится в
  `_coverage/public/html/index.html`;
- `make coverage-all` дополнительно запускает backend и private white-box
  suites; порог равен 99%, отчёт находится в
  `_coverage/all/html/index.html`.

Последний полный прогон перед обновлением этого документа дал 97,31% через
публичный API и 99,56% всеми тестами ядра. Точные цифры следует обновлять после
изменения instrumented implementation.

`benchmark/query_bench.ml` измеряет построение и компиляцию маленького запроса,
а также shapes с 20/100 условиями `WHERE` и выражениями `ORDER BY`. На текущем
локальном прогоне маленький запрос компилировался примерно 0,001 мс, а shape со
100 условиями — примерно 0,12 мс. Эти числа не оправдывают добавление общего
LRU cache на данном этапе.

## Отличия от `first_plan.md`

### Этапность вместо полного DSL сразу

Исходный план описывает широкий jOOQ-подобный API. Реализация сначала закрыла
portable вертикальные срезы PostgreSQL/SQLite и только затем добавила DML,
подзапросы, aggregates, schema codegen, derived tables, CTE и set operations.
Window functions, JSON и arrays по-прежнему не вводятся без прикладного
сценария.

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

## План и статус работ

В списках этого раздела `[x]` означает, что возможность реализована, а `[ ]` —
что работа ещё предстоит. Условные расширения остаются незакрытыми до появления
прикладного сценария и проверки его требований.

### 1. Проверить текущий API внешним RealWorld-приложением

- [ ] Реализовать в отдельном репозитории официальный RealWorld/OpenAPI 3.1:
  users/auth, profiles/follows, articles, comments, favorites и tags. Приложение
  должно зависеть только от публичных API `Typed_sql`, execution adapter и
  `../typed-endpoint`; ручной SQL и `typed-sql.private`/`typed-sql.backend` в
  application code не допускаются.

Первый runtime должен использовать SQLite `:memory:` или временный файл.
Нужные patterns уже доступны: scoped ownership mutations, transactions,
idempotent inserts, count queries, correlated flags и batch loading tags через
`IN`. Найденные неудобства следует переносить сюда как regression tests до
стабилизации generator и выпуска PPX.

#### Приоритеты по результатам разбора `typed-realworld`

Ниже — реализованные возможности и потребности из прикладного разбора RealWorld
в порядке приоритета. Scoped mutations, transactions, полноценный UPSERT,
отдельные count queries, correlated flags и batch loading через `IN` уже есть
в DSL; их неиспользование приложением само по себе не означает пробел в
`typed-sql`.

- [x] Derived tables, CTE и set operations закрывают выбор страницы до
  последующих JOIN и позволяют выразить `FROM (SELECT ...) AS page`, `WITH page
  AS (...)` и объединение read-model ветвей без ручного SQL.

- [x] Portable `Query.multiset` собирает результат коррелированного
  SELECT, а `Projection.multiset_agg` — строки текущей aggregate-группы. Оба API
  сохраняют `Projection.map`, возвращают типизированный OCaml-список,
  нормализуют пустой результат и поддерживают рекурсивные коллекции. PostgreSQL
  и SQLite используют позиционные JSON-массивы только как внутренний transport;
  JSON не выходит в публичный тип. Aggregate-local ordering и filtering доступны
  через `Aggregate_order` и именованные аргументы `multiset_agg`.

- [ ] Низкоуровневые `array_agg`, `json_agg` и `json_group_array` остаются будущими
  dialect API для случаев, когда приложению нужен сам database JSON или native
  PostgreSQL array.

- [ ] **Типизированные связи из схемы.** Генерировать FK descriptors и удобные
   отношения вроде `Articles.author`, `Comments.article`, `Favorites.user`,
   пригодные для будущего `join_fk`. FK metadata уже сохраняется, arbitrary
   JOIN уже доступен; не хватает типизированного сокращения ручных сравнений
   колонок, включая составные ключи.

- [ ] **Дополнительные SQL-конструкции.** Добавлять по прикладной необходимости
   window functions, `DISTINCT ON`, `LATERAL`, `ILIKE` и `NULLS FIRST/LAST`.
   `COUNT(*) OVER ()` может вернуть страницу и общее количество одним запросом;
   для пустой страницы потребуется отдельное получение количества. PostgreSQL
   JSON и arrays требуют dialect API. Сценарии и границы этих расширений
   описаны в разделе «Добавлять сложные запросы по прикладной необходимости».

- [ ] **Больше типов.** Добавить корректные codecs и codegen mappings для
   decimal/numeric, enums, JSON, arrays и пользовательских PostgreSQL types.
   Неизвестные типы сейчас намеренно останавливают codegen; молчаливое
   преобразование в неточный базовый тип недопустимо.

- [ ] **Более полный schema snapshot.** Расширить IR, introspection и snapshot
   обычными, expression и partial indexes, CHECK constraints и triggers.
   Текущий snapshot сохраняет columns, PK, FK и UNIQUE, но этого недостаточно
   для полного обнаружения drift производственных индексов и ограничений.

- [ ] **PostgreSQL array parameters для batch lookup.** Добавить отдельный
   PostgreSQL-specific API для native array codec и предиката
   `column = ANY (?1)`, например `Db_type.Postgresql.array` и
   `Postgresql.Expr.equals_any`. Это не `IN ?1`: placeholder кодирует одно
   native PostgreSQL array-значение, а `ANY` применяет сравнение к его
   элементам. Запись `column IN $1` не передаёт SQL-список через один
   bind parameter. Текущий portable `IN` создаёт отдельный placeholder для
   каждого элемента (`IN ($1, $2, ...)`) и потому меняет SQL shape при
   изменении длины списка.

   API нужен для запросов с непредсказуемым числом идентификаторов, которым в
   PostgreSQL полезны одна статическая SQL shape, один bind parameter и
   переиспользуемый prepared statement:

   ```ocaml
   let ids =
     params.expr
       (Db_type.Postgresql.array Db_type.int64)
       ~get:Input.ids
   in
   Query.(
     from Users.table
     |> where (fun user ->
       Postgresql.Expr.equals_any (Users.id user) ids)
     |> select Users.projection)
   ```

   Предварительно `array` должен связывать element codec с OCaml
   `array`/`list`, а `equals_any` — требовать одинаковый тип элементов с левой
   expression. Операция несёт requirement [`Postgresql], поэтому
   `Statement.Portable` и SQLite adapter должны отвергать её до rendering.
   Нужны golden tests SQL и PostgreSQL execution tests для кодирования,
   пустого массива (`= ANY` возвращает `false`) и SQL three-valued semantics при
   `NULL`-элементах. Portable batch-loading остаётся случаем для
   `Statement.Dynamic`: SQLite не получает этот API и не должен эмулировать
   PostgreSQL array через небезопасное разворачивание SQL.

Реализованные derived tables, CTE, set operations и multiset закрывают
построение сложных paginated read models. Portable UPSERT закрывает атомарное
создание или получение tags. Миграциями `typed-realworld` продолжает управлять
dbmate: выполнение миграций остаётся отдельным слоем, вне query DSL.

### 2. Кардинальность SELECT

- [x] Различать `many`, `at_most_one` и `exactly_one` в типах запросов и
  предоставлять `limit_one`, `select_exactly_one` и проверяемые
  `expect_one`/`expect_optional`.

`Query.t` и `Result_query.t` различают `many`, `at_most_one` и `exactly_one`.
`Statement.query_many` принимает любую из этих cardinality; `query_optional` —
`at_most_one` или `exactly_one`; `query_one` — только `exactly_one`.

`Query.limit_one` рендерит `LIMIT 1` и доказывает `at_most_one`. Обычные
`Query.limit` и runtime `limit_param` сбрасывают доказательство, поэтому после
замены лимита такой запрос нельзя передать в `query_optional`.

`Query.select_exactly_one` создаёт `exactly_one` для ungrouped aggregate.
Compiler дополнительно отклоняет запрос при `HAVING`, `OFFSET`, `LIMIT 0` или
отсутствии local aggregate. `LIMIT 1` сам по себе не доказывает наличие строки.

`expect_one` и `expect_optional` сохраняют явную runtime-проверку для запросов
без статического доказательства. Adapters также проверяют фактическую
кардинальность как защиту от ошибки драйвера или будущего внутреннего кода.

Compile-fail tests проверяют, что обычный SELECT нельзя передать в
`query_optional`, запрос после `limit_one` можно, а последующий произвольный
`limit` снова запрещает это.

#### Конструкторы кардинальности

- [x] **`Query.aggregate_one` и скалярные агрегаты.** Новый
   `Query.Aggregate` — узкий builder поверх прежнего четырёхпараметрического
   `Query.t`: он даёт `FROM`, joins и `WHERE`, но не открывает grouping,
   `HAVING` или pagination. Закрытый `Aggregate_projection.t` разрешает только
   известные aggregate expressions и их комбинации. Поэтому
   `Query.aggregate_one` возвращает `Cardinality.exactly_one`, сохраняя
   совместимость остального API.

   Портативны `SUM(int)`, `SUM(float)`, `MIN` и `MAX` для типов с явным
   `Db_type.Orderable` witness; суммы возвращают `None` для пустой группы или
   набора одних `NULL`. `COUNT` и `multiset_agg` доступны как terminal
   projections. В `Postgresql.Numeric` и `Postgresql.Numeric_projection` вынесены
   точные `SUM(int64)`, `SUM(numeric)`, `MIN(numeric)` и `MAX(numeric)` с
   результатом `Decimal.t option`. Numeric columns и aggregates получают явную
   ошибку при компиляции для SQLite.

   `Query.select_exactly_one` остаётся проверяемым escape hatch для запросов,
   которые нельзя выразить через безопасный builder: compiler всё ещё проверяет
   наличие local aggregate и clauses, способных удалить единственную строку.

- [x] **`Expr.coalesce` и source-free `Query.select_one` для scalar default.**
   Scalar subquery с кардинальностью zero-or-one даёт nullable expression.
   `COALESCE` превращает отсутствие строки или SQL `NULL` в заданное значение,
   а `SELECT` без `FROM` в PostgreSQL и SQLite всегда создаёт одну строку.
   Вместе эти combinators выражают частый запрос «верни scalar либо default» с
   `Cardinality.exactly_one` без aggregate validator:

   ```ocaml
   module Expr : sig
     val coalesce
       :  ('a option, 'requirements) t
       -> default:('a, 'requirements) t
       -> ('a, 'requirements) t
   end

   module Query : sig
     val select_one
       :  ('a, 'requirements) Expr.t
       -> ( 'a
          , Result_query.select
          , Cardinality.exactly_one
          , 'requirements )
          Result_query.t
   end
   ```

   Ожидаемое использование:

   ```ocaml
   Query.select_one
     (Expr.coalesce
        (Expr.scalar_subquery candidate)
        ~default:(Expr.constant Db_type.int64 0L))
   ```

   `select_one` принимает одно expression, а не произвольную projection: его
   назначение — ровно один scalar column и одна source-free row. Это сохраняет
   простой proof и не смешивает scalar fallback с подстановкой составной
   записи. Для nullable scalar, где нужно отличать «строки нет» от «строка есть,
   значение NULL», одного `COALESCE` недостаточно — эти состояния SQL scalar
   subquery намеренно объединяет.

- [ ] **`Query.default_if_empty` только для составных строк.** Этот combinator
   нужен, когда fallback состоит из нескольких полей или когда SQL `NULL`
   внутри существующей строки не должен считаться отсутствием строки. Он
   принимает candidate с доказательством `at_most_one` и отдельный fallback с
   доказательством `exactly_one`, поэтому результат статически имеет
   `exactly_one`. Пример: запрос настроек пользователя возвращает сохранённую
   запись, если она есть, иначе одну составную запись со значениями по
   умолчанию. Наличие строки с `NULL` в одном из полей не включает fallback:

   ```ocaml
   module Query : sig
     val default_if_empty
       :  default:
            ( 'result
            , Result_query.select
            , Cardinality.exactly_one
            , 'requirements )
            Result_query.t
       -> ( 'result
          , Result_query.select
          , Cardinality.at_most_one
          , 'requirements )
          Result_query.t
       -> ( 'result
          , Result_query.select
          , Cardinality.exactly_one
          , 'requirements )
          Result_query.t
   end
   ```

   Реализация не должна полагаться на порядок ветвей `UNION ALL ... LIMIT 1`.
   Нужна семантика «добавить fallback только при `NOT EXISTS candidate`», скорее
   всего через CTE, чтобы не дублировать определение candidate в SQL.
   Как и set operations, compiler обязан проверить одинаковые число, порядок и
   database types полей обеих ветвей. Нужно также определить единый decoder:
   текущие set operations применяют decoder левой ветви к обеим ветвям, даже
   если их `Projection.map` различаются. Если текущего runtime shape check
   окажется недостаточно, в `Result_query.t` потребуется отдельный phantom
   layout.

   Этот API стоит добавлять только после реального use case для составной
   строки. Для одного поля сочетание `scalar_subquery`, `Expr.coalesce` и
   `Query.select_one` короче, яснее и обычно порождает более простой SQL.

### 3. Полностью проверить PostgreSQL и довести dialect до runtime-поддержки

- [ ] Подготовить воспроизводимую PostgreSQL test database и прогнать на ней
  integration suite через Caqti и PG'OCaml, включая encode/decode,
  transaction lifecycle и SQLSTATE classification;
- [ ] Выполнять каждый portable SQL golden case на сервере и сравнивать результат
  с SQLite, а не считать успешную компиляцию SQL проверкой поддержки;
- [ ] Проверить коррелированные multiset и derived queries, set operations,
  CTE, aggregate cardinality, bind parameters, timestamp/JSON transport,
  conflict handling и schema introspection;
- [ ] Закрыть расхождения между generated SQL и PostgreSQL runtime, явно указать
  проверенные major versions и ограничения API.

До завершения этого этапа PostgreSQL остаётся экспериментальным backend.

### 4. Расширять schema tooling по результатам реальных схем

- [ ] Реализовать типы, typed FK descriptors и расширенный snapshot из списка
  приоритетов RealWorld выше;
- [ ] При появлении прикладной потребности добавить получение snapshot из
  миграций; discovery, codegen, migrations и schema diff остаются отдельными
  слоями. Формат snapshot и offline CLI уже реализованы.

### 5. Добавлять сложные запросы по прикладной необходимости

Каждое расширение следует привязать к запросу приложения, ожидаемому результату
и нужным dialects. Кандидаты:

- [ ] `ILIKE`: поиск имени или заголовка без учёта регистра в PostgreSQL. Перед
  введением API нужно определить работу с locale и indexes. Конструкция
  `LOWER(column) LIKE LOWER(pattern)` может быть достаточной для отдельного
  portable-сценария, но её нельзя объявлять эквивалентом PostgreSQL `ILIKE`
  без проверки семантики.
- [ ] `NULLS FIRST/LAST`: явное расположение `NULL` при сортировке nullable
  columns. Нужны правила для каждого dialect и проверка, что одинаковый
  portable запрос возвращает одинаковый порядок.
- [ ] `DISTINCT ON`: одна выбранная строка на ключ, например последняя статья
  каждого автора. Это PostgreSQL extension; результат зависит от `ORDER BY`,
  поэтому API должен явно задавать критерий выбора строки.
- [ ] Window functions: ранжирование строк внутри группы, накопительные суммы и
  `COUNT(*) OVER ()` для страницы с общим числом результатов. Для пустой
  страницы общее число понадобится получать отдельно. API должен выразить
  `PARTITION BY`, порядок и границы window frame без строковых SQL-фрагментов.
- [ ] `LATERAL`: подзапрос в `FROM`, зависящий от предшествующей строки, например
  несколько последних комментариев каждой статьи. Сначала следует проверить,
  покрывает ли конкретный запрос существующий correlated `Query.multiset`.
- [ ] Native JSON и arrays: публичные database-значения для приложений, которым
  нужен именно JSON или PostgreSQL array. Позиционные JSON-массивы для
  `multiset` сейчас остаются внутренним transport. Низкоуровневые
  `array_agg`, `json_agg` и `json_group_array` потребуют отдельного API.
- [ ] Список идентификаторов в одном параметре: PostgreSQL `column = ANY($1)`
  с native array codec и постоянной SQL shape. Контракт и проверки описаны
  выше в пункте о PostgreSQL array parameters; portable `IN` по-прежнему
  раскрывает список в отдельные bind parameters.

PostgreSQL extensions (`ILIKE`, `DISTINCT ON`, JSON, arrays) должны находиться
в явно именованных namespaces. Все расширения проходят capability check до
rendering; conflict targets и `DO UPDATE` не являются исключительно
PostgreSQL-возможностями. Portable approximation с другой семантикой не
допускается.

### 6. Производительность и escape hatch

- [ ] Измерить execution overhead на SQLite и PostgreSQL отдельно от уже
  измеренного compiler overhead;
- [ ] Добавить server-side prepared cache в adapters только при подтверждённом
  выигрыше и с явным lifecycle на connection;
- [ ] Определить отдельный `Unsafe`/`Raw_sql` API с typed bind fragments, когда
  появится запрос, который нельзя выразить descriptors;
- [ ] Оптимизировать построение больших condition/order lists только по benchmark;
- [ ] Проектировать PPX после проверки ручного API внешним RealWorld-приложением.

#### Статические параметры и server-side prepare

- [x] Разделять скомпилированный template и значения input; поддерживать
  runtime `LIMIT`/`OFFSET`, `Statement.choose` и `Statement.Dynamic.Portable`.

`Statement` теперь разделяет заранее скомпилированный template и значения
текущего input. Getter каждого слота запускается при `run`; AST, validation,
lowering и rendering не повторяются. Runtime `LIMIT`/`OFFSET` поддерживаются с
проверкой неотрицательности. Конечные структурные варианты объединяются через
`Statement.choose`.

Для неограниченного набора SQL shapes реализован
`Statement.Dynamic.Portable`: callback строит AST из input, а compilation
повторяется при каждом вызове без core cache. Это явный режим с отдельной
ошибкой compilation; статический путь сохраняет прежнюю гарантию compile-once.
Перед добавлением cache нужно отдельно измерить стоимость dynamic compilation
и определить ограничение памяти и lifecycle projection closures.

Остаётся измерить пользу server-side prepared handles. Они принадлежат adapter
и конкретному connection: Caqti и PG'OCaml должны независимо управлять cache,
reconnect и eviction. Решение по core API и рассмотренные альтернативы описаны
в [ADR 0001](adr/0001-static-statement-api.md).

## Definition of done текущего релизного среза

- portable expression, aggregate, subquery, timestamp и DML API документированы
  в одном публичном `.mli`;
- derived tables, set operations и CTE имеют portable SQL snapshots и
  capability diagnostics для PostgreSQL-only вариантов;
- PostgreSQL и SQLite имеют парные SQL snapshots, а portable semantics
  исполняются на SQLite;
- mapped codec, transaction и constraint errors не выходят из adapter contract;
- PostgreSQL/SQLite schema introspection и descriptor generator реализованы;
- `make release-check`, `make coverage` и `make coverage-all` проходят;
- PostgreSQL server не требуется и не используется.

После выполнения этих пунктов дальнейшее расширение API должно опираться на
внешний RealWorld-сценарий или отдельный подтверждённый use case.
