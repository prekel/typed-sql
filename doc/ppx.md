# Offline SELECT через PG’OCaml PPX

Экспериментальный пакет `typed-sql-pgocaml-ppx` проверяет ограниченное
подмножество PostgreSQL SELECT по snapshot схемы. Он сохраняет синтаксис
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
| JOIN, DISTINCT, aggregates, CTE, subqueries, DML, LIMIT/OFFSET | Явный diagnostic |
| SQL literals/expressions в projection или WHERE, OR, другие comparison operators | Явный diagnostic |
| List-подстановки, enum/domain, arrays, прочие native types | Явный diagnostic |

Поддерживаются встроенные PostgreSQL-типы `bool`, `int2`, `int4`, `int8`,
`float4`, `float8`, `text`, `varchar`, `bpchar`, `bytea`, `numeric`, `date`,
`time`, `timestamp`, `timestamptz`, `interval`, `json`, `jsonb` и `uuid`.
Используются представления PG’OCaml: например, `int4` — `int32`, `numeric` и
JSON — `string`, временные значения — типы CalendarLib. `json` можно читать,
но PostgreSQL не имеет для него операторов `=` и сортировки; такие WHERE и
ORDER BY PPX отклоняет.

Nullable колонка возвращает `option`. Flag `nullable-results` делает optional
все выбранные поля. NULL в объявленной non-null колонке и несовпадение числа
полей фактической строки сохраняют runtime-ошибки совместимого контракта.
Другие ошибки PostgreSQL остаются исключениями драйвера; `Result.t` adapter
API здесь не вводится.

Поддерживаются только выбранные output и parameter codecs. Таблица может
содержать неподдержанные колонки, если запрос не выбирает их и не использует
как параметры. Metadata или SQL вне подмножества не включают online fallback.

Prepared statements кэшируются в `PGOCaml.private_data` в прежнем формате
`PGOCaml.pa_pg_data`; пользовательские значения не входят в ключ. Соединение
с таким PPX резервирует private data для этого кэша. После изменения схемы
обновите snapshot и создайте новые runtime-соединения.

Дальнейшие шаги и выполненные части записаны в
[дорожной карте PPX](ppx_roadmap.md).
