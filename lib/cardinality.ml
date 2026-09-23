open! Base

type many = [ `Many ]
type at_most_one = [ `At_most_one ]

type exactly_one =
  [ `At_most_one
  | `Exactly_one
  ]
