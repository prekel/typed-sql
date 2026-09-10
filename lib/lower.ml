open! Base

type result_query = Ast.result_query
type command = Ast.command

let result_query ~dialect:_ query = Ok query
let command ~dialect:_ command = Ok command
let result_query_ast query = query
let command_ast command = command
