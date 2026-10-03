open! Base

type definition_error =
  { dialect : Dialect.t
  ; error : Compile_error.t
  }

exception Definition_error of definition_error

let () =
  Stdlib.Printexc.register_printer (function
    | Definition_error { dialect; error } ->
      Some
        (Stdlib.Printf.sprintf
           "Statement.Definition_error (%s): %s"
           (Dialect.to_string dialect)
           (Compile_error.to_string error))
    | _ -> None)
;;

module Parameters = struct
  type ('input, 'requirements, 'value) t = Value of 'value

  let unwrap (Value value) = value

  include Applicative.Make3_using_map2 (struct
      type nonrec ('value, 'input, 'requirements) t = ('input, 'requirements, 'value) t

      let return : type value input requirements. value -> (value, input, requirements) t =
        fun value -> Value value
      ;;

      let map
        : type value input requirements result.
          (value, input, requirements) t
          -> f:(value -> result)
          -> (result, input, requirements) t
        =
        fun (Value value) ~f -> Value (f value)
      ;;

      let map2
        : type input requirements left right result.
          (left, input, requirements) t
          -> (right, input, requirements) t
          -> f:(left -> right -> result)
          -> (result, input, requirements) t
        =
        fun (Value left) (Value right) ~f -> Value (f left right)
      ;;

      let map = `Custom map
    end)

  module Let_syntax = struct
    let return = return

    include Applicative_infix

    let ( let+ ) value f = map value ~f
    let ( and+ ) = both

    module Let_syntax = struct
      let return = return
      let map = map
      let both = both
      let ( let+ ) value f = map value ~f
      let ( and+ ) = both

      module Open_on_rhs = struct end
    end
  end
end

type binding_error_message =
  | Unknown_parameter_slot
  | Negative_pagination_value of int
[@@deriving sexp_of]

type binding_error =
  { name : string option
  ; message : binding_error_message
  }
[@@deriving sexp_of]

type sql_error =
  | Unsupported_dialect of Dialect.t
  | Dynamic_input_required
  | Invalid_parameter of binding_error
  | Compilation_error of definition_error

exception Sql_error of sql_error

let () =
  let binding_error_message_to_string = function
    | Unknown_parameter_slot -> "unknown parameter slot"
    | Negative_pagination_value value ->
      Stdlib.Printf.sprintf "must be non-negative, got %d" value
  in
  Stdlib.Printexc.register_printer (function
    | Sql_error (Unsupported_dialect dialect) ->
      Some
        (Stdlib.Printf.sprintf
           "Statement.Sql_error (unsupported dialect: %s)"
           (Dialect.to_string dialect))
    | Sql_error Dynamic_input_required ->
      Some "Statement.Sql_error (SQL shape requires input)"
    | Sql_error (Invalid_parameter { name; message }) ->
      let name = Option.value name ~default:"parameter" in
      Some
        (Stdlib.Printf.sprintf
           "Statement.Sql_error (%s: %s)"
           name
           (binding_error_message_to_string message))
    | Sql_error (Compilation_error { dialect; error }) ->
      Some
        (Stdlib.Printf.sprintf
           "Statement.Sql_error (%s): %s"
           (Dialect.to_string dialect)
           (Compile_error.to_string error))
    | _ -> None)
;;

type 'input slot =
  | Slot :
      { id : int
      ; name : string option
      ; db_type : 'value Db_type.t
      ; get : 'input -> 'value
      ; validate : 'value -> binding_error_message option
      }
      -> 'input slot

type (_, _) cardinality =
  | Many : ('row, 'row list) cardinality
  | One : ('row, 'row) cardinality
  | Optional : ('row, 'row option) cardinality

type ('input, 'row) query_plan =
  { compiled : 'row Compiler.query_plan
  ; slots : 'input slot list
  }

type 'input command_plan =
  { compiled : Compiler.command_plan
  ; slots : 'input slot list
  }

type ('plan, 'supports) plan_set =
  | Postgresql_plan : 'plan -> ('plan, [ `Postgresql ]) plan_set
  | Sqlite_plan : 'plan -> ('plan, [ `Sqlite ]) plan_set
  | Portable_plans :
      { postgresql_plan : 'plan
      ; sqlite_plan : 'plan
      }
      -> ('plan, Dialect.both) plan_set

type ('input, 'output, 'supports) t =
  | Dynamic_query :
      { cardinality : ('row, 'output) cardinality
      ; dialect : ('requirements, 'supports) Dialect.supports
      ; build : 'input -> ('row, 'kind, 'query_cardinality, 'requirements) Result_query.t
      }
      -> ('input, 'output, 'supports) t
  | Dynamic_command :
      { dialect : ('requirements, 'supports) Dialect.supports
      ; build : 'input -> 'requirements Command.t
      }
      -> ('input, Affected_rows.t, 'supports) t
  | Query :
      { cardinality : ('row, 'output) cardinality
      ; plans : (('input, 'row) query_plan, 'supports) plan_set
      }
      -> ('input, 'output, 'supports) t
  | Command :
      { plans : ('input command_plan, 'supports) plan_set }
      -> ('input, Affected_rows.t, 'supports) t
  | Choose :
      { when_ : 'input -> bool
      ; if_true : ('input, 'output, 'supports) t
      ; if_false : ('input, 'output, 'supports) t
      }
      -> ('input, 'output, 'supports) t
  | Choose_dialect :
      { postgresql : ('input, 'output, [ `Postgresql ]) t
      ; sqlite : ('input, 'output, [ `Sqlite ]) t
      }
      -> ('input, 'output, Dialect.both) t

and ('input, 'requirements, 'supports) parameters =
  { expr :
      'value.
      ?name:string
      -> 'value Db_type.t
      -> get:('input -> 'value)
      -> ('input, 'requirements, ('value, 'requirements) Expr.t) Parameters.t
  ; optional_expr :
      'value.
      ?name:string
      -> 'value Db_type.t
      -> get:('input -> 'value option)
      -> ( 'input
           , 'requirements
           , ('value, 'requirements) Optional_parameter.t )
           Parameters.t
  ; column :
      'row 'base 'value.
      ?name:string
      -> ('row, 'base, 'value) Column.t
      -> get:('input -> 'value)
      -> ('input, 'requirements, ('value, 'requirements) Expr.t) Parameters.t
  ; non_negative_int :
      name:string
      -> get:('input -> int)
      -> ('input, 'requirements, 'requirements Pagination_parameter.t) Parameters.t
  ; non_negative_int_opt :
      name:string
      -> get:('input -> int option)
      -> ('input, 'requirements, 'requirements Pagination_parameter.optional) Parameters.t
  ; query_many :
      'row 'kind 'cardinality.
      ('row, 'kind, 'cardinality, 'requirements) Result_query.t
      -> ('input, 'row list, 'supports) t
  ; query_one :
      'row 'kind 'cardinality.
      ('row, 'kind, ([> `Exactly_one ] as 'cardinality), 'requirements) Result_query.t
      -> ('input, 'row, 'supports) t
  ; query_optional :
      'row 'kind 'cardinality.
      ('row, 'kind, ([> `At_most_one ] as 'cardinality), 'requirements) Result_query.t
      -> ('input, 'row option, 'supports) t
  ; expect_one :
      'row 'kind 'cardinality.
      ('row, 'kind, 'cardinality, 'requirements) Result_query.t
      -> ('input, 'row, 'supports) t
  ; expect_optional :
      'row 'kind 'cardinality.
      ('row, 'kind, 'cardinality, 'requirements) Result_query.t
      -> ('input, 'row option, 'supports) t
  ; command : 'requirements Command.t -> ('input, Affected_rows.t, 'supports) t
  }

type 'output execution =
  | Query_execution :
      { cardinality : ('row, 'output) cardinality
      ; compiled : 'row Compiled_query.t
      }
      -> 'output execution
  | Command_execution : Compiled_command.t -> Affected_rows.t execution

type resolve_error =
  | Dialect_mismatch
  | Binding of binding_error
  | Compilation of definition_error

let next_slot = Atomic.make 0
let definition_error dialect error = { dialect; error }

let compile_query ~dialect slots query =
  Compiler.compile_query_plan ~dialect query
  |> Result.map ~f:(fun compiled ->
    ({ compiled; slots = List.rev !slots } : (_, _) query_plan))
  |> Result.map_error ~f:(definition_error dialect)
;;

let compile_command ~dialect slots command =
  Compiler.compile_command_plan ~dialect command
  |> Result.map ~f:(fun compiled ->
    ({ compiled; slots = List.rev !slots } : _ command_plan))
  |> Result.map_error ~f:(definition_error dialect)
;;

let or_raise = function
  | Ok statement -> statement
  | Error error -> raise (Definition_error error)
;;

let compile_with_witness
  : type requirements supports value error.
    (requirements, supports) Dialect.supports
    -> (Dialect.t -> (value, error) Result.t)
    -> ((value, supports) plan_set, error) Result.t
  =
  fun witness compile ->
  match witness with
  | Dialect.Portable ->
    let open Result.Let_syntax in
    let%bind postgresql_plan = compile Dialect.Postgresql in
    let%map sqlite_plan = compile Dialect.Sqlite in
    Portable_plans { postgresql_plan; sqlite_plan }
  | Dialect.Concrete_postgresql ->
    Result.map (compile Dialect.Postgresql) ~f:(fun plan -> Postgresql_plan plan)
  | Dialect.Concrete_sqlite ->
    Result.map (compile Dialect.Sqlite) ~f:(fun plan -> Sqlite_plan plan)
;;

let compile_scoped_query ~dialect ~cardinality slots query =
  compile_with_witness dialect (fun dialect -> compile_query ~dialect slots query)
  |> Result.map ~f:(fun plans -> Query { cardinality; plans })
;;

let compile_scoped_command ~dialect slots command =
  compile_with_witness dialect (fun dialect -> compile_command ~dialect slots command)
  |> Result.map ~f:(fun plans -> Command { plans })
;;

let make_parameters ~dialect slots =
  let register ?name ?(validate = fun _ -> None) db_type ~get =
    let id = Atomic.fetch_and_add next_slot 1 in
    let parameter = Ast.Slot { id; db_type = Db_type.Pack db_type } in
    slots := Slot { id; name; db_type; get; validate } :: !slots;
    parameter
  in
  let make_expr
    : type value.
      ?name:string
      -> value Db_type.t
      -> get:('input -> value)
      -> (value, 'requirements) Expr.t
    =
    fun ?name db_type ~get ->
    let parameter = register ?name db_type ~get in
    Expr.create (Ast.Param parameter) db_type
  in
  let expr ?name db_type ~get = Parameters.return (make_expr ?name db_type ~get) in
  let make_optional_expr ?name db_type ~get =
    let nullable_expr = make_expr ?name (Db_type.option db_type) ~get in
    let value_expr = Expr.create (Expr.node nullable_expr) db_type in
    Optional_parameter.create nullable_expr value_expr
  in
  let optional_expr ?name db_type ~get =
    Parameters.return (make_optional_expr ?name db_type ~get)
  in
  let column
    : type row base value.
      ?name:string
      -> (row, base, value) Column.t
      -> get:('input -> value)
      -> ('input, 'requirements, (value, 'requirements) Expr.t) Parameters.t
    =
    fun ?name column ~get ->
    Parameters.return (make_expr ?name (Column.db_type column) ~get)
  in
  let make_non_negative_int ~name ~get =
    let validate value =
      if value < 0 then
        Some (Negative_pagination_value value)
      else
        None
    in
    register ~name ~validate Db_type.int ~get |> Pagination_parameter.create
  in
  let non_negative_int ~name ~get =
    Parameters.return (make_non_negative_int ~name ~get)
  in
  let make_non_negative_int_opt ~name ~get =
    let validate = function
      | Some value when value < 0 -> Some (Negative_pagination_value value)
      | None | Some _ -> None
    in
    register ~name ~validate (Db_type.option Db_type.int) ~get
    |> Pagination_parameter.create_optional
  in
  let non_negative_int_opt ~name ~get =
    Parameters.return (make_non_negative_int_opt ~name ~get)
  in
  let query_many query =
    compile_scoped_query ~dialect ~cardinality:Many slots query |> or_raise
  in
  let query_one query =
    compile_scoped_query ~dialect ~cardinality:One slots query |> or_raise
  in
  let query_optional query =
    compile_scoped_query ~dialect ~cardinality:Optional slots query |> or_raise
  in
  let expect_one query =
    compile_scoped_query ~dialect ~cardinality:One slots query |> or_raise
  in
  let expect_optional query =
    compile_scoped_query ~dialect ~cardinality:Optional slots query |> or_raise
  in
  let command command = compile_scoped_command ~dialect slots command |> or_raise in
  { expr
  ; optional_expr
  ; column
  ; non_negative_int
  ; non_negative_int_opt
  ; query_many
  ; query_one
  ; query_optional
  ; expect_one
  ; expect_optional
  ; command
  }
;;

let with_parameters ~dialect build =
  Parameters.unwrap (build ~params:(make_parameters ~dialect (ref [])))
;;

let no_parameters
  : type requirements supports.
    dialect:(requirements, supports) Dialect.supports
    -> (unit, requirements, supports) parameters
  =
  fun ~dialect -> make_parameters ~dialect (ref [])
;;

let query_many ~dialect query = (no_parameters ~dialect).query_many query
let query_one ~dialect query = (no_parameters ~dialect).query_one query
let query_optional ~dialect query = (no_parameters ~dialect).query_optional query
let expect_one ~dialect query = (no_parameters ~dialect).expect_one query
let expect_optional ~dialect query = (no_parameters ~dialect).expect_optional query
let command ~dialect statement = (no_parameters ~dialect).command statement
let choose ~when_ ~if_true ~if_false = Choose { when_; if_true; if_false }

let choose_dialect
  : type input output.
    postgresql:(input, output, [ `Postgresql ]) t
    -> sqlite:(input, output, [ `Sqlite ]) t
    -> (input, output, Dialect.both) t
  =
  fun ~postgresql ~sqlite -> Choose_dialect { postgresql; sqlite }
;;

module Dynamic = struct
  let query_many ~dialect build = Dynamic_query { cardinality = Many; dialect; build }
  let query_one ~dialect build = Dynamic_query { cardinality = One; dialect; build }

  let query_optional ~dialect build =
    Dynamic_query { cardinality = Optional; dialect; build }
  ;;

  let expect_one ~dialect build = Dynamic_query { cardinality = One; dialect; build }

  let expect_optional ~dialect build =
    Dynamic_query { cardinality = Optional; dialect; build }
  ;;

  let command ~dialect build = Dynamic_command { dialect; build }
end

let same_dialect left right =
  match left, right with
  | Dialect.Postgresql, Dialect.Postgresql | Dialect.Sqlite, Dialect.Sqlite -> true
  | Dialect.Postgresql, Dialect.Sqlite | Dialect.Sqlite, Dialect.Postgresql -> false
;;

let supports_dialect
  : type requirements supports.
    (requirements, supports) Dialect.supports -> Dialect.t -> bool
  =
  fun witness dialect ->
  match witness with
  | Dialect.Portable -> true
  | Dialect.Concrete_postgresql -> same_dialect Dialect.Postgresql dialect
  | Dialect.Concrete_sqlite -> same_dialect Dialect.Sqlite dialect
;;

let find_plan : type plan supports. Dialect.t -> (plan, supports) plan_set -> plan option =
  fun dialect -> function
  | Portable_plans { postgresql_plan; sqlite_plan } ->
    Some
      (match dialect with
       | Dialect.Postgresql -> postgresql_plan
       | Dialect.Sqlite -> sqlite_plan)
  | Postgresql_plan plan ->
    (match dialect with
     | Dialect.Postgresql -> Some plan
     | Dialect.Sqlite -> None)
  | Sqlite_plan plan ->
    (match dialect with
     | Dialect.Postgresql -> None
     | Dialect.Sqlite -> Some plan)
;;

let select_plan
  : type plan supports. supports Dialect.Selected.t -> (plan, supports) plan_set -> plan
  =
  fun dialect plans ->
  match plans, dialect with
  | Portable_plans { postgresql_plan; _ }, Dialect.Selected.Postgresql -> postgresql_plan
  | Portable_plans { sqlite_plan; _ }, Dialect.Selected.Sqlite -> sqlite_plan
  | Postgresql_plan plan, Dialect.Selected.Postgresql -> plan
  | Sqlite_plan plan, Dialect.Selected.Sqlite -> plan
;;

let find_slot id slots = List.find slots ~f:(fun (Slot slot) -> Int.equal id slot.id)

let bind_parameter input slots = function
  | Ast.Value value -> Ok value
  | Ast.Slot { id; _ } ->
    (match find_slot id slots with
     | None -> Error (Binding { name = None; message = Unknown_parameter_slot })
     | Some (Slot slot) ->
       let value = slot.get input in
       (match slot.validate value with
        | None -> Ok (Db_type.Value (slot.db_type, value))
        | Some message -> Error (Binding { name = slot.name; message })))
;;

let bind_parameters input slots parameters =
  List.map parameters ~f:(bind_parameter input slots) |> Result.all
;;

let rec resolve
  : type input output supports.
    dialect:Dialect.t
    -> input
    -> (input, output, supports) t
    -> (output execution, resolve_error) Result.t
  =
  fun ~dialect input statement ->
  match statement with
  | Dynamic_query { cardinality; dialect = witness; build } ->
    let open Result.Let_syntax in
    let%bind () =
      if supports_dialect witness dialect then
        Ok ()
      else
        Error Dialect_mismatch
    in
    let%bind plan =
      compile_query ~dialect (ref []) (build input)
      |> Result.map_error ~f:(fun error -> Compilation error)
    in
    (match dialect with
     | Dialect.Postgresql ->
       resolve ~dialect input (Query { cardinality; plans = Postgresql_plan plan })
     | Dialect.Sqlite ->
       resolve ~dialect input (Query { cardinality; plans = Sqlite_plan plan }))
  | Dynamic_command { dialect = witness; build } ->
    let open Result.Let_syntax in
    let%bind () =
      if supports_dialect witness dialect then
        Ok ()
      else
        Error Dialect_mismatch
    in
    let%bind plan =
      compile_command ~dialect (ref []) (build input)
      |> Result.map_error ~f:(fun error -> Compilation error)
    in
    (match dialect with
     | Dialect.Postgresql ->
       resolve ~dialect input (Command { plans = Postgresql_plan plan })
     | Dialect.Sqlite -> resolve ~dialect input (Command { plans = Sqlite_plan plan }))
  | Choose { when_; if_true; if_false } ->
    resolve
      ~dialect
      input
      (if when_ input then
         if_true
       else
         if_false)
  | Choose_dialect { postgresql; sqlite } ->
    (match dialect with
     | Dialect.Postgresql -> resolve ~dialect input postgresql
     | Dialect.Sqlite -> resolve ~dialect input sqlite)
  | Query { cardinality; plans } ->
    (match find_plan dialect plans with
     | None -> Error Dialect_mismatch
     | Some plan ->
       Result.map
         (bind_parameters input plan.slots plan.compiled.parameters)
         ~f:(fun parameters ->
           let compiled =
             Compiled_query.create
               ~dialect:plan.compiled.dialect
               ~template:plan.compiled.template
               ~parameters
               ~projection:plan.compiled.projection
               ~shape:plan.compiled.shape
           in
           Query_execution { cardinality; compiled }))
  | Command { plans } ->
    (match find_plan dialect plans with
     | None -> Error Dialect_mismatch
     | Some plan ->
       Result.map
         (bind_parameters input plan.slots plan.compiled.parameters)
         ~f:(fun parameters ->
           Compiled_command.create
             ~dialect:plan.compiled.dialect
             ~template:plan.compiled.template
             ~parameters
             ~shape:plan.compiled.shape
           |> fun compiled -> Command_execution compiled))
;;

let rec sql_without_input
  : type input output supports.
    dialect:supports Dialect.Selected.t
    -> (input, output, supports) t
    -> (string, sql_error) Result.t
  =
  fun ~dialect statement ->
  match statement with
  | Query { plans; _ } ->
    let plan = select_plan dialect plans in
    Ok (Template.to_sql ~dialect:plan.compiled.dialect plan.compiled.template)
  | Command { plans } ->
    let plan = select_plan dialect plans in
    Ok (Template.to_sql ~dialect:plan.compiled.dialect plan.compiled.template)
  | Choose_dialect { postgresql; sqlite } ->
    (match dialect with
     | Dialect.Selected.Postgresql ->
       sql_without_input ~dialect:Dialect.Selected.postgresql postgresql
     | Dialect.Selected.Sqlite ->
       sql_without_input ~dialect:Dialect.Selected.sqlite sqlite)
  | Dynamic_query _ | Dynamic_command _ -> Error Dynamic_input_required
  | Choose _ -> Error Dynamic_input_required
;;

let sql
  : type input output supports.
    dialect:supports Dialect.Selected.t
    -> ?input:input
    -> (input, output, supports) t
    -> (string, sql_error) Result.t
  =
  fun ~dialect ?input statement ->
  let concrete_dialect = Dialect.selected_dialect dialect in
  match input with
  | Some input ->
    (match resolve ~dialect:concrete_dialect input statement with
     | Ok (Query_execution execution) -> Ok (Compiled_query.sql execution.compiled)
     | Ok (Command_execution execution) -> Ok (Compiled_command.sql execution)
     | Error Dialect_mismatch -> Error (Unsupported_dialect concrete_dialect)
     | Error (Binding error) -> Error (Invalid_parameter error)
     | Error (Compilation error) -> Error (Compilation_error error))
  | None -> sql_without_input ~dialect statement
;;

let sql_exn ~dialect ?input statement =
  match sql ~dialect ?input statement with
  | Ok sql -> sql
  | Error (Compilation_error error) -> raise (Definition_error error)
  | Error error -> raise (Sql_error error)
;;
