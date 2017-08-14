
open Ustring.Op


val verbose : bool -> unit
(** [verbose v] enables verbose output to standard output by supplying
    a boolean true value to parameter [v] *)


val get_section : string -> string -> bytes
(** [get_section filename section] returns the sequence of bytes from
    [section] in the file with name [filename]. For instance, to get
    the code, write [get_section "file.elf" ".text"] or to get the
    data, write [get_section "file.elf" ".sdata"]. Returns an empty
    byte array if there are any errors or if the section does not exist.
*)


val pic32_compile : string list -> bool -> int -> string -> unit
(** [pic32_compile filenames only_compile optimization_ outputname]
    compiles a C file for the target of a PIC32 MIPS processor.
    [filenames] is a list of files (C or obj-files). If [only_compile]
    is true, the output is an object file and if it is false, the
    output is executable (.elf) file. Parameter [optimization] is true
    if full optimization should be enabled. If it is false, no
    optimization is performed. Raises exception [Sys_error] if there
    is a compilation error.
*)


val section_info: string -> (string * (int * int)) list
(** [section_info filename] returns an association list, where the keys
    are text strings representing sections and the values are tuples,
    where the first element is the size of the section and the second
    element is the virtual memory address to the section. For
    instance, a returned list of element [(".text",(100,0xffff))]
    means that there is a .text section, starting at address [0xffff]
    that is of size 100 bytes.
*)

val symbol_table : string -> (string * int) list
(** [symbol_table filename] returns an association list representing the
    symbol table of object file [filename]. The key is the symbol and the
    value is the address. *)


val get_program : string -> MipsAst.program 
(** [get_program filename] reads a MIPS ELF file and returns a MIPS
    program object. *)


val assign_program_stack : MipsAst.program -> int -> int -> int -> MipsAst.program
(** [assign_program_stack prog ptr size addr] assigns and returns a new
    program object derived from [prog] with the initial stack pointer at [ptr],
    the size buffer [size] and the start address [addr] of the buffer.
*)


val get_eval_func : ?bigendian:bool -> MipsAst.program -> sid list 
                    -> ExhaustiveTA.timed_eval_func
(** [get_timed_eval_func prog statevarlist] returns the a timed eval function for
    a specific MIPS executable and the symbol table. *)


val get_init_state_vals : ?bigendian:bool -> MipsAst.program -> string ->
                          sid list -> (int * int32) list
(** [get_init_state_vals prog initfunc statelist] returns a list of init state values.
    The selected variables that are returned are given in argument [statelist]. 
    These init values depend both on global initializations in the original program,
    as well as the assignments that are made by the [initfunc] function. *)

val wcet_compile: string -> bool -> bool -> int option -> int option ->
                  bool -> int -> Ustring.ustring -> string list -> string

val verbose_enabled: unit -> bool









