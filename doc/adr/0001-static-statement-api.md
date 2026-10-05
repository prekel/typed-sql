# ADR 0001: статический `Statement` как единственный API выполнения

- Статус: принято
- Дата: 17 сентября 2026 года
- Целевая версия: 0.2.0

## Контекст

До версии 0.2 приложение строило `Result_query.t` или `Command.t` вместе с
конкретными значениями параметров. Adapter при каждом вызове запускал
normalization, validation, dialect lowering и rendering. Можно было отдельно
получить `Compiled_query`, но он уже содержал значения одного вызова и поэтому
не подходил для повторного выполнения той же формы SQL с новым input.

Очевидное разделение на аппликативный `Parameters.t` и `Prepared_query.create`
решало задачу технически, но заставляло дважды описывать каждый параметр:

```ocaml
let parameters =
  Parameters.(
    let+ name = field Db_type.text ~get:(fun input -> input.name)
    and+ min_id = field Db_type.int64 ~get:(fun input -> input.min_id) in
    name, min_id)
```

После этого те же `name` и `min_id` ещё раз появлялись в callback запроса.
Для обычного record input это лишний слой и заметный boilerplate.

## Решение

Публичная единица компиляции и выполнения —
`('input, 'output, 'requirements) Statement.t`. Statement создаётся верхнеуровневым
`let` при инициализации OCaml-модуля:

```ocaml
type input =
  { name : string
  ; min_id : int64
  }

let find_people =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let%map.Parameters name =
      params.column Person.name_column ~get:(fun input -> input.name)
    and min_id =
      params.column Person.id_column ~get:(fun input -> input.min_id)
    in
    params.query_many Query.(
      from Person.table
      |> where (fun person ->
        Person.name person =. name &&. (Person.id person >=. min_id))
      |> select Person.projection))
```

`params.column` берёт codec из column descriptor. Для значения, не связанного
с колонкой, есть `params.expr Db_type.t`. Getter одновременно связывает слот с
полем единственного input-типа. Повторное использование expression сохраняет
один bind slot.

OCaml-значение, переданное прямо в DSL через оператор с `$`, `Expr.constant`,
`Insert.set` или `Update.set`, считается константой времени создания statement.
Оно всё равно кодируется как SQL bind value и никогда не интерполируется в
строку. Значение, которое должно меняться между вызовами, может войти в запрос
только через `params` и затем используется как expression. Такое разделение
делает время жизни значения видимым в исходном коде.

Input statement не ограничен record: можно использовать обычный кортеж,
labeled tuple или любой другой OCaml-тип. Сравнение этих трёх вариантов и
полные примеры находятся в `doc/statement_inputs.mld`.

Конструктор строит semantic AST один раз. Статические конструкторы `Statement`
принимают обязательный `~dialect`: `Dialect.portable` сразу проверяет и
компилирует планы PostgreSQL и SQLite, а concrete witness компилирует только
выбранный dialect. Варианты без `_exn` возвращают `Result`; варианты `_exn`
удобны для верхнеуровневого определения и останавливают запуск приложения при
ошибке определения. Несколько запросов с общими параметрами собираются через
`Statement.with_parameters`.

Слово «статический» здесь означает время инициализации OCaml-модуля, а не
работу Dune или компилятора OCaml. SQL не вычисляется на этапе сборки бинарника.
Такой этап потребовал бы PPX или отдельной кодогенерации.

Adapter предоставляет один вызов:

```ocaml
Typed_sql_caqti_lwt.run ~conn find_people input
```

Cardinality входит в тип результата конструктора:

- `query_many` возвращает список;
- `query_one` принимает только `exactly_one` SELECT и возвращает одну строку;
- `query_optional` принимает `at_most_one` или `exactly_one` SELECT и возвращает
  `option`;
- `expect_one` и `expect_optional` выполняют runtime-проверку для запроса без
  статического доказательства;
- `command` возвращает `Affected_rows.t`.

Выполнение выбирает готовый план по dialect соединения, применяет getters,
проверяет runtime-ограничения, кодирует bind values и декодирует результат.
Semantic AST, validation, lowering и rendering при этом не повторяются.

Runtime `LIMIT` и `OFFSET` создаются через `params.non_negative_int` и
`Query.limit_param`/`Query.offset_param`. Отрицательное значение возвращает
ошибку параметра до обращения к базе.

Если input выбирает конечный набор форм SQL, каждая форма создаётся отдельно.
`Statement.choose` принимает две уже созданные ветки и predicate; вложенные
вызовы задают любое конечное число вариантов. Это подходит для optional
filters и GraphQL resolver, если набор shapes конечен. Resolver с произвольным
selection set должен либо использовать заранее объявленные batch statements,
либо явно построить ограниченный набор вариантов.

Статические конструкторы `Statement` гарантируют компиляцию SQL в ядре один
раз. Caqti adapter использует `Request.Dynamic`; PostgreSQL и SQLite drivers
кэшируют подготовленные запросы на connection. PG'OCaml adapter по умолчанию
подготавливает запрос при каждом выполнении, а `Prepared_cache` предоставляет
явный ограниченный кэш на одном connection. Время жизни handle контролирует
adapter и владелец connection.

## Дополнение: динамическая форма

Для пользовательских языков предикатов и других неограниченных наборов shapes
принят `Statement.Dynamic`. Он остаётся внутри единого `Statement.t` и
исполняется тем же adapter `run`, но вместо готового плана хранит callback
`input -> Result_query.t` или `input -> Command.t`.

Конструктор callback не запускает. Каждый `Statement.sql` или `run` вызывает
его один раз и компилирует результат только для выбранного dialect. Значения,
переданные через операторы с `$`, `Expr.constant` и DML assignments, относятся
к текущему input и остаются bind parameters. Runtime compilation не
кэшируется: безопасный cache должен отдельно решить lifetime значений и
projection closures, ограничение числа shapes и eviction.

Dynamic validation/lowering error возвращается из `Statement.sql` и adapters
как отдельная compilation error до обращения к базе. Исключение
пользовательского callback не перехватывается. `Statement.choose` разрешает
только выбранную ветку и может сочетать static и dynamic statements.

## Последствия

У приложения больше нет отдельных публичных `Compiler`, `Compiled_query`,
`Compiled_command`, `fetch`, `fetch_one`, `fetch_opt`, `execute` и
`Dialect_specific`. Один объект хранит форму, cardinality и dialect
requirements; один `run` выполняет его. Нельзя случайно передать значения
одного вызова в план другого.

Параметры статического statement должны иметь фиксированное число и типы.
Список переменной длины в `IN (...)`, произвольный набор сортировок или
динамический GraphQL projection меняют SQL shape. Для них можно выбрать
конечные варианты, использовать стабильную SQL-форму с подходящей семантикой
или применить `Statement.Dynamic`.

Создание portable statement компилирует две версии SQL и немного увеличивает
время запуска и память. Ошибка обнаруживается при старте процесса, а не при
первом запросе. Для приложения это предпочтительнее позднего отказа на горячем
пути.

## Рассмотренные варианты

### Сохранить deferred query и компилировать каждый вызов

Это самый гибкий API и он естественно поддерживает произвольную структуру,
зависящую от input. Он оставляет validation и rendering на пути каждого
запроса и не даёт объект, который явно описывает reusable operation. Такой
режим отвергнут как поведение всех statements; позднее он принят как явно
названный opt-in `Statement.Dynamic` для неограниченного набора форм.

### Прозрачный cache по shape

Cache мог бы пропускать часть lowering и rendering. Для поиска shape всё равно
пришлось бы построить и обойти AST, а lifecycle, границы памяти и функции в
projection усложнили бы поведение. Cache также скрывает, сколько форм реально
создаёт приложение.

### Отдельные `Parameters.t` и `Prepared_query.t`

Такое разделение формально чистое и позволяет независимо переиспользовать
parameter schema. Для основного сценария оно дублирует имена, codecs и getters.
Текущий `params` callback сохраняет ту же типобезопасность с меньшим API.

### PPX или кодогенерация на этапе сборки

PPX мог бы выводить getters из record и действительно генерировать план во
время сборки. Цена — отдельный синтаксис, более сложные diagnostics, зависимость
от compiler tooling и необходимость сериализовать часть DSL. К этому варианту
можно вернуться, если ручные getters окажутся главным источником boilerplate.
Он может быть сахаром над `Statement`, не меняя runtime contract.

### Функтор или модуль на каждый запрос

API вида `module Find = Statement.Make (...)` подчёркивал бы создание при
инициализации модуля, но добавлял бы module boilerplate и затруднял передачу
statements как обычных значений. Верхнеуровневый `let` уже имеет нужный
lifecycle.

### Один широкий SQL с boolean flags

Optional filter можно записать как `WHERE (NOT $enabled OR column = $value)`.
Это сохраняет один shape, но меняет SQL, может ухудшить планирование и не
подходит для projection, JOIN, GROUP BY или ORDER BY, которые действительно
различаются. Библиотека не генерирует такую замену автоматически; приложение
может выбрать её явно.

### Server-side prepared cache

Кэш сокращает работу драйвера и сервера, не меняя статическую проверку или
компиляцию DSL. Caqti сам управляет подготовкой, ограничением и освобождением
`Request.Dynamic`. PG'OCaml использует именованные statements в явном
`Prepared_cache`: ключом служат SQL и типы параметров, при вытеснении вызывается
`close_statement`, а владелец вызывает `Prepared_cache.close` до закрытия
connection. Новый connection получает новый кэш. Изменение схемы требует
закрыть старый кэш и создать новый.
