" Projective Verilog extension
" TODO decide where to handle empty nodes

command! Simvision    : call Simvision_connect()
command! UpdateDesign : call Generate_tree()

func! s:set_make(clean)
    if a:clean
        let s:files = []
        let s:modules = {}
        call Projective_save_file([], 'ncvlog/ncvlog.args')
    endif
endfunc

func! s:syntax_check()
    if !empty(getqflist({'winid': 1})) && s:last_qf_is_make | return | endif
    let s:saved_make_opts = [g:projective_make_dir, g:projective_make_cmd, g:projective_make_console]
    let g:projective_make_dir = s:syntax_check_dir
    let g:projective_make_cmd = 'ncvlog -sv -f ncvlog.args defines.v ' . expand('%:p')
    let g:projective_make_console = 0
    let s:syntax_check = 1
    call Projective_make(0)
endfunc

func! s:make_post()
    if s:syntax_check
	let lines = readfile(s:syntax_check_dir . '/ncvlog.log')
    else
        let log = expand(g:projective_make_dir . '/' . g:projective_verilog_log_file)
	let lines = systemlist('grep "nc\(vlog\|elab\):\s*\*E" ' . log)
    endif

    let my_qf = []
    for l in lines
	if l =~ '\C\v^nc%(vlog|elab): \*E,'
	    let m = matchlist(l, '(\([^)]*\),\(\d\+\)|\?\(\d*\)):\s*\(.*\)')
	    if !empty(m)
		if m[3] == ''
		    let m[3] = 0
		endif
		let fname = (m[1] =~ '^[/~$]' ? m[1] : expand(g:projective_make_dir . '/' . m[1]))
		call add(my_qf, {'filename': fname, 'lnum': m[2], 'col': m[3]+1, 'text': m[4], 'type': 'E'})
	    else
		call add(my_qf, {'text': l, 'type': 'E'})
	    endif
	endif
    endfor
    let s:last_qf_is_make = !s:syntax_check && !empty(my_qf)
    if s:syntax_check
        let [g:projective_make_dir, g:projective_make_cmd, g:projective_make_console] = s:saved_make_opts
        let s:syntax_check = 0
    elseif empty(my_qf)
        " TODO add job handle
        call job_start(['/bin/sh', '-c',
                    \ 'grep "^file:\|^\s*module\>" ' . log . ' | sed -e "s/^file: /-/; s/^\s*module \w*\.\(\w*\):.*/\1/"'],
                    \ {'close_cb': function('s:update_db')})
        let args = s:syntax_check_dir . '/ncvlog.args'
        call job_start(['/bin/sh', '-c',
                    \ 'touch ' . args . '; ' .
                    \ 'grep "^Include:" ' . log . ' | sed -e "s/^Include:/-incdir/; s+/[^/]* (.*++" >> ' . args . '; ' .
                    \ 'sort -u -o ' . args . ' ' . args],
                    \ {'close_cb': function('s:close_args')})
    endif
    return my_qf
endfunc

func! s:update_db(channel)
    let fd = {}
    let i = 0
    for f in s:files
	let fd[f] = i
        let i += 1
    endfor

    while ch_status(a:channel) == 'buffered'
        let l = ch_read(a:channel)
        if l[0] == '-'
            let f = l[1:]
            if f !~ '^[~/$]'
        	let f = g:projective_make_dir . '/' . f
            endif
            if has_key(fd, f)
                let idx = fd[f]
            else
                call add(s:files, f)
                let fd[f] = i
                let idx = i
                let i += 1
            endif
        else
            let s:modules[l] = idx
        endif
    endwhile

    call Projective_set_files(s:files)
    call Projective_save_file([string(s:modules)], 'modules.p')
"    echo 'Updating `defines...'
    let cmd = "grep -h '^\\s*`define' " . join(s:files)
    call Projective_save_file([cmd], '.tmp_exec.sh')
    let cmdf = Projective_path('.tmp_exec.sh')
    let perm = getfperm(cmdf)
    if perm[2] != 'x'
	call setfperm(cmdf, 'rwx' . perm[3:])
    endif
    call job_start(['/bin/sh', '-c', cmdf], {
                \ 'out_io': 'file',
		\ 'out_name' : s:syntax_check_dir . '/defines.v',
		\ 'close_cb': function( 's:close_defines')})
endfunc

func! s:close_defines(channel)
    "echo 'defines updated!'
endfunc

func! s:close_args(channel)
    "echo 'args updated!'
endfunc

func! s:new_tree()
    call Projective_new_tree()
    let node = Projective_new_node(g:projective_verilog_design_top)
    let node.module = g:projective_verilog_design_top
    call Projective_open_tree_browser()
endfunc

func! verilog#Projective_init()
    let g:Projective_after_make = function('s:make_post')
    let g:Projective_before_make = function('s:set_make')
    let g:Projective_tree_init_node = function('s:scope_init')
    let g:Projective_tree_user_mappings = function('s:tree_mappings')

    let s:files = Projective_get_files()
    let m = Projective_read_file('modules.p')
    if empty(m)
        let s:modules = {}
    else
        let s:modules = eval(m[0])
    endif

    let s:syntax_check_dir = Projective_path('ncvlog')
    if !isdirectory(s:syntax_check_dir)
        call mkdir(s:syntax_check_dir)
    endif

    call Projective_load_tree()
    if empty(Get_node_by_path([g:projective_verilog_design_top]))
        call s:new_tree()
    endif

    let s:tree_file = expand(g:projective_make_dir . '/scope_tree.txt')
    if !exists('s:cdn_dir')
        " TODO how to manage lang directories?
        let s:cdn_dir = globpath(&rtp, 'languages/verilog-IES')
        let s:get_scope_pl = s:cdn_dir . '/get_scope.pl'
    endif

    augroup verilog_mini_make
	au!
	au BufWritePost *.v call s:syntax_check()
	au BufWritePost *.v call s:get_instances_map()
        au BufEnter *.v if !s:event_ignore
                    \ | call s:update_cur_scope()
                    \ | call s:update_hl('')
                    \ | endif
        au CursorMoved *.v call s:hl_path()
        " TODO vim_dev
"        au BufLeave quickfix let s:global_qf_open = 0
    augroup END

    map <silent> <leader>va :call <SID>scope_up()<CR>
    map <silent> <leader>vv :call <SID>scope_down()<CR>
    map <silent> <leader>vs :call <SID>send_to_schematic()<CR>
    map <silent> <leader>vf :call <SID>get_schematic()<CR>

    let s:syntax_check = 0
    let s:prev_ln = 0
    let s:prev_inst = ''
    let s:prev_hl = {}
    let s:global_qf_open = 0

"    echo g:projective_project_type . ' init done!'
endfunc

func! verilog#Projective_cleanup()
    au! verilog_mini_make
    if exists('g:simvision_ch') && ch_status(g:simvision_ch) == 'open'
        call ch_close(g:simvision_ch)
    endif
    call Projective_save_tree()
    unlet s:modules
    unlet s:files
    unlet g:projective_verilog_64_bit

    unmap <leader>va
    unmap <leader>vv
    unmap <leader>vs
    unmap <leader>vf
"    echo g:projective_project_type . ' cleanup done!'
endfunc

""""""""""""""""""""""""""""""""""""""""""""""""
" hierarchy
""""""""""""""""""""""""""""""""""""""""""""""""
func! Generate_tree()
    let ftime = getftime(s:tree_file) " TODO print_scope_tree is not really blocking
    call s:simvision_eval('print_scope_tree')
    while getftime(s:tree_file) == ftime
        sleep 100m
    endwhile
    echo 'Design hierarchy was updated!'
    call s:new_tree()
endfunc

func! s:scope_init(node)
    let cmd = s:get_scope_pl . ' ' . s:tree_file . ' ' . join(Projective_get_path(a:node), '.')
    let ret = Projective_system(cmd)
    for s in ret
        let sp = split(s)
        let child = Projective_new_node(sp[1])
        let child.leaf = (sp[0] == '-')
        let child.module = sp[2]
        call Projective_new_child(a:node, child)
    endfor
    let a:node.cached = 1
endfunc

func! s:tree_mappings()
    map <silent> <buffer> e :call <SID>edit_tree_scope()<CR>
endfunc

let s:event_ignore = 0

func! s:edit_tree_scope()
    let node = Projective_get_node_by_line(line('.'))
    " TODO open a new window if needed
    let s:event_ignore = 1
    silent! wincmd p
    call <SID>edit_scope(node, 'e')
endfunc

func! s:edit_scope(node, cmd)
    let s:event_ignore = 1
    let f = s:files[s:modules[a:node.module]]
    exe a:cmd f
    keepj norm! gg
    call search('^\s*module\s\+' . a:node.module)
    norm! zt
    let b:verilog_scope = Projective_get_path(a:node)
    let s:cur_scope = a:node
    if !a:node.cached
        " TODO use async job
        call s:scope_init(a:node)
    endif
    call s:get_instances_map()
    call s:update_hl('')
    let s:event_ignore = 0
endfunc

func! s:update_cur_scope()
    let s:cur_scope = {}
    if exists('b:verilog_scope')
        let s:cur_scope = Get_node_by_path(b:verilog_scope)
    endif
    call s:get_instances_map()
endfunc

func! s:get_instances_map()
    "TODO might not work properly with old grep (2.5.1) - two matches in a
    "line with -o issue
    let s:instances = {}
    if empty(s:cur_scope) | return | endif
    let inst = map(Projective_get_children(s:cur_scope), {k, v -> v.name})
    let cmd = 'grep -onE ''\<(' . join(inst, '|') . ')\>\s*($|\(|/[/*])|\);'' ' . expand('%')
                \ . ' | grep -A 1 '':[^)]'''
    call job_start(['sh', '-c', cmd], {'close_cb': function('s:get_instances_map_cb')})
endfunc

func! s:get_instances_map_cb(channel)
    " TODO confirm grep results by searching for the actual module name
    let inst_lnum = 0
    while ch_status(a:channel) == 'buffered'
	let line = ch_read(a:channel)
        if line[0] == '-' | continue | endif
	let l = matchstr(line, '^\d\+')
        let t = matchstr(line, ':\zs\()\|\w\+\)')
	if t[0] != ')'
            let inst_lnum = l
	    let inst_name = t
	elseif inst_lnum
	    for i in range(inst_lnum, l)
		let s:instances[i] = inst_name
	    endfor
	    let inst_lnum = 0
	endif
    endwhile
endfunc

" TODO add protection
func! s:scope_up()
    let node = Projective_get_parent(s:cur_scope)
    call s:edit_scope(node, 'e')
endfunc

func! s:scope_down()
    let node = Get_node_by_path([s:instances[line('.')]], s:cur_scope)
    call s:edit_scope(node, 'e')
endfunc

" TODO use node ids for speed?
func! s:hl_path()
    if line('.') == s:prev_ln | return | endif
    let s:prev_ln = line('.')
    let cur_inst = get(s:instances, line('.'), '')
    if cur_inst == s:prev_inst | return | endif
    let s:prev_inst = cur_inst
    call s:update_hl(cur_inst)
endfunc

func! s:update_hl(cur_inst)
    if a:cur_inst == ''
        let hl_scope = s:cur_scope
        let hl_val = 2
    else
        let hl_scope = Get_node_by_path([a:cur_inst], s:cur_scope)
        let hl_val = 3
    endif
    while !empty(s:prev_hl)
        call Projective_set_node_hl(s:prev_hl, 0)
	let s:prev_hl = Projective_get_parent(s:prev_hl)
    endwhile
    let s:prev_hl = hl_scope
    while !empty(hl_scope)
	call Projective_set_node_hl(hl_scope, hl_val)
	if hl_val > 1 | let hl_val -= 1 | endif
        let hl_scope = Projective_get_parent(hl_scope)
    endwhile
    call Projective_hl_tree()
endfunc

""""""""""""""""""""""""""""""""""""""""""""""""
" Simvision
""""""""""""""""""""""""""""""""""""""""""""""""

func! s:simvision_eval(cmd)
    call Simvision_connect()
    while !exists('g:simvision_ch') || ch_status(g:simvision_ch) != 'open'
        sleep 100m
    endwhile
    return ch_evalraw(g:simvision_ch, "request {" . a:cmd . "}\n")
endfunc

func! s:get_word_under_cursor()
    return matchstr(getline('.'), '\w*\%' . col('.') . 'c\w*')
endfunc

func! s:send_to_schematic()
    let design_obj = join(Projective_get_path(s:cur_scope), '.') . '.' . s:get_word_under_cursor()
    call s:simvision_eval('schematic add ' . design_obj . '; select set ' . design_obj)
endfunc

func! s:get_schematic()
    let cs = s:simvision_eval('schematic curselection')
    let cs = substitute(cs, '^.*::', '', '')
    let sp = split(cs, '\.')
    let scope = Get_node_by_path([sp[0]])
    for s in sp[1:-2] " TODO add protection
        if !scope.cached
            " TODO use async job
            call s:scope_init(scope)
        endif
        let scope = Get_node_by_path([s], scope)
    endfor
    call s:edit_scope(scope, 'e')
    call search('\<' . matchstr(sp[-1], '\w\+') . '\>')
    norm! zz
endfunc

func! s:find_free_port()
    let nmap = systemlist('nmap -p 4000-6000 --open localhost')
    let open_ports = {}
    for p in nmap
        if p =~ '^\d\+/tcp'
            let open_ports[matchstr(p, '^\d\+')] = 1
        endif
    endfor
    for i in range(4000, 6000)
        if !has_key(open_ports, i)
            return i
        endif
    endfor
endfunc

if !exists('simvision_chs')
    let simvision_chs = {}
endif

func! Simvision_connect()
    if has_key(g:simvision_chs, g:projective_project_name)
        if ch_status(g:simvision_chs[g:projective_project_name].ch) != 'open'
            let g:simvision_chs[g:projective_project_name].ch = ch_open('localhost:' . g:simvision_chs[g:projective_project_name].port, {'mode': 'nl'})
        endif
        if ch_status(g:simvision_chs[g:projective_project_name].ch) == 'open'
            let g:simvision_ch = g:simvision_chs[g:projective_project_name].ch
            return
        endif
    endif

    let file = expand(g:projective_make_dir . '/projective.tcl')
    let simvision_port = s:find_free_port()
    call writefile(['startServer ' . simvision_port], file)
    let flag_64 = exists('g:projective_verilog_64_bit') && g:projective_verilog_64_bit ? '-64BIT' : ''
    let g:simvision_cmd = 'cd ' . g:projective_make_dir . '; ' .
     \ 'simvision ' . flag_64 . ' -nosplash -schematic -snapshot worklib.' . g:projective_verilog_design_top . ':v ' .
     \ '-memberplugindir ' . s:cdn_dir . '/scope_tree_plugin ' .
     \ '-input ' . s:cdn_dir . '/server.tcl -input projective.tcl &'
     call system(g:simvision_cmd)
    call timer_start(1000, function('s:simvision_connect_try', [simvision_port]), {'repeat': 60}) 
endfunc

func! s:simvision_connect_try(port, timer)
    let g:simvision_ch = ch_open('localhost:' . a:port, {'mode':'nl'})
    if ch_status(g:simvision_ch) == 'open'
        let g:simvision_chs[g:projective_project_name] = {}
        let g:simvision_chs[g:projective_project_name].ch = g:simvision_ch
        let g:simvision_chs[g:projective_project_name].port = a:port
        echo 'Successfully connected to Simvision!'
        call timer_stop(a:timer)
    endif
endfunc
