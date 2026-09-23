open! Base

type definition_error =
  { dialect : Dialect.t
  ; error : Compile_error.t
  }

exception Definition_error of definition_error

type binding_error =
  { name : string option
  ; message : string
  }

type sql_error =
  | Unsupported_dialect of Dialect.t
  | Dynamic_input_required
  | Invalid_parameter of binding_error
  | Compilation_error of definition_error

type ('input, 'requirements) parameters =
  { expr :
      'value.
      ?name:string
      -> 'value Db_type.t
      -> get:('input -> 'value)
      -> ('value, 'requirements) Expr.t
  ; column :
      'row 'base 'value.
      ?name:string
      -> ('row, 'base, 'value) Column.t
      -> get:('input -> 'value)
      -> ('value, 'requirements) Expr.t
  ; non_negative_int :
      name:string -> get:('input -> int) -> 'requirements Pagination_parameter.t
  }

type 'input slot =
  | Slot :
      { id : int
      ; name : string option
      ; db_type : 'value Db_type.t
      ; get : 'input -> 'value
      ; validate : 'value -> string option
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

type ('input, 'output, +'requirements) t =
  | Dynamic_query :
      { cardinality : ('row, 'output) cardinality
      ; build : 'input -> ('row, 'kind, 'query_cardinality, 'requirements) Result_query.t
      }
      -> ('input, 'output, 'requirements) t
  | Dynamic_command :
      ('input -> 'requirements Command.t)
      -> ('input, Affected_rows.t, 'requirements) t
  | Query :
      { cardinality : ('row, 'output) cardinality
      ; plans : ('input, 'row) query_plan list
      }
      -> ('input, 'output, 'requirements) t
  | Command :
      { plans : 'input command_plan list }
      -> ('input, Affected_rows.t, 'requirements) t
  | Choose :
      { when_ : 'input -> bool
      ; if_true : ('input, 'output, 'requirements) t
      ; if_false : ('input, 'output, 'requirements) t
      }
      -> ('input, 'output, 'requirements) t

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

let make_parameters slots =
  let register ?name ?(validate = fun _ -> None) db_type ~get =
    let id = Atomic.fetch_and_add next_slot 1 in
    let parameter = Ast.Slot { id; db_type = Db_type.Pack db_type } in
    slots := Slot { id; name; db_type; get; validate } :: !slots;
    parameter
  in
  let expr
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
  let column
    : type row base value.
      ?name:string
      -> (row, base, value) Column.t
      -> get:('input -> value)
      -> (value, 'requirements) Expr.t
    =
    fun ?name column ~get -> expr ?name (Column.db_type column) ~get
  in
  let non_negative_int ~name ~get =
    let validate value =
      if value < 0 then
        Some ("must be non-negative, got " ^ Int.to_string value)
      else
        None
    in
    register ~name ~validate Db_type.int ~get |> Pagination_parameter.create
  in
  { expr; column; non_negative_int }
;;

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

let create_query ~dialects ~cardinality build =
  let slots = ref [] in
  let query = build (make_parameters slots) in
  Result.all (List.map dialects ~f:(fun dialect -> compile_query ~dialect slots query))
  |> Result.map ~f:(fun plans -> Query { cardinality; plans })
;;

let create_command ~dialects build =
  let slots = ref [] in
  let command = build (make_parameters slots) in
  Result.all
    (List.map dialects ~f:(fun dialect -> compile_command ~dialect slots command))
  |> Result.map ~f:(fun plans -> Command { plans })
;;

let or_raise = function
  | Ok statement -> statement
  | Error error -> raise (Definition_error error)
;;

module Portable = struct
  let dialects = [ Dialect.Postgresql; Dialect.Sqlite ]
  let query_many build = create_query ~dialects ~cardinality:Many build
  let query_one build = create_query ~dialects ~cardinality:One build
  let query_optional build = create_query ~dialects ~cardinality:Optional build
  let expect_one build = create_query ~dialects ~cardinality:One build
  let expect_optional build = create_query ~dialects ~cardinality:Optional build
  let command build = create_command ~dialects build
  let query_many_exn build = query_many build |> or_raise
  let query_one_exn build = query_one build |> or_raise
  let query_optional_exn build = query_optional build |> or_raise
  let expect_one_exn build = expect_one build |> or_raise
  let expect_optional_exn build = expect_optional build |> or_raise
  let command_exn build = command build |> or_raise
end

module For_dialect = struct
  let query_many ~dialect build =
    create_query ~dialects:[ Dialect.kind dialect ] ~cardinality:Many build
  ;;

  let query_one ~dialect build =
    create_query ~dialects:[ Dialect.kind dialect ] ~cardinality:One build
  ;;

  let query_optional ~dialect build =
    create_query ~dialects:[ Dialect.kind dialect ] ~cardinality:Optional build
  ;;

  let expect_one ~dialect build =
    create_query ~dialects:[ Dialect.kind dialect ] ~cardinality:One build
  ;;

  let expect_optional ~dialect build =
    create_query ~dialects:[ Dialect.kind dialect ] ~cardinality:Optional build
  ;;

  let command ~dialect build = create_command ~dialects:[ Dialect.kind dialect ] build
  let query_many_exn ~dialect build = query_many ~dialect build |> or_raise
  let query_one_exn ~dialect build = query_one ~dialect build |> or_raise
  let query_optional_exn ~dialect build = query_optional ~dialect build |> or_raise
  let expect_one_exn ~dialect build = expect_one ~dialect build |> or_raise
  let expect_optional_exn ~dialect build = expect_optional ~dialect build |> or_raise
  let command_exn ~dialect build = command ~dialect build |> or_raise
end

let choose ~when_ ~if_true ~if_false = Choose { when_; if_true; if_false }

module Dynamic = struct
  module Portable = struct
    let query_many build = Dynamic_query { cardinality = Many; build }
    let query_one build = Dynamic_query { cardinality = One; build }
    let query_optional build = Dynamic_query { cardinality = Optional; build }
    let expect_one build = Dynamic_query { cardinality = One; build }
    let expect_optional build = Dynamic_query { cardinality = Optional; build }
    let command build = Dynamic_command build
  end
end

let same_dialect left right =
  match left, right with
  | Dialect.Postgresql, Dialect.Postgresql | Dialect.Sqlite, Dialect.Sqlite -> true
  | Dialect.Postgresql, Dialect.Sqlite | Dialect.Sqlite, Dialect.Postgresql -> false
;;

let find_query_plan dialect (plans : (_, _) query_plan list) =
  List.find plans ~f:(fun plan -> same_dialect dialect plan.compiled.dialect)
;;

let find_command_plan dialect (plans : _ command_plan list) =
  List.find plans ~f:(fun plan -> same_dialect dialect plan.compiled.dialect)
;;

let find_slot id slots = List.find slots ~f:(fun (Slot slot) -> Int.equal id slot.id)

let bind_parameter input slots = function
  | Ast.Value value -> Ok value
  | Ast.Slot { id; _ } ->
    (match find_slot id slots with
     | None -> Error (Binding { name = None; message = "unknown parameter slot" })
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
  : type input output requirements.
    dialect:Dialect.t
    -> input
    -> (input, output, requirements) t
    -> (output execution, resolve_error) Result.t
  =
  fun ~dialect input statement ->
  match statement with
  | Dynamic_query { cardinality; build } ->
    let open Result.Let_syntax in
    let%bind plan =
      compile_query ~dialect (ref []) (build input)
      |> Result.map_error ~f:(fun error -> Compilation error)
    in
    resolve ~dialect input (Query { cardinality; plans = [ plan ] })
  | Dynamic_command build ->
    let open Result.Let_syntax in
    let%bind plan =
      compile_command ~dialect (ref []) (build input)
      |> Result.map_error ~f:(fun error -> Compilation error)
    in
    resolve ~dialect input (Command { plans = [ plan ] })
  | Choose { when_; if_true; if_false } ->
    resolve
      ~dialect
      input
      (if when_ input then
         if_true
       else
         if_false)
  | Query { cardinality; plans } ->
    (match find_query_plan dialect plans with
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
    (match find_command_plan dialect plans with
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

let sql
  : type input output requirements.
    dialect:Dialect.t
    -> ?input:input
    -> (input, output, requirements) t
    -> (string, sql_error) Result.t
  =
  fun ~dialect ?input statement ->
  match input with
  | Some input ->
    (match resolve ~dialect input statement with
     | Ok (Query_execution execution) -> Ok (Compiled_query.sql execution.compiled)
     | Ok (Command_execution execution) -> Ok (Compiled_command.sql execution)
     | Error Dialect_mismatch -> Error (Unsupported_dialect dialect)
     | Error (Binding error) -> Error (Invalid_parameter error)
     | Error (Compilation error) -> Error (Compilation_error error))
  | None ->
    (match statement with
     | Query { plans; _ } ->
       (match find_query_plan dialect plans with
        | None -> Error (Unsupported_dialect dialect)
        | Some plan ->
          Ok (Template.to_sql ~dialect:plan.compiled.dialect plan.compiled.template))
     | Command { plans } ->
       (match find_command_plan dialect plans with
        | None -> Error (Unsupported_dialect dialect)
        | Some plan ->
          Ok (Template.to_sql ~dialect:plan.compiled.dialect plan.compiled.template))
     | Dynamic_query _ | Dynamic_command _ | Choose _ -> Error Dynamic_input_required)
;;

let sql_exn ~dialect ?input statement =
  match sql ~dialect ?input statement with
  | Ok sql -> sql
  | Error (Compilation_error error) -> raise (Definition_error error)
  | Error (Unsupported_dialect _) ->
    failwith "statement does not support the selected dialect"
  | Error Dynamic_input_required -> failwith "statement SQL shape requires input"
  | Error (Invalid_parameter error) ->
    let prefix = Option.value_map error.name ~default:"parameter" ~f:(fun name -> name) in
    failwith (prefix ^ " " ^ error.message)
;;
