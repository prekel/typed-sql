open! Base

let of_type_name (target : Sql_query.type_name) =
  let error message = Error { Sql_query.offset = 0; message } in
  let precision value = Int.min value 6 in
  if
    List.exists target.modifiers ~f:(fun value ->
      Int.(value < -2147483648 || value > 2147483647))
  then
    error "type modifiers require signed 32-bit integers"
  else if
    List.length target.names > 1
    && (not (String.equal (List.hd_exn target.names) "pg_catalog"))
    && not (List.is_empty target.modifiers)
  then
    error "custom type modifiers require unsupported catalog metadata"
  else (
    match
      List.last_exn target.names, target.modifiers
    with
    | ("varchar" | "bpchar"), [ length ] when Int.(length > 0 && length <= 10485760) ->
      Ok (length + 4)
    | "numeric", [ p ] when Int.(p > 0 && p <= 1000) -> Ok ((p lsl 16) + 4)
    | "numeric", [ p; s ] when Int.(p > 0 && p <= 1000 && s >= -1000 && s <= 1000) ->
      Ok ((p lsl 16) + (s land 0x7ff) + 4)
    | ("time" | "timestamp" | "timestamptz"), [ p ] when Int.(p >= 0) -> Ok (precision p)
    | "interval", values ->
      let fields =
        [ "year", 4; "month", 2; "day", 8; "hour", 1024; "minute", 2048; "second", 4096 ]
      in
      let range =
        match target.interval_fields with
        | [] -> Some 0x7fff
        | [ field ] -> List.Assoc.find fields field ~equal:String.equal
        | [ first; last ] ->
          let valid =
            List.mem
              [ "year", "month"
              ; "day", "hour"
              ; "day", "minute"
              ; "day", "second"
              ; "hour", "minute"
              ; "hour", "second"
              ; "minute", "second"
              ]
              (first, last)
              ~equal:(fun (a, b) (c, d) -> String.equal a c && String.equal b d)
          in
          if not valid then
            None
          else (
            let selected =
              List.drop_while fields ~f:(fun (name, _) -> not (String.equal name first))
            in
            let rec mask acc = function
              | [] -> acc
              | (name, value) :: rest ->
                let acc = acc lor value in
                if String.equal name last then
                  acc
                else
                  mask acc rest
            in
            Some (mask 0 selected))
        | _ -> None
      in
      (match range, values with
       | Some _, [] when List.is_empty target.interval_fields -> Ok (-1)
       | Some mask, [] -> Ok ((mask lsl 16) lor 0xffff)
       | Some mask, [ p ] when Int.(p >= 0) -> Ok ((mask lsl 16) lor precision p)
       | _ -> error "invalid interval type modifier")
    | _, [] -> Ok (-1)
    | _ -> error "invalid or unsupported PostgreSQL type modifiers")
;;
