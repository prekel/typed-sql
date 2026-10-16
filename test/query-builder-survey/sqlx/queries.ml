open! Base

(* $MDX part-begin=sx01 *)
let sx01 =
  [%pgsql.statement.object
    fun name -> "SELECT id, name FROM users WHERE name = $name ORDER BY id"]
;;

(* $MDX part-end *)

(* $MDX part-begin=sx02 *)
let sx02 =
  [%pgsql.statement
    fun (min_id, pattern) ->
      "SELECT id, name FROM users WHERE id > $min_id AND name LIKE $pattern ORDER BY id"]
;;

(* $MDX part-end *)

(* $MDX part-begin=sx03 *)
let sx03 =
  [%pgsql.statement
    fun (limit, offset) ->
      "SELECT id, name FROM users ORDER BY name, id LIMIT $limit OFFSET $offset"]
;;

(* $MDX part-end *)

(* $MDX part-begin=sx04 *)
let sx04 =
  [%pgsql.statement
    fun score ->
      "SELECT u.id, p.title FROM users u JOIN posts p ON p.user_id = u.id WHERE p.score >= $score ORDER BY u.id, p.id"]
;;

(* $MDX part-end *)

(* $MDX part-begin=sx05 *)
let sx05 =
  [%pgsql.statement
    "nullable-results"
      "SELECT u.id, p.id AS post_id FROM users u LEFT JOIN posts p ON p.user_id = u.id ORDER BY u.id, p.id"]
;;

(* $MDX part-end *)

(* $MDX part-begin=sx06 *)
let sx06 =
  [%pgsql.statement
    fun age ->
      "SELECT id, name FROM users WHERE age IS NOT DISTINCT FROM $?age ORDER BY id"]
;;

(* $MDX part-end *)

(* $MDX part-begin=sx07 *)
let sx07 =
  [%pgsql.statement
    fun adult ->
      "SELECT id, CASE WHEN age IS NULL THEN 'unknown' WHEN age >= $adult THEN 'adult' ELSE 'child' END AS category FROM users ORDER BY id"]
;;

(* $MDX part-end *)

(* $MDX part-begin=sx08 *)
let sx08 =
  [%pgsql.statement
    "SELECT user_id, COUNT(*) AS total FROM posts GROUP BY user_id ORDER BY user_id"]
;;

(* $MDX part-end *)

(* $MDX part-begin=sx09 *)
let sx09 =
  [%pgsql.statement
    fun minimum ->
      "SELECT user_id, COUNT(*) AS total FROM posts GROUP BY user_id HAVING COUNT(*) >= $minimum ORDER BY user_id"]
;;

(* $MDX part-end *)

(* $MDX part-begin=sx10 *)
let sx10 =
  [%pgsql.statement
    fun score ->
      "SELECT u.id FROM users u WHERE EXISTS (SELECT 1 FROM posts p WHERE p.user_id = u.id AND p.score > $score) ORDER BY u.id"]
;;

(* $MDX part-end *)

(* $MDX part-begin=sx11 *)
let sx11 =
  [%pgsql.statement
    "SELECT u.id FROM users u WHERE NOT EXISTS (SELECT 1 FROM posts p WHERE p.user_id = u.id) ORDER BY u.id"]
;;

(* $MDX part-end *)

(* $MDX part-begin=sx12 *)
let sx12 =
  [%pgsql.statement
    "SELECT u.id, (SELECT COUNT(*) FROM posts p WHERE p.user_id = u.id) AS total FROM users u ORDER BY u.id"]
;;

(* $MDX part-end *)

(* $MDX part-begin=sx13 *)
let sx13 =
  [%pgsql.statement
    "SELECT u.id, s.total FROM users u JOIN (SELECT user_id, SUM(score) AS total FROM posts GROUP BY user_id) s ON s.user_id = u.id ORDER BY u.id"]
;;

(* $MDX part-end *)

(* $MDX part-begin=sx14 *)
let sx14 =
  [%pgsql.statement
    fun boundary ->
      "SELECT id FROM users WHERE id < $boundary UNION ALL SELECT user_id AS id FROM posts WHERE user_id >= $boundary ORDER BY id"]
;;

(* $MDX part-end *)

(* $MDX part-begin=sx15 *)
let sx15 =
  [%pgsql.statement
    "SELECT id FROM users INTERSECT SELECT user_id AS id FROM posts ORDER BY id"]
;;

(* $MDX part-end *)

(* $MDX part-begin=sx16 *)
let sx16 =
  [%pgsql.statement
    "SELECT id FROM users EXCEPT SELECT user_id AS id FROM posts ORDER BY id"]
;;

(* $MDX part-end *)

(* $MDX part-begin=sx17 *)
let sx17 =
  [%pgsql.statement
    fun minimum ->
      "WITH popular AS (SELECT user_id FROM posts GROUP BY user_id HAVING COUNT(*) >= $minimum) SELECT u.id, u.name FROM users u JOIN popular p ON p.user_id = u.id ORDER BY u.id"]
;;

(* $MDX part-end *)

(* $MDX part-begin=sx18 *)
let sx18 =
  [%pgsql.statement
    fun root ->
      "WITH RECURSIVE tree AS (SELECT id, parent_id FROM users WHERE id = $root UNION ALL SELECT u.id, u.parent_id FROM users u JOIN tree t ON u.parent_id = t.id) SELECT id FROM tree ORDER BY id"]
;;

(* $MDX part-end *)

(* $MDX part-begin=sx19 *)
let sx19 =
  [%pgsql.statement
    "SELECT id, ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY score DESC, id) AS rank FROM posts ORDER BY user_id, rank"]
;;

(* $MDX part-end *)

(* $MDX part-begin=sx20 *)
let sx20 =
  [%pgsql.statement
    "SELECT id, SUM(score) OVER (PARTITION BY user_id ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total FROM posts ORDER BY user_id, id"]
;;

(* $MDX part-end *)

(* $MDX part-begin=sx21 *)
let sx21 =
  [%pgsql.statement
    "SELECT DISTINCT ON (user_id) user_id, id, title FROM posts ORDER BY user_id, score DESC, id"]
;;

(* $MDX part-end *)

(* $MDX part-begin=sx22 *)
let sx22 =
  [%pgsql.statement
    "nullable-results"
      "SELECT u.id, p.title FROM users u LEFT JOIN LATERAL (SELECT title FROM posts WHERE user_id = u.id ORDER BY score DESC, id LIMIT 1) p ON TRUE ORDER BY u.id"]
;;

(* $MDX part-end *)

(* $MDX part-begin=sx23 *)
let sx23 =
  [%pgsql.statement
    fun ids -> "SELECT id, name FROM users WHERE id = ANY($ids::int4[]) ORDER BY id"]
;;

(* $MDX part-end *)

(* $MDX part-begin=sx24 *)
let sx24 =
  [%pgsql.statement
    fun (ids, names) ->
      "INSERT INTO users (id, name) SELECT * FROM UNNEST($ids::int4[], $names::text[]) RETURNING id, name"]
;;

(* $MDX part-end *)

(* $MDX part-begin=sx25 *)
let sx25 =
  [%pgsql.statement
    fun (id, name) ->
      "INSERT INTO users (id, name) VALUES ($id, $name) RETURNING id, name"]
;;

(* $MDX part-end *)

(* $MDX part-begin=sx26 *)
let sx26 =
  [%pgsql.statement
    fun (id, name) ->
      "INSERT INTO users (id, name) VALUES ($id, $name) ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name RETURNING id, name"]
;;

(* $MDX part-end *)

(* $MDX part-begin=sx27 *)
let sx27 =
  [%pgsql.statement
    fun (increment, user_id) ->
      "UPDATE posts SET score = score + $increment WHERE user_id = $user_id RETURNING id, score"]
;;

(* $MDX part-end *)

(* $MDX part-begin=sx28 *)
let sx28 = [%pgsql.statement fun minimum -> "DELETE FROM posts WHERE score < $minimum"]

(* $MDX part-end *)

(* $MDX part-begin=sx29 *)
let sx29 =
  [%pgsql.statement
    fun (score, name) ->
      "UPDATE posts p SET score = $score FROM users u WHERE p.user_id = u.id AND u.name = $name RETURNING p.id, p.score"]
;;

(* $MDX part-end *)

(* $MDX part-begin=sx30 *)
let sx30 =
  [%pgsql.statement
    fun (maximum, limit) ->
      "SELECT id FROM posts WHERE score < $maximum ORDER BY id LIMIT $limit FOR UPDATE SKIP LOCKED"]
;;
(* $MDX part-end *)
