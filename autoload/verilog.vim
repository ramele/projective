" Projective Verilog extension
" Author: Ramel Eshed

command! -nargs=? -complete=dir Simvision :call s:simvision_connect(<q-args>)
command! UpdateDesign :call s:generate_tree()

if !exists('projective_verilog_smart_search')
    let projective_verilog_smart_search = 1
endif

func! s:tool_str(str)
    return substitute(a:str, '%', g:projective_verilog_tool, 'g')
endfunc

func! s:set_make(clean)
    if a:clean
        let s:files = []
        let s:modules = {}
        call Projective_save_file([], s:tool_str('%vlog/%vlog.args'))
    endif
endfunc

let s:pending_make_errors = 0

func! s:syntax_check()
    if !empty(getqflist({'winid': 1})) && s:pending_make_errors || s:syntax_check
        return
    endif
    let s:saved_make_opts = [g:projective_make_dir, g:projective_make_cmd, g:projective_make_console]
    let g:projective_make_dir = s:syntax_check_dir
    let g:projective_make_cmd = s:tool_str('%vlog ' . g:projective_verilog_syntax_check_flags . ' -f %vlog.args defines.v ' . expand('%:p'))
    let g:projective_make_console = 0
    let s:syntax_check = 1
    call Projective_make(0)
endfunc

func! s:make_post()
    if s:syntax_check
	let lines = readfile(s:tool_str(s:syntax_check_dir . '/%vlog.log'))
    else
        let log = g:projective_make_dir . '/' . g:projective_verilog_log_file
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
		let fname = (m[1] =~ '^[/~$]' ? m[1] : g:projective_make_dir . '/' . m[1])
		call add(my_qf, {'filename': fname, 'lnum': m[2], 'col': m[3]+1, 'text': m[4], 'type': 'E'})
	    else
		call add(my_qf, {'text': matchstr(l, '\*[EF],.*'), 'type': 'E'})
	    endif
	endif
    endfor
    let s:pending_make_errors = !s:syntax_check && !empty(my_qf)
    if s:syntax_check
        let [g:projective_make_dir, g:projective_make_cmd, g:projective_make_console] = s:saved_make_opts
        let s:syntax_check = 0
    elseif empty(my_qf)
        " TODO add job handle
        call job_start(['/bin/sh', '-c',
                    \ 'grep "^file:\|^\s*module\>" ' . log . ' | sed "s/^file: /-/; s/^\s*module \w*\.\(\w*\):.*/\1/"'],
                    \ {'close_cb': function('s:update_db')})
        let args = s:tool_str(s:syntax_check_dir . '/%vlog.args')
        " TODO handle include path/file
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
    let cmd = "grep -n '^\\s*`define' " . join(s:files) . ' | ' . s:get_defines_pl
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
        let s:hl_scope = {}
        let s:scope_buf = 0
        let s:search_inst_module = '~'
    endif
    call Projective_new_tree()
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

    if !exists('s:cdn_dir')
        let s:cdn_dir = globpath(&rtp, 'languages/verilog')
        let s:get_scope_pl = s:cdn_dir . '/get_scope.pl'
        let s:search_inst_pl = s:cdn_dir . '/search_inst.pl'
        let s:get_defines_pl = s:cdn_dir . '/get_defines.pl'
    endif

    let s:flag_64 = exists('g:projective_verilog_64_bit') && g:projective_verilog_64_bit ? '-64BIT ' : ''
    if exists('g:projective_verilog_grid')
        " TODO deprecated
        let g:projective_verilog_drm_cmd = g:projective_verilog_grid
    endif
    if !exists('g:projective_verilog_drm_cmd')
        let g:projective_verilog_drm_cmd = ''
    endif
    if g:projective_verilog_drm_cmd == ''
        " use non-empty string for now to invoke simvision each time UpdateDesign is called
        let g:projective_verilog_drm_cmd = ' '
    endif
    if !exists('g:projective_verilog_tool')
        let g:projective_verilog_tool = 'nc'
    endif
    if !exists('g:projective_verilog_syntax_check_flags')
        let g:projective_verilog_syntax_check_flags = '-sv'
    endif
    if !exists('projective_verilog_file_extentions')
        let g:projective_verilog_file_extentions = '*.v,*.vp,*.vs,*.sv,*.svp,*.svi,*.svh'
    endif

    let s:syntax_check_dir = Projective_path(s:tool_str('%vlog'))
    if !isdirectory(s:syntax_check_dir)
        call mkdir(s:syntax_check_dir)
    endif

    let s:tree_file = g:projective_make_dir . '/scope_tree.txt'
    let s:search_inst_file = g:projective_make_dir . '/scope_search.txt'
    let s:design_loaded = !empty(s:modules) && (glob(s:tree_file) != '')
    if s:design_loaded
        call Projective_load_tree('tree.p')
        if Projective_is_empty_tree()
            call s:new_tree(2)
        else
            " TODO close tree when not available
            call Projective_tree_refresh(1)
        endif
    endif

    let s:simvision_tree_cmd = 'cd ' . g:projective_make_dir . ';' .
                        \ ' simvision ' . s:flag_64 . '-nosplash -snapshot ' . g:projective_verilog_design_top .
                        \ ' -memberplugindir ' . s:cdn_dir . '/scope_tree_plugin'

    let s:sv_cursor_active = 0

    augroup projective_verilog_commands
	au!
	exe 'au BufWritePost        ' g:projective_verilog_file_extentions 'call s:syntax_check()'
	exe 'au BufWritePost        ' g:projective_verilog_file_extentions 'call s:get_instances_map()'
        exe 'au BufEnter            ' g:projective_verilog_file_extentions 'call s:update_cur_scope()'
        exe 'au CursorMoved         ' g:projective_verilog_file_extentions 'call s:cursor_moved()'
        exe 'au InsertEnter,BufLeave' g:projective_verilog_file_extentions 'call s:disable_hl_timer()'
    augroup END

    map <silent> <leader>va :call <SID>scope_up()<CR> " TODO deprecated
    map <silent> <leader>vf :call <SID>scope_up()<CR>
    map <silent> <leader>vv :call <SID>scope_down()<CR>
    nmap <silent> <leader>vs :call <SID>send_simvision('schematic', 'n')<CR>
    vmap <silent> <leader>vs :<C-U>call <SID>send_simvision('schematic', 'v')<CR>
    nmap <silent> <leader>vw :call <SID>send_simvision('waveform', 'n')<CR>
    vmap <silent> <leader>vw :<C-U>call <SID>send_simvision('waveform', 'v')<CR>
    map <silent> <leader>vc :call <SID>toggle_sv_cursor_bind()<CR>
    map <silent> <leader>vg :call <SID>get_simvision()<CR>
    map <silent> <leader>vi :call <SID>find_instance()<CR>

    let s:syntax_check = 0
    let s:prev_ln = 0
    let s:prev_inst = ''
    let s:hl_scope = {}
    let s:instances = {}
    let s:scope_buf = 0
    let s:console_open = 0
    let s:search_inst_module = '~'
    let s:search_inst_active = 0

    if count(split(g:projective_verilog_file_extentions, ','), substitute(bufname('%'), '.*\.', '*.', '')) 
        call s:update_cur_scope()
    endif
"    echo g:projective_project_type . ' init done!'
endfunc

func! verilog#Projective_cleanup()
    au! projective_verilog_commands
    if exists('g:simvision_ch') && ch_status(g:simvision_ch) == 'open'
        call ch_close(g:simvision_ch)
    endif
    if s:design_loaded
        call Projective_save_tree('tree.p')
    endif
    unlet s:modules
    unlet s:files
    " new flags
    unlet! g:projective_verilog_64_bit
    unlet! g:projective_verilog_syntax_check_flags
    unlet! g:projective_verilog_grid
    unlet! g:projective_verilog_drm_cmd
    unlet! g:projective_verilog_tool
    unlet! g:projective_verilog_file_extentions
    if !empty(timer_info(s:dtimer_id))
        call timer_stop(s:dtimer_id)
    endif

    unmap <leader>va
    unmap <leader>vf
    unmap <leader>vv
    unmap <leader>vs
    unmap <leader>vw
    unmap <leader>vc
    unmap <leader>vg
    unmap <leader>vi
"    echo g:projective_project_type . ' cleanup done!'
endfunc

""""""""""""""""""""""""""""""""""""""""""""""""
" hierarchy
""""""""""""""""""""""""""""""""""""""""""""""""
" TODO TEMP. waiting for setbufline() in vimL...

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
    if g:projective_verilog_drm_cmd != ''
        call s:console_msg('')
        call s:console_msg('Starting SimVision...')
        let cmdf = s:set_cmd_file([s:simvision_tree_cmd . ' -input projective.tcl'], 'simvision_get_tree.sh')
        let file = g:projective_make_dir . '/projective.tcl'
        call writefile(['print_scope_tree -include cells', 'exit'], file)
        "call writefile(['print_scope_tree', 'exit'], file)
        call s:console_send_job(g:projective_verilog_drm_cmd . ' ' . cmdf)
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
            let s:design_loaded = 1
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
    map <silent> <buffer> e     :call <SID>edit_tree_scope()<CR>
    map <silent> <buffer> <F5>  :call <SID>refresh_tree()<CR>
    map <silent> <buffer> <Esc> :call <SID>restore_tree()<CR>
endfunc

func! s:refresh_tree()
    if s:search_inst_active
        return
    endif
    let s:design_loaded = !empty(s:modules) && (glob(s:tree_file) != '')
    if s:design_loaded
        call s:new_tree(2)
    endif
endfunc

let s:event_ignore = 0

func! s:edit_tree_scope()
    let node = Projective_get_node_by_line(line('.'))
    " TODO open a new window if needed
    let s:event_ignore = 1 " will be reset in edit_scope()
    silent! wincmd p
    call s:edit_scope(node, 'e')
    if s:search_inst_active
        call s:restore_tree()
    endif
endfunc

func! s:update_tree_view()
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

func! s:get_module_file(module)
    let i = get(s:modules, a:module, -1)
    if i > -1
        return glob(s:files[i])
    else
        return ''
    endif
endfunc

func! s:edit_scope(node, cmd)
    let f = s:get_module_file(a:node.module)
    if f != ''
        let s:event_ignore = 1
        exe a:cmd f
        keepj norm! gg
        call search('^\s*module\s\+' . a:node.module)
        norm! zt
        let b:verilog_scope = Projective_get_path(a:node)
        let s:scope = a:node
        let s:scope_buf = bufnr('%')
        if !s:search_inst_active
            call s:update_tree_view()
            call s:get_instances_map()
            call s:update_hl('')
        endif
        let s:event_ignore = 0
    else
        echohl WarningMsg | echo 'Unknown module' | echohl None
    endif
endfunc

func! s:set_scope()
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
endfunc

func! s:update_cur_scope()
    " TODO use timer to make sure buffer was changed manually
    if !s:design_loaded
        let s:scope = {}
        return
    endif
    if s:event_ignore || s:scope_buf == bufnr('%')
        return
    endif
    call s:set_scope()
    if empty(s:scope)
        call s:search_inst()
    endif
endfunc

let s:find_instance_sync = 0

func! s:get_cur_module()
    let ml = search('^\s*module\>', 'bn')
    return matchstr(getline(ml), '^\s*module\s\+\zs\w\+')
endfunc

func! s:search_inst()
    " TODO use buffer locker
    let s:n_instances = 0
    let s:search_inst_module = s:get_cur_module()
    if s:search_inst_module == ''
        let s:find_instance_sync = 0
        return
    endif
    let cmd = s:search_inst_pl . ' ' . s:tree_file . ' ' . s:search_inst_module
    call job_start(['sh', '-c', cmd],
                \ { 'out_io': 'file',
		\ 'out_name' : s:search_inst_file,
                \ 'close_cb': function('s:search_inst_cb')})
endfunc

func! s:search_inst_cb(channel)
    let s:n_instances = matchstr(Projective_system('head -1 ' . s:search_inst_file)[0], '\d\+')

    if s:n_instances == 0
        echo 'verilog: Couldn''t find instances of ' . s:search_inst_module
    elseif s:n_instances == 1
        let b:verilog_scope = []
        let lines = readfile(s:search_inst_file)
        for l in lines
            let m = matchstr(l, '^\s*[+-]-\zs\w\+\ze\s\+(')
            if m != ''
                call add(b:verilog_scope, m)
            endif
        endfor
        call s:set_scope()
        echo 'verilog: Found one instance, updated scope to ' . join(b:verilog_scope, '.') 
    elseif !s:find_instance_sync
        echo 'verilog: Found ' . s:n_instances . ' instances of ' . s:search_inst_module . '. Type \vi to select an instance'
    endif
    let s:find_instance_sync = 0
endfunc

func! s:find_instance()
    if s:search_inst_module != s:get_cur_module()
        let s:find_instance_sync = 1
        call s:search_inst()
        while s:find_instance_sync
            sleep 50m
        endwhile
    endif
    if s:n_instances > 1
        let [s:b_nodes, s:b_tree_file] = [g:nodes, s:tree_file]
        let s:tree_file = s:search_inst_file
        let s:event_ignore = 1
        let s:search_inst_active = 1
        call s:enable_init_tick()
        call s:new_tree(20)
        call s:disable_init_tick()
        call Projective_open_tree_browser()
        redr
        echo 'verilog: ' . s:search_inst_module . ' instance tree (' . s:n_instances . ' nodes found)'
    endif
endfunc

func! s:restore_tree()
    if !s:search_inst_active
        return
    endif
    let [g:nodes, s:tree_file] = [s:b_nodes, s:b_tree_file]
    call Projective_open_tree_browser()
    let s:search_inst_active = 0
    let s:event_ignore = 0
    let s:scope_buf = 0
    wincmd p
endfunc

func! s:get_instances_map()
    " is not compatible with old grep (<= 2.5.1)
    let s:instances_map_valid = 0
    let s:instances = {}
    if empty(s:scope)
        return
    endif
    let inst = map(Projective_get_children(s:scope), {k, v -> v.name})
    let cmd = 'grep -onE ''\<(' . join(inst, '|') . ')\>\s*($|\(|/[/*])|\);'' ' . expand('%')
                \ . ' | grep -A 1 '':[^)]'''
    " TODO check if file name is valid
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
    let s:instances_map_valid = 1
endfunc

func! s:check_design(verify_scope)
    if !s:design_loaded
        echohl WarningMsg | echo 'Design is not loaded. Run :UpdateDesign first' | echohl None
    elseif a:verify_scope && empty(s:scope)
        echohl WarningMsg | echo 'Can''t detect design scope' | echohl None
    else
        return 1
    endif
    return 0
endfunc

func! s:cursor_on_searched_signal()
    let word = matchstr(getline('.'), '\w*\%' . col('.') . 'c\w\+')
    return word =~ @/ && @/[0:1] == '\<' && @/[-2:-1] == '\>'
endfunc

func! s:scope_up()
    if !s:check_design(1)
        return
    endif
    let inst_name = s:scope.name
    let node = Projective_get_parent(s:scope)
    if empty(node)
        echohl WarningMsg | echo 'Already at the top hierarchy' | echohl None
    else
        let auto_search = 0
        if g:projective_verilog_smart_search && s:cursor_on_searched_signal()
            let auto_search = 1
        endif
        call s:edit_scope(node, 'e')
        let timeout = 1000
        while timeout
            if s:instances_map_valid
                let inst_lnr = 0
                for i in range(1, line('$'))
                    if get(s:instances, i, '') == inst_name
                        let inst_lnr = i
                        break
                    endif
                endfor
                if !inst_lnr
                    break
                endif
                call cursor(inst_lnr, 1)
                if auto_search
                    let pat = '\.' . @/ . '[^(]*(\s*\zs\w'
                    let signal_lnr = search(pat, 'n')
                    if get(s:instances, signal_lnr, '') == inst_name
                        call search(pat)
                        let @/ = '\<' . matchstr(getline('.')[(col('.')-1):], '\w\+') . '\>'
                        call histadd('/', @/)
                    endif
                endif
                break
            endif
            sleep 20m
            let timeout -= 20
        endwhile
    endif
endfunc

func! s:scope_down()
    if !s:check_design(1)
        return
    endif
    let inst = get(s:instances, line('.'), '')
    if inst == ''
        echohl WarningMsg | echo 'Not a module instance' | echohl None
    else
        let auto_search = 0
        if g:projective_verilog_smart_search && s:cursor_on_searched_signal()
            if getline('.')[0:col('.')-2] =~ '([^)]*$'
                let signal = '\<' . matchstr(getline('.')[:(col('.')-2)], '.*\.\zs\w\+') . '\>'
                let auto_search = 1
            elseif getline('.')[0:col('.')-2] =~ '\.\w*$'
                let signal = @/
                let auto_search = 1
            endif
        endif
        let node = Get_node_by_path([inst], s:scope)
        call s:edit_scope(node, 'e')
        if auto_search
            call cursor(1,1)
            call feedkeys('/' . signal . "\<CR>", 'n')
        endif
    endif
endfunc

" TODO use node ids for speed?
func! s:cursor_moved()
    let s:moved = 1
    if line('.') == s:prev_ln || mode() != 'n'
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

func! s:signal_direction(tid)
    if mode() != 'n' || !s:moved || s:hl_scope_file == ''
        return
    endif
    let s:moved = 0
    let signal = matchstr(getline('.'), '\.\zs\w\+\ze\s*([^)]*\%' . col('.') . 'c')
    if signal == ''
        let signal = matchstr(getline('.'), '\.\zs\w\+\ze\s*(')
    endif
    if signal != s:prev_signal
        let s:prev_signal = signal
        let cmd = 'grep -E ''^\s*,?\s*(input|output|inout)\>.*\<' . signal . '\>'' ' . s:hl_scope_file
        call job_start(['sh', '-c', cmd], {'close_cb': function('s:signal_direction_cb', [signal])})
    endif
endfunc

func! s:signal_direction_cb(signal, channel)
    let dir = ''
    while ch_status(a:channel) == 'buffered'
        let l = substitute(ch_read(a:channel), '//.*', '', '')
        if l !~ '\<' . a:signal . '\>'
            continue
        endif
        let m = matchstr(l, 'input\|output\|inout')
        if dir != '' && m != dir
            let dir = ''
            break
        endif
        let dir = m
    endwhile
    if dir != s:prev_dir
        let s:prev_dir = dir
        if !empty(s:hl_scope) && Projective_get_node_hl(s:hl_scope) =~ '3'
            "u25C4, u25BA
            call Projective_set_node_hl(s:hl_scope, '3  ' . (dir == 'input' ? '◄' : dir == 'output' ? '►' : dir == 'inout' ? '◄►' : ''))
            call Projective_tree_refresh(0)
        endif
    endif
endfunc

let s:dtimer_id = 0

" TODO stop timer and refresh tree if there is no hl_scope_file
func! s:update_hl(cur_inst)
    let prev_node = s:hl_scope
    if a:cur_inst == ''
        let s:hl_scope = s:scope
        let hl_val = 2
        if !empty(timer_info(s:dtimer_id))
            call timer_stop(s:dtimer_id)
        endif
    else
        let s:hl_scope = Get_node_by_path([a:cur_inst], s:scope)
        let hl_val = 3
        let s:hl_scope_file = s:get_module_file(s:hl_scope.module)
        let s:prev_dir = '~'
        let s:prev_signal = '~'
        if empty(timer_info(s:dtimer_id))
            let s:dtimer_id = timer_start(300, function('s:signal_direction'), {'repeat': -1})
        endif
    endif
    let used = {}
    let node = s:hl_scope
    while !empty(node)
	call Projective_set_node_hl(node, hl_val)
        let used[node.id] = 1
        if hl_val > 1
            let hl_val -= 1
        endif
        let node = Projective_get_parent(node)
    endwhile
    while !empty(prev_node) && !has_key(used, prev_node.id)
        call Projective_set_node_hl(prev_node, 0)
	let prev_node = Projective_get_parent(prev_node)
    endwhile
    if a:cur_inst == ''
        " otherwise will be called from the timer
        call Projective_tree_refresh(0)
    endif
endfunc

func! s:disable_hl_timer()
    if !empty(timer_info(s:dtimer_id))
        call timer_stop(s:dtimer_id)
    endif
    let s:prev_ln = 0
    let s:prev_inst = ''
endfunc

""""""""""""""""""""""""""""""""""""""""""""""""
" Simvision
""""""""""""""""""""""""""""""""""""""""""""""""
"let g:sv_log = []

func! s:simvision_eval(cmd)
    "call add(g:sv_log, '> ' . a:cmd)
    call s:simvision_connect('')
    while !exists('g:simvision_ch') || ch_status(g:simvision_ch) != 'open'
        sleep 100m
    endwhile
    let res = ch_evalraw(g:simvision_ch, "request {" . a:cmd . "}\n")
    "call add(g:sv_log, res)
    return res
endfunc

func! s:select_cur_design_obj(mode)
    if !s:check_design(1)
        return ''
    endif
    if a:mode == 'v'
        let ids = []
        for line in getline("'<", "'>")
            let l = substitute(line, '//.*', '', '')
            for w in split(l, '\W\+')
                if w =~ '\a\w*' && w !~ '\v<(wire|reg|input|output|inout|assign)>'
                    call add(ids, w)
                endif
            endfor
        endfor
    else
        let ids = [matchstr(getline('.'), '\w*\%' . col('.') . 'c\w*')]
    endif
    let selection = ''
    for id in ids
        let obj = join(Projective_get_path(s:scope), '.') . '.' . id
        let sel = s:simvision_eval('select set ' . obj . '; select get')
        let sel = substitute(sel, '[{}]\|\[.*', '', 'g')
        if sel == obj
            if selection != ''
                let selection .= ' '
            endif
            let selection .= obj
        endif
    endfor
    if a:mode == 'v'
        let sel = s:simvision_eval('select set ' . selection)
    endif
    return selection
    " TODO handle multiple databases --
    "let scope = s:simvision_eval('waveform sidebar access designbrowser -using ' . window . ' scope')
    "let scope = substitute(scope, '::\zs.*', '', '')
    "let scope = substitute(scope, '[" ]', '\\\\\\&', 'g')
endfunc

func! s:get_target_window(type)
    let out = s:simvision_eval('window find -type ' . a:type)
    let windows = []
    while out =~ '{'
        call add(windows, matchstr(out, '{[^}]*}'))
        let out = substitute(out, '{[^}]*}', '', '')
    endwhile
    call extend(windows, split(out))
    if empty(windows)
        let win = a:type
        call s:simvision_eval(a:type . ' new -name ' . win)
    else
        let win = windows[-1] " default
        for w in windows
            if s:simvision_eval('window target ' . w) == '1'
                let win = w
                break
            endif
        endfor
    endif
    call s:simvision_eval('window activate ' . win)
    return win
endfunc

func! s:send_simvision(type, mode)
    if s:select_cur_design_obj(a:mode) == ''
        return
    endif
    let window = s:get_target_window(a:type)
    call s:simvision_eval(a:type . ' add -using ' . window . ' -selected')
endfunc

func! s:toggle_sv_cursor_bind()
    let s:sv_cursor_active = !s:sv_cursor_active
    if s:sv_cursor_active
        let s:cursor_ln = 0
        call s:set_cursor()
        augroup sv_cursor_command
            au!
            au CursorMoved <buffer> call s:set_cursor()
        augroup END
        echo 'Simvision cursor sync is ON'
    else
        au! sv_cursor_command
        echo 'Simvision cursor sync is OFF'
    endif
endfunc

func! s:set_cursor()
    if line('.') == s:cursor_ln
        return
    endif
    let s:cursor_ln = line('.')
    let time = matchstr(getline('.'), '\v<\d+%(\.\d+)?>%(\s*<%(s|ms|us|ns|ps|fs)>)?')
    let time = substitute(time, '\s\+', '', '')
    if time != ''
        call s:simvision_eval('cursor set -using TimeA -time ' . time)
    endif
endfunc

func! s:get_simvision()
    if !s:check_design(0)
        return
    endif
    let cs = s:simvision_eval('select get')
    let cs = substitute(cs, '[{}]\|\[.*', '', 'g')
    let sp = split(cs, '\.')
    call s:enable_init_tick()
    let scope = Get_node_by_path(sp)
    if empty(scope)
        let scope = Get_node_by_path(sp[0:-2])
        let signal = sp[-1]
    else
        let signal = ''
    endif
    call s:disable_init_tick()
    call s:edit_scope(scope, 'e')
    if signal != ''
        call search('\<' . matchstr(sp[-1], '\w\+') . '\>')
    endif
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

func! s:simvision_connect(db)
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

    let file = Projective_path('projective.tcl')
    let simvision_port = s:find_free_port()
    if simvision_port == 0
        return
    endif
    call writefile(['startServer ' . simvision_port], file)

    let cmd = (a:db == '' ? 'cd ' . g:projective_make_dir . ';' : '') .
                \ ' simvision ' . s:flag_64 . '-nosplash' .
                \ ' -input ' . s:cdn_dir . '/server.tcl' .
                \ ' -input ' . file .
                \ ' -title ' . g:projective_project_name . '@' . v:servername .
                \ (a:db == '' ? ' -snapshot ' . g:projective_verilog_design_top : ' ' . a:db)

    call s:console_open()
    call s:console_msg('Connecting to SimVision (localhost:' . simvision_port . '). Please wait...')
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

" func! Get_sid(var)
"    exe 'return s:' . a:var
" endfunc
