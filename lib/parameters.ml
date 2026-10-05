open! Base

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
