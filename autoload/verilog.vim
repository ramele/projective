" Projective Verilog extension

command! Simvision    :call s:simvision_connect()
command! UpdateDesign :call s:generate_tree()

func! s:set_make(clean)
    if a:clean
        let s:files = []
        let s:modules = {}
        call Projective_save_file([], 'ncvlog/ncvlog.args')
    endif
endfunc

func! s:syntax_check()
    if !empty(getqflist({'winid': 1})) && s:last_qf_is_make
        return
    endif
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
	let lines = Projective_system('grep "\*[EF]," ' . log)
    endif

    let my_qf = []
    for l in lines
	if l =~ '\C\*[EF],'
	    let m = matchlist(l, '(\([^)]*\),\(\d\+\)|\?\(\d*\)):\s*\(.*\)')
	    if !empty(m)
		if m[3] == ''
		    let m[3] = 0
		endif
		let fname = (m[1] =~ '^[/~$]' ? m[1] : expand(g:projective_make_dir . '/' . m[1]))
		call add(my_qf, {'filename': fname, 'lnum': m[2], 'col': m[3]+1, 'text': m[4], 'type': 'E'})
	    else
		call add(my_qf, {'text': matchstr(l, '\*[EF],.*'), 'type': 'E'})
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
                    \ 'grep "^file:\|^\s*module\>" ' . log . ' | sed "s/^file: /-/; s/^\s*module \w*\.\(\w*\):.*/\1/"'],
                    \ {'close_cb': function('s:update_db')})
        let args = s:syntax_check_dir . '/ncvlog.args'
        call job_start(['/bin/sh', '-c',
                    \ 'touch ' . args . '; ' .
                    \ 'grep "^Include:" ' . log . ' | sed "s/^Include:/-incdir/; s+/[^/]* (.*++" >> ' . args . '; ' .
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
    let cmdf = s:set_cmd_file([cmd], 'get_defines.sh')
    call job_start(['/bin/sh', '-c', cmdf], {
                \ 'out_io': 'file',
		\ 'out_name' : s:syntax_check_dir . '/defines.v',
		\ 'close_cb': function( 's:close_defines')})
endfunc

func! s:set_cmd_file(cmd, file)
    call Projective_save_file(a:cmd, a:file)
    let cmdf = Projective_path(a:file)
    let perm = getfperm(cmdf)
    if perm[2] != 'x'
	call setfperm(cmdf, 'rwx' . perm[3:])
    endif
    return cmdf
endfunc

func! s:close_defines(channel)
    "echo 'defines updated!'
endfunc

func! s:close_args(channel)
    "echo 'args updated!'
endfunc

func! s:new_tree(init_depth)
    if !s:search_inst_active
        let s:prev_hl = {}
    endif
    call Projective_new_tree()
    let s:scope_buf = 0
    let node = Projective_new_node(g:projective_verilog_design_top)
    let node.module = g:projective_verilog_design_top
    if a:init_depth
        call Projective_init_recursively(a:init_depth)
    endif
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

    call Projective_load_tree('tree.p')
    if Projective_is_empty_tree()
        call s:new_tree(0)
    endif

    let s:tree_file = expand(g:projective_make_dir . '/scope_tree.txt')
    let s:search_inst_file = expand(g:projective_make_dir . '/scope_search.txt')
    let s:tree_avail = (glob(s:tree_file) != '')
    if !exists('s:cdn_dir')
        " TODO how to manage lang directories?
        let s:cdn_dir = globpath(&rtp, 'languages/verilog-IES')
        let s:get_scope_pl = s:cdn_dir . '/get_scope.pl'
        let s:search_inst_pl = s:cdn_dir . '/search_inst.pl'
    endif

    let flag_64 = exists('g:projective_verilog_64_bit') && g:projective_verilog_64_bit ? '-64BIT ' : ''
    let g:simvision_cmd = 'cd ' . g:projective_make_dir . ';' .
                        \ ' simvision ' . flag_64 . '-nosplash -snapshot ' . g:projective_verilog_design_top .
                        \ ' -memberplugindir ' . s:cdn_dir . '/scope_tree_plugin'
    let g:simvision_server_cmd = g:simvision_cmd . ' -input ' . s:cdn_dir . '/server.tcl'

    augroup projective_verilog_commands
	au!
	au BufWritePost *.v,*.sv call s:syntax_check()
	au BufWritePost *.v,*.sv call s:get_instances_map()
        au BufEnter *.v,*.sv call s:update_cur_scope()
        au CursorMoved *.v,*.sv call s:hl_path()
    augroup END

    map <silent> <leader>va :call <SID>scope_up()<CR>
    map <silent> <leader>vv :call <SID>scope_down()<CR>
    map <silent> <leader>vs :call <SID>send_to_schematic()<CR>
    map <silent> <leader>vf :call <SID>get_schematic()<CR>
    map <silent> <leader>vi :call <SID>find_instance()<CR>

    let s:syntax_check = 0
    let s:prev_ln = 0
    let s:prev_inst = ''
    let s:prev_hl = {}
    let s:instances = {}
    let s:scope_buf = 0
    let s:console_open = 0
    let s:search_inst_buf = 0
    let s:search_inst_active = 0

    if &ft == 'verilog'
        call s:update_cur_scope()
    endif
"    echo g:projective_project_type . ' init done!'
endfunc

func! verilog#Projective_cleanup()
    au! projective_verilog_commands
    if exists('g:simvision_ch') && ch_status(g:simvision_ch) == 'open'
        call ch_close(g:simvision_ch)
    endif
    call Projective_save_tree('tree.p')
    unlet s:modules
    unlet s:files
    unlet! g:projective_verilog_64_bit
    unlet! g:projective_verilog_grid

    unmap <leader>va
    unmap <leader>vv
    unmap <leader>vs
    unmap <leader>vf
    unmap <leader>vi
"    echo g:projective_project_type . ' cleanup done!'
endfunc

""""""""""""""""""""""""""""""""""""""""""""""""
" hierarchy
""""""""""""""""""""""""""""""""""""""""""""""""
" TODO TEMP. waiting for setbufline() in vimL...
"
func! s:console_open()
    if s:console_open
        return
    endif
    call Projective_run_job('cat', {->0}, 'Simvision')
    let s:console_open = 1
endfunc

func! s:console_msg(...)
    if !s:console_open
        return
    endif
    call Projective_ch_send(a:000[a:0-1])
    sleep 1m
    redr
endfunc

func! s:console_close()
    if !s:console_open
        return
    endif
    sleep 10m
    call job_stop(g:projective_job)
    let s:console_open = 0
endfunc

func! s:console_send_job(job)
    " TODO kill job when hitting C-C in the console
    call job_start(['/bin/sh', '-c', a:job], {'callback': function('s:console_msg')})
endfunc

func! s:generate_tree()
    call s:console_open()
    call s:console_msg('Getting Design hierarchy from SimVision. Please wait...')
    let s:check_modified = 1
    let s:tree_ftime = getftime(s:tree_file)
    if exists('g:projective_verilog_grid')
        call s:console_msg('')
        call s:console_msg('Starting remote SimVision')
        let cmdf = s:set_cmd_file([g:simvision_cmd . ' -input projective.tcl'], 'simvision_get_tree.sh')
        let file = expand(g:projective_make_dir . '/projective.tcl')
        call writefile(['print_scope_tree -include cells', 'exit'], file)
        call s:console_send_job(g:projective_verilog_grid . ' ' . cmdf)
    else
        call s:simvision_eval('print_scope_tree -include cells')
    endif
    call timer_start(1100, function('s:generate_tree_cb'), {'repeat': -1}) " must be > 1s
endfunc

func! s:generate_tree_cb(timer)
    let new_ftime = getftime(s:tree_file)
    if s:check_modified
        if new_ftime != s:tree_ftime
            let s:check_modified = 0
        endif
    else
        if new_ftime == s:tree_ftime
            call s:console_msg('Design hierarchy was updated!')
            let s:tree_avail = 1
            call s:new_tree(2)
            call s:console_close()
            call timer_stop(a:timer)
        endif
    endif
    let s:tree_ftime = new_ftime
endfunc

let s:scope_init_tick = 0 " TODO handle this in projective.vim

func! s:enable_init_tick()
    let s:scope_init_tick = 1
    let s:rt = reltime()
endfunc

func! s:disable_init_tick()
    if s:scope_init_tick > 1
        redr
        echo 'loading design tree ' . repeat('.', s:scope_init_tick) . ' done'
    endif
    let s:scope_init_tick = 0
endfunc

func! s:scope_init(node)
    if s:scope_init_tick
        if str2float(reltimestr(reltime(s:rt))) > 0.3
            redr
            echo 'loading design tree ' . repeat('.', s:scope_init_tick)
            let s:scope_init_tick += 1
        endif
    endif
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
    map <silent> <buffer> <F5> :call <SID>refresh_tree()<CR>
    " TODO add autocmd to restore tree
endfunc

func! s:refresh_tree()
    if !s:search_inst_active
        let s:tree_avail = (glob(s:tree_file) != '')
        if s:tree_avail
            call s:new_tree(2)
        endif
    endif
endfunc

let s:event_ignore = 0

func! s:edit_tree_scope()
    let node = Projective_get_node_by_line(line('.'))
    " TODO open a new window if needed
    let s:event_ignore = 1 " will be reset in edit_scope()
    silent! wincmd p
    call <SID>edit_scope(node, 'e')
    if s:search_inst_active
        call s:restore_tree()
    endif
endfunc

func! s:update_tree_view()
    " TODO do this async?
    " TODO check if can be done from update_hl()
    if empty(s:scope)
        return
    endif
    if !s:scope.cached
        call s:scope_init(s:scope)
    endif
    let node = s:scope
    let needs_update = 0
    while !empty(node)
        if !node.expanded
            let needs_update = 1
            let node.expanded = 1
        endif
        let node = Projective_get_parent(node)
    endwhile
    if needs_update
        call Projective_tree_refresh(1)
    endif
endfunc

func! s:edit_scope(node, cmd)
    let s:event_ignore = 1
    let f = s:files[s:modules[a:node.module]]
    exe a:cmd f
    keepj norm! gg
    call search('^\s*module\s\+' . a:node.module)
    norm! zt
    let b:verilog_scope = Projective_get_path(a:node)
    let s:scope = a:node
    if !s:search_inst_active
        call s:update_tree_view()
        call s:get_instances_map()
        call s:update_hl('')
    endif
    let s:scope_buf = bufnr('%')
    let s:event_ignore = 0
endfunc

func! s:update_cur_scope()
    " TODO use timer to make sure buffer was changed manually
    if s:event_ignore || s:scope_buf == bufnr('%') || !s:tree_avail || bufwinnr('Agrep') > -1
        return
    endif
    let s:scope_buf = bufnr('%')
    if exists('b:verilog_scope')
        call s:enable_init_tick()
        let s:scope = Get_node_by_path(b:verilog_scope)
        call s:disable_init_tick()
    else
        let s:scope = {}
    endif
    call s:update_tree_view()
    call s:get_instances_map()
    call s:update_hl('')
    if empty(s:scope)
        call s:search_inst()
    endif
endfunc

let s:find_instance_sync = 0

func! s:search_inst()
    let s:n_instances = 0
    let ml = search('^\s*module\>', 'bn')
    let s:module_name = matchstr(getline(ml), '^\s*module\s\+\zs\w\+')
    if s:module_name == ''
        let s:find_instance_sync = 0
        return
    endif
    let cmd = s:search_inst_pl . ' ' . s:tree_file . ' ' . s:module_name
    call job_start(['sh', '-c', cmd],
                \ { 'out_io': 'file',
		\ 'out_name' : s:search_inst_file,
                \ 'close_cb': function('s:search_inst_cb')})
endfunc

func! s:search_inst_cb(channel)
    let s:n_instances = matchstr(Projective_system('head -1 ' . s:search_inst_file)[0], '\d\+')
    if s:find_instance_sync
        let s:find_instance_sync = 0
        return
    endif

    let s:search_inst_buf = bufnr('%')
    if s:n_instances == 1
        let b:verilog_scope = []
        let lines = readfile(s:search_inst_file)
        for l in lines
            let m = matchstr(l, '^\s*[+-]-\zs\w\+')
            if m != ''
                call add(b:verilog_scope, m)
            endif
        endfor
        let s:scope_buf = 0
        call s:update_cur_scope()
        echo 'verilog: Scope was updated to ' . join(b:verilog_scope, '.') 
    elseif s:n_instances > 1
        echo 'verilog: Found ' . s:n_instances . ' instances of ' . s:module_name . '. Type \vi to select an instance'
    else
        let s:search_inst_buf = 0
        echo 'verilog: Couldn''t find instances of ' . s:module_name
    endif
endfunc

func! s:find_instance()
    if s:search_inst_buf != bufnr('%')
        let s:find_instance_sync = 1
        call s:search_inst()
        while s:find_instance_sync
            sleep 100m
        endwhile
    endif
    " TODO message
    if s:n_instances == 0
        return
    endif
    let [s:b_nodes, s:b_tree_file] = [g:nodes, s:tree_file]
    let s:tree_file = s:search_inst_file
    let s:event_ignore = 1 " will be reset in edit_scope()
    let s:search_inst_active = 1
    call s:enable_init_tick()
    call s:new_tree(20)
    call s:disable_init_tick()
    call Projective_open_tree_browser()
endfunc

func! s:restore_tree()
    let [g:nodes, s:tree_file] = [s:b_nodes, s:b_tree_file]
    call Projective_open_tree_browser()
    let s:search_inst_active = 0
    let s:scope_buf = 0
    wincmd p
endfunc

func! s:get_instances_map()
    " is not compatible with old grep (<= 2.5.1)
    let s:instances = {}
    if empty(s:scope)
        return
    endif
    let inst = map(Projective_get_children(s:scope), {k, v -> v.name})
    let cmd = 'grep -onE ''\<(' . join(inst, '|') . ')\>\s*($|\(|/[/*])|\);'' ' . expand('%')
                \ . ' | grep -A 1 '':[^)]'''
    call job_start(['sh', '-c', cmd], {'close_cb': function('s:get_instances_map_cb')})
endfunc

func! s:get_instances_map_cb(channel)
    " TODO confirm grep results by searching for the actual module name
    let inst_lnum = 0
    while ch_status(a:channel) == 'buffered'
	let line = ch_read(a:channel)
        if line[0] == '-'
            continue
        endif
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
    let node = Projective_get_parent(s:scope)
    if empty(node)
        echohl WarningMsg | echo  'Already at the top hierarchy' | echohl None
    else
        call s:edit_scope(node, 'e')
    endif
endfunc

func! s:scope_down()
    let inst = get(s:instances, line('.'), '')
    if inst == ''
        echohl WarningMsg | echo 'Not a module instance' | echohl None
    else
        let node = Get_node_by_path([inst], s:scope)
        call s:edit_scope(node, 'e')
    endif
endfunc

" TODO use node ids for speed?
func! s:hl_path()
    if line('.') == s:prev_ln
        return
    endif
    let s:prev_ln = line('.')
    let cur_inst = get(s:instances, line('.'), '')
    if cur_inst == s:prev_inst
        return
    endif
    let s:prev_inst = cur_inst
    call s:update_hl(cur_inst)
endfunc

func! s:update_hl(cur_inst)
    if a:cur_inst == ''
        let hl_scope = s:scope
        let hl_val = 2
    else
        let hl_scope = Get_node_by_path([a:cur_inst], s:scope)
        let hl_val = 3
    endif
    while !empty(s:prev_hl)
        call Projective_set_node_hl(s:prev_hl, 0)
	let s:prev_hl = Projective_get_parent(s:prev_hl)
    endwhile
    let s:prev_hl = hl_scope
    while !empty(hl_scope)
	call Projective_set_node_hl(hl_scope, hl_val)
        if hl_val > 1
            let hl_val -= 1
        endif
        let hl_scope = Projective_get_parent(hl_scope)
    endwhile
    call Projective_tree_refresh(0)
endfunc

""""""""""""""""""""""""""""""""""""""""""""""""
" Simvision
""""""""""""""""""""""""""""""""""""""""""""""""

func! s:simvision_eval(cmd)
    call s:simvision_connect()
    while !exists('g:simvision_ch') || ch_status(g:simvision_ch) != 'open'
        sleep 100m
    endwhile
    return ch_evalraw(g:simvision_ch, "request {" . a:cmd . "}\n")
endfunc

func! s:get_word_under_cursor()
    return matchstr(getline('.'), '\w*\%' . col('.') . 'c\w*')
endfunc

func! s:send_to_schematic()
    let design_obj = join(Projective_get_path(s:scope), '.') . '.' . s:get_word_under_cursor()
    let cmd = 'schematic add ' . design_obj . '; select set ' . design_obj
    if s:simvision_eval(cmd) == 'Error: no schematic window name entered'
        call s:simvision_eval('schematic new')
        call s:simvision_eval(cmd)
    endif
endfunc

func! s:get_schematic()
    let cs = s:simvision_eval('schematic curselection')
    let cs = substitute(cs, '^.*::', '', '')
    let sp = split(cs, '\.')
    call s:enable_init_tick()
    let scope = Get_node_by_path(sp[0:-2])
    call s:disable_init_tick()
    call s:edit_scope(scope, 'e')
    call search('\<' . matchstr(sp[-1], '\w\+') . '\>')
    norm! zz
endfunc

func! s:find_free_port()
    let ss = systemlist("ss -natu | awk '{print $5}' | sed 's/.*://' | sort -u")
    if len(ss) == 1 && ss[0] =~ ':'
        echoerr "'ss' Linux command is required!"
        return 0
    endif
    let open_ports = {}
    for p in ss
        let open_ports[p] = 1
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

func! s:simvision_connect()
    " TODO move to check_sv_connection()
    " TODO handle error
    let s:sv_close_console = !s:console_open
    if has_key(g:simvision_chs, g:projective_project_name)
        if ch_status(g:simvision_chs[g:projective_project_name].ch) != 'open'
            let g:simvision_chs[g:projective_project_name].ch = ch_open('localhost:' . g:simvision_chs[g:projective_project_name].port, {'mode': 'nl'})
        endif
        if ch_status(g:simvision_chs[g:projective_project_name].ch) == 'open'
            let g:simvision_ch = g:simvision_chs[g:projective_project_name].ch
            call s:console_msg('Connected to SimVision (port: ' . g:simvision_chs[g:projective_project_name].port . ')')
            if s:sv_close_console
                call s:console_close()
            endif
            return
        endif
    endif

    let file = expand(g:projective_make_dir . '/projective.tcl')
    let simvision_port = s:find_free_port()
    if simvision_port == 0
        return
    endif
    call writefile(['startServer ' . simvision_port], file)
    let cmd = g:simvision_server_cmd . ' -input projective.tcl'
    call s:console_open()
    call s:console_msg('Connecting to SimVision (port: ' . simvision_port . '). Please wait...')
    call s:console_msg(cmd)
    call s:console_msg('')
    call s:console_send_job(cmd)
    call timer_start(1000, function('s:simvision_connect_try', [simvision_port]), {'repeat': 90}) 
endfunc

func! s:simvision_connect_try(port, timer)
    let g:simvision_ch = ch_open('localhost:' . a:port, {'mode':'nl'})
    if ch_status(g:simvision_ch) == 'open'
        let g:simvision_chs[g:projective_project_name] = {}
        let g:simvision_chs[g:projective_project_name].ch = g:simvision_ch
        let g:simvision_chs[g:projective_project_name].port = a:port
        call s:console_msg('Successfully connected to SimVision!')
        if s:sv_close_console
            call s:console_close()
        endif
        call timer_stop(a:timer)
    endif
endfunc

"func! Get_sid(var)
"    exe 'echo s:' . a:var
"endfunc
