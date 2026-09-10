open! Base

type t = Ast.command

module Private = struct
  let create command = command
  let ast command = command
end
