# Offline SQL через PG’OCaml PPX

Экспериментальный пакет `typed-sql-pgocaml-ppx` проверяет ограниченное
подмножество PostgreSQL SELECT, INSERT, UPDATE и DELETE по snapshot схемы. Он сохраняет синтаксис
`[%pgsql ...]` и `[%pgsql.object ...]` и выполняет запрос через модуль
`PGOCaml` приложения. Компиляция не подключается к БД.

## Подключение

Создайте snapshot после применения миграций через один из существующих
PostgreSQL-дамперов. Для PPX необходимы точные типы колонок из snapshot
версии 3. Старые snapshot версии 2 остаются пригодны для codegen descriptors,
но не содержат необходимых PPX metadata.

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

`$name` и `${expression}` принимают значение типа сравниваемой колонки.
`$?name` и `$?{expression}` принимают `option` того же типа и кодируют `None`
как SQL NULL. Равенство с NULL сохраняет SQL-семантику: это не условие
`IS NULL`. Каждое вхождение подстановки получает отдельный `$n`; значения
отправляются отдельно от SQL.

Одна выбранная колонка возвращается как список значений; несколько — как
список tuples. Object-вариант использует имена колонок или projection aliases.
Имена должны быть допустимыми OCaml method names и не повторяться. `SELECT *`
и `alias.*` используют порядок колонок snapshot. Изменение порядка или состава
колонок в БД требует обновления snapshot и перекомпиляции приложения.

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
| WHERE `column = parameter`, AND, группирующие скобки | Поддерживается |
| ORDER BY исходным колонкам, ASC/DESC | Поддерживается |
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
| JOIN, DISTINCT, aggregates, CTE, subqueries, LIMIT/OFFSET | Явный diagnostic |
| SQL literals/expressions в projection или WHERE, OR, другие comparison operators | Явный diagnostic |
| List-подстановки, enum/domain, arrays, прочие native types | Явный diagnostic |

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
