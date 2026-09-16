# Дорожная карта

Состояние проекта на 15 сентября 2026 года. Документ сопоставляет текущую
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
двухпробельными отступами. `Compiled_query.sql`/`Compiled_command.sql`, их
`pp`-printers и execution adapters используют одно представление; отдельного
compact SQL нет. Layout не входит в `Shape.t`, поэтому форматирование не меняет
идентичность плана или порядок bind parameters.

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
- `Ptime.t` как timestamp with time zone, отдельный `Date.t` для SQL `DATE` и
  `CURRENT_TIMESTAMP`.

Aggregate validator запрещает aggregates в `WHERE`, `JOIN ON` и `GROUP BY`,
nested aggregates и non-grouped expressions. Наличие `HAVING` создаёт
aggregate context; SQLite отклоняет `HAVING` без `GROUP BY` и aggregate в
projection через capability error. Точное составное выражение из
columns, arithmetic и portable string functions можно повторить в projection и
`ORDER BY` после `GROUP BY`.

Scalar subquery возвращает `option`: отсутствие строки не может быть decoded
как значение non-null column. Встраивание требует `LIMIT 0`/`LIMIT 1` либо
local aggregate без `GROUP BY`; иначе compiler возвращает
`Scalar_subquery_may_return_many_rows`. Для nullable expression отдельный
`scalar_subquery_nullable` не создаёт вложенный `option`.

Пустой `CASE` нормализуется в `else_`, поэтому не попадает в renderer как
некорректный `CASE ELSE ... END`.

### DML

Реализованы multi-row `INSERT`, SQL `DEFAULT`, scoped `UPDATE`/`DELETE`,
`RETURNING`, `UPDATE ... FROM` и условные assignments для PATCH. Multi-row
builder проверяет пустые строки, повторные columns и одинаковый набор columns
во всех строках. `Update.set_opt` различает «не менять» и запись `NULL` для
nullable columns.

Portable UPSERT API для PostgreSQL и SQLite поддерживает global и
target-specific `DO NOTHING`, составной conflict target и `DO UPDATE` с
типизированными ссылками на existing/excluded rows. В разрабатываемой 0.2.0
`Insert.Conflict_update.(empty |> set_expr ... |> where ...)` задаёт
assignments и предикат обновления. Повторные предикаты объединяются через
`AND`; пропущенное обновление не возвращает строку в `RETURNING`.
Builder поддерживает `set_opt` и `set_expr_opt`. UPSERT совместим с
multi-row `VALUES` и `RETURNING`; пустые или повторные update assignments и
повторные target columns отклоняются compiler. SQLite не поддерживает
`DEFAULT` внутри `VALUES` и `UPDATE SET DEFAULT`, поэтому compiler возвращает
`Unsupported_operation`, не подменяя семантику.

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

Последний полный прогон перед обновлением этого документа дал 97,90% через
публичный API и 100,00% всеми тестами ядра. Точные цифры следует обновлять после
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

#### Приоритеты по результатам разбора `typed-realworld`

Ниже — потребности из прикладного разбора RealWorld в порядке приоритета.
Это будущие расширения, а не уже доступный API. Scoped mutations, transactions,
полноценный UPSERT, отдельные count queries, correlated flags и batch loading
через `IN` уже есть в DSL; их неиспользование приложением само по себе не
означает пробел в `typed-sql`.

1. **Derived tables и CTE.** Добавить `FROM (SELECT ...) AS page` и
   `WITH page AS (...)`. Для read model статьи сначала выбирать страницу с
   фильтрами, сортировкой и `LIMIT/OFFSET`, затем присоединять authors, tags и
   favorites. Так размножение строк после JOIN не меняет границы страницы.

2. **Агрегация коллекций.** Добавить aggregates вроде `array_agg`, `json_agg`
   и `json_group_array` с типизированным декодированием коллекций. Сейчас
   вложенный read model можно собирать несколькими batch-запросами; другой
   portable вариант — плоский JOIN и группировка строк в OCaml с сохранением
   корректной пагинации. JSON aggregation для PostgreSQL и SQLite должна
   иметь отдельные dialect namespaces.

3. **Типизированные связи из схемы.** Генерировать FK descriptors и удобные
   отношения вроде `Articles.author`, `Comments.article`, `Favorites.user`,
   пригодные для будущего `join_fk`. FK metadata уже сохраняется, arbitrary
   JOIN уже доступен; не хватает типизированного сокращения ручных сравнений
   колонок, включая составные ключи.

4. **Prepared queries.** Рассмотреть `('params, 'result) Prepared_query.t`
   для отделения заранее скомпилированного плана от значений конкретного
   выполнения. Для RealWorld это пока оптимизация низкого приоритета;
   реализация требует измерений. Подробности и граница с prepared statement
   cache adapter приведены в разделе «Параметры и возможный `Prepared_query`».

5. **Дополнительные SQL-конструкции.** Добавлять по прикладной необходимости
   `UNION`, `INTERSECT`, `EXCEPT`, window functions, `DISTINCT ON`, `LATERAL`,
   `ILIKE` и `NULLS FIRST/LAST`. `COUNT(*) OVER ()` может вернуть страницу и
   общее количество одним запросом; для пустой страницы потребуется отдельное
   получение количества. PostgreSQL JSON и arrays требуют dialect API.

6. **Больше типов.** Добавить корректные codecs и codegen mappings для
   decimal/numeric, enums, JSON, arrays и пользовательских PostgreSQL types.
   Неизвестные типы сейчас намеренно останавливают codegen; молчаливое
   преобразование в неточный базовый тип недопустимо.

7. **Более полный schema snapshot.** Расширить IR, introspection и snapshot
   обычными, expression и partial indexes, CHECK constraints и triggers.
   Текущий snapshot сохраняет columns, PK, FK и UNIQUE, но этого недостаточно
   для полного обнаружения drift производственных индексов и ограничений.

Первое расширение закрывает построение сложных paginated read models. Задача
атомарного создания или получения tags закрыта portable UPSERT. Миграциями
`typed-realworld` продолжает управлять dbmate:
выполнение миграций остаётся отдельным слоем, вне query DSL.

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

- реализовать типы, typed FK descriptors и расширенный snapshot из списка
  приоритетов RealWorld выше;
- при появлении прикладной потребности добавить получение snapshot из
  миграций; discovery, codegen, migrations и schema diff остаются отдельными
  слоями. Формат snapshot и offline CLI уже реализованы.

### 4. Добавлять сложные запросы по прикладной необходимости

Начать с derived tables и CTE согласно приоритетам RealWorld выше. Остальные
конструкции вводить по прикладной необходимости. PostgreSQL extensions
(`ILIKE`, `DISTINCT ON`, JSON, arrays)
должны находиться в явно именованных namespaces. Все расширения должны
проходить capability check до rendering; conflict targets и `DO UPDATE`
не являются исключительно PostgreSQL-возможностями. Portable approximation
с другой семантикой не допускается.

### 5. Производительность и escape hatch

- измерить execution overhead на SQLite и PostgreSQL отдельно от уже
  измеренного compiler overhead;
- добавить compilation cache по normalized shape только при подтверждённом
  выигрыше, не смешивая его с prepared-statement cache adapter;
- определить отдельный `Unsafe`/`Raw_sql` API с typed bind fragments, когда
  появится запрос, который нельзя выразить descriptors;
- оптимизировать построение больших condition/order lists только по benchmark;
- проектировать PPX после проверки ручного API внешним RealWorld-приложением.

#### Параметры и возможный `Prepared_query`

Сейчас bind values входят в immutable query AST, но не интерполируются в SQL.
Обычный вызов execution adapter выполняет normalization, validation, dialect
lowering и rendering, после чего передаёт значения отдельно от SQL с
placeholders. Caqti adapter также принимает заранее полученные
`Compiled_query`/`Compiled_command` и умеет отдельно профилировать compilation,
подготовку request, database round trip и decoding. `Shape.t` не содержит сами значения: он определяется
dialect, SQL template, типами параметров и типами результата. Поэтому запросы
с одинаковой структурой и разными значениями получают одинаковый shape.

Нельзя кэшировать целый `Compiled_query`: вместе с reusable SQL plan он хранит
значения конкретного вызова и текущий projection decoder, включая функции из
`Projection.map`. Безопасный compilation cache должен разделять данные так:

```text
cached plan:
  SQL template + parameter layout + codec layout + result column layout

per execution:
  current parameter values + current projection decoder
```

Прозрачный cache по shape сохраняет существующий DSL, но для cache lookup всё
равно требует построить и обойти AST, чтобы определить форму и собрать новые
значения. Он может пропустить validation, lowering и rendering, однако не
устраняет всю работу по построению запроса.

Если benchmark покажет необходимость компилировать горячий запрос ровно один
раз, предпочтителен явный `Prepared_query`. Все его входные параметры должны
образовывать один OCaml-тип; для прикладного кода это должна быть именованная
record, а не публичный heterogeneous list или вложенные tuples. Отдельный
аппликативный descriptor вида `('input, 'slots) Parameters.t` сможет связать
поля record с `Db_type` и передать callback типизированные parameter
expressions:

```ocaml
type find_people =
  { name : string
  ; min_id : int64
  }

let parameters =
  Parameters.(
    let+ name = field Db_type.text ~get:(fun input -> input.name)
    and+ min_id = field Db_type.int64 ~get:(fun input -> input.min_id) in
    name, min_id)

let find_people =
  Prepared_query.create parameters ~query:(fun (name, min_id) ->
    Query.(
      from Person.table
      |> where (fun person ->
        Person.name person =. name &&. Person.id person >=. min_id)
      |> select Person.projection))
```

Execution такого значения принимает `find_people` record, извлекает текущие
значения через getters и связывает их с заранее назначенными slots. Если вход
меняет структуру SQL, например условно добавляет `WHERE`, это другая форма и
отдельный prepared plan. Для полноценного API также понадобятся typed
parameters в `LIMIT`/`OFFSET` и аналогичный `Prepared_command` для DML.

Compilation cache остаётся частью backend-independent ядра. Prepared statement
cache принадлежит adapter и connection: Caqti и PG'OCaml должны независимо
управлять собственными backend handles. Реализовывать любой из этих cache
следует после измерений на RealWorld, поскольку текущая стоимость компиляции
маленького запроса значительно ниже обычного database round trip.

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
