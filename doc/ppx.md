# Offline SQL через PG’OCaml PPX

Экспериментальный пакет `typed-sql-pgocaml-ppx` проверяет ограниченное
подмножество PostgreSQL SELECT, INSERT, UPDATE и DELETE по snapshot схемы. Он сохраняет синтаксис
`[%pgsql ...]` и `[%pgsql.object ...]` и выполняет запрос через модуль
`PGOCaml` приложения. Компиляция не подключается к БД.

Минимальная версия PG’OCaml — 4.3.0. Она требует OCaml младше 5.0 и проверяется
с OCaml 4.14.1; для OCaml 5 используется PG’OCaml 4.4.0.

## Подключение

Создайте snapshot версии 3 после применения миграций через один из существующих
PostgreSQL-дамперов. Старые snapshot версии 2 пригодны для генерации descriptors,
но не содержат точных типов, нужных PPX. Для enum/domain и arrays нужны
вложенные native types; для чтения domain-колонок также нужен native attribute
flag nullability.

Сгенерируйте из snapshot OCaml-модуль, затем подключите его как PPX-библиотеку:

```lisp
(rule
 (target schema_ppx.ml)
 (deps schema.json)
 (action
  (with-stdout-to
   %{target}
   (run %{bin:typed-sql-codegen} --target pgocaml-ppx %{dep:schema.json}))))

(library
 (name app_schema_ppx)
 (modules schema_ppx)
 (kind ppx_rewriter)
 (libraries base typed-sql-schema typed-sql-pgocaml-ppx))

(library
 (name app)
 (libraries base pgocaml)
 (preprocess (pps app_schema_ppx)))
```

Здесь `schema.json` — вход генерации, а Dune связывает сгенерированную
библиотеку с `typed-sql-pgocaml-ppx` при подготовке PPX-драйвера. Запросы
проверяются по зарегистрированной схеме; при подключении нескольких schema
библиотек PPX сообщает об ошибке. Пакет `pgocaml_ppx` одновременно подключать
нельзя: оба пакета регистрируют одинаковые extension names.

Код приложения зависит от `pgocaml`. Для выполнения не нужны schema dump
packages или файл snapshot: сгенерированный модуль используется только при
компиляции. Runtime-соединение и его `search_path` должны соответствовать схеме
снимка; неквалифицированные таблицы PPX разрешает в `public`. Для других схем
используйте явное `schema.table`.

## Совместное выполнение с query builder

Quotations и query builder могут использовать одно Lwt-соединение и одну
транзакцию. Подключите `typed-sql-pgocaml-lwt`, выберите общий модуль `PGOCaml`
и создайте `Typed_sql_pgocaml_lwt.Make (PGOCaml)`. В callback его `transaction`
передавайте один `conn` как в `run`, так и в quotations. `Ok` фиксирует все
изменения; `Error` или исключение quotation откатывает их. Дополнительный
BEGIN внутри quotations не нужен.

[Integration test](../ppx/test/mixed_transaction_postgresql_test.ml) проверяет
оба направления чтения/записи, object → record converter, видимость из второго
соединения и rollback при unique violation из PPX. Он включён в
`make test-postgres`; для обычной offline-сборки БД не нужна.

## Запросы

Для таблицы `public.people` с `id integer NOT NULL`, `name text NOT NULL` и
`note varchar NULL`:

```ocaml
open! Base

let names conn id : string list =
  [%pgsql conn "SELECT name FROM people WHERE id = $id ORDER BY id"]
;;

let rows conn id =
  [%pgsql.object conn
    {sql|SELECT p.id AS identifier, p.name, p.note
         FROM public.people AS p
         WHERE p.id = $id
         ORDER BY p.id DESC|sql}]
;;
```

`id` имеет тип `int32`, как в PG’OCaml. Object-результат содержит методы
`identifier : int32`, `name : string` и `note : string option`.

Обычные OCaml-строки, `{|...|}` и `{sql|...|sql}` поддерживаются обоими
extensions. Это включает изменение из
[upstream PR #80](https://github.com/darioteixeira/pgocaml/pull/80).

```ocaml
open! Base

let find conn note =
  [%pgsql conn
    {|SELECT id, name FROM people
      WHERE note = $?note AND id = ${Int32.succ 0l}|}]
;;

let optional_ids conn =
  [%pgsql conn "nullable-results" "SELECT id FROM people"]
;;
```

`$name` и `${expression}` принимают значение типа, выведенного из SQL-контекста.
Для прямого сравнения с колонкой это обычно её тип; фиксированный IN выбирает
общий тип operands. Например, smallint-колонка вместе с integer literal в IN
даёт `int32` для параметра, как в PostgreSQL.
`$?name` и `$?{expression}` принимают `option` того же типа и кодируют `None`
как SQL NULL. Равенство с NULL сохраняет SQL-семантику: это не условие
`IS NULL`. Каждое вхождение подстановки получает отдельный `$n`; значения
отправляются отдельно от SQL.

Одна выбранная колонка возвращается как список значений; несколько — как
список tuples. Object-вариант использует имена колонок или projection aliases.
Имена должны быть допустимыми OCaml method names и не повторяться. `SELECT *`
и `alias.*` используют порядок колонок snapshot. Изменение порядка или состава
колонок в БД требует обновления snapshot и перекомпиляции приложения.

## Только статическая форма SQL

SQL-текст, число placeholders и тип результата фиксируются при компиляции.
При выполнении меняются только значения bind parameters. Optional значение
`None` передаётся как NULL и не удаляет условие из запроса. Значения LIMIT/OFFSET
могут менять число возвращённых строк, но сохраняют ту же форму SQL.

Фиксированный список в IN поддерживается:

```ocaml
open! Base

let find_two conn first second =
  [%pgsql conn "SELECT id FROM people WHERE id IN ($first, $second)"]
;;

let find_many conn (ids : int32 option list) =
  [%pgsql conn "SELECT id FROM people WHERE id = ANY($ids) ORDER BY id"]
;;

let page conn (limit : int64 option) (offset : int64) =
  [%pgsql conn "SELECT id FROM people ORDER BY id LIMIT $?limit OFFSET $offset"]
;;
```

Native array — один bind parameter. Длина array, включая пустой array, не
меняет SQL и не создаёт новый prepared statement. Элементы имеют тип option:
`[Some 1l; None]` отличается от SQL NULL всего array, который задаётся
optional-подстановкой `$?ids`. Для пустого array ANY не находит совпадений,
а ALL сохраняет PostgreSQL-семантику пустого множества.

List-подстановки `$@name`, `$@{expression}`, `$@?name` и `$@?{expression}`
отложены в roadmap и дают compile-time diagnostic. В оригинальном pgocaml_ppx
они разворачиваются в переменное число placeholders при выполнении и меняют
форму SQL. Это отдельный механизм от native array, хотя оба используют OCaml
lists. Строки и комментарии с текстом `$@name` остаются обычным SQL-текстом.

У каждого quotation подготовленный SQL и имя prepared statement вычисляются
PPX заранее. Runtime не собирает SQL из пользовательских значений.

## WHERE и pagination

Поддержаны NOT, AND, OR и скобки с precedence PostgreSQL; `=`, `<>`, `!=`, `<`,
`<=`, `>`, `>=`; IS NULL/IS NOT NULL; LIKE/ILIKE и отрицательные формы с
необязательным ESCAPE; BETWEEN/NOT BETWEEN; фиксированный IN/NOT IN и comparison
ANY/ALL с array-параметром или array-колонкой. Boolean-колонка допустима как
отдельное условие. WHERE одинаково проверяется у SELECT, UPDATE, DELETE и
ON CONFLICT DO UPDATE.

Operands — прямые колонки, scalar/optional подстановки, обычные SQL strings
с удвоением кавычек, signed numbers с decimal/exponent, NULL/TRUE/FALSE.
Подстановки внутри SQL literals не распознаются. Обычные строки предполагают
`standard_conforming_strings=on`. Поддержаны `E'...'`/`e'...'` с backslash,
octal/hex и Unicode escapes, а также `$$...$$` и `$tag$...$tag$` без escaping.
Теги чувствительны к регистру. Строки, разделённые whitespace с переводом
строки, объединяются по правилам PostgreSQL; при продолжении E-string
сохраняется её escape mode. Незакрытые literals и неправильные Unicode escapes
дают diagnostic с byte offset. Исходный SQL при выполнении не переписывается,
кроме настоящих bind-подстановок. SQL literals доступны в predicates и pagination, а grammar
projection/RETURNING и присваиваний DML остаётся прежней. Проверку значений
literals и ограничений данных завершает сервер.

Поддержаны comparisons одинаковых native types и встроенные numeric/text
coercions. Разные enum-типы не смешиваются. Domain раскрывается до base для
выбора операторов и serializer; неизвестный оператор или неподдержанная
coercion возвращает diagnostic. Изолированный `$value IS NULL` или сравнение
двух подстановок без SQL type context отклоняются как неоднозначные.

LIMIT/OFFSET доступны только SELECT: integer literals, scalar/optional
параметры типа `int64` и NULL; LIMIT также принимает ALL. Допустимы оба порядка
clauses и отдельный OFFSET; повторный clause отклоняется. NULL в LIMIT снимает
ограничение, NULL в OFFSET действует как ноль. Отрицательное значение
проверяет PostgreSQL при выполнении.

## Enum, domain и arrays

Enum сохраняет представление PG’OCaml `string`; допустимые labels и их порядок
содержатся в snapshot. Domain рекурсивно использует представление base:
например, domain над int2 имеет тип `int`, а над int4 — `int32`. Ограничения
самого domain проверяет сервер; PPX не подменяет их генератором DSL codecs.

Одномерные native arrays встроенных scalar-типов, enum и domain представлены
как `'a option list`. Поддержаны array-of-domain и domain-over-array. Nullable
array возвращает внешний option; `nullable-results` добавляет этот внешний
option и к NOT NULL array. NULL-элемент, строка `"NULL"`, пустая строка, кавычки
и обратные слеши кодируются отдельно и не смешиваются.

Array-codecs используют небольшую библиотеку `typed-sql-pgocaml-ppx.runtime`,
автоматически подключаемую Dune через `ppx_runtime_libraries`. При ручном запуске
PPX и компилятора эту библиотеку нужно добавить к runtime-зависимостям.
Она обрабатывает wire format arrays; scalar conversion продолжает выполняться
через модуль PGOCaml приложения. Поддержка arrays всех имеющихся scalar
codecs, включая enum/domain combinations, расширяет upstream 4.4.0.

Многомерные arrays и значения с явными нестандартными bounds при чтении дают
`PGOCaml.Error`: OCaml list здесь описывает одну dimension без индексов.
Серверный timezone может менять текст timestamptz; array elements используют
тот же scalar conversion PGOCaml, что и отдельная колонка.

Nullability прямых domain-колонок определяется по `pg_attribute.attnotnull`,
как в upstream, а не по domain NOT NULL. Поэтому NOT NULL constraint на domain
при nullable attribute всё равно даёт внешний option в результате PPX.
Portable codegen сохраняет собственные metadata nullability.

## Соединения таблиц

SELECT поддерживает `JOIN ... ON` и `INNER JOIN ... ON`, цепочки соединений и
self-JOIN с различными aliases. Например, если snapshot содержит таблицы
`people` и `memberships` с колонками `person_id`, `active` и `label`:

```ocaml
open! Base

let find conn ~active ~min_id =
  [%pgsql.object conn
    {|SELECT p.id AS identifier, p.name, m.label
      FROM people AS p
      INNER JOIN memberships AS m
        ON p.id = m.person_id AND m.active = $active
      WHERE p.id >= $min_id
      ORDER BY p.id|}]
;;
```

В ON доступны те же predicates, что и в WHERE, но только таблицы слева и
текущий присоединяемый источник; последующие JOIN ещё не видны. Параметры
из ON, WHERE и LIMIT/OFFSET нумеруются в порядке появления в SQL. Исходный
SQL сохраняется, изменяются только OCaml-подстановки.

Неквалифицированная колонка должна однозначно разрешаться среди видимых
источников. Alias скрывает исходное имя таблицы, в том числе schema-qualified
форму. `*` возвращает колонки в порядке FROM/JOIN, внутри таблицы — в порядке
snapshot; `alias.*` выбирает один источник. Если несколько колонок имеют
одинаковое имя, для object output нужны разные projection aliases.

INNER JOIN сохраняет nullability исходных колонок, даже если ON или WHERE
отсекает NULL. `nullable-results` делает optional все поля, как и в обычном
SELECT. Object methods и существующие object → record converters продолжают
работать с теми же PG’OCaml-типами.

Поддержаны также LEFT/RIGHT/FULL с необязательным OUTER, CROSS, USING,
NATURAL, запятые в FROM и группировка источников скобками. JOIN связывает
источники сильнее запятой; ON не видит таблицы из другой ветви списка FROM.
Alias группы скрывает имена её отдельных источников.

USING возвращает объединённые колонки в порядке списка USING, затем остальные
колонки слева и справа. NATURAL использует общие имена в порядке левого
источника. Qualified references по-прежнему обращаются к исходным колонкам.

Эвристика upstream для прямых колонок сохраняется и в outer JOIN: NOT NULL
колонка остаётся non-option, даже на стороне, где JOIN может создать NULL.
Для таких строк без `nullable-results` сохраняется прежняя runtime-ошибка.
Объединённая колонка FULL USING не имеет прямого column origin и получает
`option`.

Поддержан LATERAL для derived SELECT в FROM, CROSS/INNER/LEFT JOIN LATERAL.
Он видит предшествующие источники, но не последующие; RIGHT/FULL JOIN не
допускают LATERAL-ссылку на свою левую сторону. Некоррелированный LATERAL
в этих JOIN допустим. В FROM также поддерживаются `unnest` и `generate_series`:
функции могут ссылаться на предшествующие источники без ключевого слова LATERAL.

```ocaml
let expand conn (ids : int32 option list) =
  [%pgsql.object conn
    "SELECT u.id, u.n FROM unnest($ids::integer[]) WITH ORDINALITY AS u(id,n) ORDER BY u.n"]
;;
```

`unnest` принимает один массив или несколько массивов разных типов; короткие
массивы дополняются NULL. Форма с несколькими аргументами использует
неквалифицированное имя `unnest`. `WITH ORDINALITY` добавляет колонку `int8`
с именем `ordinality`, если alias колонки не задан. Значения функций и ordinality
имеют вычисляемую upstream-nullability: например, методы примера —
`id : int32 option` и `n : int64 option`. Доступны tuples, wildcards и aliases.

`generate_series` поддерживает integer/bigint/numeric с двумя или тремя
аргументами, а также timestamp/timestamptz с обязательным interval-шагом.
Числовые overloads учитывают расширение integer → bigint → numeric. Для
полностью неизвестных аргументов и неоднозначного smallint overload нужен
явный SQL-cast. Нулевой шаг остаётся
ошибкой сервера; NULL и несовпадающее со знаком шага направление дают пустую
серию. Четвёртый timezone-аргумент, SRF в SELECT list, ROWS FROM и остальные
пользовательские/table functions пока отклоняются. Table functions доступны
также в поддержанных UPDATE FROM и DELETE USING.

## Выражения, агрегаты и вложенные запросы

SELECT и RETURNING принимают literals, параметры, numeric `+ - * / %`,
unary `+`/`-`, текстовую конкатенацию, CAST/`::`, simple/searched CASE,
COALESCE и NULLIF. Поддержан SELECT без FROM. Параметры остаются bind values,
в том числе внутри expressions, casts и CASE.

Типы casts берутся из поддержанных builtin-типов и native metadata snapshot
для enum/domain и одномерных arrays. Optional поле snapshot v3
`postgresql_type_modifier` хранит точный `pg_attribute.atttypmod`. Поддержаны
modifiers varchar/bpchar, numeric, time/timestamp/timestamptz и interval,
включая `INTERVAL DAY TO SECOND(p)`. Совпадение типа и typmod сохраняет column
origin; изменение typmod даёт вычисляемый результат с `option`, как upstream.
Например, для NOT NULL `varchar(10)` cast `::varchar(10)` возвращает `string`,
а `::varchar(20)` и `::varchar` — `string option`.
Старые v3 snapshots читаются, но неоднозначный same-type cast при отсутствии
metadata требует обновить snapshot. Преобразование в другой поддержанный тип
и casts literals/параметров доступны без этих metadata.

GROUP BY и HAVING поддерживают expressions, output names и позиции; ORDER BY
также принимает expressions, aliases, позиции и NULLS FIRST/LAST. Доступны
`count`, `sum`, `avg`, `min`, `max`, `bool_and`, `bool_or`, `string_agg` и
одномерный `array_agg` для известных overloads, с DISTINCT, FILTER и
aggregate-local ORDER BY. Негруппированные ссылки и nested aggregates
отклоняются. GROUPING SETS/ROLLUP/CUBE пока не поддержаны.

Если GROUP BY содержит весь non-deferrable primary key экземпляра базовой
таблицы, остальные его колонки разрешены в SELECT, wildcard, HAVING, ORDER BY
и оконных выражениях. Self-JOIN проверяет каждый источник отдельно. UNIQUE,
неполный или deferrable PK и ключи через CTE/derived tables не дают этого права.
Для доказательства используется optional table metadata snapshot v3
`postgresql_primary_key_deferrable: false`. Старый snapshot читается, но для
такого сокращённого GROUP BY без metadata нужно обновить снимок.

Вычисляемое поле без column origin получает `option` по эвристике upstream,
даже если PostgreSQL всегда возвращает значение: например, `count(*)`
имеет результат `int64 option list`. `sum(integer)` использует `int64`,
`avg(integer)` — `string` для numeric, с внешним option в обоих случаях.
Нужные object methods по-прежнему задаются projection aliases; существующий
converter object → record можно использовать для совпадающих типов методов.

Поддержаны UNION/INTERSECT/EXCEPT с ALL/DISTINCT и скобками, обычный SELECT
DISTINCT, derived tables с aliases, scalar subqueries, EXISTS/NOT EXISTS,
IN/NOT IN и ANY/ALL с SELECT. Scalar/predicate subqueries могут обращаться к
внешним источникам; их имена и ссылки проверяются с учётом shadowing.
Scalar subquery должен возвращать одну колонку; превышение одной строки
обрабатывает PostgreSQL. Агрегаты, принадлежащие внешнему уровню запроса,
пока отклоняются.

## Оконные и скалярные функции

Поддержаны `row_number`, `rank`, `dense_rank`, `percent_rank`, `cume_dist`,
`ntile`, `lag`, `lead`, `first_value`, `last_value`, `nth_value`, а также
перечисленные aggregates с `OVER`. Доступны inline specifications, именованные
`WINDOW` definitions и их наследование, PARTITION BY, ORDER BY и frames
ROWS/RANGE/GROUPS с EXCLUDE. RANGE offsets проверяются для известных numeric
и temporal overloads; GROUPS требует ORDER BY. Frame offsets не ссылаются
на колонки; отрицательные и NULL-значения проверяет PostgreSQL при выполнении.

Window expressions разрешены в SELECT и ORDER BY, но не в WHERE, HAVING,
GROUP BY, JOIN ON, DML SET/RETURNING или внутри другого окна/агрегата.
`sum(count(*)) OVER (...)` допустим при корректной группировке. DISTINCT
и aggregate-local ORDER BY с OVER отклоняются; FILTER доступен для оконных
агрегатов. Полиморфный аргумент без SQL type context требует явного cast.
`row_number()` возвращает `int64 option`, как и остальные вычисляемые outputs.

```ocaml
open! Base

let page_positions conn preceding =
  [%pgsql.object conn
    {|SELECT id, row_number() OVER w AS position,
             sum(id) OVER (w ROWS $preceding PRECEDING) AS running
      FROM people WINDOW w AS (ORDER BY id) ORDER BY id|}]
;;
```

Из скалярных функций поддержаны `lower`/`upper`, `length`, `char_length` /
`character_length`, `octet_length`, `trim` и `btrim`/`ltrim`/`rtrim`,
позиционные `substring`/`substr`, `replace`, `concat`, `abs` и `round`.
Типы параметров соответствуют выбранной PostgreSQL-перегрузке: например,
`round(integer)` даёт `float option`, а `round(numeric, integer)` — `string option`.
У позиционного substring числовой контекст должен выбирать overload,
например `substring(name FROM 1 FOR $count)` или `substring(name, $start::integer)`.
Regex-overloads substring и неизвестные пользовательские функции отклоняются.

Доступны `IS DISTINCT FROM` / `IS NOT DISTINCT FROM` и JSON/JSONB extraction
`->`, `->>`, `#>`, `#>>`. Ключ имеет тип text или integer; path — `text[]`.
`->`/`#>` сохраняют JSON-тип, `->>`/`#>>` возвращают text; OCaml-представление
обоих — `string option`. Новые выражения не меняют статическую форму SQL.

`cardinality(array)` возвращает int4 (0 для пустого массива),
`array_length(array, dimension)` — int4 или NULL для пустого массива/отсутствующей
размерности. `array_to_string(array, delimiter [, null_string])` возвращает text:
NULL-элементы пропускаются, если замена не задана или равна SQL NULL; `''` также
допустима как строка замены. Все три результата имеют внешний option по
upstream-эвристике. Тип массива должен быть известен из колонки или SQL-cast;
dimension имеет тип int32, delimiter/null_string — string с поддержкой `$?`.

## WITH и recursive CTE

WITH поддерживает несколько зависимых и вложенных CTE, aliases колонок,
MATERIALIZED/NOT MATERIALIZED и использование перед SELECT или DML.
Recursive SELECT имеет форму `anchor UNION [ALL] recursive_term`: типы
задаёт anchor, recursive term должен вернуть те же типы. Поддерживается одна
self-reference в FROM/JOIN recursive term; mutual recursion, aggregate term,
SEARCH/CYCLE и ссылки на nullable стороне outer JOIN отклоняются.

В верхнеуровневом WITH доступны INSERT/UPDATE/DELETE, в том числе без
RETURNING. Только RETURNING образует relation для чтения; CTE без результата
всё равно выполняет побочный эффект. Поддержан INSERT SELECT. Результат
quotation определяется основным statement: `unit` без RETURNING или rows
для SELECT/RETURNING. Сам statement передаётся PostgreSQL целиком, поэтому
порядок и выполнение побочных эффектов не имитируются на стороне OCaml.
Вложенный data-modifying WITH и recursive DML self-reference запрещены.

## Изменение данных

```ocaml
open! Base

let insert conn id name note : unit =
  [%pgsql conn
    {|INSERT INTO people (id, name, note)
      VALUES ($id, $name, $?note)|}]
;;

let rename conn id name =
  [%pgsql.object conn
    {|UPDATE people AS p SET name = $name
      WHERE p.id = $id
      RETURNING p.id AS identifier, p.name, p.note|}]
;;

let delete conn id : int32 list =
  [%pgsql conn "DELETE FROM people WHERE id = $id RETURNING id"]
;;
```

UPDATE FROM и DELETE USING принимают таблицы, joins, derived sources и CTE.
Присваивания изменяют только target; WHERE и RETURNING могут читать остальные
источники. Неквалифицированная колонка должна разрешаться однозначно.
Target недоступен внутри собственного FROM/USING relation, включая LATERAL;
для self-JOIN используйте отдельный alias. Если source даёт несколько
совпадений для одной target-строки, выбор строки остаётся поведением PostgreSQL.

Без RETURNING `[%pgsql ...]` возвращает `unit` в monad модуля PGOCaml.
С RETURNING действуют те же правила scalar/tuple/object results и NULL, что
у SELECT. `[%pgsql.object ...]` требует RETURNING. UPDATE и DELETE могут
не содержать WHERE: тогда PostgreSQL изменяет все строки таблицы.

INSERT требует явного списка колонок для VALUES. Поддерживаются несколько
строк VALUES, DEFAULT в отдельных позициях и отдельная форма DEFAULT VALUES.
UPDATE поддерживает несколько присваиваний выражений или DEFAULT.
Пропущенные колонки, DEFAULT, identity/generated rules и ограничения данных
обрабатываются PostgreSQL при выполнении. `None` остаётся SQL NULL, в том
числе при записи в NOT NULL колонку; ошибку возвращает драйвер.

Для таблицы `people` с primary key на `id`:

```ocaml
open! Base

let save conn id name note =
  [%pgsql conn
    {|INSERT INTO people AS p (id, name, note)
      VALUES ($id, $name, $?note)
      ON CONFLICT (id) DO UPDATE
      SET name = EXCLUDED.name, note = EXCLUDED.note
      WHERE p.id = $id
      RETURNING p.id, p.name, p.note|}]
;;

let create_defaults conn =
  [%pgsql conn "INSERT INTO people DEFAULT VALUES RETURNING id"]
;;
```

ON CONFLICT принимает список колонок полного primary или unique key из
snapshot; порядок колонок ключа несущественен. DO NOTHING допускается и без
conflict target. DO UPDATE требует target и разрешает присваивать подстановки,
DEFAULT или EXCLUDED.column. Присваивание EXCLUDED требует одинаковых точных
native types; implicit casts пока отклоняются. WHERE в DO UPDATE поддерживает
`column = parameter`, AND и скобки, включая ссылки на EXCLUDED слева.
EXCLUDED недоступен в RETURNING или обычном WHERE; target с именем `excluded`
для DO UPDATE требует другого alias.

Snapshot не описывает deferrability и все правила выбора arbiter: успешная
offline-проверка ключа не гарантирует его пригодность для ON CONFLICT на
сервере. DO NOTHING или ложный WHERE в DO UPDATE могут дать пустой RETURNING.
Порядок строк сохраняется относительно ответа драйвера; сортировка RETURNING
не обещается. INSERT alias задаётся только через AS; UPDATE/DELETE допускают
AS и bare alias. Колонки слева в INSERT/SET и conflict target не квалифицируются.

## Поддержанное подмножество

| Возможность | Состояние |
| --- | --- |
| Одна таблица в FROM, `schema.table`, table alias с `AS` или без него | Поддерживается |
| INNER/LEFT/RIGHT/FULL/CROSS JOIN, USING/NATURAL, скобки и запятые в FROM | Поддерживается |
| Прямые колонки, qualified references, `*`, `alias.*`, projection alias через `AS` | Поддерживается |
| WHERE с boolean predicates, comparisons, IS NULL, LIKE/BETWEEN, fixed IN и ANY/ALL | Поддерживается |
| ORDER BY исходным колонкам, ASC/DESC; LIMIT/OFFSET | Поддерживается |
| SQL comments, quoted identifiers, один завершающий `;` | Поддерживается |
| Scalar/optional подстановки и OCaml expressions | Поддерживается |
| `nullable-results` | Поддерживается |
| Другие flags, включая `execute`, `show`, параметры подключения | Явный diagnostic |
| Custom converters, включая `PGCUSTOM_CONVERTERS_CONFIG` | Явный diagnostic |
| INSERT с явными колонками, несколькими VALUES, DEFAULT/DEFAULT VALUES | Поддерживается |
| UPDATE SET expressions/DEFAULT, DELETE, необязательный WHERE | Поддерживается |
| RETURNING expressions, aliases и wildcard | Поддерживается |
| ON CONFLICT по колонкам ключа, DO NOTHING, DO UPDATE с параметрами/DEFAULT/EXCLUDED | Поддерживается |
| INSERT SELECT, scalar/EXISTS/IN/ANY/ALL subqueries и derived tables | Поддерживается |
| SELECT DISTINCT, GROUP BY/HAVING, перечисленные aggregates | Поддерживается |
| UNION/INTERSECT/EXCEPT, ALL/DISTINCT | Поддерживается |
| SELECT и DML CTE, recursive SELECT установленной формы | Поддерживается |
| CASE, COALESCE/NULLIF, numeric expressions, casts известных типов | Поддерживается с описанными ограничениями |
| UPDATE FROM, DELETE USING, source columns в RETURNING | Поддерживается |
| ON CONSTRAINT, partial-index predicates | Явный diagnostic |
| LATERAL derived SELECT, перечисленные window functions и frames | Поддерживается |
| unnest/generate_series в FROM, LATERAL и WITH ORDINALITY | Поддерживается |
| GROUP BY по полному non-deferrable PK базовой таблицы | Поддерживается с metadata v3 |
| cardinality, array_length, array_to_string | Поддерживается |
| GROUPING SETS, SEARCH/CYCLE, MERGE, остальные table functions и SRF в SELECT | Явный diagnostic |
| E-strings, dollar quoting, перечисленные scalar functions и JSON operators | Поддерживается |
| Прочие функции/операторы | Явный diagnostic |
| Enum/domain и одномерные native arrays поддержанных scalar-типов | Поддерживается с nested metadata |
| List-подстановки и прочие native types | Явный diagnostic |

Поддерживаются встроенные PostgreSQL-типы `bool`, `int2`, `int4`, `int8`,
`float4`, `float8`, `text`, `varchar`, `bpchar`, `bytea`, `numeric`, `date`,
`time`, `timestamp`, `timestamptz`, `interval`, `json`, `jsonb` и `uuid`.
Используются представления PG’OCaml: например, `int4` — `int32`, `numeric` и
JSON — `string`, временные значения — типы CalendarLib. `json` можно читать и записывать,
но PostgreSQL не имеет для него операторов `=` и сортировки; такие WHERE и
ORDER BY PPX отклоняет.

Nullable колонка возвращает `option`. Flag `nullable-results` делает optional
все возвращаемые поля. NULL в объявленной non-null колонке и несовпадение числа
полей фактической строки сохраняют runtime-ошибки совместимого контракта.
Другие ошибки PostgreSQL остаются исключениями драйвера; `Result.t` adapter
API здесь не вводится.

Поддерживаются только выбранные output и parameter codecs. Таблица может
содержать неподдержанные колонки, если запрос не возвращает их и не использует
как параметры или EXCLUDED-значения. DEFAULT не требует codec колонки. Metadata или SQL вне подмножества не включают online fallback.

Prepared statements кэшируются в `PGOCaml.private_data` в прежнем формате
`PGOCaml.pa_pg_data`; пользовательские значения не входят в ключ. Соединение
с таким PPX резервирует private data для этого кэша. После изменения схемы
обновите snapshot и создайте новые runtime-соединения.

## Почему поддержка SQL расширяется по группам

При выполнении PPX отправляет исходный SQL, заменяя только OCaml-подстановки
на `$1`, `$2` и далее. Ограничения относятся к offline-компиляции: нужно заранее
определить OCaml-типы параметров и результатов. Оригинальный
[pgocaml_ppx](https://github.com/darioteixeira/pgocaml/blob/v4.4.0/ppx/ppx_pgsql.ml)
получает их от PostgreSQL через prepare/describe_statement; наш PPX разбирает
SQL и выводит их по snapshot самостоятельно.

Snapshot таблиц не содержит всей информации и правил, необходимых для
произвольных SQL expressions, перегруженных функций, операторов и casts.
Полная совместимость остаётся целью: parser и вывод типов будут расширяться
проверяемыми группами. DML и обычный upsert добавлены одной такой группой,
поскольку их типы можно вывести из имеющихся metadata колонок. Последующие
группы SQL проверяются по тем же правилам: типы, имена и nullability сравниваются
с upstream, а побочные эффекты и результаты — выполнением в PostgreSQL. Неподдержанная
конструкция возвращает diagnostic, без обращения к БД при компиляции.

Дальнейшие шаги и выполненные части записаны в
[дорожной карте PPX](ppx_roadmap.md).

Проверки запускаются через `make build`, `make test`, `make fmt` и
`make test-postgres`. Для отдельного сравнения с standalone driver upstream
4.4.0 используется `TYPED_SQL_UPSTREAM_PPX=/path/to/driver.exe make test-postgres`:
одни fixtures проверяют OCaml-типы и результаты обоих PPX. Обычные offline
проверки и компиляция приложения этого driver и доступной БД не требуют.

Tagged dollar strings и текст, похожий на подстановки внутри literals,
проверяются напрямую на PostgreSQL: regexp-подстановки upstream 4.4.0 не
распознают эти границы. Остальные новые группы дополнительно проверяются
общей fixture `compatibility_postgresql_test.ml` с upstream и offline PPX.

## Проверяемый контракт

Differential runner раскрывает каждый общий исходник двумя PPX, компилирует
оба результата и сравнивает их вывод после выполнения в PostgreSQL. Offline
driver запускается с недоступным `PGHOST`; только upstream-компиляция и
выполнение используют тестовую БД. Аннотации OCaml-типов и assertions в общих
fixtures проверяются для обоих вариантов.

| Общая fixture | Что сравнивается |
| --- | --- |
| [upstream_contract.ml](../ppx/test/upstream_contract.ml) | Predicates, LIMIT/OFFSET, фиксированный IN, domain-колонки, arrays и ANY |
| [join_postgresql_test.ml](../ppx/test/join_postgresql_test.ml) | JOIN, порядок полей, aliases, tuples/objects, optional fields |
| [rich_postgresql_test.ml](../ppx/test/rich_postgresql_test.ml) | Outer JOIN, expressions/casts, aggregates, set operations, подзапросы и CTE, DML-побочные эффекты |
| [compatibility_postgresql_test.ml](../ppx/test/compatibility_postgresql_test.ml) | Typmod/nullability, LATERAL, windows/frames, scalar functions, JSON operators, UPDATE FROM/DELETE USING |
| [srf_postgresql_test.ml](../ppx/test/srf_postgresql_test.ml) | SRF, ordinality, функции массивов, GROUP BY по PK и DML с table functions |
| [runtime_contract_postgresql_test.ml](../ppx/test/runtime_contract_postgresql_test.ml) | Граничные значения codecs, NULL, SQLSTATE, rollback, savepoints, изоляция и восстановление выполнения после ошибок |

Runtime fixture проверяет минимальные/максимальные integer-значения, float4
на границах нормального диапазона, большие/малые float8, NaN и infinities,
пустые строки, UTF-8, кавычки и текст SQL внутри bind parameter. Bytea проходит
через все 256 значений байта в форматах `hex` и `escape`. SQL NULL, пустой
array, NULL-элемент и строка `"NULL"` проверяются раздельно. Для date/time и
timestamp проверяются обычные значения и границы суток/календаря, представимые
codecs PG’OCaml; это не обещает поддержки всего диапазона PostgreSQL.

Ошибки сравниваются по SQLSTATE и стабильным структурированным полям сервера,
включая имена таблицы, колонки и constraint. Fixtures ожидают `22003`, `22P02`,
`22021`, `2201W`, `2201X`, `23502`, `23505` и `25P02`. После ошибки повторно
выполняется тот же запрос с другими параметрами; после rollback соединение
используется для новой транзакции. Второе соединение проверяет видимость
только зафиксированных изменений.
NUL в text отклоняется самим драйвером как `PGOCaml.Error` до отправки SQL;
это поведение сравнивается отдельно от серверного SQLSTATE `22021` для
некорректного UTF-8.

Матрица фиксирует текущее покрытие, а не полное соответствие PostgreSQL.
Все native array codecs дополнительно проверяются offline и прямыми
PostgreSQL-тестами; общая runtime fixture сравнивает text/int4 arrays.
Upstream может требовать custom converter для enum/domain-typed bind;
общее сравнение enum labels и вложенных domain-casts использует встроенные
типы на входе и выходе SQL. Прямая enum-сериализация, остальные array codecs
и неподдержанные SQL-возможности требуют дальнейшего differential-покрытия.
