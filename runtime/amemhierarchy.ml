open Amemtype
open Amemory
open Acache
open Printf
open Aint32congruence
open Config

open Cpumodel
       
type cache_t =
  | Uni of acache
  | Sep of acache * acache

type cache_hierarchy_t =
  cache_t list
                    
type amemhierarchy = {
    mem : amemory;
    cache : cache_hierarchy_t;
    amap : mapstype option; 
  }

type memory_access_t = | DCache | ICache

let get_initialized_amh = function
  | AAny -> false
  | AInt32 v | AInt16(v,_) | AInt8(v,_,_,_) -> get_initialized v


let set_initialized_amh v i =
  match v with
  | AAny -> AInt32 (aint32_any_set i)
  | AInt32 v -> AInt32 (set_initialized v i)
  | AInt16(v1,v2) -> AInt16(set_initialized v1 i,set_initialized v2 i)
  | AInt8(v1,v2,v3,v4) -> AInt8(set_initialized v1 i,
                                set_initialized v2 i,
                                set_initialized v3 i,
                                set_initialized v4 i)

let get_cache ctype cache =
  match ctype,cache with
  | DCache, Uni dcache
    | DCache, Sep (_,dcache) -> dcache
  | ICache, Uni icache
    | ICache, Sep (icache,_) -> icache
                                  
let update_cache cache ctype c =
  match cache,ctype with
  | Uni cache,ICache
    | Uni cache,DCache -> Uni c
  | Sep (ic,dc),ICache -> Sep (c,dc)
  | Sep (ic,dc),DCache -> Sep (ic,c)

(************************ INIT BSS/SBSS ***********************)

type zero_section_t = BSS | SBSS
                              
let hmem_init_zero section addr size amem = 
  match section with
  | BSS -> 
     {amem.mem with bss = { addr = addr; size = size }} 
  | SBSS -> 
     {amem.mem with sbss = { addr = addr; size = size }} 
       
let disable_dcache hmem =
  let disable_internal cache = 
    match cache with
    | Uni cache -> Uni (disable_cache cache) 
    | Sep (icache,dcache) -> Sep (icache, disable_cache dcache)
  in
  let caches = hmem.cache in
  let cache = List.map disable_internal caches in
  {hmem with cache = cache}

let enable_dcache hmem =
  let enable_internal cache = 
    match cache with
    | Uni cache -> Uni (enable_cache cache) 
    | Sep (icache,dcache) -> Sep (icache, enable_cache dcache)
  in
  let caches = hmem.cache in
  let cache = List.map enable_internal caches in
  {hmem with cache = cache}

(* Update hmem_init to initialize *)
let hmem_init () =
  let init_internal c1 =
    match c1 with
    | U c -> Uni (cache_init_info c)
    | S (ic,dc) -> Sep (cache_init_info ic, cache_init_info dc)
  in
  let cache = List.map init_internal cache_model in
  {
    mem = mem_init ();
    cache = cache;
    amap = tag_init;
  }

let hmem_update_cache cache hmem =
  {hmem with cache = cache}

let hmem_update_mem mem hmem =
  {hmem with mem = mem}

let hmem_update_amap amap hmem =
  {hmem with amap = amap}

(************************ WRITE TO MEM HIERARCHY ***********************)

let rec reverse_append l1 l2 =
  match l1 with
  | [] -> l2
  | l::ls -> reverse_append ls (l::l2)

let get_tmaps t ts =
  let amap_others = List.map amap_read ts in
  let amap_others =
    match amap_others with
    | [] -> None
    | m::ms -> List.fold_left amap_merge m ms
  in 
  check_coherence amap_others (amap_read t)

let write_mem addr aval ctype caches mem amap =
  let mem = set_memval addr aval mem in

  let rec write_caches caches ticks ncaches =
    match caches with
    | [] -> ticks + mem.access_time, List.rev ncaches
    | c::cs ->
       let nticks,resp,c',_,_ = write_cache addr (get_cache ctype c) None in
       match resp with
       | Hit ->
          ticks + nticks,
         reverse_append ncaches ((update_cache c ctype c')::cs)
       | Miss ->
          write_caches cs (ticks+nticks)
            ((update_cache c ctype c')::ncaches) 
  in
  (*TODO(Romy): Check if needed None*)
  let write_cache_one caches amap =
    match caches with
    | [] -> mem.access_time,[],mem,None,amap
    | c::cs ->
       let nticks,resp,c',amap',coh = write_cache addr (get_cache ctype c) amap in
       let c' = (update_cache c ctype c') in
       match resp,coh with
       | Hit,Some Private | Hit, None -> nticks, c'::cs, mem, None,amap'
       | Miss,Some Private | Miss, None ->
          let ticks, caches = write_caches cs nticks [c'] in
          ticks, caches, mem, None, amap'
       | Hit,Some (OtherRead(_)) ->
          nticks + !inv_penalty, c'::cs, mem, None,amap'
       (*TODO(Romy): go up to the first shared cache/mem*)
       | Miss,Some (OtherRead(_)) ->
          let ticks, caches = write_caches cs nticks [c'] in
          max ticks !cache_penalty, caches, mem, None, amap'
          (*max ticks !cache_penalty, c'::cs, mem, None, amap'*)
       | Hit,Some (ThisRead) | Miss,Some (ThisRead) ->
          let ticks, caches = write_caches cs nticks [c'] in
          (* possible write - any data *)
          let mem = set_memval addr (AInt32 (aint32_any_set true)) mem in
          max ticks !cache_penalty, caches, mem, None, amap'
          (*max ticks !cache_penalty, c'::cs, mem, None, amap'*)
       | Hit,Some (ThisRW(_)) | Miss,Some (ThisRW(_)) ->
          let ticks, caches = write_caches cs nticks [c'] in
          (* possible write - any data *)
          let mem = set_memval addr (AInt32 (aint32_any_set true)) mem in
          max ticks (!cache_penalty + !inv_penalty), caches, mem, None, amap'
          (*max ticks (!cache_penalty + !inv_penalty), c'::cs, mem, None, amap'*)
  in
  if (!nocache) then
    (mem.access_time,caches,mem,None,amap)
  else
    write_cache_one caches amap

      
let read_mem addr slist ctype caches mem amap =
  let mem,sl,v = get_memval addr slist mem in
  let rec read_caches caches ticks ncaches otherW =
    match caches with
    | [] -> ticks + mem.access_time, List.rev ncaches
    | c::cs ->
       let cache = get_cache ctype c in
       if (otherW && (is_shared cache))
       then (
         read_caches cs (ticks + (cache_hit_rate cache)) ((update_cache c ctype cache)::ncaches)) otherW  
       else (
         let nticks,resp,c',_,_ = read_cache addr
           cache None in
         match resp with
         | Hit ->
            ticks + nticks, reverse_append ncaches ((update_cache c ctype c')::cs)
         | Miss ->
            read_caches cs (ticks+nticks) ((update_cache c ctype c')::ncaches) otherW)
  in
  let read_cache_one caches amap =
    match caches with
    | [] -> mem.access_time,sl,[],mem,v,amap
    | c::cs ->
       let nticks,resp,c',amap',coh = read_cache addr (get_cache ctype c) amap in
       let c' = (update_cache c ctype c') in
       match resp,coh with
       | Hit,Some Private | Hit, None -> 
		nticks, sl, c'::cs, mem, v,amap'
       | Miss,Some Private | Miss, None ->
          let ticks, caches = read_caches cs nticks [c'] false in
          ticks, sl, caches, mem, v, amap'
          (*ticks, sl, c'::cs, mem, v, amap'*)
       | Hit,Some (OtherRead(_)) -> nticks, sl,c'::cs, mem, v,amap'
       (*TODO(Romy): go up to the first shared cache/mem*)
       | Miss,Some (OtherRead(_)) ->
          let ticks, caches = read_caches cs nticks [c'] false in
          max ticks !cache_penalty, sl, caches, mem, v, amap'
          (*max ticks !cache_penalty, sl, c'::cs, mem, v, amap'*)
       | Hit,Some (ThisRead) | Miss,Some (ThisRead) ->
          let ticks, caches = read_caches cs nticks [c'] true in
          let v = AInt32 (aint32_any_set true) in (* (get_initialized_amh v)) in *)
          max ticks !cache_penalty, sl, caches, mem, v, amap'
          (*max ticks !cache_penalty, sl, c'::cs, mem, v, amap'*)
       | Hit,Some (ThisRW(_)) | Miss,Some (ThisRW(_)) ->
          let ticks, caches = read_caches cs nticks [c'] true in
          let v = AInt32 (aint32_any_set true) in (* (get_initialized_amh v)) in *)
          (*max ticks (!cache_penalty + !inv_penalty), sl, c'::cs, mem, v, amap'*)
          max ticks (!cache_penalty + !inv_penalty), sl, caches, mem, v, amap'
  in
  if (!nocache) then
    (mem.access_time,sl,caches,mem,v,amap)
  else 
    read_cache_one caches amap 

(************************* MAIN MEMORY OPERATIONS ************************)
    
let getval_aint32 bigendian v =
  match v with
  | AInt32 v -> v
  | AInt16 (v1,v2) ->
     if bigendian then aint16_merge v1 v2
     else aint16_merge v1 v2
  | AInt8 (v0,v1,v2,v3) ->
     if bigendian then
       aint16_merge (aint8_merge v0 v1) (aint8_merge v2 v3)
     else
       aint16_merge (aint8_merge v3 v2) (aint8_merge v1 v0)
  | AAny -> aint32_any_set true

let getval_aint16 bigendian v =
  let v0,v2 =
    match v with
    | AInt32 v -> aint32_split bigendian v
    | AInt16 (v0,v2) -> (v0,v2)
    | AInt8 (v0,v1,v2,v3) ->
       if bigendian then
         ((aint8_merge v0 v1),(aint8_merge v2 v3))
       else
         ((aint8_merge v1 v0),(aint8_merge v3 v2))
    | AAny -> (aint32_any_set true,aint32_any_set true)
  in (v0,v2)
    
let getval_aint8 bigendian v =
    match v with
    | AInt32 v ->
       let v0,v2 = aint32_split bigendian v in
       let v0,v1 = aint16_split bigendian v0 in
       let v2,v3 = aint16_split bigendian v2 in
       (v0,v1,v2,v3)
    | AInt16 (v0,v2) ->
       let v0,v1 = aint16_split bigendian v0 in
       let v2,v3 = aint16_split bigendian v2 in
       (v0,v1,v2,v3)
    | AInt8 (v0,v1,v2,v3) -> (v0,v1,v2,v3)
    | AAny -> (aint32_any_set true,aint32_any_set true,aint32_any_set true,aint32_any_set true)


(**************** Read and Write operations ****************)

let set_memval_word addr v mem =
  let ticks,c,m,_,amap = write_mem addr (AInt32 v) DCache
                                   mem.cache mem.mem mem.amap in
  (ticks,mem |> hmem_update_cache c
         |> hmem_update_mem m |> hmem_update_amap amap)

let set_memval_hword addr v mem =
  let addr0, hword = (addr lsr 2) lsl 2, addr land 0x3 in
  let ticks,_,_,m,oldv,_ = read_mem addr0 [] DCache
                                  mem.cache mem.mem None in 
  let v0,v2 = getval_aint16 false oldv in
  let v = check_aint16 v in
  let newv =
    match hword with
    | 0 -> AInt16 (v,v2) | 2 -> AInt16(v0,v)
    | _ -> failwith (sprintf "Error set_memval_hword hword=%d" hword)
  in
  let _,c,m,_,amap = write_mem addr0 newv DCache
                               mem.cache mem.mem mem.amap in
  (ticks,mem |> hmem_update_cache c |> hmem_update_mem m |> hmem_update_amap amap)


let set_memval_byte addr v mem =
  let addr0, byte = (addr lsr 2) lsl 2, addr land 0x3 in 
  let ticks,_,_,m,oldv,_ = read_mem addr0 [] DCache mem.cache mem.mem None in 
  let v0,v1,v2,v3 = getval_aint8 false oldv in
  let v = check_aint8 v in
  let newv =
    match byte with
    | 0 -> AInt8 (v,v1,v2,v3)
    | 1 -> AInt8 (v0,v,v2,v3)
    | 2 -> AInt8 (v0,v1,v,v3)
    | 3 -> AInt8 (v0,v1,v2,v)
    | _ -> failwith (sprintf "Error set_memval_byte byte=%d" byte)            in
  let ticks,c,m,_,amap = write_mem addr0 newv DCache mem.cache mem.mem mem.amap in
  (ticks,mem |> hmem_update_cache c |> hmem_update_mem m |> hmem_update_amap amap)

let get_memval_word addr slist mem =
  let ticks,sl,c,m,v,amap = read_mem addr slist DCache mem.cache mem.mem mem.amap in 
  (ticks,
   sl,
   mem |> hmem_update_cache c |> hmem_update_mem m |> hmem_update_amap amap,
   v |> getval_aint32 false)
      
let get_memval_hword addr slist mem =
  let addr0, hword = (addr lsr 2) lsl 2, addr land 0x3 in
  let ticks,sl,c,m,v,amap = read_mem addr0 slist DCache mem.cache mem.mem mem.amap in 
  let v0,v2 = getval_aint16 false v in
  let v =
    match hword with
    | 0 -> v0  | 2 -> v2
    | _ -> failwith (sprintf "Error get_memval_hword hword=%d" hword)
  in (ticks,
      sl,
      mem |> hmem_update_cache c |> hmem_update_mem m |> hmem_update_amap amap,
      v)

let get_memval_byte addr slist mem =
  let addr0, byte = (addr lsr 2) lsl 2, addr land 0x3 in
  let ticks,sl,c,m,v,amap = read_mem addr0 slist DCache mem.cache mem.mem mem.amap in 
  let v0,v1,v2,v3 = getval_aint8 false v in
  let v =
      match byte with
      | 0 -> v0  | 1 -> v1  | 2 -> v2  | 3 -> v3
      | _ -> failwith (sprintf "Error get_memval_byte byte=%d" byte)
  in (ticks,
      sl,
      mem |> hmem_update_cache c |> hmem_update_mem m
      |> hmem_update_amap amap,
      v)

let hcache_join c1 c2 = 
  let join_internal c1 c2 =
    match c1,c2 with
    | Uni c1, Uni c2 -> Uni (cache_join c1 c2)
    | Sep (ic1,dc1), Sep (ic2,dc2) -> Sep (cache_join ic1 ic2, cache_join dc1 dc2) 
    | _ -> failwith ("impossible")
  in
  (List.map2 join_internal c1 c2) 

let hmem_join m1 m2 =
  {
    mem = mem_join [m1.mem;m2.mem];
    cache = hcache_join m1.cache m2.cache;
    amap = amap_join m1.amap m2.amap;
  }
  

(********* INSTRUCTION CACHE **********)
let get_instruction addr hmem =
  let ticks,_,cache,mem,_,amap = read_mem addr [] ICache hmem.cache hmem.mem hmem.amap in
  (ticks,hmem |> hmem_update_cache cache |> hmem_update_amap amap)

(* Instruction Miss for return address "jr ra" *)
let get_instruction_always_miss hmem =
  let ma = get_mem_acc () in
  List.fold_left (fun t c -> t + miss_cache (get_cache ICache c)) (ma) (hmem.cache)

(********* LD and ST -> ANY - Case of a interval access *******) 
let ld_any hmem =
  let caches = hmem.cache in
  let ma = get_mem_acc () in
  let ticks = List.fold_left (fun t c -> t + miss_cache (get_cache DCache c)) (ma) caches in
  (ticks, hmem, aint32_any_set true)

let st_any hmem =
  let cache_to_any cache = 
    match cache with
    | Uni c ->   Uni (cache_to_any c) 
    | Sep (ic,dc) -> Sep (ic, cache_to_any dc)
  in
  let cs = hmem.cache in
  let ma = get_mem_acc () in
  let ticks = List.fold_left (fun t c -> t + miss_cache (get_cache DCache c)) (ma) (cs) in
  let cache = List.map cache_to_any hmem.cache in
  let hmem = {hmem with mem = mem_to_any hmem.mem;
                        cache = cache;}
  in
  (ticks, hmem)


(********************************************)
let print_amem str hmem =
  match hmem.amap with
  | Some (RMap amap) ->
     amap_print str amap
  | _ -> ""

let print_amem2 str amap =
  amap_print str amap
    
let read_amem lst =
  amap_read lst

let print_hmem_stats hmem = ()
    
