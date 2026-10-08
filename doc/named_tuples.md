# Именованные кортежи

Этот документ содержит примеры синтаксиса именованных кортежей OCaml 5.5+.

## Кортеж с метками и объявленным типом

Labeled tuple сохраняет имена. Известный тип позволяет каждому getter читать
только своё поле через partial pattern `..`:

```ocaml
type input =
  name:string
  * min_id:int64
  * max_id:int64
  * email:string
  * min_age:int
  * max_age:int
  * city:string
  * active:bool
  * maximum_rows:int
  * start_at:int

let name ((~name, ..) : input) = name
let min_id ((~min_id, ..) : input) = min_id
let max_id ((~max_id, ..) : input) = max_id
let email ((~email, ..) : input) = email
let min_age ((~min_age, ..) : input) = min_age
let max_age ((~max_age, ..) : input) = max_age
let city ((~city, ..) : input) = city
let active ((~active, ..) : input) = active
let maximum_rows ((~maximum_rows, ..) : input) = maximum_rows
let start_at ((~start_at, ..) : input) = start_at

let find_people =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let%map.Parameters name = params.column Person.name_column ~get:name
    and min_id = params.column Person.id_column ~get:min_id
    and max_id = params.column Person.id_column ~get:max_id
    and email = params.column Person.email_column ~get:email
    and min_age = params.column Person.age_column ~get:min_age
    and max_age = params.column Person.age_column ~get:max_age
    and city = params.column Person.city_column ~get:city
    and active = params.column Person.active_column ~get:active
    and maximum_rows =
      params.non_negative_int ~name:"maximum_rows" ~get:maximum_rows
    and start_at = params.non_negative_int ~name:"start_at" ~get:start_at in
    params.query_many
      (build_query
         ~name ~min_id ~max_id ~email ~min_age ~max_age ~city ~active
         ~maximum_rows ~start_at))

let result =
  Typed_sql_caqti_lwt.run
    ~conn
    find_people
    ( ~name:"Ada"
    , ~min_id:1L
    , ~max_id:100L
    , ~email:"ada@example.test"
    , ~min_age:18
    , ~max_age:120
    , ~city:"London"
    , ~active:true
    , ~maximum_rows:50
    , ~start_at:0 )
```

## Кортеж с метками без объявления типа

OCaml может вывести тот же десятиэлементный тип без `type input`. Первый getter
должен задать полную форму кортежа; после этого остальные getters используют
partial patterns:

```ocaml
let find_people =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let%map.Parameters name =
      params.column Person.name_column
        ~get:
          (fun
            ( ~name
            , ~min_id:_
            , ~max_id:_
            , ~email:_
            , ~min_age:_
            , ~max_age:_
            , ~city:_
            , ~active:_
            , ~maximum_rows:_
            , ~start_at:_ )
          -> name)
    and min_id =
      params.column Person.id_column ~get:(fun (~min_id, ..) -> min_id)
    and max_id =
      params.column Person.id_column ~get:(fun (~max_id, ..) -> max_id)
    and email =
      params.column Person.email_column ~get:(fun (~email, ..) -> email)
    and min_age =
      params.column Person.age_column ~get:(fun (~min_age, ..) -> min_age)
    and max_age =
      params.column Person.age_column ~get:(fun (~max_age, ..) -> max_age)
    and city =
      params.column Person.city_column ~get:(fun (~city, ..) -> city)
    and active =
      params.column Person.active_column ~get:(fun (~active, ..) -> active)
    and maximum_rows =
      params.non_negative_int ~name:"maximum_rows"
        ~get:(fun (~maximum_rows, ..) -> maximum_rows)
    and start_at =
      params.non_negative_int ~name:"start_at"
        ~get:(fun (~start_at, ..) -> start_at)
    in
    params.query_many
      (build_query
         ~name ~min_id ~max_id ~email ~min_age ~max_age ~city ~active
         ~maximum_rows ~start_at))
```

Если все getters используют `..` и тип не указан снаружи, компилятор не может
восстановить пропущенные поля. Поэтому вариант без объявления типа всё равно
требует один полный десятиэлементный pattern.
