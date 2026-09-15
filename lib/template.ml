open! Base

type t =
  | Empty
  | Text of string
  | Param of int
  | Break of string
  | Concat of t list
  | Nest of t

let indentation = 2

let concat = function
  | [] -> Empty
  | [ template ] -> template
  | templates -> Concat templates
;;

let of_parts = concat
let indentation_text width = Stdlib.Format.asprintf "%*s" width ""

let rec fold template ~indent ~init ~text ~param ~break =
  match template with
  | Empty -> init
  | Text value -> text init value
  | Param index -> param init index
  | Break flat -> break init ~indent flat
  | Concat templates ->
    List.fold templates ~init ~f:(fun init template ->
      fold template ~indent ~init ~text ~param ~break)
  | Nest nested -> fold nested ~indent:(indent + indentation) ~init ~text ~param ~break
;;

let map template ~text ~param =
  fold
    template
    ~indent:0
    ~init:[]
    ~text:(fun fragments value -> text value :: fragments)
    ~param:(fun fragments index -> param index :: fragments)
    ~break:(fun fragments ~indent _ ->
      let fragments = text "\n" :: fragments in
      if Int.equal indent 0 then
        fragments
      else
        text (indentation_text indent) :: fragments)
  |> List.rev
;;

let pp_with_param ~param formatter template =
  fold
    template
    ~indent:0
    ~init:()
    ~text:(fun () value -> Stdlib.Format.pp_print_string formatter value)
    ~param:(fun () index -> param formatter index)
    ~break:(fun () ~indent _ ->
      Stdlib.Format.pp_print_char formatter '\n';
      Stdlib.Format.fprintf formatter "%*s" indent "")
;;

let pp ~dialect formatter template =
  pp_with_param
    ~param:(fun formatter index ->
      match dialect with
      | Dialect.Postgresql -> Stdlib.Format.fprintf formatter "$%d" (index + 1)
      | Dialect.Sqlite -> Stdlib.Format.fprintf formatter "?%d" (index + 1))
    formatter
    template
;;

let to_sql ~dialect template = Stdlib.Format.asprintf "%a" (pp ~dialect) template

let pp_shape formatter template =
  fold
    template
    ~indent:0
    ~init:()
    ~text:(fun () value -> Stdlib.Format.pp_print_string formatter value)
    ~param:(fun () index -> Stdlib.Format.fprintf formatter "${%d}" index)
    ~break:(fun () ~indent:_ flat -> Stdlib.Format.pp_print_string formatter flat)
;;

let shape_string template = Stdlib.Format.asprintf "%a" pp_shape template
