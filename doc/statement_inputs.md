# Входные значения статического statement

Эта страница описывает фиксированную SQL-форму, созданную
`Statement.with_parameters` с typed `~dialect`. Когда input меняет структуру
предиката, projection или число bind slots, используется
`Statement.Dynamic`; см. [описание динамических statements](dynamic_statements.md).

У statement есть два разных времени жизни значений. OCaml-значение, переданное
прямо в DSL через оператор с `$`, `Expr.constant`, `Insert.set` или
`Update.set`, захватывается один раз при создании `Statement.t`. Это константа
statement:

```ocaml
let ada_after_ten =
  Statement.query_many ~dialect:Dialect.portable
      Query.(
        from Person.table
        |> where (fun person ->
          Person.name person =$ "Ada" &&. (Person.id person >$ 10L))
        |> select Person.projection)
```

`"Ada"` и `10L` остаются SQL bind values: renderer выдаёт placeholders, а не
вставляет значения в SQL. Однако при разных вызовах `ada_after_ten` они уже не
меняются.

Значение времени выполнения объявляется через аргумент `params` конструктора.
Для объединения параметров рекомендуется `let%map.Parameters`
без локального открытия модуля; последующие параметры в том же выражении
добавляются через `and`.
`params.column` выводит `Db_type` из descriptor колонки, а `params.expr`
принимает его явно. В следующих вариантах один statement получает десять
значений: восемь фильтров, `LIMIT` и `OFFSET`. Все варианты вызывают один
query-builder:

```ocaml
let build_query
      ~name
      ~min_id
      ~max_id
      ~email
      ~min_age
      ~max_age
      ~city
      ~active
      ~maximum_rows
      ~start_at
  =
  Query.(
    from Person.table
    |> where (fun person ->
      Person.name person =. name
      &&. (Person.id person >=. min_id)
      &&. (Person.id person <=. max_id)
      &&. (Person.email person =. email)
      &&. (Person.age person >=. min_age)
      &&. (Person.age person <=. max_age)
      &&. (Person.city person =. city)
      &&. (Person.active person =. active))
    |> limit_param maximum_rows
    |> offset_param start_at
    |> select Person.projection)
```

Getter сохраняется в скомпилированном statement и применяется к input каждого
вызова. Повторное использование одного expression повторяет один и тот же bind
slot. Форма SQL и число slots остаются статическими.

## Диагностика SQL-параметров

`Statement.inspect` возвращает SQL и отдельный список параметров в порядке
placeholders. Без `~input` статический statement показывает позиции, имена и
типы; с `~input` — также закодированные значения. Для `params.column` имя по
умолчанию берётся из колонки, а `~name` переопределяет его. PostgreSQL
показывает тип SQL, SQLite при наличии значения — его storage class.

Результат также содержит выбранный диалект, `shape` скомпилированного плана и
`output`. Для query `output` перечисляет SQL-колонки, их типы и ожидаемую
кардинальность; имя есть только у прямой ссылки на колонку. Для command
`output` указывает, что результат — число затронутых строк. Поле `tree` показывает структуру
`Choose`/`Choose_dialect`, отмечает выбранный путь и различает статические и
динамические ветви. Невыбранные callbacks не запускаются.

```ocaml
let sql, inspection =
  Statement.inspect_exn ~dialect:Postgresql ~input find_people
in
Stdlib.print_endline sql;
List.iter inspection.parameters ~f:(fun parameter ->
  Statement.sexp_of_parameter parameter
  |> Sexp.to_string_hum
  |> Stdlib.print_endline)
```

Значения остаются вне SQL и не являются SQL-литералами: текст диагностики
нельзя подставлять вместо placeholders. `None` в поле `value` означает, что
input не передан; `Some Null` — привязанный SQL `NULL`. Ошибка mapped codec
возвращается как `Statement.Codec_error` с позицией и именем параметра.
Для запроса, который можно вставить в `psql` или SQLite, используйте
`Statement.debug_sql_exn` с `~input`; пример есть в
[руководстве по запросам во время разработки](development_workflow.md).

## Вложенный input и необязательная пагинация PostgreSQL

`Statement.with_parameters` собирает несколько statements с общими параметрами
в одном лексическом блоке. Callback возвращает их кортежем, а каждый statement
компилируется через те же `params`. Все они принимают один тип input; getters
явно выбирают поля вложенного значения.

```ocaml
type filters =
  { min_age : int
  ; city : string
  }

type 'a paged =
  { inner : 'a
  ; limit : int option
  ; offset : int
  }

type input = filters paged

let page, total =
  Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
    let%map.Parameters min_age =
      params.column Person.age_column ~get:(fun input -> input.inner.min_age)
    and city = params.column Person.city_column ~get:(fun input -> input.inner.city)
    and maximum_rows =
      params.non_negative_int_opt ~name:"limit" ~get:(fun input -> input.limit)
    and start_at =
      params.non_negative_int ~name:"offset" ~get:(fun input -> input.offset)
    in
    let filtered =
      Query.(
        from Person.table
        |> where (fun person ->
          Person.age person >=. min_age &&. (Person.city person =. city)))
    in
    let total =
      params.query_one
        Query.(filtered |> select_exactly_one (fun _ -> Projection.expr Expr.count_all))
    in
    let page =
      params.query_many
        Query.(
          filtered
          |> order_by Person.id `Asc
          |> Postgresql.Query.limit_param_opt maximum_rows
          |> offset_param start_at
          |> select Person.projection)
    in
    page, total)
```

Оба statement принимают `input = filters paged`; `total` просто не читает
поля пагинации. `None` в поле `limit` привязывается как SQL `NULL`: PostgreSQL
выполняет `LIMIT NULL OFFSET 20` без верхней границы, пропуская первые 20 строк.
Для nullable `offset` доступны `params.non_negative_int_opt` и
`Postgresql.Query.offset_param_opt`; `None` соответствует нулевому offset.
Отрицательный `Some` отклоняется при привязке. SQLite не принимает `NULL` в
`LIMIT` или `OFFSET`, поэтому эти операции доступны только в
`Postgresql.Query`.

## Рекомендуемая структура модуля

Переиспользуемую операцию рекомендуется оформлять отдельным модулем. Вложенный
`Input` владеет типом входа и его getters, а `statement` явно обозначает
готовую статическую операцию:

```ocaml
module Find_people = struct
  module Input = struct
    type t =
      { name : string
      ; min_id : int64
      ; maximum_rows : int
      }
    [@@deriving fields ~getters]
  end

  let statement =
    Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
      let%map.Parameters name = params.column Person.name_column ~get:Input.name
      and min_id = params.column Person.id_column ~get:Input.min_id
      and maximum_rows =
        params.non_negative_int ~name:"maximum_rows" ~get:Input.maximum_rows
      in
      params.query_many
        Query.(
          from Person.table
          |> where (fun person ->
            Person.name person =. name
            &&. (Person.id person >=. min_id))
          |> limit_param maximum_rows
          |> select Person.projection))
end

let result =
  Typed_sql_caqti_lwt.run
    ~conn
    Find_people.statement
    { Find_people.Input.name = "Ada"
    ; min_id = 1L
    ; maximum_rows = 50
    }
```

Такой layout даёт тип `Find_people.Input.t`, не выпускает сгенерированные имена
в окружающий модуль и оставляет рядом контракт входа и SQL-операцию. Имена
`Input` и `statement` предпочтительнее сокращений `p` и `s`: они остаются
понятными в сигнатурах, сообщениях компилятора и результатах поиска.

Для генерации getters приложение добавляет `ppx_fields_conv` в зависимости и
включает PPX в Dune:

```dune
(preprocess
 (pps ppx_fields_conv))
```

Следующие разделы сравнивают этот рекомендуемый вариант с кортежами и record с
ручными getters на одном десятипараметрическом statement.

## Обычный кортеж

В обычном кортеже позиция каждого из десяти элементов входит в контракт:

```ocaml
type input =
  string * int64 * int64 * string * int * int * string * bool * int * int

let find_people =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let%map.Parameters name =
      params.column Person.name_column
        ~get:(fun (name, _, _, _, _, _, _, _, _, _) -> name)
    and min_id =
      params.column Person.id_column
        ~get:(fun (_, min_id, _, _, _, _, _, _, _, _) -> min_id)
    and max_id =
      params.column Person.id_column
        ~get:(fun (_, _, max_id, _, _, _, _, _, _, _) -> max_id)
    and email =
      params.column Person.email_column
        ~get:(fun (_, _, _, email, _, _, _, _, _, _) -> email)
    and min_age =
      params.column Person.age_column
        ~get:(fun (_, _, _, _, min_age, _, _, _, _, _) -> min_age)
    and max_age =
      params.column Person.age_column
        ~get:(fun (_, _, _, _, _, max_age, _, _, _, _) -> max_age)
    and city =
      params.column Person.city_column
        ~get:(fun (_, _, _, _, _, _, city, _, _, _) -> city)
    and active =
      params.column Person.active_column
        ~get:(fun (_, _, _, _, _, _, _, active, _, _) -> active)
    and maximum_rows =
      params.non_negative_int ~name:"maximum_rows"
        ~get:(fun (_, _, _, _, _, _, _, _, value, _) -> value)
    and start_at =
      params.non_negative_int ~name:"start_at"
        ~get:(fun (_, _, _, _, _, _, _, _, _, value) -> value)
    in
    params.query_many
      (build_query
         ~name ~min_id ~max_id ~email ~min_age ~max_age ~city ~active
         ~maximum_rows ~start_at))

let result =
  Typed_sql_caqti_lwt.run
    ~conn
    find_people
    ("Ada", 1L, 100L, "ada@example.test", 18, 120, "London", true, 50, 0)
```

При десяти значениях позиционный вариант уже трудно читать и менять: добавление
одного элемента требует исправить каждый pattern.

Примеры именованных кортежей доступны в отдельной странице документации для OCaml
5.5 и новее.

## Record

Record требует одно объявление полей, после чего каждый getter использует
обычную projection через точку:

```ocaml
type input =
  { name : string
  ; min_id : int64
  ; max_id : int64
  ; email : string
  ; min_age : int
  ; max_age : int
  ; city : string
  ; active : bool
  ; maximum_rows : int
  ; start_at : int
  }

let find_people =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let%map.Parameters name = params.column Person.name_column ~get:(fun input -> input.name)
    and min_id = params.column Person.id_column ~get:(fun input -> input.min_id)
    and max_id = params.column Person.id_column ~get:(fun input -> input.max_id)
    and email = params.column Person.email_column ~get:(fun input -> input.email)
    and min_age = params.column Person.age_column ~get:(fun input -> input.min_age)
    and max_age = params.column Person.age_column ~get:(fun input -> input.max_age)
    and city = params.column Person.city_column ~get:(fun input -> input.city)
    and active = params.column Person.active_column ~get:(fun input -> input.active)
    and maximum_rows =
      params.non_negative_int ~name:"maximum_rows"
        ~get:(fun input -> input.maximum_rows)
    and start_at =
      params.non_negative_int ~name:"start_at"
        ~get:(fun input -> input.start_at)
    in
    params.query_many
      (build_query
         ~name ~min_id ~max_id ~email ~min_age ~max_age ~city ~active
         ~maximum_rows ~start_at))

let result =
  Typed_sql_caqti_lwt.run
    ~conn
    find_people
    { name = "Ada"
    ; min_id = 1L
    ; max_id = 100L
    ; email = "ada@example.test"
    ; min_age = 18
    ; max_age = 120
    ; city = "London"
    ; active = true
    ; maximum_rows = 50
    ; start_at = 0
    }
```

## Record с getters от ppx_fields_conv

Jane Street
[ppx_fields_conv](https://github.com/janestreet/ppx_fields_conv) умеет
генерировать обычные getter-функции для каждого поля record. Он подключается в
`preprocess` Dune и используется через `@@deriving fields ~getters`:

```ocaml
module Find_people = struct
  module Input = struct
    type t =
      { name : string
      ; min_id : int64
      ; max_id : int64
      ; email : string
      ; min_age : int
      ; max_age : int
      ; city : string
      ; active : bool
      ; maximum_rows : int
      ; start_at : int
      }
    [@@deriving fields ~getters]
  end

  let statement =
    Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
      let%map.Parameters name = params.column Person.name_column ~get:Input.name
      and min_id = params.column Person.id_column ~get:Input.min_id
      and max_id = params.column Person.id_column ~get:Input.max_id
      and email = params.column Person.email_column ~get:Input.email
      and min_age = params.column Person.age_column ~get:Input.min_age
      and max_age = params.column Person.age_column ~get:Input.max_age
      and city = params.column Person.city_column ~get:Input.city
      and active = params.column Person.active_column ~get:Input.active
      and maximum_rows =
        params.non_negative_int ~name:"maximum_rows" ~get:Input.maximum_rows
      and start_at =
        params.non_negative_int ~name:"start_at" ~get:Input.start_at
      in
      params.query_many
        (build_query
           ~name ~min_id ~max_id ~email ~min_age ~max_age ~city ~active
           ~maximum_rows ~start_at))
end

let result =
  Typed_sql_caqti_lwt.run
    ~conn
    Find_people.statement
    { Find_people.Input.name = "Ada"
    ; min_id = 1L
    ; max_id = 100L
    ; email = "ada@example.test"
    ; min_age = 18
    ; max_age = 120
    ; city = "London"
    ; active = true
    ; maximum_rows = 50
    ; start_at = 0
    }
```

Селектор `~getters` генерирует только функции вроде
`Find_people.Input.name : Find_people.Input.t -> string`. Statement не зависит
от first-class field descriptors и не меняет свой API.

При десяти параметрах оба record-варианта сохраняют явные имена и номинальный
тип. Ручные lambdas `fun input -> input.field` проще для небольшого input;
`ppx_fields_conv` убирает их в крупных records. Вложенный `Input` с
`ppx_fields_conv` — рекомендуемый вариант для переиспользуемых и экспортируемых
statements. Именованные кортежи полезны для локальной операции, когда отдельный
record кажется лишним; примеры доступны в странице «Именованные кортежи» на
OCaml 5.5+.
