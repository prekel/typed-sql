# Offline SQL через PG’OCaml PPX

Экспериментальный пакет `typed-sql-pgocaml-ppx` проверяет ограниченное
подмножество PostgreSQL SELECT, INSERT, UPDATE и DELETE по snapshot схемы. Он сохраняет синтаксис
`[%pgsql ...]` и `[%pgsql.object ...]` и выполняет запрос через модуль
`PGOCaml` приложения. Компиляция не подключается к БД.

## Подключение

Создайте snapshot после применения миграций через один из существующих
PostgreSQL-дамперов. Для PPX необходимы точные типы колонок из snapshot
версии 3. Старые snapshot версии 2 остаются пригодны для codegen descriptors,
но не содержат необходимых PPX metadata. Для enum/domain и arrays нужен
обновлённый snapshot v3 с вложенными native types; для чтения domain-колонок
также нужен native attribute flag nullability.

В примере ниже библиотека находится в `app/`, а snapshot — в
`app/schema.json`. Относительный путь сначала разрешается от каталога
исходного OCaml-файла, затем от текущего каталога процесса PPX. Если оба файла
доступны, приоритет имеет файл рядом с исходником. Абсолютный путь используется
напрямую. Это правило соответствует
[ppx_blob начиная с 0.8.0](https://github.com/johnwhitington/ppx_blob/blob/0.8.0/src/ppx_blob.ml)
и работает в Dune sandbox и Merlin/ocamllsp. `preprocessor_deps` задаётся
относительно каталога stanza.

```lisp
(library
 (name app)
 (libraries base pgocaml)
 (preprocessor_deps schema.json)
 (preprocess
  (pps typed-sql-pgocaml-ppx -- --typed-sql-schema schema.json)))
```

Flags PPX передаются через `--` по
[правилам Dune](https://dune.readthedocs.io/en/stable/reference/preprocessing-spec.html#arguments-to-ppx-rewriters).
`preprocessor_deps` делает snapshot зависимостью preprocessing и обеспечивает
пересборку при его изменении. Пакет `pgocaml_ppx` одновременно с заменой
подключать нельзя: оба регистрируют одинаковые extension names.

Код приложения по-прежнему зависит от `pgocaml`. Для выполнения не нужны
schema dump packages или файл snapshot: metadata используются только при
компиляции. Runtime-соединение и его `search_path` должны соответствовать схеме
снимка; неквалифицированные таблицы PPX разрешает в `public`. Для других схем
используйте явное `schema.table`.

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
`standard_conforming_strings=on`; E-strings и PostgreSQL dollar quoting пока
отклоняются. SQL literals доступны в predicates и pagination, а grammar
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

Без RETURNING `[%pgsql ...]` возвращает `unit` в monad модуля PGOCaml.
С RETURNING действуют те же правила scalar/tuple/object results и NULL, что
у SELECT. `[%pgsql.object ...]` требует RETURNING. UPDATE и DELETE могут
не содержать WHERE: тогда PostgreSQL изменяет все строки таблицы.

INSERT требует явного списка колонок для VALUES. Поддерживаются несколько
строк VALUES, DEFAULT в отдельных позициях и отдельная форма DEFAULT VALUES.
UPDATE поддерживает несколько присваиваний параметров или DEFAULT.
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
| Прямые колонки, qualified references, `*`, `alias.*`, projection alias через `AS` | Поддерживается |
| WHERE с boolean predicates, comparisons, IS NULL, LIKE/BETWEEN, fixed IN и ANY/ALL | Поддерживается |
| ORDER BY исходным колонкам, ASC/DESC; LIMIT/OFFSET | Поддерживается |
| SQL comments, quoted identifiers, один завершающий `;` | Поддерживается |
| Scalar/optional подстановки и OCaml expressions | Поддерживается |
| `nullable-results` | Поддерживается |
| Другие flags, включая `execute`, `show`, параметры подключения | Явный diagnostic |
| Custom converters, включая `PGCUSTOM_CONVERTERS_CONFIG` | Явный diagnostic |
| INSERT с явными колонками, несколькими VALUES, DEFAULT/DEFAULT VALUES | Поддерживается |
| UPDATE SET параметрами/DEFAULT, DELETE, необязательный WHERE | Поддерживается |
| RETURNING прямых колонок, aliases и wildcard | Поддерживается |
| ON CONFLICT по колонкам ключа, DO NOTHING, DO UPDATE с параметрами/DEFAULT/EXCLUDED | Поддерживается |
| ON CONSTRAINT, partial-index predicates, INSERT SELECT, UPDATE FROM, DELETE USING | Явный diagnostic |
| JOIN, DISTINCT, aggregates, CTE, subqueries | Явный diagnostic |
| Вычисляемые expressions/projections, casts, функции, E-strings, dollar quoting | Явный diagnostic |
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
произвольных SQL expressions, перегруженных функций, операторов, casts и JOIN.
Полная совместимость остаётся целью: parser и вывод типов будут расширяться
проверяемыми группами. DML и обычный upsert добавлены одной такой группой,
поскольку их типы можно вывести из имеющихся metadata колонок. Неподдержанная
конструкция возвращает diagnostic, без обращения к БД при компиляции.

Дальнейшие шаги и выполненные части записаны в
[дорожной карте PPX](ppx_roadmap.md).

Проверки запускаются через `make build`, `make test`, `make fmt` и
`make test-postgres`. Для отдельного сравнения с standalone driver upstream
4.4.0 используется `TYPED_SQL_UPSTREAM_PPX=/path/to/driver.exe make test-postgres`:
одни fixtures проверяют OCaml-типы и результаты обоих PPX. Обычные offline
проверки и компиляция приложения этого driver и доступной БД не требуют.
