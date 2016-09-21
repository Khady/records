(** Dynamic records *)

open Result

(** {2 Layouts} *)

(** The representation of record types. ['s] is usually a phantom type.
    Two interfaces are provided for creating layouts, in [Unsafe] and [Safe].
*)
type 's layout

(** Raised by [field] or [seal] if layout has already been sealed. *)
exception ModifyingSealedStruct of string

(** {2 Records} *)

(** The representation of record values. *)
type 's t =
  {
    layout: 's layout;
    content: 's content;
  }
and 's content

(** Get the layout of a record. *)
val get_layout : 'a t -> 'a layout

(** Raised by [make] when the corresponding layout has not been sealed. *)
exception AllocatingUnsealedStruct of string

(** {3 Type converters} *)
module Type : sig
  (**
     How to convert a type to and from JSON.
  *)
  type 'a t

  val name : 'a t -> string
  val of_yojson : 'a t -> (Yojson.Safe.json -> ('a, string) result)
  val to_yojson : 'a t -> ('a -> Yojson.Safe.json)

  (** Declare a new type. *)
  val make:
    name: string ->
    to_yojson: ('a -> Yojson.Safe.json) ->
    of_yojson: (Yojson.Safe.json -> ('a, string) result) ->
    unit -> 'a t

  (** Declare a new type that marshal/unmarshal to strings. *)
  val make_string:
    name: string ->
    to_string: ('a -> string) ->
    of_string: (string -> ('a, string) result) ->
    unit -> 'a t

  (** How to represent exceptions. *)
  val exn: exn t

  (** Raised by [exn.of_json] *)
  exception UnserializedException of string

  (** How to represent [unit]. *)
  val unit: unit t

  (** How to represent [string]. *)
  val string: string t

  (** How to represent [int]. *)
  val int: int  t

  (** Build a representation of a list. *)
  val list: 'a t -> 'a list t

  (** Build a representation of a couple.
      The labels identify the elements, not their types.
   *)
  val product_2: string -> 'a t -> string -> 'b t -> ('a * 'b) t

  (** Build a representation of a [result]. *)
  val result : 'a t -> 'b t -> ('a, 'b) Result.result t

  (** Build a ['b] type which has the same JSON encoding as the ['a] type from
      conversion functions [read] and [write]. *)
  val view : name:string -> read:('a -> ('b, string) result) -> write:('b -> 'a) -> 'a t -> 'b t
end

module Field : sig
  (** A field of type ['a] within a ['s layout]. *)
  type ('a,'s) t

  (** Get the name of the field (as passed to [field]). *)
  val name : ('a, 's) t -> string

  (** Get the type of the field (as passed to [field]). *)
  val ftype : ('a, 's) t -> 'a Type.t
end

(** Get the value of a field. *)
val get: 's t -> ('a,'s) Field.t -> 'a

(** Set the value of a field. *)
val set: 's t -> ('a,'s) Field.t -> 'a -> unit

(** Raised by [get] if the field was not set. *)
exception UndefinedField of string

module Polid : sig
  (** The type of identifiers associated to type ['a]. *)
  type 'a t

  (** Make a new, fresh identifier.
      This is the only way to obtain a value of type [t]. *)
  val fresh: unit -> 'a t

  (** Type constraint which is conditioned on identifier equality. *)
  type ('a, 'b) equal =
    | Equal: ('a, 'a) equal
    | Different: ('a, 'b) equal

  (** Equality predicate. *)
  val equal: 'a t -> 'b t -> ('a, 'b) equal

  (** Convert an identifier to an integer.
      The integer is guaranteed to be unique for each call to {!fresh}. *)
  val to_int: 'a t -> int

  (** [equal] projected to a plain [bool]. *)
  val is_equal: 'a t -> 'b t -> bool
end

(** {3 Unsafe interface} *)
module Unsafe : sig
  (** The [Unsafe.declare] function returns a ['s layout], which is only safe
      when ['s] is only instanciated once in this context.

      @see <https://github.com/cryptosense/records/pull/8> for discussion
   *)

  (** Create a new layout with the given name. *)
  val declare : string -> 's layout

  (** Add a field to a layout. This modifies the layout and returns the field. *)
  val field: 's layout -> string -> 'a Type.t -> ('a,'s) Field.t

  (** Make the layout unmodifiable. It is necessary before constructing values. *)
  val seal : 's layout -> unit

  (** Allocate a record of a given layout, with all fields initially unset. *)
  val make: 's layout -> 's t

  (** Get the name that was given to a layout. *)
  val layout_name : 's layout -> string

  (** Get the unique identifier given to a layout. *)
  val layout_id: 's layout -> 's Polid.t
end

(** {3 Safe interface} *)
module Safe :
sig
  (**
     This interface is similar to [Unsafe] except that the phantom type normally
     passed to [declare] is generated by a functor. This has the other advantage
     of making the [layout] argument implicit in the output module.
  *)

  module type LAYOUT =
  sig
    type s

    (** A value representing the layout. *)
    val layout : s layout

    (** Add a field to the layout. This modifies the layout and returns the field. *)
    val field : string -> 'a Type.t -> ('a, s) Field.t

    (** Make the layout unmodifiable. It is necessary before constructing values. *)
    val seal : unit -> unit

    (** The name that was given to the layout. *)
    val layout_name : string

    (** The unique identifier given to a layout. *)
    val layout_id : s Polid.t

    (** Allocate a record of the layout, with all fields initially unset. *)
    val make : unit -> s t
  end

  (** Create a new layout with the given name. *)
  val declare : string -> (module LAYOUT)
end

(** {2 Miscellaneous} *)

(** Convert a record to JSON. *)
val to_yojson: 'a t -> Yojson.Safe.json

(** Convert a JSON value into a given schema. *)
val of_yojson: 'a layout -> Yojson.Safe.json -> ('a t, string) result

module Util : sig
  (** Get the [Type.t] representation of a layout. *)
  val layout_type : 'a layout -> 'a t Type.t

  (** Shortcut to build a layout with no fields. *)
  val declare0 : name:string -> 's layout

  (** Shortcut to build a layout with 1 field. *)
  val declare1 : name:string
              -> f1_name:string
              -> f1_type:'a Type.t
              -> ('s layout * ('a, 's) Field.t)

  (** Shortcut to build a layout with 2 fields. *)
  val declare2 : name:string
              -> f1_name:string
              -> f1_type:'a1 Type.t
              -> f2_name:string
              -> f2_type:'a2 Type.t
              -> ('s layout * ('a1, 's) Field.t * ('a2, 's) Field.t)

  (** Shortcut to build a layout with 3 fields. *)
  val declare3 : name:string
              -> f1_name:string
              -> f1_type:'a1 Type.t
              -> f2_name:string
              -> f2_type:'a2 Type.t
              -> f3_name:string
              -> f3_type:'a3 Type.t
              -> ('s layout * ('a1, 's) Field.t * ('a2, 's) Field.t
                            * ('a3, 's) Field.t)

  (** Shortcut to build a layout with 4 fields. *)
  val declare4 : name:string
              -> f1_name:string
              -> f1_type:'a1 Type.t
              -> f2_name:string
              -> f2_type:'a2 Type.t
              -> f3_name:string
              -> f3_type:'a3 Type.t
              -> f4_name:string
              -> f4_type:'a4 Type.t
              -> ('s layout * ('a1, 's) Field.t * ('a2, 's) Field.t
                            * ('a3, 's) Field.t * ('a4, 's) Field.t)
end

(** Equality predicate. *)
val equal: 'a layout -> 'b layout -> ('a, 'b) Polid.equal

(** Print the JSON representation of a record to a formatter. *)
val format: Format.formatter -> 'a t -> unit
[@@deprecated "Please use Yojson.Safe.to_string instead"]
