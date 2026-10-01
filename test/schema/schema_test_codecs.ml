open! Base
open Typed_sql

module Local_float = struct
  type t = float

  let date = Date.of_ymd_exn ~year:1970 ~month:1 ~day:1

  let db_type =
    Db_type.map
      ~name:"local seconds within 1970-01-01"
      ~encode:(fun value ->
        if (not (Float.is_finite value)) || Float.(value < 0. || value >= 86_400.) then
          Error "seconds outside fixture day"
        else (
          let whole = Float.to_int value in
          let microsecond = Float.to_int ((value -. Float.of_int whole) *. 1_000_000.) in
          Local_timestamp.create
            ~date
            ~hour:(whole / 3_600)
            ~minute:(whole % 3_600 / 60)
            ~second:(whole % 60)
            ~microsecond))
      ~decode:(fun value ->
        if not (Date.equal (Local_timestamp.date value) date) then
          Error "timestamp outside fixture day"
        else
          Ok
            (Float.of_int
               ((Local_timestamp.hour value * 3_600)
                + (Local_timestamp.minute value * 60)
                + Local_timestamp.second value)
             +. (Float.of_int (Local_timestamp.microsecond value) /. 1_000_000.)))
      Db_type.Postgresql.local_timestamp
  ;;
end

module Small_int = struct
  type t = Small of int

  let db_type =
    Db_type.map
      ~name:"small application integer"
      ~encode:(fun (Small value) ->
        if Int.(value >= 0 && value <= 255) then
          Ok value
        else
          Error "outside 0..255")
      ~decode:(fun value ->
        if Int.(value >= 0 && value <= 255) then
          Ok (Small value)
        else
          Error "outside 0..255")
      Db_type.int
  ;;
end

module Inet = struct
  type t = Ipaddr.Prefix.t

  let db_type =
    Db_type.map
      ~name:"inet prefix"
      ~encode:(fun value -> Ok (Ipaddr.Prefix.to_string value))
      ~decode:(fun value ->
        match Ipaddr.Prefix.of_string value with
        | Ok value -> Ok value
        | Error (`Msg message) -> Error message)
      (Db_type.Postgresql.named
         ~schema:(Identifier.of_string_exn "pg_catalog")
         ~name:(Identifier.of_string_exn "inet")
         Db_type.text)
  ;;
end

module Rational = struct
  type t = Q.t

  let db_type =
    Db_type.map
      ~name:"rational fixture"
      ~encode:(fun value -> Ok (Q.to_string value))
      ~decode:(fun value ->
        try Ok (Q.of_string value) with
        | _ -> Error "invalid rational fixture")
      (Db_type.Postgresql.named
         ~schema:(Identifier.of_string_exn "public")
         ~name:(Identifier.of_string_exn "rational")
         Db_type.text)
  ;;
end

module Geometry = struct
  type t = float * float

  let db_type =
    Db_type.map
      ~name:"geometry point fixture"
      ~encode:(fun (x, y) -> Ok (Stdlib.Printf.sprintf "POINT(%g %g)" x y))
      ~decode:(fun value ->
        try Ok (Stdlib.Scanf.sscanf value "POINT(%f %f)" (fun x y -> x, y)) with
        | _ -> Error "invalid geometry point fixture")
      (Db_type.Postgresql.named
         ~schema:(Identifier.of_string_exn "public")
         ~name:(Identifier.of_string_exn "geometry")
         Db_type.text)
  ;;
end
