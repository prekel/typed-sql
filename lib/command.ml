open! Base

type +'requirements t = Ast.command_statement

let create command = Ast.Structured_command command
let raw command = Ast.Raw_command command
let ast command = command
