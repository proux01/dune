(** Build rules *)

open! Stdune
open! Import

(** {1 Setup} *)

(** {2 Creation} *)

type caching =
  { cache : (module Cache.Caching)
  ; check_probability : float
  }

(** Initializes the build system. This must be called first. *)
val init :
     contexts:Build_context.t list
  -> promote_source:
       (   ?chmod:(int -> int)
        -> src:Path.Build.t
        -> dst:Path.Source.t
        -> Build_context.t option
        -> unit Fiber.t)
  -> ?caching:caching
  -> sandboxing_preference:Sandbox_mode.t list
  -> unit
  -> unit

val reset : unit -> unit

module Subdir_set : sig
  type t =
    | All
    | These of String.Set.t

  val empty : t

  val union : t -> t -> t

  val union_all : t list -> t

  val mem : t -> string -> bool
end

type extra_sub_directories_to_keep = Subdir_set.t

module Context_or_install : sig
  type t =
    | Install of Context_name.t
    | Context of Context_name.t

  val to_dyn : t -> Dyn.t
end

(** Set the rule generators callback. There must be one callback per build
    context name.

    Each callback is used to generate the rules for a given directory in the
    corresponding build context. It receives the directory for which to generate
    the rules and the split part of the path after the build context. It must
    return an additional list of sub-directories to keep. This is in addition to
    the ones that are present in the source tree and the ones that already
    contain rules.

    It is expected that [f] only generate rules whose targets are descendant of
    [dir].

    [init] can generate rules in any directory, so it's always called. *)
val set_rule_generators :
     init:(unit -> unit)
  -> gen_rules:
       (   Context_or_install.t
        -> (   dir:Path.Build.t
            -> string list
            -> extra_sub_directories_to_keep Fiber.t)
           option)
  -> unit

(** Set the list of VCS repositiories contained in the source tree *)
val set_vcs : Vcs.t list -> unit Fiber.t

(** All other functions in this section must be called inside the rule generator
    callback. *)

(** {2 Primitive for rule generations} *)

(** [prefix_rules t prefix ~f] Runs [f] and adds [prefix] as a dependency to all
    the rules generated by [f] *)
val prefix_rules : unit Build.t -> f:(unit -> 'a) -> 'a

(** [eval_pred t \[glob\]] returns the list of files in [File_selector.dir glob]
    that matches [File_selector.predicate glob]. The list of files includes the
    list of targets. *)
val eval_pred : File_selector.t -> Path.Set.t Fiber.t

(** Returns the set of targets in the given directory. *)
val targets_of : dir:Path.t -> Path.Set.t Fiber.t

(** Load the rules for this directory. *)
val load_dir : dir:Path.t -> unit Fiber.t

(** Sets the package assignment *)
val set_packages : (Path.Build.t -> Package.Id.Set.t) -> unit

(** Assuming [files] is the list of files in [_build/install] that belong to
    package [pkg], [package_deps t pkg files] is the set of direct package
    dependencies of [package]. *)
val package_deps : Package.t -> Path.Set.t -> Package.Id.Set.t Build.t

(** {2 Aliases} *)

module Alias : sig
  type t = Alias.t

  (** Alias for all the files in [_build/install] that belong to this package *)
  val package_install : context:Build_context.t -> pkg:Package.t -> t

  (** [dep t = Build.path (stamp_file t)] *)
  val dep : t -> unit Build.t

  (** Implements [@@alias] on the command line *)
  val dep_multi_contexts :
       dir:Path.Source.t
    -> name:Alias.Name.t
    -> contexts:Context_name.t list
    -> unit Build.t

  (** Implements [(alias_rec ...)] in dependency specification *)
  val dep_rec : t -> loc:Loc.t -> unit Build.t

  (** Implements [@alias] on the command line *)
  val dep_rec_multi_contexts :
       dir:Path.Source.t
    -> name:Alias.Name.t
    -> contexts:Context_name.t list
    -> unit Build.t
end

(** {1 Building} *)

(** All the functions in this section must be called outside the rule generator
    callback. *)

(** Do the actual build *)
val do_build : request:'a Build.t -> 'a Fiber.t

(** {2 Other queries} *)

val is_target : Path.t -> bool Fiber.t

val static_deps_of_request : 'a Build.t -> Path.Set.t

val rules_for_transitive_closure : Path.Set.t -> Rule.t list

val contexts : unit -> Build_context.t Context_name.Map.t

(** List of all buildable targets. *)
val all_targets : unit -> Path.Build.Set.t Fiber.t

(** The set of files that were created in the source tree and need to be
    deleted. *)
val files_in_source_tree_to_delete : unit -> Path.Set.t

(** {2 Build rules} *)

(** A fully evaluated rule. *)
module Evaluated_rule : sig
  type t = private
    { id : Rule.Id.t
    ; dir : Path.Build.t
    ; deps : Dep.Set.t
    ; targets : Path.Build.Set.t
    ; context : Build_context.t option
    ; action : Action.t
    }
end

(** Return the list of fully evaluated rules used to build the given targets. If
    [recursive] is [true], also include the rules needed to build the transitive
    dependencies of the targets. *)
val evaluate_rules :
  recursive:bool -> request:unit Build.t -> Evaluated_rule.t list Fiber.t

val get_cache : unit -> caching option
