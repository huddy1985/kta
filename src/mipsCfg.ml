
open Ustring.Op
open MipsAst
open Printf

let arrow_padding = 40  (* Characters for the printed arrows |> *)
let inden_inst = us"  " (* Characters indent for the instruction *)
let identifier_padding = 15
    
let idno = ref 1  
let unique_addr = ref 0x100000000
  
(* Used for checking visited nodes *)
module IntSet = Set.Make(
  struct
    let compare = Pervasives.compare
    type t = int
  end)    

  
(** Add a new symbol with address to the program *)  
let add_addrsym_prog prog addr sym =
  {prog with sym2addr = Sym2Addr.add sym addr prog.sym2addr;
             addr2sym = Addr2Sym.add addr sym prog.addr2sym}

(* Creates new symbol if address to symbol already exists. 
   Returns a tuple: the new program with the added symbol and the actual symbol *)
let rec new_unique_sym prog addr =
  let sym = "ex" ^ string_of_int !idno in
  if not (MipsAst.Sym2Addr.mem sym prog.sym2addr) then (
    idno := !idno + 1;
    (add_addrsym_prog prog addr sym, sym))
  else
    new_unique_sym prog addr

(* Creates a new unique symbol with a new unique (negative) address *)      
let new_unique_symaddr prog =
  let (prog,sym) = new_unique_sym prog !unique_addr in
  let addr = !unique_addr in
  unique_addr := !unique_addr + 1;
  (prog,addr,sym)

      
  
let getinstidx prog addr =
  (addr - prog.text_sec.addr)/4

(* Checks if there is a symbol for the address. If not, create a new
   symbol. Returns a tuple (prog',sym) where prog' is the updated program *)
let mksym_from_addr prog addr =
  try (prog,MipsAst.Addr2Sym.find addr prog.addr2sym)
  with _ -> new_unique_sym prog addr 

(* Returns the address for a specific symbol. Assumes that the symbol exists *)    
let s2a prog sym = MipsAst.Sym2Addr.find sym prog.sym2addr
  
  
    
(* Returns the tuple (prog',codelist,exittype) where prog' the updated program,
   codelist the code list for the basic block, and exittype the actual [exittype]. *)
let rec getblockcode prog addr acc_code =
  let inst = prog.code.(getinstidx prog addr) in
  let ds_help prog = 
    let inst_ds = prog.code.(getinstidx prog (addr+4)) in
    let (prog,next_addr_sym) = mksym_from_addr prog (addr+8) in    
    let codelist = List.rev (inst_ds::inst::acc_code) in
    (prog,codelist,next_addr_sym)
  in
  match inst with
  | MipsBEQ(_,_,_,s)  | MipsBGEZ(_,_,s) | MipsBGTZ(_,_,s) |
    MipsBLEZ(_,_,s) | MipsBLTZ(_,_,s) | MipsBNE(_,_,_,s) 
      ->
    let (prog,codelist,next_addr_sym) = ds_help prog in
    (prog,codelist,ExitTypeBranch(s,next_addr_sym))
  | MipsBEQL(_,_,_,s) | MipsBNEL(_,_,_,s) |
      MipsBLEZL(_,_,s) | MipsBLTZL(_,_,s) |
        MipsBGEZL(_,_,s) | MipsBGTZL(_,_,s)->
    let (prog,codelist,next_addr_sym) = ds_help prog in
    (prog,codelist,ExitTypeBrLikely(s,next_addr_sym))
  | MipsJALR(rs) -> failwith "JALR not implemented yet"
  | MipsJR(rs) ->
    let inst_ds = prog.code.(getinstidx prog (addr+4)) in
    let codelist = List.rev (inst_ds::inst::acc_code) in
      (* TODO: This is just temp code. It assumes that the mapping to ra is correct. 
         Cannot handle jump tables, will fail *)
     if rs = reg_ra then 
       (prog,codelist,ExitTypeReturn)
     else failwith "Indirect jumps (used in switch statements) are not supported."
  | MipsJ(_,s) ->
    let (prog,codelist,_) = ds_help prog in
    (prog,codelist,ExitTypeJump(s))
  | MipsB(_,s) ->
    let (prog,codelist,_) = ds_help prog in
    (prog,codelist,ExitTypeJump(s))
  | MipsJAL(_,s) ->
    let (prog,codelist,next_addr_sym) = ds_help prog in
    (prog,codelist,ExitTypeCall(s,next_addr_sym))
  | _ ->
    try let sym = MipsAst.Addr2Sym.find (addr+4) prog.addr2sym in
        let codelist = List.rev (inst::acc_code) in
        (prog,codelist,ExitTypeNext(sym))
    with Not_found -> getblockcode prog (addr+4) (inst::acc_code) 

(* returns a tuple (prog',block) *)   
let getbblock prog addr =
  let (prog,codelist,exittype) = getblockcode prog addr [] in
  let block = {
    block_addr = addr;
    block_code = codelist;
    block_exit = exittype;
    block_dist = 0;
  } in
  (prog,block)

    
(* Traverse a function and generates the CFG *)
let make_cfg addr prog =
  (* The first pass - traverse and generate graph *)
  let rec traverse addr prog graph visited funccalls = 
    (* Check if already visited *)
    if IntSet.mem addr visited then (prog,graph,visited,funccalls)
    else(
      (* Get one basic block and add it to the graph *)
      let (prog,block) = getbblock prog addr in
      (* Add to graph, new symbol if necessary *)
      let (prog,sym) = mksym_from_addr prog addr in
      let graph = BlockMap.add sym block graph in
      (* Mark as visited *)
      let visited = IntSet.add addr visited in
 
      (* Go to next node *)
      match block.block_exit with
      | ExitTypeNext(nid) ->
         traverse (s2a prog nid) prog graph visited funccalls
      | ExitTypeBranch(tid,fid) ->
        let (prog,graph,visited,funccalls) =
          traverse (s2a prog fid) prog graph visited funccalls in
        traverse (s2a prog tid) prog graph visited funccalls
      | ExitTypeBrLikely(tid,fid) ->
        let (prog,graph,visited,funccalls) =
          traverse (s2a prog fid) prog graph visited funccalls in
        traverse (s2a prog tid) prog graph visited funccalls
      | ExitTypeJump(id) ->
        traverse (s2a prog id) prog graph visited funccalls
      | ExitTypeCall(callid,nid) ->
         traverse (s2a prog nid) prog graph visited (callid::funccalls)
      | ExitTypeReturn ->
        (prog,graph,visited,funccalls)
    )in
  (* Second pass. Generate extra nodes for all likely finish nodes, e.g., bnel *)
  let rec expand_likely prog graph =
    let (likely,graph) = BlockMap.partition
      (fun _ block -> match block.block_exit with| ExitTypeBrLikely(_,_) -> true | _ -> false) graph in
    BlockMap.fold (fun name block (prog,graph) -> (
      let nextsym = match block.block_exit with
                    ExitTypeBrLikely(_,next) -> next | _ -> failwith "Should not" in      
      let new_addr = block.block_addr + (List.length block.block_code - 1) * 4 in
      let (prog,new_sym) = mksym_from_addr prog new_addr in
      let (inst,truebranch,new_block_code) =
        match List.rev block.block_code with
        | inst::MipsBEQL(rs,rt,imm,s)::rest -> (inst,s,List.rev (MipsBEQL(rs,rt,imm,new_sym)::rest))
        | inst::MipsBNEL(rs,rt,imm,s)::rest -> (inst,s,List.rev (MipsBNEL(rs,rt,imm,new_sym)::rest))
        | inst::MipsBGEZL(rs,imm,s)::rest -> (inst,s,List.rev (MipsBGEZL(rs,imm,new_sym)::rest))
        | inst::MipsBGTZL(rs,imm,s)::rest -> (inst,s,List.rev (MipsBGTZL(rs,imm,new_sym)::rest))
        | inst::MipsBLEZL(rs,imm,s)::rest -> (inst,s,List.rev (MipsBLEZL(rs,imm,new_sym)::rest))
        | inst::MipsBLTZL(rs,imm,s)::rest -> (inst,s,List.rev (MipsBLTZL(rs,imm,new_sym)::rest))
        | _ -> failwith "should not happen"
      in
      let new_exit_branch =
        match block.block_exit with
        | ExitTypeBrLikely(tid,fid) -> ExitTypeBrLikely(tid,nextsym)
        | _ -> ExitTypeNext(nextsym)
      in
      let block1 = {block with block_code = new_block_code; block_exit = new_exit_branch} in
      let block2 = {block_addr = new_addr; block_code=[inst];
                    block_exit = ExitTypeNext(truebranch); block_dist=0} in
      let graph = BlockMap.add name block1 graph in
      let graph = BlockMap.add new_sym block2 graph in
      (prog,graph)
    )) likely (prog,graph)
  in
  (* If more than one return node, create a common exit node *)
  let rec make_common_exit_node prog oldgraph =
    let (returns,graph) = BlockMap.partition
      (fun _ block -> match block.block_exit with| ExitTypeReturn -> true | _ -> false) oldgraph in
    if BlockMap.cardinal returns = 1 then
      let exit_node = BlockMap.bindings returns |> List.hd |> fst in
      (prog,oldgraph,exit_node)
    else
      let (prog,addr,sym) = new_unique_symaddr prog in
      let graph = BlockMap.fold (fun name block graph -> (
        let nblock = {block with block_exit = ExitTypeNext(sym)} in
        BlockMap.add name nblock graph        
      )) returns graph in
      let retblock = {block_addr=0; block_code=[]; block_exit=ExitTypeReturn; block_dist=0} in
      let graph = BlockMap.add sym retblock graph in
      (prog,graph,sym)
  in
  (* Create entry node symbol *)
  let (prog,entry_node) = mksym_from_addr prog addr in
  (* Traverse the graph *)
  let (prog,graph,_,funccalls) = traverse addr prog BlockMap.empty IntSet.empty [] in
  (* Expand likely nodes *)
  let (prog,graph) = expand_likely prog graph in
  (* Make sure that there is only one exit node *)
  let (prog,graph,exit_node) = make_common_exit_node prog graph in
  (* Construct and return the control flow graph *)
  let cfg = {
      entry_node = entry_node; 
      exit_node  = exit_node;
      cfg_graph = graph;
  } in
  (prog,cfg,funccalls)
  

(* Creates a mapping: bblockid -> bblockid list *)
module BackMap = Map.Make(String)
type backkmap = (bblockid list) BackMap.t
module StringSet = Set.Make(String)
  
(* Assign distances to a control flow graph *)
let assign_distances cfg =
  (* Create the nodes for a back-edge graph *)
  let bgraph = BlockMap.fold (fun k b a -> BackMap.add k [] a)
    cfg.cfg_graph BackMap.empty in

  (* Create the graph with back edges *)
  let bgraph = BlockMap.fold (fun k b a ->
    match b.block_exit with
    | ExitTypeNext(id) | ExitTypeJump(id) | ExitTypeCall(_,id) 
      -> BackMap.add id (k::(BackMap.find id a)) a
    | ExitTypeBranch(id1,id2) | ExitTypeBrLikely(id1,id2) 
      -> let a = BackMap.add id1 (k::(BackMap.find id1 a)) a in
         BackMap.add id2 (k::(BackMap.find id2 a)) a
    | ExitTypeReturn -> a      
  ) cfg.cfg_graph bgraph in

  (* Compute the distance properties using shortest path *)
  let rec shortest_path next dist graph =    
    let (graph,next) = List.fold_left (fun (graph,next) v ->
      List.fold_left (fun (graph,next) w ->
        let block = (BlockMap.find w graph) in
        if block.block_dist = 0 && w != cfg.exit_node then
          let block = {block with block_dist = dist} in
          let graph = BlockMap.add w block graph in
          (graph,w::next)
        else
          (graph,next)          
      ) (graph,next) (BackMap.find v bgraph)         
    ) (graph,[]) next
    in
    if next = [] then graph
    else shortest_path next (dist+1) graph
  in
  let graph = shortest_path [cfg.exit_node] 1 cfg.cfg_graph in
  {cfg with cfg_graph = graph}
 

    
(* Construct the CFG map of the whole program.
   Returns tuple (prog,cfgmap)  *)
let make_cfgmap startname prog =
  let rec traverse prog cfgmap visited funccalls =
    match funccalls with
    | f::fs ->
       let addr = s2a prog f in
      if IntSet.mem addr visited then
        traverse prog cfgmap visited fs
      else(
        let (prog,cfg,newcalls) = make_cfg addr prog in
        let cfg = assign_distances cfg in
        let cfgmap = CfgMap.add f cfg cfgmap in
        let visited = IntSet.add addr visited in
        traverse prog cfgmap visited (newcalls@funccalls))
    | [] -> (prog,cfgmap)
  in
  traverse prog CfgMap.empty IntSet.empty [startname]
    
  

(* Pretty print one basic block *)
let pprint_bblock name block =
  let add_arrow str = (Ustring.spaces_after str arrow_padding) ^. us"|>\n" in
  let head = us"let " ^. (us name) ^. us" ms = ms" |> add_arrow in
  let rec instlist a instlst =
    match instlst with
    | i::is ->
      instlist (a ^. add_arrow(inden_inst ^. MipsUtils.pprint_inst_ocaml i)) is
    | [] -> a
  in
  let final = (match block.block_exit with
    | ExitTypeNext(_)  | ExitTypeBranch(_,_)  | ExitTypeJump(_) |
      ExitTypeCall(_,_) -> inden_inst ^.  us"next" ^. us"\n"
    | ExitTypeBrLikely(_,_) -> inden_inst ^.  us"next" ^. us"\n"
    | ExitTypeReturn -> inden_inst ^.  us"ret" ^. us"\n")
  in
    head ^. instlist (us"") block.block_code ^. final


(* Pretty print a whole control flow graph *)      
let pprint_ocaml_cps_from_cfg nice_output cfg prog k =
  let cfglst = BlockMap.bindings cfg.cfg_graph in
  let cfglst = if nice_output then cfglst 
                  |> List.map (fun (s,b) -> (s2a prog s,(s,b)))
                  |> List.fast_sort (fun (k1,_) (k2,_) -> compare k1 k2) 
                  |> List.split |> snd
               else cfglst
  in        
  List.fold_left (fun (lst,k,a) (name,block) ->
    ((name,k,block)::lst,k+1,a ^. pprint_bblock name block ^. us"\n")
  ) ([],k,us"") cfglst

    
(* Pretty print a whole program as an analyzable .ml file *)  
let pprint_ocaml_cps_from_cfgmap record fnames task_n nice_output name cfgmap prog =
  (* Sort the CFGs according to memory addresses *)
  let cfglst = CfgMap.bindings cfgmap in
  let cfglst =
    if nice_output then cfglst 
    |> List.map (fun (s,b) -> (s2a prog s,(s,b)))
    |> List.fast_sort (fun (k1,_) (k2,_) -> compare k1 k2) 
    |> List.split |> snd
    else cfglst
  in
  let mem_start = us"let mem = [" in
  let mem_end = us"]\n\n" in
  let rec mem_get_data d n lst =
    let get_byte d i =
      int_of_char (Bytes.get d i)
    in
    match n with
    | n when n<0 -> lst
    | n ->
       let b = get_byte d n in
       mem_get_data d (n-1) (us (sprintf "%d;" b) ^. lst)
  in
  let rec mem_zero_data n lst =
    match n with
    | n when n<0 -> lst
    | n -> mem_zero_data (n-1) (us (sprintf "0;" ) ^. lst)
  in

  let print_mem_sec sec name =
    match sec.addr,sec.size with
    | 0,0 -> us ""
    | _,_ ->
       us"{" ^. 
         us(sprintf "address=(%d); size=%d; sect_name=\"%s\"; data=["
		(Utils.sign_extension (sec.addr land 0xffffffff) 32)
                   sec.size name) ^.               
           (match name with
            | ".sbss" ->
               mem_zero_data (sec.size-1) (us"")
            | ".bss" ->
               us ""
            | name ->
               mem_get_data sec.d (sec.size-1) (us""))
           ^. us"]};\n"
  in
  let mem_all = print_mem_sec prog.data_sec ".data" ^.
                  print_mem_sec prog.sdata_sec ".sdata" ^.
                    print_mem_sec prog.rodata_sec ".rodata" ^.
                      print_mem_sec prog.sbss_sec ".sbss" ^. 
                       print_mem_sec prog.bss_sec ".bss"
  in
  (* Intro header *)
  let intro =
    us"open AbstractMIPS\n\n" ^.
      us"open Printf\n\n" ^.
      us"open Unix\n\n" ^.
      (if not record then
          List.fold_left
            (fun str (i,fn) -> (us("open Memmap_") ^. fn ^. us "_" ^. (ustring_of_int i) ^. us "\n\n") ^. str)
            (us"") ((0, us name)::fnames)
       else us "") ^.

        us (sprintf "let gp_addr=(%d)\n" (Utils.sign_extension (prog.gp land 0xffffffff) 32)) ^.
          mem_start ^. mem_all ^. mem_end ^.
          us"(* -- Basic Block Identifiers -- *)\n\n"
  in
  
  (* Info before program code *)
  let blocks_header =
    us"(* -- Program Code -- *)\n\n"
  in
  (* Pretty print all basic blocks from all CFGs *)
  let (namelist_rev,_,basic_blocks) = List.fold_left (fun (lst,k,acc) (name,cfg) ->
    let (lst',k,cfgstr) = pprint_ocaml_cps_from_cfg true cfg prog k in
    let acc = acc ^. us"(* Function: " ^. us(name) ^. us" *)\n\n" ^. cfgstr ^. us"\n" in
    (lst'@lst,k,acc) 
  ) ([],1,us"") cfglst in
  let namelist =
    ("final",0,{block_addr=0; block_code=[];
     block_exit=ExitTypeReturn; block_dist=0})::(List.rev namelist_rev) in

  let final_block = us"let final ms = ms\n\n" in
  
  (* Pretty print identifier list *)
  let ident_list = (List.fold_left (fun acc (n,k,_) ->
    acc ^. Ustring.spaces_after (us"let " ^. us n ^. us"_") identifier_padding ^.
    us(sprintf "= %d\n" k)
  ) (us"") namelist) ^. us"\n"
  in

  (* Get the next block id, or "na" if there is no next id *)
  let getNextId block =
    match block.block_exit with
    | ExitTypeNext(id) | ExitTypeBranch(_,id) | ExitTypeBrLikely(_,id) |
      ExitTypeJump(id) | ExitTypeCall(_,id) -> us id
    | ExitTypeReturn -> us"na"
  in

  (* Returns a "true" string if the block is a caller, else a "false" string *)
  let isCaller block =
    match block.block_exit with
    | ExitTypeCall(_,_) -> us"true"
    | _ -> us"false"
  in  

  (* Pretty print the basic block table *)
  let bbtable_start = us"let bblocks =\n[|\n" in
  let bbtable_end = us"|]\n\n" in
  let bbtable_list = List.fold_left (fun acc (n,_,b) ->
    acc ^. us"{" ^.
    Ustring.spaces_after (us"func=" ^. us n ^. us";") 14 ^.
    Ustring.spaces_after (us"name=\"" ^. us n ^. us"\";") 15 ^.
    Ustring.spaces_after (us"nextid=" ^. getNextId b ^. us"_;") 14 ^.
    Ustring.spaces_after (us"dist=" ^. us(sprintf "%d" b.block_dist) ^. us";") 10 ^.
    (us"addr=" ^. us(sprintf "0x%08x" b.block_addr) ^. us"; ")  ^.
    (us"caller=" ^. isCaller b ^. us";") ^.
    us"};\n"  
  ) (us"") namelist
  in
  let bbtable = bbtable_start ^. bbtable_list ^. bbtable_end in

  (* Analyze text *)
  let analyze = us"(* -- Start of Analysis -- *)\n\n" ^.
    us"let main = \n\t"
                  ^. us"let _st_time = Unix.gettimeofday() in\n"
                  ^. us"\tanalyze " ^. us name ^. us"_ bblocks gp_addr mem []" ^.
                  (if not record then
                      (
                      us" [" ^.
                         List.fold_left
                         (fun str (i,fn) -> (us "amap_" ^. fn ^. us ";") ^. str)
                         (us"] " ^. (ustring_of_int task_n)) (fnames @ [(0, us name)]))
                   else us " [] " ^. (ustring_of_int task_n))
    ^. us ";\n"
    ^. us"\tprintf \"Time Elapsed: %fs\\n\" (Unix.gettimeofday() -. _st_time)\n" in
  
  (* Return the complete .ml file *)
  intro ^. ident_list ^. blocks_header ^.
  final_block ^. basic_blocks ^. bbtable ^. analyze



 
  
  
type cfg =
{
  entry_node : bblockid;  (* ID to the entry node. This is the same as the function name *)
  exit_node  : bblockid;  (* ID to the exit node *)
  cfg_graph  : blockmap;  (* The mapping that represents the actual graph *)
}
    
type bblock =
{   
  block_addr : int;           (* Memory address of the first instruction in the block *)
  block_code : inst list;     (* Assembly code instructions of the bloc *)
  block_exit : exittype;      (* Exist variants with string block ids to the next nodes *)
  block_dist : int;           (* Shortest distance to the exit node in the CFG *)
}
                                  
let test prog fname cm_args =
  let (prog,cfgmap) = make_cfgmap fname prog in
  match cm_args with
  | (_,_,_,_,fnames,record,n,true,_) ->
     let program_code = pprint_ocaml_cps_from_cfgmap record fnames 0 true fname cfgmap prog in
     uprint_endline program_code
  | (args,optimize,max_cycles,bsconfig,fnames,record,task_n,pr_option,nocache)  ->
     try
       let debug = MipsSys.verbose_enabled() in
       let program_code = pprint_ocaml_cps_from_cfgmap record fnames task_n true fname cfgmap prog in
       let record = if record && fnames != [] then record else  false in
       args |> MipsSys.wcet_compile fname optimize debug max_cycles bsconfig record task_n nocache program_code |> print_endline;
     with Sys_error e ->
        e |> eprintf "%s\n";
     

        
