# Дорожная карта PPX, совместимого с pgocaml_ppx

Состояние на 16 октября 2026 года. Реализованы два экспериментальных режима
`typed-sql-pgocaml-ppx`. Они сохраняют `[%pgsql ...]`, `[%pgsql.object ...]`,
PG’OCaml-типы, соединения, monad и выполнение через `PGOCaml` приложения.
Сборка и OCaml LSP работают без подключения к БД.

## Две ветви развития

| Ветвь | Источник типов | Когда нужна БД | Когда обновлять metadata |
| --- | --- | --- | --- |
| A: SQL parser и вывод типов | Собственный разбор SQL и snapshot схемы v3 | При дампе схемы | После изменения схемы |
| B: SQL cache | PostgreSQL Prepare/Describe и каталоги, сохранённые в `queries.json` v2 (legacy v1 читается) | При явных `prepare` и `check` | После изменения SQL или схемы |

Ветви развиваются отдельно и используют общую генерацию совместимого runtime.
Один PPX-драйвер подключает ровно один источник metadata; автоматического
fallback между ветвями или подключения к БД при компиляции нет.
Ветвь B не требует расширять собственную SQL-грамматику и inference для каждой
новой конструкции PostgreSQL. Ветвь A сохраняет возможность менять запросы
без получения нового описания каждого SQL, пока snapshot достаточен.

Непосредственная цель обеих ветвей — заменить `pgocaml_ppx` в существующем
приложении без переписывания quotations. Следующий общий путь — query/command
quotations через raw SQL API, затем постепенный переход отдельных запросов
на query builder. Для ветви B реализован первый query/command API в
`typed-sql-ppx`; snapshot-frontend для него пока отложен.

Эталон совместимости —
[pgocaml_ppx 4.4.0](https://github.com/darioteixeira/pgocaml/tree/v4.4.0/ppx).
Полная совместимость не обещается: поддержка SQL зависит от выбранной ветви,
а codecs, flags и статическая форма SQL остаются отдельными ограничениями.
[Руководство](ppx.md), [README пакета](../ppx/README.md) и
[инструкция проверки в приложении](../ppx/TRY_IN_APP.md) описывают текущий API.
Общая работа над DSL описана в [дорожной карте проекта](roadmap.md).

## Ветвь A: SQL parser и вывод типов по snapshot

Конвейер: SQL literal → parser с byte offsets → разрешение таблиц, колонок
и областей видимости по snapshot → PostgreSQL inference → serializers/decoders.
Неизвестная конструкция или неоднозначный тип дают diagnostic. Наличие parser
само по себе не заменяет правила PostgreSQL для операторов, overloads и casts.

Вход — [snapshot версии 3](schema_snapshot.md), общий с генератором DSL
descriptors. Codegen создаёт schema PPX библиотеку, которую Dune связывает
с драйвером. JSON не читается при раскрытии quotations; OCaml-значения
прикладных descriptors до typechecking не извлекаются. Версия 2 остаётся
пригодной для прежнего codegen, но не содержит точных native metadata для PPX.

### Metadata схемы

- [x] Сохранять точное имя native type каждой колонки, включая `int2`/`int4`
  и имена enum/domain/array; оба дампера создают одинаковый snapshot.
- [x] Сохранять точные native types domain bases и array elements, сверх
  portable nested descriptors, как необязательное расширение snapshot v3.
  Сохранять attribute NOT NULL для совместимого чтения domain-колонок.
- [x] Зафиксировать формат snapshot v3 и поведение reader/codegen для
  старых файлов. Потерянные сведения нельзя восстанавливать догадкой;
  совместимый PPX должен требовать достаточно полный snapshot.
- [x] Сохранить единый источник для PPX и генератора DSL descriptors, с
  отдельным выбором OCaml-представлений для каждого потребителя.
- [x] Описать настройку schema file и разрешение неквалифицированных имён.
  Одинаковые имена в разных схемах не должны разрешаться случайным порядком.
- [x] Описать и проверить пересборку Dune при изменении snapshot. Файлы
  metadata не содержат credentials.

Критерий завершения: round-trip snapshot сохраняет необходимые точные типы,
а PPX и codegen читают одну схему без доступа к БД.

### Parser и базовый SQL

- [x] Реализовать небольшой parser SELECT с комментариями, quoted identifiers
  и byte offsets diagnostics; грамматика полностью проверяет входной SQL.
- [x] Расширить parser до поддержанных SQL expressions/literals и вложенных
  query blocks с сохранением offsets исходного SQL.
- [x] Добавить PostgreSQL E-strings и dollar quoting с сохранением bind boundaries,
  Unicode escaping, newline continuations и исходных offsets.
- [x] Поддержать SELECT одной таблицы, columns/projection aliases, `*`, WHERE
  `column = parameter`, AND со скобками и ORDER BY исходным колонкам.
- [x] Добавить NOT/AND/OR, comparisons, IS NULL, LIKE/ILIKE, BETWEEN,
  фиксированный IN/NOT IN, ANY/ALL и literals в predicates; LIMIT/OFFSET.
  Остальные expressions и операторы вне подмножества по-прежнему отклонять.
- [x] Поддержать базовые INSERT/UPDATE/DELETE по одной таблице, включая
  RETURNING, несколько VALUES, DEFAULT и ON CONFLICT по колонкам ключа с
  DO NOTHING/DO UPDATE и EXCLUDED. Operators и statements вне заявленного
  подмножества отклонять.
- [x] Проверить DML offline fixtures и выполнением в PostgreSQL: unit без
  RETURNING, scalar/tuple/object results, NULL, defaults, обе ветви upsert,
  пустой RETURNING и порядок bind parameters.
- [x] Сохранить scalar/optional подстановки и `${...}`, вывод типов
  параметров по контексту запроса, tuples, objects и порядок строк.
- [x] Сохранить nullability прямых колонок и flag `nullable-results`.
- [x] Добавить nullability поддержанных вычисляемых expressions;
  отсутствие подтверждённого column origin учитывать по upstream-контракту.
- [x] Сохранить PG’OCaml serializers/decoders для поддержанных типов.
  Неподдержанные converters и flags сопровождать отдельными diagnostics.
- [x] Добавить пакет через `dune-project` и руководство подключения с
  точным перечнем поддержанного SQL и примером изменения Dune.

Критерий завершения: downstream fixtures собираются без доступной БД,
совпадают с upstream по OCaml-типам и дают те же результаты при отдельной
проверке выполнения в PostgreSQL.

### Расширение собственной грамматики и inference

- [x] Добавить JOIN/INNER JOIN с ON, цепочками и self-JOIN, разрешением aliases,
  проверкой неоднозначных колонок, wildcard order и параметрами ON/WHERE.
  Сохранить PG’OCaml-типы, object output и исходную nullability колонок.
- [x] Добавить LEFT/RIGHT/FULL/CROSS, USING/NATURAL, скобки и запятые в FROM.
- [x] Добавить numeric expressions, CAST/`::`, CASE, COALESCE и NULLIF с
  контекстными типами параметров и сохранением column origin.
- [x] Добавить count/sum/avg/min/max, bool_and/bool_or, string_agg/array_agg,
  GROUP BY/HAVING, DISTINCT, FILTER и aggregate-local ORDER BY.
- [x] Добавить UNION/INTERSECT/EXCEPT с ALL/DISTINCT и правильными приоритетами.
- [x] Добавить derived tables, scalar/EXISTS/IN/ANY/ALL subqueries и
  корреляцию scalar/predicate subqueries.
- [x] Добавить обычные и recursive SELECT CTE, INSERT/UPDATE/DELETE CTE,
  INSERT SELECT и проверки побочных эффектов; сохранить snapshot v3.
- [x] Добавить LATERAL derived SELECT, window functions и WINDOW/frames
  ROWS/RANGE/GROUPS/EXCLUDE, а также UPDATE FROM и DELETE USING с RETURNING.
- [x] Сохранить optional typmod metadata колонок в snapshot v3 и обоих дамперах;
  проверять origin same-type casts varchar/bpchar/numeric и временных колонок.
  Старые v3 без metadata читаются; неоднозначные casts требуют обновления снимка.
- [x] Добавить lower/upper, length, trim, позиционный substring, replace, concat,
  abs/round, JSON extraction и IS DISTINCT FROM с проверенными overloads.
- [x] Добавить unnest и generate_series в FROM, включая implicit/explicit
  LATERAL, несколько массивов, aliases и WITH ORDINALITY. Сохранить codecs,
  upstream-nullability и статическую форму SQL.
- [x] Добавить SRF в SELECT list, scalar/nested expressions, GROUP BY/ORDER BY
  и INSERT SELECT; поддержать ROWS FROM с известными SRF/scalar functions,
  общим WITH ORDINALITY и LATERAL. Проверить NULL padding, object output,
  контекстные запреты и сравнить типы/выполнение с upstream.
- [x] Поддержать функциональную зависимость GROUP BY от полного non-deferrable
  primary key экземпляра базовой таблицы. Optional metadata deferrability
  сохраняются в snapshot v3 и обоих дамперах; старые снимки читаются.
- [x] Добавить cardinality, array_length и array_to_string с проверенными
  overloads, NULL и параметрами; сравнить типы и выполнение с upstream.
- [ ] Расширять оставшиеся формы: GROUPING SETS, SEARCH/CYCLE, mutual recursion,
  остальные table/set-returning functions и aggregates внешнего уровня.
  MERGE остаётся вне поддержанного DML.
- [ ] Расширять остальные функции, операторы и implicit coercions;
  regex-overloads substring пока отклоняются. Ограничения групп описаны
  в руководстве, неизвестные overloads не восстанавливаются догадкой.
- [ ] Для пользовательских функций определить дополнительные metadata snapshot.
  Отсутствующие сведения не заменять предположением.

Критерий каждого расширения: обновлённая матрица поддержки, положительные и
compile-fail fixtures, сравнение типов и выполнения с PostgreSQL/upstream.
Эти задачи относятся к ветви A: наличие SQL в query cache не реализует его
разбор или inference по snapshot.

## Ветвь B: SQL cache через Prepare/Describe

Конвейер подготовки: OCaml AST исходников → quotations → сканер подстановок →
Prepare/Describe и каталоги PostgreSQL → `queries.json`. Конвейер сборки:
JSON → встроенный Dune-модуль → поиск точного SQL → serializers/decoders.
Пользовательский SQL во время подготовки не выполняется; его grammar и типы
проверяет сервер. Собственный parser и inference ветви A здесь не вызываются.

Кеш содержит точный SQL с позиционными bind slots, логические типы параметров,
порядок, имена и nullability результата. OID, credentials и значения параметров
не сохраняются. Изменение OCaml-имени bind или расположения quotation не меняет
ключ. Полностью офлайн невозможно обнаружить изменение схемы БД; актуальность
проверяет явный `check`. Формат кеша v1 независим от snapshot v3.

### Реализовано и следующие задачи

- [x] Сбор `[%pgsql]` / `[%pgsql.object]` из OCaml AST перечисленных `.ml` файлов.
- [x] Сканер статических подстановок без разбора SQL; Prepare/Describe и каталоги
  PostgreSQL определяют типы вместо собственного SQL inference.
- [x] `typed-sql-pgocaml-queries prepare/check/codegen`, детерминированный
  `queries.json` версии 2 без OID и значений параметров, атомарное обновление.
  Старый выполняющий PPX продолжает читать v1.
- [x] Встраивание кеша в PPX через Dune; офлайн-сборка и LSP без чтения JSON
  при раскрытии quotations. Отсутствующий запрос требует явной регенерации.
- [x] Повторное использование runtime generation, codecs и PG’OCaml-nullability;
  отдельные offline/PostgreSQL-тесты и общие сравнения с upstream.
- [ ] Сбор quotations, создаваемых другими PPX, после соответствующего preprocessing.
- [x] Добавить kind SELECT / DML RETURNING / command и top-level-only в кеш v2.
  Внешнюю команду и WITH классифицирует небольшой lexer после серверной
  проверки SQL; неизвестная структура отклоняется новым query PPX.
  Классификация не выполняет DML и не выводит SQL-типы.
- [x] Выделить логические PostgreSQL metadata без PG’OCaml codecs в
  `typed-sql-ppx.cache`. Legacy-потребитель вычисляет свои codecs, новый PPX —
  descriptors typed-sql; офлайн-потребителю не нужен драйвер.

Критерий расширения: новые запросы готовятся сервером и собираются офлайн;
результаты, OCaml-типы и ошибки codecs проверяются отдельными fixtures.
GROUPING SETS и regex substring уже проверяются в этой ветви, хотя parser
ветви A пока их отклоняет. Это не означает поддержки всех типов и flags upstream.

## Общий контракт и архитектура обеих ветвей

`lib/` остаётся backend-independent. SQL frontend, `ppxlib`, PostgreSQL
интроспекция и совместимые codecs находятся за его пределами. Dune встраивает
metadata в драйвер; во время раскрытия quotation JSON не открывается.
Пользовательские значения всегда передаются bind parameters.

- [x] Зафиксировать матрицу поддержанного синтаксиса и flags в руководстве:
  поддержанные scalar quotations и явные diagnostics для остальных возможностей.
- [ ] Расширить проверяемый статический контракт upstream 4.4.0:
  tuples, objects, `$name`, `$?name`, `${...}`, `nullable-results` и source
  comments. Динамические lists, расширение flags подключения и Custom Type
  Conversions не входят в текущий статический контракт.
- [x] Перенести и адаптировать
  [upstream PR #80](https://github.com/darioteixeira/pgocaml/pull/80): поддержку
  OCaml quoted strings `{|...|}` и `{sql|...|sql}` при разборе аргументов PPX.
  Добавить regression fixtures для многострочного SQL, обоих видов quotations
  (`pgsql` и `pgsql.object`), обычных строк и подстановок внутри quoted strings.
- [x] Зафиксировать для поддержанного SELECT OCaml-типы, output names, порядок
  строк, NULL и работу prepared statements в downstream fixtures.
- [ ] Расширить эти fixtures вместе с поддержкой остального SQL.
- [x] Описать судьбу каждого flag: поддержка или явный diagnostic. В первой
  версии отклонять compile-time `execute` и flags подключения к БД.
- [x] При заимствовании кода выделить файлы с лицензией и указать tag/commit
  upstream, чтобы изменения можно было сверять с исходной реализацией.
- [x] Добавить enum/domain codecs и одномерные native arrays поддержанных
  scalar-типов, включая enum/domain combinations, NULL и escaping.
- [ ] Поддержать source comments с отдельной проверкой совместимости.
- [x] Проверить upstream-эвристику NULL для outer JOIN и поддержанных expressions.
  Улучшение nullability, меняющее OCaml-тип результата, документировать как
  изменение контракта; не выдавать его за прозрачную замену.

Представления PG’OCaml и codegen различаются:

| PostgreSQL-тип | Контракт совместимого PPX | Текущий codegen typed-sql |
| --- | --- | --- |
| `smallint` | `int` (`PGOCaml.int16`) | `int` |
| `integer` | `int32` | `int` |
| `bigint` | `int64` | `int64` |
| `numeric` | `string` | `Decimal.t` |
| `date` | Представление PG’OCaml/CalendarLib | `Date.t` |
| `timestamp` | Представление PG’OCaml/CalendarLib | `Local_timestamp.t` |
| `timestamptz` | Представление PG’OCaml/CalendarLib | `Ptime.t` |
| enum | `string`, если не задан custom converter | Сгенерированный variant |
| domain | Представление базового типа или custom converter | Отдельный тип-обёртка |

Совместимый PPX сохраняет контракт PG’OCaml. Правила codecs генератора
typed-sql нельзя автоматически применять вместо custom converters PG’OCaml.

Если код заимствуется из upstream, сохраняются copyright notices, происхождение
и применимая [лицензия](../ppx/ORIGIN.md). Лицензия MIT ядра не заменяет
лицензию заимствованных файлов.

## Общий путь к DSL: query/command quotations с `Expr.t`

Следующий API строится через [raw SQL API](adr/0002-raw-sql-escape-hatch.md).
Источник типов может быть любым: inference ветви A или metadata ветви B.
Перевод SQL в DSL для этого не требуется. Существующие выполняющие quotations
`[%pgsql ...]` и `[%pgsql.object ...]` сохраняются.

### Выбранное направление

В cache-ветви реализованы формы — `[%pgsql.query ...]`, `[%pgsql.query.object ...]`
и `[%pgsql.command ...]`, а также прямые `[%pgsql.statement ...]` /
`[%pgsql.statement.object ...]`. В query/command подстановки принимают типизированные
`Expr.t`, а не неявно захватывают обычные OCaml values. Quotation можно передать
прямо в `params.query_many`; отдельная функция-builder не требуется.
Ниже — реализованный API ветви B:

```ocaml
type input =
  { status : string
  ; limit : int64
  }

let find_statement =
  Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
    let%map.Parameters status =
      params.expr Db_type.text ~get:(fun input -> input.status)
    and limit =
      params.expr Db_type.int64 ~get:(fun input -> input.limit)
    in
    params.query_many
      [%pgsql.query.object
        "SELECT id, name FROM people WHERE status = $status LIMIT $limit"])
```

Здесь `$status` и `$limit` используют локальные выражения bind slots из
`let%map.Parameters`. Query строится при определении `find_statement`, план
компилируется один раз. При каждом
`Adapter.run ~conn find_statement { status; limit }` getters читают новый input;
построение query и компиляция не повторяются. `Statement.Dynamic` этому пути
не требуется. Через `Expr.constant` можно явно зафиксировать OCaml-значение
на время определения Statement; это также bind, а не SQL interpolation.
При необходимости quotation можно вынести в обычную функцию с именованными
аргументами `Expr.t`; это способ переиспользования, а не обязательная обёртка.

`Result_query.t` описывает одну декодированную строку; `.object` создаёт объект
с методами выбранных полей. Список появляется при `params.query_many`.
DML без RETURNING создаёт `Command.t`, а Statement возвращает `Affected_rows.t`.
Прямые `%pgsql.statement` / `.statement.object` объявляют runtime input
через `fun input_pattern -> SQL` и возвращают готовый статический Statement;
их контракт описан ниже.

### Реализованный срез ветви B

- [x] Добавить `typed-sql-ppx` и общую библиотеку `typed-sql-ppx.cache` без
  зависимости от PGOCaml. Metadata v2 содержат kind и placement, а не имена
  PGOCaml codecs; legacy PPX читает v1/v2 и сохраняет свои OCaml-типы.
- [x] Генерировать SELECT и INSERT/UPDATE/DELETE RETURNING через `.query` /
  `.query.object`, DML без результата через `.command`.
- [x] Добавить `Raw_sql.Postgresql` и аппликативный `Raw_sql.Output`, typed binds,
  точную проверку SQL-descriptors, shared slots и статический Statement input.
- [x] Классифицировать внешнюю команду и WITH маленьким lexer после серверной
  проверки SQL. Неизвестный kind отклонять, data-modifying CTE и внешние row locks
  разрешать только на верхнем уровне. Полный parser/inference не вызывается.
- [x] Проверить UNION ALL raw/DSL, derived tables, SELECT/DML CTE, nullable binds,
  objects, numeric/enum/array codecs и выполнение через Caqti и PGOCaml.
- [x] Добавить [руководство и путь миграции](../query-ppx/README.md), embedded
  codegen `--target typed-sql-ppx` и offline/compile-fail fixtures.

### Прямые statement quotations — реализовано в ветви B

- [x] `%pgsql.statement` и `%pgsql.statement.object` из кеша v2. Подстановки
  используют `fun input_pattern -> SQL` и генерируют typed bind slots/getters
  через `Statement.with_parameters`. Результат — готовый `Statement.t`,
  определённый на уровне модуля и принимающий новый runtime input при запуске.
- [x] SELECT/RETURNING возвращают список scalar/tuple-строк либо объектов;
  DML без RETURNING через `.statement` возвращает `Affected_rows.t`.
  `.statement.object` для DML без результата отклоняется.
- [x] Поддержать optional binds, `${expression}`, `nullable-results`, сбор
  quotations online-инструментом и проверку выполнения через оба adapters.
- [x] Поддержать input в виде одиночного значения, tuple или записи; getters
  читают его только при binding. SQL компилируется один раз. Параметризованный
  SQL без input-pattern отклоняется; input `unit` остаётся для SQL без параметров
  в literal-форме. Input-pattern без SQL-подстановок отклоняется.
  Для композиции с DSL доступны `.query` / `.command` и явный
  `Statement.with_parameters`.

Ниже остаются общие критерии для обоих frontend; наличие среза B не закрывает
выделение parser/inference A и его подключение к новым quotations.

### Raw API и генерация

- [ ] Реализовать raw SELECT с типизированными binds, output descriptors и
  decoder → `Result_query.t`. Подготовить общий контракт metadata для обоих
  источников типов; cache-ветвь не должна зависеть от SQL parser/inference.
- [ ] Для первой версии принимать в holes только `Expr.t`, представляющие bind
  parameters или constants: результаты `params.expr`, `params.column` и
  `Expr.constant`. Nullable binds должны иметь явный контракт; проверить
  `Optional_parameter` и совместимость `$?name`. Выражения колонок и вычисляемые
  SQL expressions не вставлять как обычные bind slots.
- [ ] Проверять совместимость точных SQL-descriptors параметров с metadata,
  регистрацию input slots в текущем Statement и nullable representations.
  Совпадение только OCaml-типов не доказывает совместимость SQL-типов.
- [ ] Поддержать tuples/scalars и object output. Для SELECT использовать
  `Result_query.select`, для DML RETURNING — `Result_query.returning`;
  DML без результата — отдельное command-направление с `Command.t`.
- [ ] Сохранить PostgreSQL requirements. Raw PostgreSQL SQL не становится
  portable из-за выбора Caqti; без доказательства кардинальности не приписывать
  `exactly_one` или `at_most_one`. Предусмотреть runtime `expect_one/optional`.
- [ ] Обеспечить детерминированную нумерацию binds, сохранение shared slots и
  независимость параметров разных запросов. Значения не включать в SQL,
  cache key или shape; не заменять placeholders простым поиском по строке.
- [ ] Проверить смешанные raw/DSL set operations, derived tables и CTE через
  descriptors выходных колонок. Проверять позицию вложения, SQL-типы,
  nullability и codecs; неподдержанные случаи возвращают явную ошибку.
  Object decoder не заменяет relation fields, а готовый `Result_query.t`
  не получает автоматически операции незавершённого `Query.t`.

### Отдельный пакет и codecs

- [ ] Выпустить `typed-sql-ppx` без зависимости от `pgocaml`, включая generated
  код и runtime dependencies. Подготовка кеша с доступом к PostgreSQL остаётся
  отдельным online-инструментом; выполнение — в существующих adapters.
- [ ] Выделить общие scanner, metadata и raw generation. Для ветви A отдельно
  выделить frontend parser/inference без драйвера; для ветви B читать логические
  описания кеша, не требуя parser. Ядро не получает драйвер, Lwt или ppxlib.
- [ ] Использовать descriptors/codecs typed-sql. Проверить scalar, enum/domain
  и arrays на границе обоих adapters; документировать `int32`/`int`, CalendarLib,
  numeric и пользовательские типы. Совместимый PPX сохраняет PG’OCaml codecs.
- [ ] Проверить сборку без установленного PGOCaml и выполнение через Caqti
  PostgreSQL, а также отдельно через PG’OCaml adapter.

### Миграция и критерии проверки

- [ ] Написать инструкцию `pgocaml_ppx` → совместимый offline PPX любой ветви →
  query/command quotation с `Expr.t` → DSL. Один запрос можно переносить
  независимо от остальных; [текущая инструкция](../ppx/TRY_IN_APP.md) пока
  покрывает только замену выполняющего PPX.
- [ ] Показать именованные аргументы функции, явные параметры через
  `Statement.with_parameters`, constants и повторные выполнения готового плана.
  Отдельно объяснить, что вызов builder и создание Statement внутри каждой
  прикладной функции повторяют компиляцию даже при одинаковой SQL shape.
- [ ] Сохранить `%pgsql.object`, прикладной deriving и object → record converter
  на первом шаге. Показать `%pgsql.query.object` с тем же converter там, где
  совпадают типы методов; различия PG’OCaml/typed-sql преобразовывать явно.
- [ ] Переписать raw запрос на DSL, показать перенос converter в decoder через
  `Projection.map` и возможную генерацию record projection прикладным deriving.
- [ ] Подготовить парные SELECT и DML RETURNING для raw/DSL, общее соединение
  и транзакцию. DSL записывать через локальное открытие, завершая `select`
  либо `command`. Описать замену adapter на Caqti и переход от исключений
  PG’OCaml к `Result.t`, от `unit` команд — к `Affected_rows.t`.
- [ ] Regression/compile-fail tests проверяют `Expr.t` нужного типа, nullable
  binds, неверные SQL-descriptors, чужие slots и запрет неподдержанных expression
  nodes. Тесты getters подтверждают: builder вызывается при определении,
  значения читаются при выполнении, повторной компиляции нет.
- [ ] Golden и PostgreSQL fixtures проверяют одинаковую shape при новых input,
  композицию параметризованных raw/DSL запросов, object → record и одинаковые
  результаты через Caqti/PG’OCaml. Отдельно проверить оба источника metadata.

Следующий шаг — попробовать cache-quotations в приложении и проверить типы
object → record на реальных запросах. Подключение snapshot-frontend остаётся
отдельной задачей. Специальный синтаксис input в PPX не требуется.

## Общие проверки и критерии выпуска

- [x] Поддержать PG’OCaml 4.3.0: нижняя граница зависимости PPX снижена до
  4.3.0. Сборка и offline fixtures проверены на OCaml 4.14.1; scalar codecs,
  bind parameters, NULL, prepared cache и одинаковые snapshots обоих дамперов —
  на PostgreSQL 18.6. Сохранены проверки на OCaml 5.1.1 / PG’OCaml 4.4.0.
- [x] Проверить PostgreSQL 15, в том числе в связке с PG’OCaml 4.3.0:
  полный интеграционный прогон на PostgreSQL 15.19 и 18.6 прошёл с PG’OCaml
  4.3.0 / OCaml 4.14.1 и 4.4.0 / OCaml 5.1.1, включая codecs, prepared cache
  и schema dump. MERGE-сценарии и мегазапрос требуют PostgreSQL 17+.
- [x] Проверить query builder и offline PPX в одной Lwt-транзакции на общем
  соединении через `Make (PGOCaml)`: оба направления чтения/записи,
  object → record, commit, явный rollback и rollback при исключении PPX.
  Второе соединение проверяет изоляцию до commit и отсутствие откатившихся
  записей. Одна fixture компилируется в режимах snapshot и query cache;
  оба проверены с PG’OCaml 4.3.0 и 4.4.0 на PostgreSQL 18.6.
- [x] Compile-time fixtures запускаются с недоступным PostgreSQL; переменные
  окружения `PG*` не включают скрытый online fallback. Отсутствующий snapshot
  или запись query cache даёт diagnostic.
- [x] Fixtures фиксируют OCaml-типы upstream для параметров/результата, включая
  `option`, tuples и object methods поддержанного SELECT.
- [ ] Расширить сравнение на enum/domain и остальной SQL. Проверки custom
  converters относятся к отдельно согласованному последнему этапу.
- [x] Compile-fail сценарии покрывают неизвестные таблицы и колонки,
  неверные source references, несовместимые типы и неподдержанные SQL/flags
  parser-ветви; cache-ветвь проверяет ошибки Prepare/Describe, устаревший
  кеш и отсутствие записи при офлайн-компиляции.
- [x] Небольшие отдельные expect snapshots проверяют diagnostics и
  bind SQL; offline assertions проверяют результаты генерации. Значения
  никогда не интерполируются в SQL.
- [x] Отдельные PostgreSQL-тесты сравнивают результаты, NULL, порядок строк,
  WHERE и повторное выполнение в рамках зафиксированного upstream-контракта.
  Они не становятся условием обычной компиляции приложения.
- [ ] Расширять differential-тесты upstream `pgocaml_ppx` и offline-замены,
  сверяя их покрытие с матрицей поддерживаемого контракта: для каждой
  поддержанной возможности нужны общая compile-time fixture и сравнение
  результатов/побочных эффектов на PostgreSQL. Текущее покрытие и ограничения
  сравнения перечислены в [матрице проверок](ppx.md#проверяемый-контракт).
- [x] Добавить общую runtime fixture с upstream для граничных значений
  integer/float codecs, NULL, UTF-8/text/bytea, numeric/uuid, временных типов,
  JSON и native arrays. Проверить SQLSTATE и структурированные поля ошибок,
  восстановление prepared execution после ошибок, rollback, savepoints и
  `PGOCaml.transact`; второе соединение проверяет изоляцию и commit.
  Enum/domain сравниваются через встроенные codecs на границах SQL;
  custom converters этим этапом не включаются.
- [x] Расширить PostgreSQL-проверки на RETURNING, predicates, pagination и
  native codecs; добавить fixtures сравнения с upstream 4.4.0.
- [x] Добавить offline, compile-fail и differential fixtures для outer JOIN,
  CASE/casts, агрегатов, set operations, подзапросов, recursive и DML CTE;
  проверить object → record и побочные эффекты на PostgreSQL.
- [x] Добавить offline/compile-fail и PostgreSQL fixtures для новых literals, typmod,
  LATERAL, окон, scalar functions, JSON operators и UPDATE FROM/DELETE USING;
  сравнить общую SQL fixture с upstream по типам и результатам. Tagged dollar
  literals, которые upstream разбирает как параметры, проверяются отдельно.
- [x] Добавить offline, compile-fail и общую PostgreSQL/differential fixture для
  SRF в FROM, функций массивов и GROUP BY по PK; проверить ошибки и side effects
  UPDATE FROM/DELETE USING с table functions.
- [x] Проверки Dune подтверждают пересборку после изменения metadata и
  воспроизводимость генерации при неизменном input.
- [x] [Инструкция проверки обоих режимов в приложении](../ppx/TRY_IN_APP.md):
  локальная установка, подготовка metadata, переключение Dune и офлайн-сборка.

Обычные offline проверки не требуют внешнего сервиса. Проверки соответствия
PostgreSQL запускаются отдельно: SQLite не заменяет PostgreSQL для проверки
вывода типов и поведения совместимого PPX.

## Отложенные задачи для обеих ветвей

Эти пункты не входят в текущую статическую замену `pgocaml_ppx` и первый
query/command API. Развитие одной ветви само по себе не включает их реализацию.

### Динамическая форма SQL и list-подстановки

- [ ] Добавить динамическую форму SQL и list-подстановки `$@...` отдельным
  этапом. Пока поддерживается только статическая форма: SQL, число
  placeholders и result shape известны при компиляции. Native array
  остаётся одним параметром независимо от длины и не относится к этому этапу.
  Для lists проверить runtime numbering, cache по итоговому SQL, несколько
  длин и совместимое поведение пустого списка; кодировки параметров не
  включать в SQL или cache key.
- [ ] Проверить динамические lists и их ограничения отдельными offline,
  runtime и differential fixtures после реализации динамической формы.

### Произвольные выражения в holes query quotations

- [ ] Рассмотреть `Expr.lower`, арифметику, scalar subqueries и column references
  в подстановках. Определить отличия expression holes от bind holes, проверки
  source scope, точных SQL-типов и соответствия metadata результата.
  Первоначальный API с bind/constant `Expr.t` этого не обещает.

### Views и выбор дальнейшей судьбы ветвей

- [ ] **Отложено по запросу пользователя:** специальная поддержка views и их
  metadata. Не добавлять отдельную реализацию для views на текущем этапе.
- [ ] По опыту использования решить, заменяет ли SQL cache parser/inference
  или обе ветви остаются доступными. Сейчас сохраняются обе; удаление
  собственного frontend не является частью внедрения кеша.
- [ ] Возможный PPX для сокращения ручного DSL-кода рассматривать отдельно
  после проверки API внешним RealWorld-приложением.

### Custom Type Conversions — последними, по отдельному согласию

Выполняется после остальных незавершённых пунктов roadmap, включая поддержку
PG’OCaml 4.3.0 и PostgreSQL 15. Пока не поддерживать sexp config и quotations
с `load_custom_from=...`, в том числе в сочетании с `show`. Текущие diagnostics
для этих возможностей сохраняются до отдельно согласованной реализации.

Даже при поручении «сделай всё из roadmap» сначала спросить
«Custom Type Conversions тоже?» и дождаться ответа. Отдельный явный запрос
пользователя на Custom Type Conversions или уже полученное согласие разрешает
работу без повторного вопроса.

- [ ] Добавить sexp config и выбор файла через `load_custom_from=...` или
  `PGCUSTOM_CONVERTERS_CONFIG`, с совместимым выбором serializers/decoders.
- [ ] Добавить config в Dune dependencies и проверить пересборку после его
  изменения, сохранив offline-компиляцию.
- [ ] Поддержать `show`/`show=...` и сочетание object quotations с custom
  converters, включая пример с `load_custom_from=tests_ppx/config.sexp`.
- [ ] Добавить отдельные regression, compile-fail и PostgreSQL-проверки
  converters, некорректного config и совместимости OCaml-типов с upstream.

Критерий завершения: отдельно согласованные custom conversions работают по
upstream-контракту; конфигурация не требует доступа к БД при компиляции.
