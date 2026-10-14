open! Base

let exec conn query =
  PGOCaml.prepare conn ~query ();
  ignore (PGOCaml.execute conn ~params:[] () : string option list list)
;;

let () =
  let conn = PGOCaml.connect () in
  Exn.protect
    ~finally:(fun () -> PGOCaml.close conn)
    ~f:(fun () ->
      exec
        conn
        "CREATE TABLE public.people (small_value smallint NOT NULL, id integer NOT NULL, big_value bigint NOT NULL, real_value real NOT NULL, double_value double precision NOT NULL, name text NOT NULL, note varchar, fixed_value char(3) NOT NULL, active boolean NOT NULL, data bytea NOT NULL, amount numeric NOT NULL, day date NOT NULL, clock time NOT NULL, local_time timestamp NOT NULL, instant timestamptz NOT NULL, duration interval NOT NULL, document json NOT NULL, binary_document jsonb NOT NULL, external_id uuid NOT NULL)";
      exec
        conn
        "INSERT INTO public.people VALUES (7, 1, 9000000000, 1.5, 2.5, 'Ada', NULL, 'abc', true, '\\x00ff', 12.345, '2026-10-14', '12:34:56', '2026-10-14 12:34:56', '2026-10-14 12:34:56+00', '2 days', '{\"id\":1}', '{\"id\":1}', '550e8400-e29b-41d4-a716-446655440000')";
      exec
        conn
        "INSERT INTO public.people SELECT small_value, 2, big_value, real_value, double_value, 'Grace', 'note', fixed_value, active, data, amount, day, clock, local_time, instant, duration, document, binary_document, external_id FROM public.people WHERE id = 1";
      let all = [%pgsql conn {|SELECT * FROM public.people ORDER BY id DESC|}] in
      let ( _
          , id
          , big
          , real
          , double
          , name
          , note
          , fixed
          , active
          , data
          , amount
          , day
          , clock
          , local_time
          , instant
          , duration
          , document
          , binary_document
          , external_id )
        =
        List.hd_exn all
      in
      assert (Int32.equal id 2l && Int64.equal big 9000000000L);
      assert (Float.equal real 1.5 && Float.equal double 2.5);
      assert (String.equal name "Grace" && Option.equal String.equal note (Some "note"));
      assert (String.equal fixed "abc" && active && String.equal data "\000\255");
      assert (String.equal amount "12.345");
      assert (String.equal (PGOCaml.string_of_date day) "2026-10-14");
      assert (String.is_substring (PGOCaml.string_of_time clock) ~substring:"12:34:56");
      ignore (PGOCaml.string_of_timestamp local_time : string);
      ignore (PGOCaml.string_of_timestamptz instant : string);
      ignore (PGOCaml.string_of_interval duration : string);
      assert (
        String.is_substring document ~substring:"1"
        && String.is_substring binary_document ~substring:"1");
      assert (String.equal external_id "550e8400-e29b-41d4-a716-446655440000");
      let find id =
        [%pgsql.object
          conn
            {sql|SELECT p.id, p.name, p.note FROM public.people AS p WHERE p.id = $id ORDER BY p.id|sql}]
      in
      let ada = List.hd_exn (find 1l) in
      let grace = List.hd_exn (find 2l) in
      assert (
        Int32.equal ada#id 1l && String.equal ada#name "Ada" && Option.is_none ada#note);
      assert (Int32.equal grace#id 2l && String.equal grace#name "Grace");
      let note = Some "note" in
      assert (
        List.equal
          String.equal
          [%pgsql conn "SELECT name FROM people WHERE note = $?note"]
          [ "Grace" ]);
      let maybe_id = Some 1l in
      let optional : int32 option list =
        [%pgsql conn "nullable-results" "SELECT id FROM people WHERE id = $?maybe_id"]
      in
      assert (List.equal (Option.equal Int32.equal) optional [ Some 1l ]);
      let check
            ~small_value
            ~id
            ~big_value
            ~real_value
            ~double_value
            ~name
            ~note
            ~fixed_value
            ~active
            ~data
            ~amount
            ~day
            ~clock
            ~local_time
            ~instant
            ~duration
            ~document
            ~binary_document
            ~external_id
        =
        [%pgsql
          conn
            {|SELECT id FROM people WHERE small_value = $small_value AND id = $id AND big_value = $big_value AND real_value = $real_value AND double_value = $double_value AND name = $name AND note = $?note AND fixed_value = $fixed_value AND active = $active AND data = $data AND amount = $amount AND day = $day AND clock = $clock AND local_time = $local_time AND instant = $instant AND duration = $duration AND binary_document = $binary_document AND external_id = $external_id|}]
        |> fun result ->
        ignore (document : string);
        result
      in
      assert (
        List.equal
          Int32.equal
          (check
             ~small_value:7
             ~id
             ~big_value:big
             ~real_value:real
             ~double_value:double
             ~name
             ~note
             ~fixed_value:fixed
             ~active
             ~data
             ~amount
             ~day
             ~clock
             ~local_time
             ~instant
             ~duration
             ~document
             ~binary_document
             ~external_id)
          [ 2l ]))
;;
